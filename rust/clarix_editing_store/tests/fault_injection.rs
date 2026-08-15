use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    DurableCommit, EditorCommand, EditorSessionState, ObjectId, PageId, PageNode, PdfBox,
    ProjectRepository, RecoveryRequest, SessionId, TextBlock, Utf16Range,
};
use clarix_editing_store::{FaultPoint, ProjectLocation, ProjectSeed, SqliteProjectRepository};

fn fixture() -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("fault/page");
    let object_id = ObjectId::from_source_key("fault/object");
    let model = DocumentModel::new(
        DocumentId::from_source_key("fault/document"),
        "sha256:fault".into(),
        vec![PageNode::new(
            page_id,
            1,
            100.0,
            100.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                "Before",
                PdfBox::new(0.0, 0.0, 50.0, 10.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (model, object_id)
}

fn commit(model: &DocumentModel, object_id: ObjectId) -> DurableCommit {
    let session = EditorSessionState::new(SessionId::new(), model.clone());
    let prepared = session
        .prepare(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 6).unwrap(),
                replacement: "After".into(),
            },
        ))
        .unwrap();
    DurableCommit::from_prepared(&prepared)
}

#[test]
fn failures_before_commit_recover_the_complete_old_revision() {
    for point in [
        FaultPoint::BeforeBegin,
        FaultPoint::AfterCommandInsert,
        FaultPoint::AfterInverseInsert,
        FaultPoint::AfterModelUpdate,
        FaultPoint::BeforeCommit,
    ] {
        let temp = tempfile::tempdir().unwrap();
        let (model, object_id) = fixture();
        let location = ProjectLocation::under(temp.path(), model.id);
        let repository = SqliteProjectRepository::open(
            location.clone(),
            ProjectSeed {
                model: model.clone(),
                undo_cursor: 0,
                materialized_revision: None,
            },
        )
        .unwrap();
        repository.inject_once(point);
        assert!(
            repository.append(&commit(&model, object_id)).is_err(),
            "{point:?}"
        );
        drop(repository);

        let reopened = SqliteProjectRepository::open(
            location,
            ProjectSeed {
                model: model.clone(),
                undo_cursor: 0,
                materialized_revision: None,
            },
        )
        .unwrap();
        let recovered = reopened
            .recover(RecoveryRequest {
                document_id: model.id,
                source_fingerprint: model.source_fingerprint.clone(),
            })
            .unwrap();
        assert_eq!(
            recovered.model.revision,
            DocumentRevision::INITIAL,
            "{point:?}"
        );
        let DocumentObject::Text(block) = recovered.model.object(object_id).unwrap() else {
            panic!("fixture object must remain text")
        };
        assert_eq!(block.text, "Before", "{point:?}");
    }
}

#[test]
fn interruption_after_commit_recovers_the_complete_new_revision() {
    let temp = tempfile::tempdir().unwrap();
    let (model, object_id) = fixture();
    let location = ProjectLocation::under(temp.path(), model.id);
    let repository = SqliteProjectRepository::open(
        location.clone(),
        ProjectSeed {
            model: model.clone(),
            undo_cursor: 0,
            materialized_revision: None,
        },
    )
    .unwrap();
    repository.inject_once(FaultPoint::AfterCommit);
    repository.append(&commit(&model, object_id)).unwrap();
    drop(repository);

    let reopened = SqliteProjectRepository::open(
        location,
        ProjectSeed {
            model: model.clone(),
            undo_cursor: 0,
            materialized_revision: None,
        },
    )
    .unwrap();
    let recovered = reopened
        .recover(RecoveryRequest {
            document_id: model.id,
            source_fingerprint: model.source_fingerprint,
        })
        .unwrap();
    assert_eq!(recovered.model.revision.value(), 1);
    let DocumentObject::Text(block) = recovered.model.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(block.text, "After");
}
