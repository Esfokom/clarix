use clarix_editing_core::{
    validate_utf16_range, AffineTransform, DocumentId, DocumentModel, DocumentObject,
    DocumentRevision, ObjectId, ObjectKind, PageId, PageNode, PdfBox, TextBlock, Utf16Range,
};

#[test]
fn ids_revisions_and_utf16_ranges_are_stable() {
    let id = ObjectId::from_source_key("sha256:abc/page:3/object:7");
    assert_eq!(id.to_string().parse::<ObjectId>().unwrap(), id);
    assert_eq!(DocumentRevision::INITIAL.next().unwrap().value(), 1);
    assert!(Utf16Range::new(5, 4).is_err());
    assert!(validate_utf16_range("A😀B", Utf16Range::new(1, 3).unwrap()).is_ok());
    assert!(validate_utf16_range("A😀B", Utf16Range::new(1, 2).unwrap()).is_err());
}

#[test]
fn document_graph_indexes_stable_objects() {
    let page_id = PageId::from_source_key("doc/page/1");
    let object_id = ObjectId::from_source_key("doc/page/1/text/1");
    let block = TextBlock::plain(
        object_id,
        page_id,
        "Hello",
        PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
    );
    let page = PageNode::new(page_id, 1, 612.0, 792.0, vec![DocumentObject::text(block)]);
    let model = DocumentModel::new(
        DocumentId::from_source_key("doc"),
        "source-sha256".into(),
        vec![page],
    )
    .unwrap();
    assert_eq!(model.object(object_id).unwrap().kind(), ObjectKind::Text);
    assert_eq!(AffineTransform::IDENTITY.determinant(), 1.0);
}

#[test]
fn document_graph_rejects_duplicate_object_ids() {
    let page_id = PageId::from_source_key("duplicate/page/1");
    let object_id = ObjectId::from_source_key("duplicate/object");
    let bounds = PdfBox::new(0.0, 0.0, 10.0, 10.0).unwrap();
    let page = PageNode::new(
        page_id,
        1,
        612.0,
        792.0,
        vec![
            DocumentObject::text(TextBlock::plain(object_id, page_id, "one", bounds)),
            DocumentObject::text(TextBlock::plain(object_id, page_id, "two", bounds)),
        ],
    );

    let result = DocumentModel::new(
        DocumentId::from_source_key("duplicate"),
        "sha256:duplicate".into(),
        vec![page],
    );

    assert!(matches!(
        result,
        Err(clarix_editing_core::ModelError::DuplicateObjectId(id)) if id == object_id
    ));
}

#[test]
fn document_json_round_trip_rebuilds_indexes_without_native_state() {
    let page_id = PageId::from_source_key("round-trip/page/1");
    let object_id = ObjectId::from_source_key("round-trip/object/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("round-trip"),
        "sha256:round-trip".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                "Hello 😀",
                PdfBox::new(1.0, 2.0, 30.0, 40.0).unwrap(),
            ))],
        )],
    )
    .unwrap();

    let json = serde_json::to_string(&model).unwrap();
    assert!(json.contains(&object_id.to_string()));
    assert!(json.contains("\"revision\":0"));
    assert!(!json.to_ascii_lowercase().contains("handle"));
    assert!(!json.contains("C:\\"));

    let restored: DocumentModel = serde_json::from_str(&json).unwrap();
    assert_eq!(restored.object(object_id).unwrap().kind(), ObjectKind::Text);
    assert_eq!(restored.revision, DocumentRevision::INITIAL);
}
