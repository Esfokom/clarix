use clarix_editing_core::{
    AtomicEdit, CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject,
    DocumentRevision, EditorCommand, EditorSessionState, InverseOperation, ObjectId, PageId,
    PageNode, ParagraphStyle, PdfBox, SessionId, TextAlignment, TextBlock, TypingGroup, Utf16Range,
};

fn fixture_session(text: &str) -> (EditorSessionState, ObjectId) {
    let page_id = PageId::from_source_key("history/page/1");
    let object_id = ObjectId::from_source_key("history/page/1/text/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("history"),
        "sha256:history".into(),
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
    (EditorSessionState::new(SessionId::new(), model), object_id)
}

fn replace(
    object_id: ObjectId,
    revision: u64,
    range: std::ops::Range<u32>,
    replacement: &str,
) -> CommandEnvelope {
    CommandEnvelope::user(
        CommandId::new(),
        DocumentRevision::from_value(revision),
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(range.start, range.end).unwrap(),
            replacement: replacement.into(),
        },
    )
}

#[test]
fn prepare_does_not_publish_and_carries_inverse() {
    let (mut session, object_id) = fixture_session("Before");

    let prepared = session
        .prepare(replace(object_id, 0, 0..6, "After"))
        .unwrap();

    assert_eq!(session.text(object_id).unwrap(), "Before");
    assert_eq!(session.revision(), DocumentRevision::INITIAL);
    assert_eq!(prepared.previous_revision, DocumentRevision::INITIAL);
    assert_eq!(prepared.committed_revision.value(), 1);
    assert_eq!(prepared.before_objects.len(), 1);
    assert_eq!(prepared.after_objects.len(), 1);
    assert!(matches!(
        prepared.inverse,
        InverseOperation::ReplaceObjects(_)
    ));

    let result = session.publish(prepared).unwrap();
    assert_eq!(result.previous_revision, DocumentRevision::INITIAL);
    assert_eq!(session.text(object_id).unwrap(), "After");
}

#[test]
fn paragraph_style_is_a_typed_invertible_command() {
    let (mut session, object_id) = fixture_session("Paragraph");
    let result = session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::SetParagraphStyle {
                object_id,
                style: ParagraphStyle {
                    alignment: TextAlignment::Right,
                    line_spacing: 1.5,
                },
            },
        ))
        .unwrap();
    assert_eq!(result.previous_revision, DocumentRevision::INITIAL);
    let snapshot = session.snapshot().unwrap();
    let DocumentObject::Text(block) = snapshot.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(block.layout.paragraph.alignment, TextAlignment::Right);

    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            result.committed_revision,
            EditorCommand::Undo,
        ))
        .unwrap();
    let snapshot = session.snapshot().unwrap();
    let DocumentObject::Text(block) = snapshot.object(object_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(block.layout.paragraph.alignment, TextAlignment::Left);
}

#[test]
fn continuous_typing_group_undoes_as_one_edit() {
    let (mut session, object_id) = fixture_session("");
    let first = replace(object_id, 0, 0..0, "a").with_typing_group(TypingGroup {
        id: "typing-1".into(),
        composition_id: None,
        caret_before: 0,
        caret_after: 1,
        composition_boundary: false,
    });
    let first_result = session.submit(first).unwrap();
    let second = replace(object_id, 1, 1..1, "b").with_typing_group(TypingGroup {
        id: "typing-1".into(),
        composition_id: None,
        caret_before: 1,
        caret_after: 2,
        composition_boundary: false,
    });
    let second_result = session.submit(second).unwrap();
    assert_eq!(session.text(object_id).unwrap(), "ab");

    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            second_result.committed_revision,
            EditorCommand::Undo,
        ))
        .unwrap();
    assert_eq!(session.text(object_id).unwrap(), "");
    assert_eq!(first_result.committed_revision.value(), 1);
}

#[test]
fn grapheme_replacement_rebases_selection_by_utf16_length() {
    let (mut session, object_id) = fixture_session("A😀B");
    let result = session.submit(replace(object_id, 0, 1..3, "👩🏽‍💻")).unwrap();
    let rebase = result.selection_rebase.unwrap();
    assert_eq!(rebase.object_id, object_id);
    assert_eq!(rebase.replaced_range, Utf16Range::new(1, 3).unwrap());
    assert_eq!(rebase.inserted_utf16_length, 7);
}

#[test]
fn transaction_replaces_two_objects_and_undoes_them_together() {
    let page_id = PageId::from_source_key("transaction/page/1");
    let first_id = ObjectId::from_source_key("transaction/page/1/text/1");
    let second_id = ObjectId::from_source_key("transaction/page/1/text/2");
    let model = DocumentModel::new(
        DocumentId::from_source_key("transaction"),
        "sha256:transaction".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![
                DocumentObject::text(TextBlock::plain(
                    first_id,
                    page_id,
                    "first",
                    PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
                )),
                DocumentObject::text(TextBlock::plain(
                    second_id,
                    page_id,
                    "second",
                    PdfBox::new(0.0, 30.0, 100.0, 50.0).unwrap(),
                )),
            ],
        )],
    )
    .unwrap();
    let mut session = EditorSessionState::new(SessionId::new(), model);
    let mut command = CommandEnvelope::user(
        CommandId::new(),
        DocumentRevision::INITIAL,
        EditorCommand::ApplyTransaction {
            edits: vec![
                AtomicEdit::ReplaceTextRange {
                    object_id: first_id,
                    range: Utf16Range::new(0, 5).unwrap(),
                    replacement: "FIRST".into(),
                },
                AtomicEdit::ReplaceTextRange {
                    object_id: second_id,
                    range: Utf16Range::new(0, 6).unwrap(),
                    replacement: "SECOND".into(),
                },
            ],
        },
    );
    command.transaction_id = Some("0f8fad5b-d9cb-469f-a165-70867728950e".into());

    let result = session.submit(command).unwrap();

    assert_eq!(result.committed_revision.value(), 1);
    assert_eq!(result.object_patches.len(), 2);
    assert_eq!(session.text(first_id).unwrap(), "FIRST");
    assert_eq!(session.text(second_id).unwrap(), "SECOND");

    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            result.committed_revision,
            EditorCommand::Undo,
        ))
        .unwrap();
    assert_eq!(session.text(first_id).unwrap(), "first");
    assert_eq!(session.text(second_id).unwrap(), "second");
}

#[test]
fn transaction_with_one_invalid_edit_leaves_every_object_unchanged() {
    let (mut session, object_id) = fixture_session("Before");
    let mut command = CommandEnvelope::user(
        CommandId::new(),
        DocumentRevision::INITIAL,
        EditorCommand::ApplyTransaction {
            edits: vec![
                AtomicEdit::ReplaceTextRange {
                    object_id,
                    range: Utf16Range::new(0, 6).unwrap(),
                    replacement: "After".into(),
                },
                AtomicEdit::ReplaceTextRange {
                    object_id,
                    range: Utf16Range::new(7, 7).unwrap(),
                    replacement: "!".into(),
                },
            ],
        },
    );
    command.transaction_id = Some("5f8fad5b-d9cb-469f-a165-70867728950e".into());

    assert!(session.submit(command).is_err());
    assert_eq!(session.revision(), DocumentRevision::INITIAL);
    assert_eq!(session.text(object_id).unwrap(), "Before");
}
