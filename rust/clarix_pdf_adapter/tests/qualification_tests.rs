use std::path::PathBuf;

use clarix_pdf_adapter::{CapabilityStatus, PdfImporter, PdfOxideImporter, SourceRef};

fn corpus_file(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/generated")
        .join(name)
}

#[test]
fn pdf_oxide_import_is_deterministic_and_read_only() {
    let fixture = corpus_file("standard-latin.pdf");
    let source = SourceRef::from_path(&fixture).unwrap();
    let importer = PdfOxideImporter;
    let first = importer.inspect_page(&source, 1).unwrap();
    let second = importer.inspect_page(&source, 1).unwrap();
    assert_eq!(first.page, second.page);
    assert_eq!(first.report.import, CapabilityStatus::Supported);
    assert!(matches!(
        first.report.clean_patch,
        CapabilityStatus::Unsupported(_)
    ));
    assert!(matches!(
        first.report.materialization,
        CapabilityStatus::Unsupported(_)
    ));
    assert!(matches!(
        first.report.validation,
        CapabilityStatus::Unsupported(_)
    ));
    assert!(!first.page.objects.is_empty());
}

#[test]
fn malformed_input_has_stable_error_code() {
    let source = SourceRef::from_path(corpus_file("malformed.pdf")).unwrap();
    let error = PdfOxideImporter.inspect_document(&source).unwrap_err();
    assert_eq!(error.code(), "invalid_pdf");
}

#[test]
fn out_of_range_page_has_stable_error_code() {
    let source = SourceRef::from_path(corpus_file("standard-latin.pdf")).unwrap();
    let error = PdfOxideImporter.inspect_page(&source, 2).unwrap_err();
    assert_eq!(error.code(), "page_out_of_range");
}

#[test]
fn every_generated_valid_case_is_repeatable_and_matches_manifest_hash() {
    let manifest_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/manifest.json");
    let manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(manifest_path).unwrap()).unwrap();
    let cases = manifest["cases"].as_array().unwrap();
    let importer = PdfOxideImporter;

    for case in cases {
        let relative_path = case["path"].as_str().unwrap();
        if !relative_path.starts_with("generated/") || case.get("expectedError").is_some() {
            continue;
        }
        let source = SourceRef::from_path(
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../..")
                .join("test_fixtures/editing_corpus")
                .join(relative_path),
        )
        .unwrap();
        assert_eq!(source.fingerprint(), case["sha256"].as_str().unwrap());
        let document = importer.inspect_document(&source).unwrap();
        assert_eq!(
            document.page_count,
            case["expectedPages"].as_u64().unwrap() as u32
        );
        let first = importer.inspect_page(&source, 1).unwrap();
        let second = importer.inspect_page(&source, 1).unwrap();
        assert_eq!(first.page, second.page, "case {relative_path}");
        assert_eq!(first.report, second.report, "case {relative_path}");
    }
}

#[test]
fn private_font_cases_are_qualified_when_present() {
    let local = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/local");
    if !local.exists() {
        return;
    }
    for name in ["embedded-truetype.pdf", "subset-font.pdf"] {
        let source = SourceRef::from_path(local.join(name)).unwrap();
        let page = PdfOxideImporter.inspect_page(&source, 1).unwrap();
        assert!(!page.page.objects.is_empty(), "private case {name}");
    }
    assert!(
        std::fs::metadata(local.join("subset-font.pdf"))
            .unwrap()
            .len()
            < std::fs::metadata(local.join("embedded-truetype.pdf"))
                .unwrap()
                .len()
    );
}

#[test]
fn source_fingerprint_mismatch_is_rejected_before_import() {
    let path = corpus_file("standard-latin.pdf");
    let source = SourceRef::new("wrong-fingerprint", path);
    let error = PdfOxideImporter.inspect_document(&source).unwrap_err();
    assert_eq!(error.code(), "fingerprint_mismatch");
}
