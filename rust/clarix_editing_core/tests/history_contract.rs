use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    EditorCommand, EditorSessionState, InverseOperation, ObjectId, PageId, PageNode,
    ParagraphStyle, PdfBox, SessionId, TextAlignment, TextBlock, TypingGroup, Utf16Range,
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
