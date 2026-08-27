use clarix_editing_core::CommandId;
use clarix_pdf_oxide::editing_api::{
    NativeAnnotation, NativeAnnotationAnchorKind, NativeAnnotationCommandRequest,
    NativeAnnotationKind, NativeApproveFontFallbackRequest, NativeCleanPatchRequest,
    NativeDeleteAnnotationRequest, NativeEditorCommand, NativeEditorCommandKind,
    NativeEditorSaveMode, NativeEditorSaveRequest, NativeEditorSession,
    NativeFontFallbackProposalRequest, NativeObjectDetailsRequest, NativeOpenEditorRequest,
    NativePageSceneRequest, NativeSaveAssociation, NativeSearchMode, NativeSearchRequest,
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
fn native_session_searches_the_rust_authoritative_page_model() {
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
    let scene = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    let query = scene.objects[0].text.clone().unwrap();

    let result = session
        .search(NativeSearchRequest {
            expected_revision: 0,
            query,
            mode: NativeSearchMode::Exact,
            whole_word: false,
            offset: 0,
            limit: 10,
        })
        .unwrap();

    assert_eq!(result.revision, 0);
    assert_eq!(result.total_matches, 1);
    assert_eq!(result.matches[0].object_id, scene.objects[0].object_id);
    session.close().unwrap();
}

#[test]
fn native_session_creates_reads_and_deletes_canonical_annotations() {
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
    let scene = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    let annotation_id = clarix_editing_core::ObjectId::from_source_key("bridge/annotation/1");
    let created = session
        .create_annotation(NativeAnnotationCommandRequest {
            schema_version: 1,
            command_id: clarix_editing_core::CommandId::new().to_string(),
            base_revision: 0,
            annotation: NativeAnnotation {
                object_id: annotation_id.to_string(),
                page_id: scene.page_id,
                bounds: clarix_pdf_oxide::editing_api::NativePdfBox {
                    left: 10.0,
                    bottom: 10.0,
                    right: 11.0,
                    top: 11.0,
                },
                kind: NativeAnnotationKind::Comment,
                anchor_kind: NativeAnnotationAnchorKind::PagePoint,
                anchor_x: Some(10.0),
                anchor_y: Some(10.0),
                ranges: Vec::new(),
                title: String::new(),
                body: "Bridge comment".into(),
                color_rgba: vec![255, 212, 59, 255],
                opacity: 1.0,
                resolved: false,
            },
        })
        .unwrap();
    assert_eq!(created.committed_revision, 1);
    assert_eq!(
        session
            .annotation_details(annotation_id.to_string())
            .unwrap()
            .body,
        "Bridge comment"
    );

    let deleted = session
        .delete_annotation(NativeDeleteAnnotationRequest {
            schema_version: 1,
            command_id: clarix_editing_core::CommandId::new().to_string(),
            base_revision: 1,
            object_id: annotation_id.to_string(),
        })
        .unwrap();
    assert_eq!(deleted.committed_revision, 2);
    assert!(session
        .annotation_details(annotation_id.to_string())
        .is_err());
    session.close().unwrap();
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
fn native_submit_rejects_missing_glyphs_and_overflow_before_durability() {
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
    let scene = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    let object = &scene.objects[0];
    let object_id = object.object_id.clone();
    let missing_glyph = session
        .submit(NativeSubmitCommandRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 0,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::ReplaceTextRange,
                object_id: Some(object_id.clone()),
                start: Some(0),
                end: Some(1),
                replacement: Some("漢".into()),
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
    assert!(missing_glyph.starts_with("font_fallback_required:"));
    assert_eq!(session.metadata().unwrap().revision, 0);

    let text_length = object.text.as_ref().unwrap().encode_utf16().count() as u32;
    let overflow = session
        .submit(NativeSubmitCommandRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 0,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::ReplaceTextRange,
                object_id: Some(object_id),
                start: Some(0),
                end: Some(text_length),
                replacement: Some("A".repeat(object.character_boxes.len() + 1)),
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
    assert!(overflow.starts_with("text_overflow:"));
    assert_eq!(session.metadata().unwrap().revision, 0);
    session.close().unwrap();
}

#[test]
fn native_font_fallback_requires_a_bound_one_time_approval() {
    let project_root = tempfile::tempdir().unwrap();
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(project_root.path().to_string_lossy().into_owned()),
    })
    .unwrap();
    let scene = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    let object_id = scene.objects[0].object_id.clone();
    let proposal = session
        .propose_font_fallback(NativeFontFallbackProposalRequest {
            schema_version: 1,
            base_revision: 0,
            object_id: object_id.clone(),
            start: 0,
            end: 1,
            replacement: "€".into(),
        })
        .unwrap();
    assert!(proposal.embedding_allowed);
    assert_eq!(proposal.affected_characters, "€");

    let committed = session
        .approve_font_fallback(NativeApproveFontFallbackRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 0,
            proposal_token: proposal.token.clone(),
        })
        .unwrap();
    assert!(committed.durable);
    assert_eq!(committed.committed_revision, 1);
    assert_ne!(
        committed.object_patches[0].font_fingerprint,
        scene.objects[0].font_fingerprint
    );
    let asset = committed.object_patches[0]
        .font_asset_handle
        .as_ref()
        .expect("approved fallback must be copied into project assets")
        .clone();
    assert!(Path::new(&asset).starts_with(project_root.path()));
    assert!(Path::new(&asset).is_file());
    assert!(session
        .approve_font_fallback(NativeApproveFontFallbackRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 1,
            proposal_token: proposal.token,
        })
        .unwrap_err()
        .starts_with("font_fallback_proposal_invalid:"));
    let updated = session
        .object_details(NativeObjectDetailsRequest { object_id })
        .unwrap();
    assert_ne!(updated.font_fingerprint, scene.objects[0].font_fingerprint);
    session.close().unwrap();

    let recovered = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(project_root.path().to_string_lossy().into_owned()),
    })
    .unwrap();
    assert_eq!(recovered.metadata().unwrap().revision, 1);
    let restored = recovered
        .object_details(NativeObjectDetailsRequest {
            object_id: updated.object_id,
        })
        .unwrap();
    assert_eq!(restored.font_asset_handle.as_deref(), Some(asset.as_str()));
    recovered.close().unwrap();
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
fn live_command_prepares_a_physical_plan_before_it_is_published() {
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
    let scene = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::Visible,
        })
        .unwrap();
    let object = &scene.objects[0];
    let original = object.text.as_ref().unwrap();
    let prepared = session
        .prepare_live_command(NativeSubmitCommandRequest {
            schema_version: 1,
            command_id: CommandId::new().to_string(),
            base_revision: 0,
            payload: NativeEditorCommand {
                kind: NativeEditorCommandKind::ReplaceTextRange,
                object_id: Some(object.object_id.clone()),
                start: Some(0),
                end: Some(original.encode_utf16().count() as u32),
                replacement: Some("Prepared replacement".into()),
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

    assert_eq!(prepared.previous_revision, 0);
    assert_eq!(prepared.committed_revision, 1);
    assert_eq!(prepared.plan.operations.len(), 1);
    assert_eq!(prepared.plan.operations[0].object_id, object.object_id);
    assert_eq!(prepared.plan.operations[0].expected_text, *original);
    assert_eq!(
        prepared.plan.operations[0].replacement,
        "Prepared replacement"
    );
    assert_eq!(session.metadata().unwrap().revision, 0);

    let published = session
        .publish_prepared_live_command(prepared.token.clone())
        .unwrap();
    assert_eq!(published.committed_revision, 1);
    assert!(published.durable);
    assert_eq!(session.metadata().unwrap().revision, 1);
    assert_eq!(
        session
            .publish_prepared_live_command(prepared.token)
            .unwrap_err(),
        "prepared_command_not_found"
    );
    session.close().unwrap();
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
use std::path::Path;
