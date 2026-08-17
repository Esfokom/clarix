use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
};

use clarix_editing_core::{
    AnnotationAnchor, AnnotationNode, CommandEnvelope, CommandId, DocumentId, DocumentModel,
    DocumentObject, DocumentRevision, DurableCommit, EditorCommand, EditorSessionActor,
    EditorSessionState, ImportedPage, ObjectId, PageId, PageImportRequest, PageImportSource,
    PageNode, PageSceneRequest, PageSceneService, PdfBox, ProjectRepository, RecoveryRequest,
    SessionId, SourceReference, TextBlock, Utf16Range,
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
fn journal_recovery_replays_annotation_creation() {
    let temp = tempfile::tempdir().unwrap();
    let (model, _) = fixture_model("Before");
    let page_id = model.pages[0].id;
    let annotation_id = ObjectId::from_source_key("store/page/1/comment/1");
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
            EditorCommand::CreateAnnotation {
                annotation: AnnotationNode::comment(
                    annotation_id,
                    page_id,
                    PdfBox::new(10.0, 10.0, 11.0, 11.0).unwrap(),
                    AnnotationAnchor::PagePoint { x: 10.0, y: 10.0 },
                    "Durable comment",
                ),
            },
        ))
        .unwrap();
    repository
        .append(&DurableCommit::from_prepared(&prepared))
        .unwrap();
    drop(repository);

    let connection = rusqlite::Connection::open(&location.database).unwrap();
    connection.execute(
        "UPDATE project SET model_json = 'corrupt', model_sha256 = 'invalid' WHERE singleton = 1",
        [],
    ).unwrap();
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
    assert!(matches!(
        recovered.model.object(annotation_id),
        Some(DocumentObject::Annotation(annotation)) if annotation.body == "Durable comment"
    ));
}

#[test]
fn journal_recovery_replays_annotation_deletion() {
    let temp = tempfile::tempdir().unwrap();
    let (model, _) = fixture_model("Before");
    let page_id = model.pages[0].id;
    let annotation_id = ObjectId::from_source_key("store/page/1/comment/delete");
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
    let mut session = EditorSessionState::new(SessionId::new(), model.clone());
    let created = session
        .prepare(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::CreateAnnotation {
                annotation: AnnotationNode::comment(
                    annotation_id,
                    page_id,
                    PdfBox::new(10.0, 10.0, 11.0, 11.0).unwrap(),
                    AnnotationAnchor::PagePoint { x: 10.0, y: 10.0 },
                    "Delete me",
                ),
            },
        ))
        .unwrap();
    repository
        .append(&DurableCommit::from_prepared(&created))
        .unwrap();
    let created_result = session.publish(created).unwrap();
    let deleted = session
        .prepare(CommandEnvelope::user(
            CommandId::new(),
            created_result.committed_revision,
            EditorCommand::DeleteAnnotation {
                object_id: annotation_id,
            },
        ))
        .unwrap();
    repository
        .append(&DurableCommit::from_prepared(&deleted))
        .unwrap();
    drop(repository);

    let connection = rusqlite::Connection::open(&location.database).unwrap();
    connection.execute(
        "UPDATE project SET model_json = 'corrupt', model_sha256 = 'invalid' WHERE singleton = 1",
        [],
    ).unwrap();
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
    assert!(recovered.model.object(annotation_id).is_none());
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

#[test]
fn reopened_actor_preserves_undo_and_redo_history() {
    let temp = tempfile::tempdir().unwrap();
    let (model, object_id) = fixture_model("Before");
    let location = ProjectLocation::under(temp.path(), model.id);
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
    actor
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 6).unwrap(),
                replacement: "After".into(),
            },
        ))
        .unwrap();
    actor.close().unwrap();
    drop(actor);
    drop(repository);

    let reopened_repository = Arc::new(
        SqliteProjectRepository::open(
            location,
            ProjectSeed {
                model: model.clone(),
                undo_cursor: 0,
                materialized_revision: None,
            },
        )
        .unwrap(),
    );
    let recovered = EditorSessionActor::spawn_recovered(
        SessionId::new(),
        reopened_repository,
        RecoveryRequest {
            document_id: model.id,
            source_fingerprint: model.source_fingerprint,
        },
    )
    .unwrap();

    let undo = recovered
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::from_value(1),
            EditorCommand::Undo,
        ))
        .unwrap();
    assert_eq!(undo.committed_revision.value(), 2);
    let DocumentObject::Text(after_undo) = recovered
        .snapshot()
        .unwrap()
        .object(object_id)
        .unwrap()
        .clone()
    else {
        panic!("fixture object must remain text")
    };
    assert_eq!(after_undo.text, "Before");

    recovered
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::from_value(2),
            EditorCommand::Redo,
        ))
        .unwrap();
    let DocumentObject::Text(after_redo) = recovered
        .snapshot()
        .unwrap()
        .object(object_id)
        .unwrap()
        .clone()
    else {
        panic!("fixture object must remain text")
    };
    assert_eq!(after_redo.text, "After");
    recovered.close().unwrap();
}

