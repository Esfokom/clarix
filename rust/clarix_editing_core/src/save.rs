use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    AtomicReplaceRequest, AtomicReplacementPort, DocumentModel, MaterializationPort,
    MaterializationReport, SourceReference, ValidationExpectation, ValidationPort,
    ValidationReport,
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SaveRequest {
    pub source: SourceReference,
    pub target: PathBuf,
    pub mode: SaveMode,
    pub snapshot: DocumentModel,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SaveReport {
    pub completed_stages: Vec<SaveStage>,
    pub materialization: MaterializationReport,
    pub validation: ValidationReport,
}

pub struct SaveCoordinator<'a> {
    materializer: &'a dyn MaterializationPort,
    validator: &'a dyn ValidationPort,
    replacer: &'a dyn AtomicReplacementPort,
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
        }
    }

    pub fn save(&self, request: SaveRequest) -> Result<SaveReport, SaveError> {
        let working = working_path(&request.target);
        let materialization = self
            .materializer
            .materialize(&request.snapshot, &working)
            .map_err(|error| error.at_stage(SaveStage::MaterializeTemp))?;
        let expectation = ValidationExpectation {
            document_id: request.snapshot.id,
            revision: request.snapshot.revision,
            page_count: request.snapshot.pages.len() as u32,
        };
        let validation = self
            .validator
            .validate(&working, &expectation)
            .map_err(|error| error.at_stage(SaveStage::ValidateTemp))?;
        if !validation.valid {
            return Err(SaveError::new(
                SaveStage::ValidateTemp,
                "validation_failed",
                "the materialized PDF did not satisfy its save expectation",
            ));
        }
        let backup = (request.mode == SaveMode::Save).then(|| backup_path(&request.target));
        self.replacer
            .replace(AtomicReplaceRequest {
                working,
                target: request.target,
                backup,
                replace_existing: request.mode == SaveMode::Save,
            })
            .map_err(|error| error.at_stage(SaveStage::ReplaceOrMove))?;
        Ok(SaveReport {
            completed_stages: vec![
                SaveStage::MaterializeTemp,
                SaveStage::ValidateTemp,
                SaveStage::ReplaceOrMove,
            ],
            materialization,
            validation,
        })
    }
}

fn working_path(target: &std::path::Path) -> PathBuf {
    let file_name = target
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("document.pdf");
    target.with_file_name(format!(".{file_name}.clarix-working.pdf"))
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
