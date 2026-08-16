use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    EditorCommand, EditorSessionState, FontFallbackApproval, FontRef, FontSource, ObjectId,
    OverflowPolicy, PageId, PageNode, PdfBox, SessionId, SourceGlyph, TextBlock, TextCharacterBox,
    TextLayoutRecipe, Utf16Range,
};

fn sample_model(text: &str) -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("command-test/page/1");
    let object_id = ObjectId::from_source_key("command-test/page/1/text/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("command-test"),
        "sha256:command-test".into(),
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
fn replacement_commits_once_and_stale_commands_do_not_mutate() {
    let (model, object_id) = sample_model("Hello world");
    let mut session = EditorSessionState::new(SessionId::new(), model);
    let command = CommandEnvelope::user(
        CommandId::new(),
        DocumentRevision::INITIAL,
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(6, 11).unwrap(),
            replacement: "Rust".into(),
        },
    );
    let result = session.submit(command).unwrap();
    assert_eq!(result.committed_revision.value(), 1);
    assert_eq!(result.object_patches.len(), 1);
    assert_eq!(session.text(object_id).unwrap(), "Hello Rust");

    let stale = CommandEnvelope::user(
        CommandId::new(),
        DocumentRevision::INITIAL,
        EditorCommand::CreateCheckpoint {
            label: "stale".into(),
        },
    );
    assert_eq!(
        session.submit(stale).unwrap_err().code(),
        "revision_conflict"
    );
    assert_eq!(session.revision().value(), 1);
    assert_eq!(session.text(object_id).unwrap(), "Hello Rust");
}

#[test]
fn emoji_replacement_undo_and_redo_preserve_utf16_boundaries() {
    let (model, object_id) = sample_model("A😀B");
    let mut session = EditorSessionState::new(SessionId::new(), model);

    let replaced = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(1, 3).unwrap(),
                replacement: "X".into(),
            },
        ))
        .unwrap();
    assert_eq!(replaced.committed_revision.value(), 1);
    assert_eq!(session.text(object_id).unwrap(), "AXB");

    let undone = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL.next().unwrap(),
            EditorCommand::Undo,
        ))
        .unwrap();
    assert_eq!(undone.committed_revision.value(), 2);
    assert_eq!(session.text(object_id).unwrap(), "A😀B");

    let redone = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            undone.committed_revision,
            EditorCommand::Redo,
        ))
        .unwrap();
    assert_eq!(redone.committed_revision.value(), 3);
    assert_eq!(session.text(object_id).unwrap(), "AXB");
}

#[test]
fn failed_command_is_atomic_and_does_not_consume_its_id() {
    let (model, object_id) = sample_model("A😀B");
    let mut session = EditorSessionState::new(SessionId::new(), model);
    let command_id = CommandId::new();
    let invalid = CommandEnvelope::user(
        command_id,
        DocumentRevision::INITIAL,
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(1, 2).unwrap(),
            replacement: "X".into(),
        },
    );

    assert_eq!(
        session.submit(invalid).unwrap_err().code(),
        "invalid_text_boundary"
    );
    assert_eq!(session.revision(), DocumentRevision::INITIAL);
    assert_eq!(session.text(object_id).unwrap(), "A😀B");

    let retry = CommandEnvelope::user(
        command_id,
        DocumentRevision::INITIAL,
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(1, 3).unwrap(),
            replacement: "X".into(),
        },
    );
    assert_eq!(session.submit(retry).unwrap().committed_revision.value(), 1);
    assert_eq!(session.text(object_id).unwrap(), "AXB");

    let duplicate = CommandEnvelope::user(
        command_id,
        DocumentRevision::INITIAL.next().unwrap(),
        EditorCommand::CreateCheckpoint {
            label: "duplicate".into(),
        },
    );
    assert_eq!(
        session.submit(duplicate).unwrap_err().code(),
        "duplicate_command"
    );
    assert_eq!(session.revision().value(), 1);
}

