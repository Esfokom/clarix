use std::path::PathBuf;

use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    DurableCommit, EditorCommand, EditorSessionState, ObjectId, PageId, PageNode, PdfBox,
    ProjectRepository, RecoveryRequest, SessionId, TextBlock, Utf16Range,
};
use clarix_editing_store::{ProjectLocation, ProjectSeed, SqliteProjectRepository, StoreTable};

fn fixture_model(text: &str) -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("store/page/1");
    let object_id = ObjectId::from_source_key("store/object/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("store/document"),
        "sha256:store-source".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                text,
                PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (model, object_id)
}

#[test]
fn project_location_is_scoped_to_local_app_data_and_document_id() {
    let root = PathBuf::from(r"C:\Users\tester\AppData\Local");
    let document_id = DocumentId::from_source_key("store/document");

    let location = ProjectLocation::under(&root, document_id);

    let expected_root = root
        .join("Clarix")
        .join("Projects")
        .join(document_id.to_string());
    assert_eq!(location.root, expected_root);
    assert_eq!(location.database, expected_root.join("project.sqlite"));
    assert_eq!(location.assets, expected_root.join("assets"));
    assert_eq!(location.previews, expected_root.join("previews"));
    assert_eq!(location.recovery, expected_root.join("recovery"));
}

#[test]
fn append_atomically_persists_command_inverse_and_resulting_model() {
    let temp = tempfile::tempdir().unwrap();
    let (model, object_id) = fixture_model("Before");
    let location = ProjectLocation::under(temp.path(), model.id);
    let repository = SqliteProjectRepository::open(
        location,
        ProjectSeed {
            model: model.clone(),
            undo_cursor: 0,
            materialized_revision: None,
        },
    )
    .unwrap();
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

    repository
        .append(&DurableCommit::from_prepared(&prepared))
        .unwrap();
    drop(repository);

    let reopened = SqliteProjectRepository::open(
        ProjectLocation::under(temp.path(), model.id),
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
    let DocumentObject::Text(block) = recovered.model.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(block.text, "After");
    assert_eq!(recovered.model.revision.value(), 1);
    assert_eq!(reopened.row_count(StoreTable::Commands).unwrap(), 1);
    assert_eq!(
        reopened.row_count(StoreTable::InverseOperations).unwrap(),
        1
    );
}

#[test]
fn corrupt_current_model_falls_back_to_snapshot_and_replays_journal() {
    let temp = tempfile::tempdir().unwrap();
    let (model, object_id) = fixture_model("Before");
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
    repository
        .append(&DurableCommit::from_prepared(&prepared))
        .unwrap();
    drop(repository);

    let connection = rusqlite::Connection::open(&location.database).unwrap();
    connection
        .execute(
            "UPDATE project SET model_json = 'corrupt', model_sha256 = 'invalid' WHERE singleton = 1",
            [],
        )
        .unwrap();
    drop(connection);

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
    assert_eq!(
        recovered.warnings,
        vec!["current model checksum invalid; recovered from snapshot and journal"]
    );
    let DocumentObject::Text(block) = recovered.model.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(block.text, "After");
}
