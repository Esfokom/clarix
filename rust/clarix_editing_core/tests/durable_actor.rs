use std::sync::{Arc, Mutex};

use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    DurableCommit, DurableSnapshot, EditingError, EditorCommand, EditorEvent, EditorSessionActor,
    MaterializationRecord, ObjectId, PageId, PageNode, PdfBox, PersistenceError,
    ProjectCheckpoint, ProjectRepository, RecoveredProject, RecoveryRequest, SessionId, TextBlock,
    Utf16Range,
};

fn fixture_model(text: &str) -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("durable/page");
    let object_id = ObjectId::from_source_key("durable/object");
    let model = DocumentModel::new(
        DocumentId::from_source_key("durable/document"),
        "sha256:durable".into(),
        vec![PageNode::new(
            page_id,
            1,
            100.0,
            100.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                text,
                PdfBox::new(0.0, 0.0, 50.0, 10.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (model, object_id)
}

struct MemoryRepository {
    recovered: Mutex<RecoveredProject>,
    fail_append: bool,
    appends: Mutex<usize>,
}

impl MemoryRepository {
    fn new(model: DocumentModel, fail_append: bool) -> Self {
        Self {
            recovered: Mutex::new(RecoveredProject {
                model,
                undo_cursor: 0,
                materialized_revision: None,
                warnings: Vec::new(),
            }),
            fail_append,
            appends: Mutex::new(0),
        }
    }
}

impl ProjectRepository for MemoryRepository {
    fn recover(&self, _: RecoveryRequest) -> Result<RecoveredProject, PersistenceError> {
        Ok(self.recovered.lock().unwrap().clone())
    }

    fn append(&self, commit: &DurableCommit) -> Result<(), PersistenceError> {
        if self.fail_append {
            return Err(PersistenceError::Transaction("injected append failure".into()));
        }
        *self.appends.lock().unwrap() += 1;
        self.recovered.lock().unwrap().model = commit.resulting_model.clone();
        Ok(())
    }

    fn write_snapshot(&self, _: &DurableSnapshot) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn checkpoint(&self, _: &ProjectCheckpoint) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn record_materialization(&self, _: MaterializationRecord) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn close(&self) -> Result<(), PersistenceError> {
        Ok(())
    }
}

fn replacement(object_id: ObjectId) -> CommandEnvelope {
    CommandEnvelope::user(
        CommandId::new(),
        DocumentRevision::INITIAL,
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(0, 6).unwrap(),
            replacement: "After".into(),
        },
    )
}

#[test]
fn repository_failure_does_not_publish_or_emit_commit() {
    let (model, object_id) = fixture_model("Before");
    let repository = Arc::new(MemoryRepository::new(model.clone(), true));
    let actor = EditorSessionActor::spawn_durable(SessionId::new(), model, repository);
    let events = actor.subscribe().unwrap();
    assert!(matches!(events.recv().unwrap(), EditorEvent::Ready { .. }));

    let error = actor.submit(replacement(object_id)).unwrap_err();

    assert!(matches!(error, EditingError::SidecarCommitFailed(_)));
    assert_eq!(actor.snapshot().unwrap().revision, DocumentRevision::INITIAL);
    assert_eq!(events.try_recv(), Err(crossbeam_channel::TryRecvError::Empty));
    actor.close().unwrap();
}

#[test]
fn acknowledged_command_is_durable_before_event_and_recovery() {
    let (model, object_id) = fixture_model("Before");
    let repository = Arc::new(MemoryRepository::new(model.clone(), false));
    let session_id = SessionId::new();
    let actor = EditorSessionActor::spawn_durable(session_id, model.clone(), repository.clone());
    let events = actor.subscribe().unwrap();
    let _ = events.recv().unwrap();

    let result = actor.submit(replacement(object_id)).unwrap();

    assert!(result.durable);
    assert_eq!(*repository.appends.lock().unwrap(), 1);
    let event = events.recv().unwrap();
    assert!(matches!(event, EditorEvent::CommandCommitted { result } if result.durable));
    actor.close().unwrap();

    let recovered = EditorSessionActor::spawn_recovered(
        SessionId::new(),
        repository,
        RecoveryRequest {
            document_id: model.id,
            source_fingerprint: model.source_fingerprint,
        },
    )
    .unwrap();
    let snapshot = recovered.snapshot().unwrap();
    let DocumentObject::Text(block) = snapshot.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(block.text, "After");
    recovered.close().unwrap();
}
