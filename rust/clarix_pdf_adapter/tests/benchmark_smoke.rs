use std::path::PathBuf;

use clarix_pdf_adapter::{PdfImporter, PdfOxideImporter, SourceRef};

#[test]
#[ignore = "functional benchmark smoke"]
fn every_generated_corpus_page_has_bounded_objects() {
    let corpus = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/generated");
    let importer = PdfOxideImporter;
    for entry in std::fs::read_dir(corpus).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().and_then(|value| value.to_str()) != Some("pdf")
            || path.file_name().and_then(|value| value.to_str()) == Some("malformed.pdf")
        {
            continue;
        }
        let source = SourceRef::from_path(&path).unwrap();
        let document = importer.inspect_document(&source).unwrap();
        for page_number in 1..=document.page_count {
            let page = importer.inspect_page(&source, page_number).unwrap();
            assert!(page.page.objects.len() <= 10_000, "{}", path.display());
        }
    }
}
