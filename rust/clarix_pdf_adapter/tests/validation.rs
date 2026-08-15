use std::path::PathBuf;

use clarix_pdf_adapter::{IndependentPdfValidator, SourceRef};

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
