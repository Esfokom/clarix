use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    EditorCommand, EditorSessionState, ObjectId, PageId, PageNode, PdfBox, SearchMode,
    SearchRequest, TextBlock,
};

fn fixture_session() -> (EditorSessionState, ObjectId) {
    let page_id = PageId::from_source_key("replace/page/1");
    let object_id = ObjectId::from_source_key("replace/page/1/text/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("replace"),
        "sha256:replace".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                "draft draft",
                PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (
        EditorSessionState::new(clarix_editing_core::SessionId::new(), model),
        object_id,
    )
}

#[test]
fn approved_replace_all_commits_once_and_undoes_every_match() {
    let (mut session, object_id) = fixture_session();
    let preview = session
        .preview_replace_all(
            SearchRequest {
                query: "draft".into(),
                mode: SearchMode::Exact,
                whole_word: true,
                offset: 0,
                limit: 10,
            },
            "final",
        )
        .unwrap();

    assert_eq!(preview.matches.len(), 2);
    assert_eq!(preview.revision, DocumentRevision::INITIAL);

    let result = session
        .approve_replace_all(&preview.preview_id, CommandId::new(), preview.revision)
        .unwrap();
    assert_eq!(result.committed_revision.value(), 1);
    assert_eq!(result.object_patches.len(), 1);
    assert_eq!(session.text(object_id).unwrap(), "final final");

    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            result.committed_revision,
            EditorCommand::Undo,
        ))
        .unwrap();
    assert_eq!(session.text(object_id).unwrap(), "draft draft");
}

#[test]
fn replace_all_rejects_a_preview_after_an_unrelated_revision_change() {
    let (mut session, object_id) = fixture_session();
    let preview = session
        .preview_replace_all(
            SearchRequest {
                query: "draft".into(),
                mode: SearchMode::Exact,
                whole_word: true,
                offset: 0,
                limit: 10,
            },
            "final",
        )
        .unwrap();
    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            DocumentRevision::INITIAL,
            EditorCommand::ReplaceTextRange {
                object_id,
                range: clarix_editing_core::Utf16Range::new(0, 5).unwrap(),
                replacement: "note".into(),
            },
        ))
        .unwrap();

    assert!(session
        .approve_replace_all(&preview.preview_id, CommandId::new(), preview.revision)
        .is_err());
    assert_eq!(session.text(object_id).unwrap(), "note draft");
}
