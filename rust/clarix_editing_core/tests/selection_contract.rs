use clarix_editing_core::{
    DocumentId, DocumentModel, DocumentObject, DocumentRevision, EditorSessionState, ObjectId,
    PageId, PageNode, PdfBox, SelectionKind, SelectionSet, SessionId, TextBlock, TextRangeRef,
};

fn fixture_session() -> (EditorSessionState, ObjectId, PageId) {
    let page_id = PageId::from_source_key("selection/page/1");
    let object_id = ObjectId::from_source_key("selection/page/1/text/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("selection"),
        "sha256:selection".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                "hello world",
                PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (
        EditorSessionState::new(SessionId::new(), model),
        object_id,
        page_id,
    )
}

#[test]
fn selection_validation_merges_adjacent_ranges_and_refreshes_the_quote() {
    let (session, object_id, page_id) = fixture_session();

    let selection = session
        .validate_selection(SelectionSet {
            revision: DocumentRevision::INITIAL,
            kind: SelectionKind::TextRanges,
            ranges: vec![
                TextRangeRef {
                    object_id,
                    page_id,
                    page_number: 1,
                    start_utf16: 5,
                    end_utf16: 6,
                    quoted_text: " ".into(),
                },
                TextRangeRef {
                    object_id,
                    page_id,
                    page_number: 1,
                    start_utf16: 0,
                    end_utf16: 5,
                    quoted_text: "hello".into(),
                },
            ],
            object_ids: vec![],
            primary_index: Some(1),
        })
        .unwrap();

    assert_eq!(selection.ranges.len(), 1);
    assert_eq!(selection.ranges[0].start_utf16, 0);
    assert_eq!(selection.ranges[0].end_utf16, 6);
    assert_eq!(selection.ranges[0].quoted_text, "hello ");
    assert_eq!(selection.primary_index, Some(0));
}

#[test]
fn selection_validation_rejects_a_stale_quoted_range() {
    let (session, object_id, page_id) = fixture_session();

    let result = session.validate_selection(SelectionSet {
        revision: DocumentRevision::INITIAL,
        kind: SelectionKind::TextRanges,
        ranges: vec![TextRangeRef {
            object_id,
            page_id,
            page_number: 1,
            start_utf16: 0,
            end_utf16: 5,
            quoted_text: "other".into(),
        }],
        object_ids: vec![],
        primary_index: Some(0),
    });

    assert!(result.is_err());
}
