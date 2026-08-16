use std::path::PathBuf;

use clarix_editing_core::DocumentObject;
use clarix_pdf_adapter::{IndependentPdfValidator, PdfImporter, PdfOxideImporter, SourceRef};

fn fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../test_fixtures/editing_corpus/generated/standard-latin.pdf")
}

#[test]
fn validator_accepts_a_readable_source_with_expected_page_count() {
    let report = IndependentPdfValidator
        .validate_document(&fixture(), 1)
        .unwrap();
    assert!(report.valid);
    assert!(report.failures.is_empty());
}

#[test]
fn validator_rejects_tampered_output_independently() {
    let directory = tempfile::tempdir().unwrap();
    let tampered = directory.path().join("tampered.pdf");
    std::fs::write(&tampered, b"not a pdf").unwrap();

    let report = IndependentPdfValidator
        .validate_document(&tampered, 1)
        .unwrap();

    assert!(!report.valid);
    assert!(report
        .failures
        .iter()
        .any(|failure| failure.code == "pdf_unreadable"));
    assert!(SourceRef::from_path(tampered).is_ok());
}

#[test]
#[ignore = "requires CLARIX_PHASE1_SAVED_PDF and expected text evidence"]
fn phase1_saved_pdf_is_searchable_extractable_and_old_text_is_absent() {
    let path = PathBuf::from(std::env::var("CLARIX_PHASE1_SAVED_PDF").unwrap());
    let expected = std::env::var("CLARIX_PHASE1_EXPECTED_TEXT").unwrap();
    let old = std::env::var("CLARIX_PHASE1_OLD_TEXT").ok();
    let document = pdf_oxide::PdfDocument::open(&path).unwrap();
    let page_count = document.page_count().unwrap() as u32;
    let report = IndependentPdfValidator
        .validate_document(&path, page_count)
        .unwrap();
    assert!(report.valid, "{:?}", report.failures);

    let source = SourceRef::from_path(path).unwrap();
    let mut extracted = String::new();
    let mut matching_bounds = Vec::new();
    for page_number in 1..=page_count {
        let page = PdfOxideImporter.inspect_page(&source, page_number).unwrap();
        for object in page.page.objects {
            let bounds = object.bounds();
            if let DocumentObject::Text(text) = object {
                if text.text.contains(&expected) {
                    matching_bounds.push(bounds);
                }
                extracted.push_str(&text.text);
                extracted.push('\n');
            }
        }
    }

    assert!(
        extracted.contains(&expected),
        "expected text was not extractable"
    );
    assert!(
        !matching_bounds.is_empty(),
        "expected text had no selectable geometry"
    );
    assert!(matching_bounds.iter().all(|bounds| {
        bounds.right > bounds.left
            && bounds.top > bounds.bottom
            && [bounds.left, bounds.bottom, bounds.right, bounds.top]
                .into_iter()
                .all(f64::is_finite)
    }));
    if let Some(old) = old.filter(|value| !value.is_empty()) {
        assert!(!extracted.contains(&old), "old text remains extractable");
    }
}
