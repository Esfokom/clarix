use std::sync::Arc;

use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, EditorCommand,
    EditorSessionActor, ObjectId, PageId, PageNode, PdfBox, ProjectRepository, RecoveryRequest,
    SessionId, TextBlock, Utf16Range,
};
use clarix_editing_store::{ProjectLocation, ProjectSeed, SqliteProjectRepository, StoreTable};

fn fixture() -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("sidecar-smoke/page/1");
    let object_id = ObjectId::from_source_key("sidecar-smoke/object/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("sidecar-smoke/document"),
        "sha256:sidecar-smoke".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                "A",
                PdfBox::new(0.0, 0.0, 20.0, 20.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (model, object_id)
}

#[test]
fn ten_thousand_durable_replace_undo_operations_survive_reopen() {
    let directory = tempfile::tempdir().unwrap();
    let (model, object_id) = fixture();
    let location = ProjectLocation::under(directory.path(), model.id);
    let repository = Arc::new(
        SqliteProjectRepository::open(
            location.clone(),
            ProjectSeed {
                model: model.clone(),
                undo_cursor: 0,
                materialized_revision: None,
            },
        )
        .unwrap(),
    );
    let actor =
        EditorSessionActor::spawn_durable(SessionId::new(), model.clone(), repository.clone());

    for _ in 0..5_000 {
        let revision = actor.snapshot().unwrap().revision;
        let replacement = actor
            .submit(CommandEnvelope::user(
                CommandId::new(),
                revision,
                EditorCommand::ReplaceTextRange {
                    object_id,
                    range: Utf16Range::new(0, 1).unwrap(),
                    replacement: "B".into(),
                },
            ))
            .unwrap();
        assert!(replacement.durable);
        let undo = actor
            .submit(CommandEnvelope::user(
                CommandId::new(),
                replacement.committed_revision,
                EditorCommand::Undo,
            ))
            .unwrap();
        assert!(undo.durable);
    }
    actor.close().unwrap();
    assert_eq!(repository.row_count(StoreTable::Commands).unwrap(), 10_000);
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
    assert_eq!(recovered.model.revision.value(), 10_000);
    let DocumentObject::Text(block) = recovered.model.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(block.text, "A");
    assert_eq!(reopened.row_count(StoreTable::Commands).unwrap(), 10_000);
    assert_eq!(
        reopened.row_count(StoreTable::InverseOperations).unwrap(),
        10_000
    );
}
