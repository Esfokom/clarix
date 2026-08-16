use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};

use clarix_editing_core::{
    AtomicReplaceRequest, AtomicReplacementPort, DocumentId, DocumentModel, MaterializationPort,
    MaterializationRecord, MaterializationReport, PersistenceError, ProjectCheckpoint,
    ProjectRepository, RecoveredProject, RecoveryRequest, SaveAssociation, SaveCoordinator,
    SaveError, SaveMode, SaveRequest, SaveStage, SaveStageGate, SourceReference,
    ValidationExpectation, ValidationPort, ValidationReport,
};
use sha2::{Digest, Sha256};

struct Harness {
    materialize_calls: AtomicUsize,
}

impl MaterializationPort for Harness {
    fn materialize(
        &self,
        _: &DocumentModel,
        target: &Path,
    ) -> Result<MaterializationReport, SaveError> {
        self.materialize_calls.fetch_add(1, Ordering::AcqRel);
        std::fs::write(target, b"replacement").unwrap();
        Ok(MaterializationReport {
            output_sha256: format!("{:x}", Sha256::digest(b"replacement")),
            bytes_written: 11,
            warnings: Vec::new(),
        })
    }
}

impl ValidationPort for Harness {
    fn validate(&self, _: &Path, _: &ValidationExpectation) -> Result<ValidationReport, SaveError> {
        Ok(ValidationReport {
            valid: true,
            warnings: Vec::new(),
        })
    }
}

impl AtomicReplacementPort for Harness {
    fn replace(&self, request: AtomicReplaceRequest) -> Result<(), SaveError> {
        std::fs::rename(request.working, request.target).unwrap();
        Ok(())
    }
}

#[test]
fn source_fingerprint_conflict_stops_before_materialization() {
    let directory = tempfile::tempdir().unwrap();
    let source_path = directory.path().join("source.pdf");
    let target = directory.path().join("output.pdf");
    std::fs::write(&source_path, b"changed externally").unwrap();
    let harness = Harness {
        materialize_calls: AtomicUsize::new(0),
    };
    let model = DocumentModel::new(
        DocumentId::from_source_key("save-conflict"),
        "0".repeat(64),
        Vec::new(),
    )
    .unwrap();

    let error = SaveCoordinator::new(&harness, &harness, &harness)
        .save(SaveRequest {
            source: SourceReference::new("0".repeat(64), source_path),
            target,
            mode: SaveMode::SaveAs,
            association: SaveAssociation::KeepOriginalAssociation,
            recovery_directory: None,
            snapshot: model,
        })
        .unwrap_err();

    assert_eq!(error.code, "source_changed");
    assert_eq!(harness.materialize_calls.load(Ordering::Acquire), 0);
}

#[test]
fn save_as_runs_every_stage_and_follows_new_source_when_requested() {
    let directory = tempfile::tempdir().unwrap();
    let source_path = directory.path().join("source.pdf");
    let target = directory.path().join("output.pdf");
    std::fs::write(&source_path, b"source").unwrap();
    let fingerprint = format!("{:x}", Sha256::digest(b"source"));
    let harness = Harness {
        materialize_calls: AtomicUsize::new(0),
    };
    let model = DocumentModel::new(
        DocumentId::from_source_key("save-as"),
        fingerprint.clone(),
        Vec::new(),
    )
    .unwrap();

    let report = SaveCoordinator::new(&harness, &harness, &harness)
        .save(SaveRequest {
            source: SourceReference::new(fingerprint, source_path),
            target: target.clone(),
            mode: SaveMode::SaveAs,
            association: SaveAssociation::FollowNewSource,
            recovery_directory: None,
            snapshot: model,
        })
        .unwrap();

    assert_eq!(std::fs::read(target).unwrap(), b"replacement");
    assert_eq!(report.completed_stages, SaveStage::ALL);
    assert!(report.rebased_model.is_some());
}

struct FailingHarness {
    stage: SaveStage,
}

impl MaterializationPort for FailingHarness {
    fn materialize(
        &self,
        _: &DocumentModel,
        target: &Path,
    ) -> Result<MaterializationReport, SaveError> {
        std::fs::write(target, b"replacement").unwrap();
        if self.stage == SaveStage::MaterializeTemp {
            return Err(SaveError::new(self.stage, "injected", "materialize"));
        }
        Ok(MaterializationReport {
            output_sha256: format!("{:x}", Sha256::digest(b"replacement")),
            bytes_written: 11,
            warnings: Vec::new(),
        })
    }
}

impl ValidationPort for FailingHarness {
    fn validate(
        &self,
        output: &Path,
        _: &ValidationExpectation,
    ) -> Result<ValidationReport, SaveError> {
        if self.stage == SaveStage::ValidateTemp {
            return Err(SaveError::new(self.stage, "injected", "validate"));
        }
        if self.stage == SaveStage::FlushTemp {
            std::fs::remove_file(output).unwrap();
        }
        Ok(ValidationReport {
            valid: true,
            warnings: Vec::new(),
        })
    }
}

impl AtomicReplacementPort for FailingHarness {
    fn replace(&self, _: AtomicReplaceRequest) -> Result<(), SaveError> {
        Err(SaveError::new(
            SaveStage::ReplaceOrMove,
            "injected",
            "replace",
        ))
    }
}

