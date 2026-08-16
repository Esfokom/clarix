use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};

use clarix_editing_core::{
    AtomicReplaceRequest, AtomicReplacementPort, DocumentId, DocumentModel, MaterializationPort,
    MaterializationReport, SaveAssociation, SaveCoordinator, SaveError, SaveMode, SaveRequest,
    SaveStage, SourceReference, ValidationExpectation, ValidationPort, ValidationReport,
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
