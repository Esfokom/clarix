use clarix_editing_core::{
    DocumentId, DocumentModel, DocumentObject, DocumentRevision, ObjectId, PageId, PageNode,
    PdfBox, SearchIndex, SearchMode, SearchRequest, TextBlock,
};

fn fixture_index() -> SearchIndex {
    let first_page = PageId::from_source_key("search/page/1");
    let second_page = PageId::from_source_key("search/page/2");
    let model = DocumentModel::new(
        DocumentId::from_source_key("search"),
        "sha256:search".into(),
        vec![
            PageNode::new(
                first_page,
                1,
                612.0,
                792.0,
                vec![DocumentObject::text(TextBlock::plain(
                    ObjectId::from_source_key("search/page/1/text/1"),
                    first_page,
                    "Caf\u{00e9} cafe CAF\u{00c9}",
                    PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
                ))],
            ),
            PageNode::new(
                second_page,
                2,
                612.0,
                792.0,
                vec![DocumentObject::text(TextBlock::plain(
                    ObjectId::from_source_key("search/page/2/text/1"),
                    second_page,
                    "cafe-42 cafe42",
                    PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
                ))],
            ),
        ],
    )
    .unwrap();
    SearchIndex::from_document(&model)
}

#[test]
fn normalized_search_returns_stable_ranges_in_page_and_offset_order() {
    let index = fixture_index();

    let page = index
        .search(SearchRequest {
            query: "CAF\u{00c9}".into(),
            mode: SearchMode::Normalized,
            whole_word: true,
            offset: 0,
            limit: 10,
        })
        .unwrap();

    assert_eq!(page.revision, DocumentRevision::INITIAL);
    assert_eq!(page.total_matches, 2);
    assert_eq!(page.matches.len(), 2);
    assert_eq!(page.matches[0].page_number, 1);
    assert_eq!(page.matches[0].start_utf16, 0);
    assert_eq!(page.matches[1].page_number, 1);
    assert_eq!(page.matches[1].start_utf16, 10);
}

#[test]
fn regex_search_honors_unicode_word_boundaries_and_pagination() {
    let index = fixture_index();

    let first_page = index
        .search(SearchRequest {
            query: r"cafe\d*".into(),
            mode: SearchMode::Regex,
            whole_word: true,
            offset: 0,
            limit: 1,
        })
        .unwrap();
    let third_page = index
        .search(SearchRequest {
            query: r"cafe\d*".into(),
            mode: SearchMode::Regex,
            whole_word: true,
            offset: 2,
            limit: 1,
        })
        .unwrap();

    assert_eq!(first_page.total_matches, 3);
    assert_eq!(first_page.matches[0].quoted_text, "cafe");
    assert_eq!(third_page.matches[0].quoted_text, "cafe42");
}
