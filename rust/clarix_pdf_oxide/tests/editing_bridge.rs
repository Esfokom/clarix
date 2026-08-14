use clarix_editing_core::CommandId;
use clarix_pdf_oxide::editing_api::{
    NativeEditorCommand, NativeEditorCommandKind, NativeEditorSession, NativeOpenEditorRequest,
    NativePageSceneRequest, NativeSubmitCommandRequest,
};

fn fixture_path() -> String {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/generated/standard-latin.pdf")
        .to_string_lossy()
        .into_owned()
}

#[test]
fn native_editor_session_opens_edits_and_closes() {
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
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
        })
        .unwrap();
    let object_id = scene.objects[0].object_id.clone();
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
    assert_eq!(committed.object_patches.len(), 1);
    let updated = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 1,
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
