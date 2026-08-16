use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

use crate::{
    AtomicReplaceRequest, AtomicReplacementPort, CommandId, DocumentModel, MaterializationPort,
    MaterializationRecord, MaterializationReport, ProjectRepository, SourceReference,
    ValidationExpectation, ValidationPort, ValidationReport,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SaveStage {
    FlushCommands,
    Snapshot,
    VerifySource,
    MaterializeTemp,
    ValidateTemp,
    FlushTemp,
    ReplaceOrMove,
    Rebase,
    RecordMaterializedRevision,
}

impl SaveStage {
    pub const ALL: [Self; 9] = [
        Self::FlushCommands,
        Self::Snapshot,
        Self::VerifySource,
        Self::MaterializeTemp,
        Self::ValidateTemp,
        Self::FlushTemp,
        Self::ReplaceOrMove,
        Self::Rebase,
        Self::RecordMaterializedRevision,
    ];
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SaveMode {
    Save,
    SaveAs,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SaveAssociation {
    KeepOriginalAssociation,
    FollowNewSource,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SaveRequest {
    pub source: SourceReference,
    pub target: PathBuf,
    pub mode: SaveMode,
    pub association: SaveAssociation,
    pub recovery_directory: Option<PathBuf>,
    pub snapshot: DocumentModel,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SaveReport {
    pub completed_stages: Vec<SaveStage>,
    pub materialization: MaterializationReport,
    pub validation: ValidationReport,
    pub association: SaveAssociation,
    pub rebased_model: Option<DocumentModel>,
}

pub struct SaveCoordinator<'a> {
    materializer: &'a dyn MaterializationPort,
    validator: &'a dyn ValidationPort,
    replacer: &'a dyn AtomicReplacementPort,
    repository: Option<&'a dyn ProjectRepository>,
    stage_gate: Option<&'a dyn SaveStageGate>,
}

pub trait SaveStageGate: Send + Sync {
    fn enter(&self, stage: SaveStage) -> Result<(), SaveError>;
}

impl<'a> SaveCoordinator<'a> {
    pub fn new(
        materializer: &'a dyn MaterializationPort,
        validator: &'a dyn ValidationPort,
        replacer: &'a dyn AtomicReplacementPort,
    ) -> Self {
        Self {
            materializer,
            validator,
            replacer,
            repository: None,
            stage_gate: None,
        }
    }

    pub fn with_repository(mut self, repository: &'a dyn ProjectRepository) -> Self {
        self.repository = Some(repository);
        self
    }

    pub fn with_stage_gate(mut self, stage_gate: &'a dyn SaveStageGate) -> Self {
        self.stage_gate = Some(stage_gate);
        self
    }

    pub fn save(&self, request: SaveRequest) -> Result<SaveReport, SaveError> {
        self.enter(SaveStage::FlushCommands)?;
        self.enter(SaveStage::Snapshot)?;
        self.enter(SaveStage::VerifySource)?;
        let actual_fingerprint = fingerprint_file(&request.source.path).map_err(|message| {
            SaveError::new(SaveStage::VerifySource, "source_unavailable", message)
        })?;
        if actual_fingerprint != request.source.fingerprint
            || request.snapshot.source_fingerprint != request.source.fingerprint
        {
            return Err(SaveError::new(
                SaveStage::VerifySource,
                "source_changed",
                "the source PDF changed after the editing project was opened",
            ));
        }
        let working = working_path(&request.target);
        self.enter(SaveStage::MaterializeTemp)?;
        let materialization = self
            .materializer
            .materialize(&request.snapshot, &working)
            .map_err(|error| {
                let _ = std::fs::remove_file(&working);
                error.at_stage(SaveStage::MaterializeTemp)
            })?;
        let expectation = ValidationExpectation {
            document_id: request.snapshot.id,
            revision: request.snapshot.revision,
            page_count: request.snapshot.pages.len() as u32,
        };
        self.enter_with_working_cleanup(SaveStage::ValidateTemp, &working)?;
        let validation = self
            .validator
            .validate(&working, &expectation)
            .map_err(|error| {
                let _ = std::fs::remove_file(&working);
                error.at_stage(SaveStage::ValidateTemp)
            })?;
        if !validation.valid {
            let _ = std::fs::remove_file(&working);
            return Err(SaveError::new(
                SaveStage::ValidateTemp,
                "validation_failed",
                "the materialized PDF did not satisfy its save expectation",
            ));
        }
        self.enter_with_working_cleanup(SaveStage::FlushTemp, &working)?;
        flush_file(&working).map_err(|message| {
            let _ = std::fs::remove_file(&working);
            SaveError::new(SaveStage::FlushTemp, "flush_failed", message)
        })?;
        let backup = (request.mode == SaveMode::Save).then(|| backup_path(&request.target));
        self.enter_with_working_cleanup(SaveStage::ReplaceOrMove, &working)?;
        self.replacer
            .replace(AtomicReplaceRequest {
                working: working.clone(),
                target: request.target.clone(),
                backup: backup.clone(),
                replace_existing: request.mode == SaveMode::Save,
            })
            .map_err(|error| {
                let _ = std::fs::remove_file(&working);
                error.at_stage(SaveStage::ReplaceOrMove)
            })?;

        let installed_fingerprint = fingerprint_file(&request.target).map_err(|message| {
            partial_finalization_error("installed_output_unreadable", message)
        })?;
        if installed_fingerprint != materialization.output_sha256 {
            return Err(partial_finalization_error(
                "installed_output_unreadable",
                "the installed output hash differs from the validated temporary file",
            ));
        }
        self.enter(SaveStage::Rebase)?;
        let association = if request.mode == SaveMode::Save {
            SaveAssociation::FollowNewSource
        } else {
            request.association
        };
        let mut rebased_model = None;
        if association == SaveAssociation::FollowNewSource {
            let mut model = request.snapshot.clone();
            model.rebase_source(installed_fingerprint.clone());
            rebased_model = Some(model);
        }
        self.enter(SaveStage::RecordMaterializedRevision)?;
        if let Some(repository) = self.repository {
            repository
                .record_materialization(MaterializationRecord {
                    revision: request.snapshot.revision,
                    output_sha256: installed_fingerprint.clone(),
                    target_path: request.target.to_string_lossy().into_owned(),
                })
                .map_err(|error| {
                    partial_finalization_error("sidecar_record_failed", error.to_string())
                })?;
        }
        if let (Some(backup), Some(recovery_directory)) =
            (backup.as_ref(), request.recovery_directory.as_ref())
        {
            if backup.exists() {
                std::fs::create_dir_all(recovery_directory).map_err(|error| {
                    partial_finalization_error("backup_archive_failed", error.to_string())
                })?;
                let archived = recovery_directory.join(
                    backup
                        .file_name()
                        .unwrap_or_else(|| std::ffi::OsStr::new("clarix-backup.pdf")),
                );
                std::fs::rename(backup, archived).map_err(|error| {
                    partial_finalization_error("backup_archive_failed", error.to_string())
                })?;
            }
        }
        Ok(SaveReport {
            completed_stages: SaveStage::ALL.to_vec(),
            materialization,
            validation,
            association,
            rebased_model,
        })
    }

    fn enter(&self, stage: SaveStage) -> Result<(), SaveError> {
        self.stage_gate.map_or(Ok(()), |gate| {
            gate.enter(stage).map_err(|error| error.at_stage(stage))
        })
    }

    fn enter_with_working_cleanup(
        &self,
        stage: SaveStage,
        working: &std::path::Path,
    ) -> Result<(), SaveError> {
        self.enter(stage).inspect_err(|_| {
            let _ = std::fs::remove_file(working);
        })
    }
}

fn working_path(target: &std::path::Path) -> PathBuf {
    let file_name = target
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("document.pdf");
    target.with_file_name(format!(
        ".{file_name}.{}.clarix-working.pdf",
        CommandId::new()
    ))
}

fn backup_path(target: &std::path::Path) -> PathBuf {
    let file_name = target
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("document.pdf");
    target.with_file_name(format!(".{file_name}.clarix-backup.pdf"))
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Error)]
#[error("save failed at {stage:?}: {code}: {message}")]
pub struct SaveError {
    pub stage: SaveStage,
    pub code: String,
    pub message: String,
    pub retryable: bool,
}

impl SaveError {
    pub fn new(stage: SaveStage, code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            stage,
            code: code.into(),
            message: message.into(),
            retryable: false,
        }
    }

    pub fn at_stage(mut self, stage: SaveStage) -> Self {
        self.stage = stage;
        self
    }
}

fn fingerprint_file(path: &std::path::Path) -> Result<String, String> {
    let bytes = std::fs::read(path).map_err(|error| error.to_string())?;
    Ok(format!("{:x}", Sha256::digest(bytes)))
}

fn flush_file(path: &std::path::Path) -> Result<(), String> {
    std::fs::OpenOptions::new()
        .write(true)
        .open(path)
        .and_then(|file| file.sync_all())
        .map_err(|error| error.to_string())
}

fn partial_finalization_error(code: impl Into<String>, message: impl Into<String>) -> SaveError {
    let mut error = SaveError::new(SaveStage::RecordMaterializedRevision, code, message);
    error.retryable = true;
    error
}
