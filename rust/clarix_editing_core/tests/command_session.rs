use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    EditorCommand, EditorSessionState, ObjectId, PageId, PageNode, PdfBox, SessionId, TextBlock,
    Utf16Range,
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
            vec![DocumentObject::Text(TextBlock::plain(
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
