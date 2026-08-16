use clarix_editing_core::CommandId;
use clarix_pdf_oxide::editing_api::{
    NativeCleanPatchRequest, NativeEditorCommand, NativeEditorCommandKind, NativeEditorSaveMode,
    NativeEditorSaveRequest, NativeEditorSession, NativeObjectDetailsRequest,
    NativeOpenEditorRequest, NativePageSceneRequest, NativeSaveAssociation,
    NativeSubmitCommandRequest, NativeViewportPriority,
};

fn fixture_path() -> String {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/generated/standard-latin.pdf")
        .to_string_lossy()
        .into_owned()
}

#[test]
fn native_session_persists_requested_page_index_metadata() {
    let project_root = tempfile::tempdir().unwrap();
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(project_root.path().to_string_lossy().into_owned()),
    })
    .unwrap();
    session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    session.close().unwrap();

    let projects = project_root.path().join("Clarix").join("Projects");
    let document_directory = std::fs::read_dir(projects)
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let database = document_directory.join("project.sqlite");
    let connection = rusqlite::Connection::open(database).unwrap();
    let indexed_pages: i64 = connection
        .query_row("SELECT COUNT(*) FROM pages", [], |row| row.get(0))
        .unwrap();
    assert_eq!(indexed_pages, 1);
}

#[test]
fn native_session_indexes_pages_without_widget_requests() {
    let project_root = tempfile::tempdir().unwrap();
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(project_root.path().to_string_lossy().into_owned()),
    })
    .unwrap();
    let projects = project_root.path().join("Clarix").join("Projects");
    let document_directory = std::fs::read_dir(projects)
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let database = document_directory.join("project.sqlite");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
    let indexed_pages = loop {
        let connection = rusqlite::Connection::open(&database).unwrap();
        let count: i64 = connection
            .query_row("SELECT COUNT(*) FROM pages", [], |row| row.get(0))
            .unwrap();
        if count > 0 || std::time::Instant::now() >= deadline {
            break count;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    };
    session.close().unwrap();

    assert_eq!(indexed_pages, 1);
}

#[test]
fn native_editor_session_opens_edits_and_closes() {
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(
            tempfile::tempdir()
                .unwrap()
                .keep()
                .to_string_lossy()
                .into_owned(),
        ),
    })
    .unwrap();
    let metadata = session.metadata().unwrap();
    assert_eq!(metadata.schema_version, 1);
    assert_eq!(metadata.revision, 0);
    assert_eq!(metadata.page_count, 1);

    let scene = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    assert!(!scene.objects[0].character_boxes.is_empty());
    assert_eq!(scene.objects[0].character_boxes[0].start, 0);
    assert!(scene.objects[0].character_boxes[0].end > 0);
    let object_id = scene.objects[0].object_id.clone();
    let patch = session
        .clean_patch(NativeCleanPatchRequest {
            object_id: object_id.clone(),
            dpi: 144,
        })
        .unwrap();
    assert_eq!(patch.object_id, object_id);
    assert_eq!(
        patch.rgba_bytes.len(),
        patch.width as usize * patch.height as usize * 4
    );
    assert!(patch
        .rgba_bytes
        .chunks_exact(4)
        .all(|pixel| pixel == [255, 255, 255, 255]));
    let committed = session
        .submit(NativeSubmitCommandRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 0,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::ReplaceTextRange,
                object_id: Some(object_id.clone()),
                start: Some(0),
                end: Some(6),
                replacement: Some("Fast".into()),
                style: None,
                transform: None,
                bounds: None,
                radians: None,
                center_x: None,
                center_y: None,
                label: None,
            },
        })
        .unwrap();
    assert_eq!(committed.committed_revision, 1);
    assert!(committed.durable);
    assert_eq!(committed.object_patches.len(), 1);
    let updated = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 1,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    assert!(updated.objects[0]
        .text
        .as_deref()
        .unwrap()
        .starts_with("Fast"));

    let stale = session
        .submit(NativeSubmitCommandRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 0,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::CreateCheckpoint,
                object_id: None,
                start: None,
                end: None,
                replacement: None,
                style: None,
                transform: None,
                bounds: None,
                radians: None,
                center_x: None,
                center_y: None,
                label: Some("stale".into()),
            },
        })
        .unwrap_err();
    assert!(stale.starts_with("revision_conflict:"));

    session.close().unwrap();
    assert!(session
        .metadata()
        .unwrap_err()
        .starts_with("session_closed:"));
    assert!(session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 1,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap_err()
        .starts_with("session_closed:"));
    assert!(session
        .submit(NativeSubmitCommandRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 1,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::Undo,
                object_id: None,
                start: None,
                end: None,
                replacement: None,
                style: None,
                transform: None,
                bounds: None,
                radians: None,
                center_x: None,
                center_y: None,
                label: None,
            },
        })
        .unwrap_err()
        .starts_with("session_closed:"));
    session.close().unwrap();
}