#[test]
fn replacement_reflows_legal_character_boxes_and_undo_restores_source_geometry() {
    let page_id = PageId::from_source_key("geometry-command/page");
    let object_id = ObjectId::from_source_key("geometry-command/object");
    let original_boxes = vec![
        TextCharacterBox {
            range: Utf16Range::new(0, 1).unwrap(),
            bounds: PdfBox::new(0.0, 0.0, 40.0, 20.0).unwrap(),
        },
        TextCharacterBox {
            range: Utf16Range::new(1, 2).unwrap(),
            bounds: PdfBox::new(40.0, 0.0, 100.0, 20.0).unwrap(),
        },
    ];
    let block = TextBlock::plain(
        object_id,
        page_id,
        "AB",
        PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
    )
    .with_character_boxes(original_boxes.clone());
    let model = DocumentModel::new(
        DocumentId::from_source_key("geometry-command"),
        "sha256:geometry-command".into(),
        vec![PageNode::new(
            page_id,
            1,
            100.0,
            20.0,
            vec![DocumentObject::text(block)],
        )],
    )
    .unwrap();
    let mut session = EditorSessionState::new(SessionId::new(), model);
    let result = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(1, 2).unwrap(),
                replacement: "👩🏽‍💻".into(),
            },
        ))
        .unwrap();
    assert_eq!(
        result.object_patches[0]
            .character_boxes
            .as_ref()
            .unwrap()
            .last()
            .unwrap()
            .range
            .end,
        8
    );

    let edited = session.snapshot().unwrap();
    let DocumentObject::Text(edited) = edited.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(edited.character_boxes.len(), 2);
    assert_eq!(edited.character_boxes.last().unwrap().range.end, 8);
    let encoded = serde_json::to_string(&session.snapshot().unwrap()).unwrap();
    serde_json::from_str::<DocumentModel>(&encoded).unwrap();

    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::from_value(1),
            EditorCommand::Undo,
        ))
        .unwrap();
    let restored = session.snapshot().unwrap();
    let DocumentObject::Text(restored) = restored.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(restored.character_boxes, original_boxes);
}

#[test]
fn resizing_text_reflows_and_publishes_character_geometry() {
    let page_id = PageId::from_source_key("resize-geometry/page");
    let object_id = ObjectId::from_source_key("resize-geometry/object");
    let block = TextBlock::plain(
        object_id,
        page_id,
        "AB",
        PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
    )
    .with_character_boxes(vec![
        TextCharacterBox {
            range: Utf16Range::new(0, 1).unwrap(),
            bounds: PdfBox::new(0.0, 0.0, 40.0, 20.0).unwrap(),
        },
        TextCharacterBox {
            range: Utf16Range::new(1, 2).unwrap(),
            bounds: PdfBox::new(40.0, 0.0, 100.0, 20.0).unwrap(),
        },
    ]);
    let model = DocumentModel::new(
        DocumentId::from_source_key("resize-geometry"),
        "sha256:resize-geometry".into(),
        vec![PageNode::new(
            page_id,
            1,
            200.0,
            40.0,
            vec![DocumentObject::text(block)],
        )],
    )
    .unwrap();
    let mut session = EditorSessionState::new(SessionId::new(), model);

    let result = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ResizeObject {
                object_id,
                bounds: PdfBox::new(0.0, 0.0, 200.0, 40.0).unwrap(),
            },
        ))
        .unwrap();

    let boxes = result.object_patches[0].character_boxes.as_ref().unwrap();
    assert_eq!(boxes[0].bounds.right, 100.0);
    assert_eq!(boxes[1].bounds.right, 200.0);

    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::from_value(1),
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 2).unwrap(),
                replacement: "ABCD".into(),
            },
        ))
        .unwrap();
}

#[test]
fn replacement_rejects_unencodable_glyph_before_revision_advances() {
    let (model, object_id) = qualified_text_model(OverflowPolicy::Reject);
    let mut session = EditorSessionState::new(SessionId::new(), model);
    let command_id = CommandId::new();
    let command = CommandEnvelope::user(
        command_id,
        DocumentRevision::INITIAL,
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(0, 1).unwrap(),
            replacement: "漢".into(),
        },
    );

    assert_eq!(
        session.submit(command.clone()).unwrap_err().code(),
        "font_fallback_required"
    );
    assert_eq!(session.revision(), DocumentRevision::INITIAL);
    assert_eq!(session.text(object_id).unwrap(), "AB");

    let retry = CommandEnvelope {
        payload: EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(0, 1).unwrap(),
            replacement: "C".into(),
        },
        ..command
    };
    assert_eq!(session.submit(retry).unwrap().committed_revision.value(), 1);
}

#[test]
fn approved_fallback_atomically_replaces_text_and_font() {
    let (model, object_id) = qualified_text_model(OverflowPolicy::Reject);
    let mut session = EditorSessionState::new(SessionId::new(), model);
    let result = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRangeWithFontFallback {
                object_id,
                range: Utf16Range::new(0, 1).unwrap(),
                replacement: "€".into(),
                approval: Box::new(fallback_approval(true)),
            },
        ))
        .unwrap();

    assert_eq!(session.text(object_id).unwrap(), "€B");
    let font = result.object_patches[0].font.as_ref().unwrap();
    assert_eq!(font.postscript_name, "ArialMT");
    assert_eq!(font.source, FontSource::ApprovedFallback);
    let snapshot = session.snapshot().unwrap();
    let DocumentObject::Text(block) = snapshot.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(block.font(), Some(font));

    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::from_value(1),
            EditorCommand::Undo,
        ))
        .unwrap();
    let restored = session.snapshot().unwrap();
    let DocumentObject::Text(restored) = restored.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(restored.text, "AB");
    assert_eq!(restored.font().unwrap().postscript_name, "FixtureSans");
}

