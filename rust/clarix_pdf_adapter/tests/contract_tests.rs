use clarix_editing_core::{DocumentObject, ObjectId, PageId, PageNode, PdfBox, TextBlock};
use clarix_pdf_adapter::{
    CapabilityReport, CapabilityStatus, DocumentImport, PageImport, PdfAdapterError, PdfImporter,
    SourceRef,
};

struct FakeImporter;

impl FakeImporter {
    fn one_text_page(_text: &str) -> Self {
        Self
    }
}

impl PdfImporter for FakeImporter {
    fn adapter_id(&self) -> &'static str {
        "fake/1"
    }

    fn inspect_document(&self, source: &SourceRef) -> Result<DocumentImport, PdfAdapterError> {
        Ok(DocumentImport {
            source_fingerprint: source.fingerprint().to_owned(),
            page_count: 1,
            report: CapabilityReport::read_only(self.adapter_id()),
        })
    }

    fn inspect_page(
        &self,
        source: &SourceRef,
        page_number: u32,
    ) -> Result<PageImport, PdfAdapterError> {
        let page_id = PageId::from_source_key(&format!("{}/page/1", source.fingerprint()));
        let object_id =
            ObjectId::from_source_key(&format!("{}/page/1/text/1", source.fingerprint()));
        Ok(PageImport {
            page: PageNode::new(
                page_id,
                page_number,
                612.0,
                792.0,
                vec![DocumentObject::text(TextBlock::plain(
                    object_id,
                    page_id,
                    "Hello",
                    PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
                ))],
            ),
            report: CapabilityReport::read_only(self.adapter_id()),
            warnings: Vec::new(),
        })
    }
}

#[test]
fn capabilities_report_each_operation_independently() {
    let report = CapabilityReport::new("fake/1")
        .with_import(CapabilityStatus::Supported)
        .with_clean_patch(CapabilityStatus::Unsupported("not implemented".into()))
        .with_materialization(CapabilityStatus::Unsupported("not implemented".into()))
        .with_validation(CapabilityStatus::Supported);
    assert!(report.import.is_supported());
    assert!(!report.materialization.is_supported());
}

#[test]
fn importer_returns_stable_objects_without_native_handles() {
    let importer = FakeImporter::one_text_page("Hello");
    let source = SourceRef::new("hash", "fixture.pdf");
    let first = importer.inspect_page(&source, 1).unwrap();
    let second = importer.inspect_page(&source, 1).unwrap();
    assert_eq!(first.page, second.page);

    let json = serde_json::to_string(&first.page).unwrap();
    assert!(!json.to_ascii_lowercase().contains("handle"));
    assert!(!json.contains("fixture.pdf"));
}