#[test]
fn checkpoint_command_persists_checkpoint_snapshot_and_history_cursor() {
    let temp = tempfile::tempdir().unwrap();
    let (model, object_id) = fixture_model("Before");
    let location = ProjectLocation::under(temp.path(), model.id);
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
    let actor = EditorSessionActor::spawn_durable(SessionId::new(), model, repository);
    actor
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 6).unwrap(),
                replacement: "After".into(),
            },
        ))
        .unwrap();
    actor
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::from_value(1),
            EditorCommand::CreateCheckpoint {
                label: "Before review".into(),
            },
        ))
        .unwrap();
    actor.close().unwrap();

    let connection = rusqlite::Connection::open(&location.database).unwrap();
    let checkpoint: (String, i64, String) = connection
        .query_row(
            "SELECT label, revision, kind FROM checkpoints WHERE label = 'Before review'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(checkpoint, ("Before review".into(), 2, "User".into()));
    let snapshot_count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM snapshots WHERE revision = 2",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(snapshot_count, 1);
    let cursor: i64 = connection
        .query_row(
            "SELECT undo_cursor FROM project WHERE singleton = 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(cursor, 2);
}

#[test]
fn undo_persists_the_canonical_history_cursor() {
    let temp = tempfile::tempdir().unwrap();
    let (model, object_id) = fixture_model("Before");
    let location = ProjectLocation::under(temp.path(), model.id);
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
    let actor = EditorSessionActor::spawn_durable(SessionId::new(), model, repository);
    actor
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 6).unwrap(),
                replacement: "After".into(),
            },
        ))
        .unwrap();
    actor
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::from_value(1),
            EditorCommand::Undo,
        ))
        .unwrap();
    actor.close().unwrap();

    let connection = rusqlite::Connection::open(&location.database).unwrap();
    let cursor: i64 = connection
        .query_row(
            "SELECT undo_cursor FROM project WHERE singleton = 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(cursor, 0);
}

#[test]
fn recovered_actor_rejects_a_corrupt_history_cursor() {
    let temp = tempfile::tempdir().unwrap();
    let (model, object_id) = fixture_model("Before");
    let location = ProjectLocation::under(temp.path(), model.id);
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
    actor
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 6).unwrap(),
                replacement: "After".into(),
            },
        ))
        .unwrap();
    actor.close().unwrap();
    drop(actor);
    drop(repository);
    let connection = rusqlite::Connection::open(&location.database).unwrap();
    connection
        .execute(
            "UPDATE project SET undo_cursor = 99 WHERE singleton = 1",
            [],
        )
        .unwrap();
    drop(connection);

    let reopened = Arc::new(
        SqliteProjectRepository::open(
            location,
            ProjectSeed {
                model: model.clone(),
                undo_cursor: 0,
                materialized_revision: None,
            },
        )
        .unwrap(),
    );
    let result = EditorSessionActor::spawn_recovered(
        SessionId::new(),
        reopened,
        RecoveryRequest {
            document_id: model.id,
            source_fingerprint: model.source_fingerprint,
        },
    );

    assert!(
        matches!(result, Err(clarix_editing_core::EditingError::SidecarCommitFailed(message)) if message.contains("history cursor"))
    );
}

struct IndexedFixtureImporter {
    page: PageNode,
    imports: AtomicUsize,
}

impl PageImportSource for IndexedFixtureImporter {
    fn import_page(&self, _: PageImportRequest) -> Result<ImportedPage, String> {
        self.imports.fetch_add(1, Ordering::AcqRel);
        Ok(ImportedPage {
            page: self.page.clone(),
            warnings: vec!["fixture warning".into()],
        })
    }
}

#[test]
fn indexed_page_metadata_survives_repository_reopen_without_reimport() {
    let temp = tempfile::tempdir().unwrap();
    let (model, _) = fixture_model("CAFE\u{301}");
    let location = ProjectLocation::under(temp.path(), model.id);
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
    let first_importer = Arc::new(IndexedFixtureImporter {
        page: model.pages[0].clone(),
        imports: AtomicUsize::new(0),
    });
    let service = PageSceneService::new(
        model.id,
        SourceReference::new(&model.source_fingerprint, "fixture.pdf"),
        1,
        2,
        first_importer.clone(),
    )
    .unwrap()
    .with_index_repository(repository.clone());
    service.index_all_pages().unwrap();
    assert_eq!(first_importer.imports.load(Ordering::Acquire), 1);
    drop(service);
    drop(repository);

    let reopened = Arc::new(
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
    let second_importer = Arc::new(IndexedFixtureImporter {
        page: model.pages[0].clone(),
        imports: AtomicUsize::new(0),
    });
    let reopened_service = PageSceneService::new(
        model.id,
        SourceReference::new(&model.source_fingerprint, "fixture.pdf"),
        1,
        2,
        second_importer.clone(),
    )
    .unwrap()
    .with_index_repository(reopened);
    let scene = reopened_service
        .request(PageSceneRequest::visible(1, DocumentRevision::INITIAL))
        .unwrap();

    assert_eq!(scene.page, model.pages[0]);
    assert_eq!(scene.warnings, vec!["fixture warning"]);
    assert_eq!(second_importer.imports.load(Ordering::Acquire), 0);
    let connection = rusqlite::Connection::open(&location.database).unwrap();
    let persisted: (i64, i64, i64, String) = connection
        .query_row(
            "SELECT (SELECT COUNT(*) FROM pages), (SELECT COUNT(*) FROM objects), (SELECT COUNT(*) FROM text_runs), (SELECT normalized_text FROM text_index LIMIT 1)",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();
    assert_eq!(persisted, (1, 1, 1, "café".into()));
}
