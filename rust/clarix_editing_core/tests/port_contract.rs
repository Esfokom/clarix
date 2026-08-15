use std::{path::Path, sync::Mutex};

use clarix_editing_core::{
    AtomicReplaceRequest, AtomicReplacementPort, DocumentId, DocumentModel, DocumentRevision,
    DurableCommit, EditorSessionState, MaterializationPort, MaterializationReport, ObjectId,
    PageId, PageNode, PdfBox, ProjectRepository, RecoveredProject, RecoveryRequest,
    SaveAssociation, SaveCoordinator, SaveError, SaveMode, SaveRequest, SaveStage, SessionId,
    SourceReference, TextBlock, ValidationExpectation, ValidationPort, ValidationReport,
};
use sha2::{Digest, Sha256};

struct RecordingRepository {
    commits: Mutex<Vec<DurableCommit>>,
}

impl ProjectRepository for RecordingRepository {
    fn recover(
        &self,
        _: RecoveryRequest,
    ) -> Result<RecoveredProject, clarix_editing_core::PersistenceError> {
        Err(clarix_editing_core::PersistenceError::Unavailable(
            "not used by this test".into(),
        ))
    }

    fn append(&self, commit: &DurableCommit) -> Result<(), clarix_editing_core::PersistenceError> {
        self.commits.lock().unwrap().push(commit.clone());
        Ok(())
    }

    fn write_snapshot(
        &self,
        _: &clarix_editing_core::DurableSnapshot,
    ) -> Result<(), clarix_editing_core::PersistenceError> {
        Ok(())
    }

    fn checkpoint(
        &self,
        _: &clarix_editing_core::ProjectCheckpoint,
    ) -> Result<(), clarix_editing_core::PersistenceError> {
        Ok(())
    }

    fn record_materialization(
        &self,
        _: clarix_editing_core::MaterializationRecord,
    ) -> Result<(), clarix_editing_core::PersistenceError> {
        Ok(())
    }

    fn close(&self) -> Result<(), clarix_editing_core::PersistenceError> {
        Ok(())
    }
}

#[derive(Default)]
struct RecordingMaterializer {
    calls: Mutex<Vec<SaveStage>>,
}

impl MaterializationPort for RecordingMaterializer {
    fn materialize(
        &self,
        _: &DocumentModel,
        target: &Path,
    ) -> Result<MaterializationReport, SaveError> {
        self.calls.lock().unwrap().push(SaveStage::MaterializeTemp);
        std::fs::write(target, b"a").unwrap();
        Ok(MaterializationReport {
            output_sha256: format!("{:x}", Sha256::digest(b"a")),
            bytes_written: 1,
            warnings: Vec::new(),
        })
    }
}

impl ValidationPort for RecordingMaterializer {
    fn validate(&self, _: &Path, _: &ValidationExpectation) -> Result<ValidationReport, SaveError> {
        self.calls.lock().unwrap().push(SaveStage::ValidateTemp);
        Ok(ValidationReport {
            valid: true,
            warnings: Vec::new(),
        })
    }
}

impl AtomicReplacementPort for RecordingMaterializer {
    fn replace(&self, request: AtomicReplaceRequest) -> Result<(), SaveError> {
        self.calls.lock().unwrap().push(SaveStage::ReplaceOrMove);
        std::fs::rename(request.working, request.target).unwrap();
        Ok(())
    }
}

#[test]
fn durable_commit_contains_inverse_before_actor_publication() {
    let page_id = PageId::from_source_key("ports/page");
    let object_id = ObjectId::from_source_key("ports/object");
    let model = DocumentModel::new(
        DocumentId::from_source_key("ports/document"),
        "source".into(),
        vec![PageNode::new(
            page_id,
            1,
            100.0,
            100.0,
            vec![clarix_editing_core::DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                "Before",
                PdfBox::new(0.0, 0.0, 40.0, 10.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    let session = EditorSessionState::new(SessionId::new(), model);
    let prepared = session
        .prepare(clarix_editing_core::CommandEnvelope::user(
            clarix_editing_core::CommandId::new(),
            DocumentRevision::INITIAL,
            clarix_editing_core::EditorCommand::ReplaceTextRange {
                object_id,
                range: clarix_editing_core::Utf16Range::new(0, 6).unwrap(),
                replacement: "After".into(),
            },
        ))
        .unwrap();

    let durable = DurableCommit::from_prepared(&prepared);
    let repository = RecordingRepository {
        commits: Mutex::new(Vec::new()),
    };
    repository.append(&durable).unwrap();

    assert_eq!(durable.previous_revision, DocumentRevision::INITIAL);
    assert_eq!(durable.committed_revision.value(), 1);
    assert_eq!(durable.before_objects.len(), 1);
    assert_eq!(durable.after_objects.len(), 1);
    assert_eq!(repository.commits.lock().unwrap().len(), 1);
}

#[test]
fn save_coordinator_materializes_validates_and_replaces_in_order() {
    let adapter = RecordingMaterializer::default();
    let directory = tempfile::tempdir().unwrap();
    let source_path = directory.path().join("source.pdf");
    std::fs::write(&source_path, b"source").unwrap();
    let fingerprint = format!("{:x}", Sha256::digest(b"source"));
    let source = SourceReference::new(fingerprint.clone(), source_path);
    let model =
        DocumentModel::new(DocumentId::from_source_key("save"), fingerprint, Vec::new()).unwrap();
    let report = SaveCoordinator::new(&adapter, &adapter, &adapter)
        .save(SaveRequest {
            source,
            target: directory.path().join("target.pdf"),
            mode: SaveMode::SaveAs,
            association: SaveAssociation::KeepOriginalAssociation,
            recovery_directory: None,
            snapshot: model,
        })
        .unwrap();

    assert_eq!(
        *adapter.calls.lock().unwrap(),
        vec![
            SaveStage::MaterializeTemp,
            SaveStage::ValidateTemp,
            SaveStage::ReplaceOrMove
        ]
    );
    assert_eq!(report.completed_stages, SaveStage::ALL);
}
