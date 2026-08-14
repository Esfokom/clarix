use std::path::PathBuf;

use clarix_pdf_adapter::{PdfImporter, PdfOxideImporter, SourceRef};
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn valid_fixtures() -> Vec<PathBuf> {
    let corpus = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/generated");
    let mut fixtures: Vec<_> = std::fs::read_dir(corpus)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| {
            path.extension().and_then(|value| value.to_str()) == Some("pdf")
                && path.file_name().and_then(|value| value.to_str()) != Some("malformed.pdf")
        })
        .collect();
    fixtures.sort();
    fixtures
}

fn page_inspection(c: &mut Criterion) {
    let importer = PdfOxideImporter;
    let mut group = c.benchmark_group("page_inspection");
    for path in valid_fixtures() {
        let source = SourceRef::from_path(&path).unwrap();
        let document = importer.inspect_document(&source).unwrap();
        for page_number in 1..=document.page_count {
            let name = format!(
                "{}/page_{}",
                path.file_stem().unwrap().to_string_lossy(),
                page_number
            );
            group.bench_function(name, |b| {
                b.iter(|| {
                    black_box(
                        importer
                            .inspect_page(black_box(&source), page_number)
                            .unwrap(),
                    )
                })
            });
        }
    }
    group.finish();
}

criterion_group!(benches, page_inspection);
criterion_main!(benches);
