use std::path::PathBuf;

use clarix_editing_core::{DocumentObject, EditCapability};
use clarix_pdf_adapter::{PdfImporter, PdfOxideImporter, SourceRef};

fn fixture(name: &str) -> SourceRef {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../test_fixtures/editing_corpus")
        .join(name);
    SourceRef::from_path(path).unwrap()
}

#[test]
fn importer_never_marks_incomplete_font_mapping_editable() {
    let page = PdfOxideImporter
        .inspect_page(&fixture("local/subset-font.pdf"), 1)
        .unwrap();
    let DocumentObject::Text(text) = &page.page.objects[0] else {
        panic!("fixture must contain text")
    };

    assert_eq!(text.capability(), EditCapability::ReadOnly);
    assert_eq!(
        text.capability_reason().unwrap().code,
        "font_encoding_incomplete"
    );
    assert!(text.runs[0].style.font_family.is_some());
    assert!(text.runs[0].style.font_size > 0.0);
    assert!(text.layout.line_height > 0.0);
    assert!(text.layout.horizontal_scale > 0.0);
}

#[test]
fn imported_scene_is_deterministic() {
    let source = fixture("generated/multi-run-text.pdf");
    let first = PdfOxideImporter.inspect_page(&source, 1).unwrap();
    let second = PdfOxideImporter.inspect_page(&source, 1).unwrap();

    assert_eq!(
        serde_json::to_vec(&first).unwrap(),
        serde_json::to_vec(&second).unwrap()
    );
}