#[test]
fn pre_install_faults_preserve_original_and_remove_working_files() {
    for stage in [
        SaveStage::MaterializeTemp,
        SaveStage::ValidateTemp,
        SaveStage::FlushTemp,
        SaveStage::ReplaceOrMove,
    ] {
        let directory = tempfile::tempdir().unwrap();
        let source_path = directory.path().join("source.pdf");
        std::fs::write(&source_path, b"source").unwrap();
        let fingerprint = format!("{:x}", Sha256::digest(b"source"));
        let model = DocumentModel::new(
            DocumentId::from_source_key(&format!("save-fault-{stage:?}")),
            fingerprint.clone(),
            Vec::new(),
        )
        .unwrap();
        let harness = FailingHarness { stage };

        let error = SaveCoordinator::new(&harness, &harness, &harness)
            .save(SaveRequest {
                source: SourceReference::new(fingerprint, source_path.clone()),
                target: source_path.clone(),
                mode: SaveMode::Save,
                association: SaveAssociation::FollowNewSource,
                recovery_directory: None,
                snapshot: model,
            })
            .unwrap_err();

        assert_eq!(error.stage, stage);
        assert_eq!(std::fs::read(&source_path).unwrap(), b"source", "{stage:?}");
        let leaked = std::fs::read_dir(directory.path())
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| path != &source_path)
            .collect::<Vec<_>>();
        assert!(leaked.is_empty(), "{stage:?}: {leaked:?}");
    }
}

struct MatrixHarness {
    fail_at: SaveStage,
    sidecar_records: AtomicUsize,
}

impl SaveStageGate for MatrixHarness {
    fn enter(&self, stage: SaveStage) -> Result<(), SaveError> {
        if stage == self.fail_at {
            Err(SaveError::new(stage, "injected", format!("{stage:?}")))
        } else {
            Ok(())
        }
    }
}

impl MaterializationPort for MatrixHarness {
    fn materialize(
        &self,
        _: &DocumentModel,
        target: &Path,
    ) -> Result<MaterializationReport, SaveError> {
        std::fs::write(target, b"replacement").unwrap();
        Ok(MaterializationReport {
            output_sha256: hash(b"replacement"),
            bytes_written: 11,
            warnings: Vec::new(),
        })
    }
}

impl ValidationPort for MatrixHarness {
    fn validate(&self, _: &Path, _: &ValidationExpectation) -> Result<ValidationReport, SaveError> {
        Ok(ValidationReport {
            valid: true,
            warnings: Vec::new(),
        })
    }
}

impl AtomicReplacementPort for MatrixHarness {
    fn replace(&self, request: AtomicReplaceRequest) -> Result<(), SaveError> {
        if let Some(backup) = request.backup {
            std::fs::rename(&request.target, backup).unwrap();
        }
        std::fs::rename(request.working, request.target).unwrap();
        Ok(())
    }
}

impl ProjectRepository for MatrixHarness {
    fn recover(&self, _: RecoveryRequest) -> Result<RecoveredProject, PersistenceError> {
        unreachable!("the save matrix does not recover")
    }

    fn append(&self, _: &clarix_editing_core::DurableCommit) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn write_snapshot(
        &self,
        _: &clarix_editing_core::DurableSnapshot,
    ) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn checkpoint(&self, _: &ProjectCheckpoint) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn record_materialization(&self, _: MaterializationRecord) -> Result<(), PersistenceError> {
        self.sidecar_records.fetch_add(1, Ordering::AcqRel);
        Ok(())
    }

    fn close(&self) -> Result<(), PersistenceError> {
        Ok(())
    }
}

#[test]
fn every_save_stage_fault_has_a_hash_proven_recovery_state() {
    for stage in SaveStage::ALL {
        let directory = tempfile::tempdir().unwrap();
        let source_path = directory.path().join("document.pdf");
        std::fs::write(&source_path, b"source").unwrap();
        let source_hash = hash(b"source");
        let replacement_hash = hash(b"replacement");
        let model = DocumentModel::new(
            DocumentId::from_source_key(&format!("save-matrix-{stage:?}")),
            source_hash.clone(),
            Vec::new(),
        )
        .unwrap();
        let harness = MatrixHarness {
            fail_at: stage,
            sidecar_records: AtomicUsize::new(0),
        };

        let error = SaveCoordinator::new(&harness, &harness, &harness)
            .with_repository(&harness)
            .with_stage_gate(&harness)
            .save(SaveRequest {
                source: SourceReference::new(source_hash.clone(), source_path.clone()),
                target: source_path.clone(),
                mode: SaveMode::Save,
                association: SaveAssociation::FollowNewSource,
                recovery_directory: None,
                snapshot: model,
            })
            .unwrap_err();

        assert_eq!(error.stage, stage);
        let target_hash = hash(&std::fs::read(&source_path).unwrap());
        let backup = directory.path().join(".document.pdf.clarix-backup.pdf");
        if matches!(
            stage,
            SaveStage::Rebase | SaveStage::RecordMaterializedRevision
        ) {
            assert_eq!(target_hash, replacement_hash, "{stage:?}");
            assert_eq!(
                hash(&std::fs::read(&backup).unwrap()),
                source_hash,
                "{stage:?}"
            );
        } else {
            assert_eq!(target_hash, source_hash, "{stage:?}");
            assert!(!backup.exists(), "{stage:?}");
        }
        let working_files = std::fs::read_dir(directory.path())
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| path.to_string_lossy().contains("clarix-working"))
            .collect::<Vec<_>>();
        assert!(working_files.is_empty(), "{stage:?}: {working_files:?}");
        assert_eq!(harness.sidecar_records.load(Ordering::Acquire), 0);
    }
}

fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
