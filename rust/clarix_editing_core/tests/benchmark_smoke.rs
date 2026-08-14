use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, EditorCommand,
    EditorSessionState, ObjectId, PageId, PageNode, PdfBox, SessionId, TextBlock, Utf16Range,
};

fn session() -> (EditorSessionState, ObjectId) {
    let page_id = PageId::from_source_key("benchmark/page/1");
    let object_id = ObjectId::from_source_key("benchmark/page/1/text/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("benchmark"),
        "sha256:benchmark".into(),
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
    (EditorSessionState::new(SessionId::new(), model), object_id)
}

#[test]
#[ignore = "functional benchmark smoke"]
fn one_thousand_replace_undo_pairs_are_stable() {
    let (mut session, object_id) = session();
    for _ in 0..1000 {
        let revision = session.revision();
        session
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
        session
            .submit(CommandEnvelope::user(
                CommandId::new(),
                session.revision(),
                EditorCommand::Undo,
            ))
            .unwrap();
    }
    assert_eq!(session.text(object_id).unwrap(), "A");
    assert_eq!(session.revision().value(), 2000);
}
