use clarix_editing_core::{
    CapabilityReason, CompatibilityReporter, DocumentId, DocumentModel, DocumentObject,
    EditCapability, ObjectId, PageId, PageNode, PdfBox, TextBlock,
};

#[test]
fn report_explains_each_noneditable_object_with_its_stable_identity() {
    let page_id = PageId::from_source_key("compatibility/page/1");
    let object_id = ObjectId::from_source_key("compatibility/page/1/text/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("compatibility"),
        "sha256:compatibility".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(
                TextBlock::plain(
                    object_id,
                    page_id,
                    "read only",
                    PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
                )
                .with_capability(
                    EditCapability::ReadOnly,
                    Some(CapabilityReason {
                        code: "unsupported_layout".into(),
                        message: "This text layout cannot safely round-trip.".into(),
                    }),
                ),
            )],
        )],
    )
    .unwrap();

    let report = CompatibilityReporter::for_document(&model);

    assert_eq!(report.read_only_count, 1);
    assert_eq!(report.issues.len(), 1);
    assert_eq!(report.issues[0].object_id, object_id);
    assert_eq!(report.issues[0].page_id, page_id);
    assert_eq!(report.issues[0].code, "unsupported_layout");
    assert_eq!(report.issues[0].supported_operations, vec!["search"]);
}