#[test]
fn native_editor_session_rejects_schema_and_identifier_mismatches() {
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(
            tempfile::tempdir()
                .unwrap()
                .keep()
                .to_string_lossy()
                .into_owned(),
        ),
    })
    .unwrap();
    let schema_error = session
        .submit(NativeSubmitCommandRequest {
            schema_version: 2,
            command_id: CommandId::new().to_string(),
            base_revision: 0,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::Undo,
                object_id: None,
                start: None,
                end: None,
                replacement: None,
                style: None,
                transform: None,
                bounds: None,
                radians: None,
                center_x: None,
                center_y: None,
                label: None,
            },
        })
        .unwrap_err();
    assert!(schema_error.starts_with("schema_mismatch:"));

    let id_error = session
        .submit(NativeSubmitCommandRequest {
            schema_version: 1,
            command_id: "not-a-uuid".into(),
            base_revision: 0,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::Undo,
                object_id: None,
                start: None,
                end: None,
                replacement: None,
                style: None,
                transform: None,
                bounds: None,
                radians: None,
                center_x: None,
                center_y: None,
                label: None,
            },
        })
        .unwrap_err();
    assert!(id_error.starts_with("invalid_command_id:"));
    session.close().unwrap();
}

#[test]
fn accepted_command_is_durable_before_native_result_returns() {
    let project_root = tempfile::tempdir().unwrap();
    let open = || NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(project_root.path().to_string_lossy().into_owned()),
    };
    let session = NativeEditorSession::open(open()).unwrap();
    let scene = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    let object_id = scene.objects[0].object_id.clone();
    let original_length = scene.objects[0]
        .text
        .as_ref()
        .unwrap()
        .encode_utf16()
        .count() as u32;
    let result = session
        .submit(NativeSubmitCommandRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 0,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::ReplaceTextRange,
                object_id: Some(object_id.clone()),
                start: Some(0),
                end: Some(original_length),
                replacement: Some("After".into()),
                style: None,
                transform: None,
                bounds: None,
                radians: None,
                center_x: None,
                center_y: None,
                label: None,
            },
        })
        .unwrap();
    assert!(result.durable);
    session.close().unwrap();

    let recovered = NativeEditorSession::open(open()).unwrap();
    let details = recovered
        .object_details(NativeObjectDetailsRequest { object_id })
        .unwrap();
    assert_eq!(details.text.as_deref(), Some("After"));
    assert_eq!(
        recovered.metadata().unwrap().revision,
        result.committed_revision
    );
    recovered.close().unwrap();
}

#[test]
fn native_save_as_materializes_and_validates_the_current_revision() {
    let directory = tempfile::tempdir().unwrap();
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(
            directory
                .path()
                .join("project")
                .to_string_lossy()
                .into_owned(),
        ),
    })
    .unwrap();
    session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    let target = directory.path().join("saved-copy.pdf");
    let result = session
        .save(NativeEditorSaveRequest {
            target_path: target.to_string_lossy().into_owned(),
            mode: NativeEditorSaveMode::SaveAs,
            association: NativeSaveAssociation::FollowNewSource,
            recovery_directory: Some(
                directory
                    .path()
                    .join("recovery")
                    .to_string_lossy()
                    .into_owned(),
            ),
        })
        .unwrap();

    assert!(target.exists());
    assert_eq!(result.schema_version, 1);
    assert_eq!(result.materialized_revision, 0);
    assert_eq!(result.completed_stages.len(), 9);
    assert!(result.follows_new_source);
    session.close().unwrap();
}