#[test]
fn invalid_fallback_approval_does_not_advance_revision() {
    let (model, object_id) = qualified_text_model(OverflowPolicy::Reject);
    let mut session = EditorSessionState::new(SessionId::new(), model);
    let error = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRangeWithFontFallback {
                object_id,
                range: Utf16Range::new(0, 1).unwrap(),
                replacement: "€".into(),
                approval: Box::new(fallback_approval(false)),
            },
        ))
        .unwrap_err();

    assert_eq!(error.code(), "invalid_command");
    assert_eq!(session.revision(), DocumentRevision::INITIAL);
    assert_eq!(session.text(object_id).unwrap(), "AB");
}

#[test]
fn reject_overflow_policy_preserves_canonical_text_and_revision() {
    let (model, object_id) = qualified_text_model(OverflowPolicy::Reject);
    let mut session = EditorSessionState::new(SessionId::new(), model);

    let error = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 2).unwrap(),
                replacement: "ABC".into(),
            },
        ))
        .unwrap_err();

    assert_eq!(error.code(), "text_overflow");
    assert_eq!(session.revision(), DocumentRevision::INITIAL);
    assert_eq!(session.text(object_id).unwrap(), "AB");
}

#[test]
fn increase_bounds_overflow_policy_expands_and_publishes_bounds() {
    let (model, object_id) = qualified_text_model(OverflowPolicy::IncreaseBounds);
    let mut session = EditorSessionState::new(SessionId::new(), model);

    let result = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 2).unwrap(),
                replacement: "ABC".into(),
            },
        ))
        .unwrap();

    assert_eq!(result.object_patches[0].bounds.unwrap().right, 150.0);
    assert_eq!(session.text(object_id).unwrap(), "ABC");
}

#[test]
fn shortening_text_does_not_shrink_persistent_layout_capacity() {
    let (model, object_id) = qualified_text_model(OverflowPolicy::Reject);
    let mut session = EditorSessionState::new(SessionId::new(), model);
    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 2).unwrap(),
                replacement: "A".into(),
            },
        ))
        .unwrap();

    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::from_value(1),
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, 1).unwrap(),
                replacement: "AB".into(),
            },
        ))
        .unwrap();

    assert_eq!(session.text(object_id).unwrap(), "AB");
}

fn qualified_text_model(overflow: OverflowPolicy) -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("qualified-command/page");
    let object_id = ObjectId::from_source_key("qualified-command/object");
    let layout = TextLayoutRecipe {
        overflow,
        ..TextLayoutRecipe::default()
    };
    let block = TextBlock::plain(
        object_id,
        page_id,
        "AB",
        PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
    )
    .with_text_contract(
        FontRef {
            postscript_name: "FixtureSans".into(),
            bytes_sha256: "a".repeat(64),
            asset_id: Some("fixture-font".into()),
            source: FontSource::Embedded,
            embeddable: true,
        },
        layout,
        ['A', 'B', 'C']
            .into_iter()
            .map(|character| SourceGlyph {
                utf16_start: 0,
                utf16_end: 1,
                character_code: character as u32,
                glyph_id: character as u32,
            })
            .collect(),
    )
    .with_character_boxes(vec![
        TextCharacterBox {
            range: Utf16Range::new(0, 1).unwrap(),
            bounds: PdfBox::new(0.0, 0.0, 50.0, 20.0).unwrap(),
        },
        TextCharacterBox {
            range: Utf16Range::new(1, 2).unwrap(),
            bounds: PdfBox::new(50.0, 0.0, 100.0, 20.0).unwrap(),
        },
    ]);
    let model = DocumentModel::new(
        DocumentId::from_source_key("qualified-command"),
        "sha256:qualified-command".into(),
        vec![PageNode::new(
            page_id,
            1,
            200.0,
            100.0,
            vec![DocumentObject::text(block)],
        )],
    )
    .unwrap();
    (model, object_id)
}

fn fallback_approval(embeddable: bool) -> FontFallbackApproval {
    FontFallbackApproval {
        proposal_token: "proposal-token".into(),
        font: FontRef {
            postscript_name: "ArialMT".into(),
            bytes_sha256: "b".repeat(64),
            asset_id: Some(r"C:\Windows\Fonts\arial.ttf".into()),
            source: FontSource::ApprovedFallback,
            embeddable,
        },
        glyphs: ['€', 'B']
            .into_iter()
            .map(|character| SourceGlyph {
                utf16_start: 0,
                utf16_end: character.len_utf16() as u32,
                character_code: character as u32,
                glyph_id: character as u32,
            })
            .collect(),
    }
}
