use std::path::PathBuf;

use clarix_editing_core::{AtomicReplaceRequest, AtomicReplacementPort, DocumentId, DocumentModel};
use clarix_pdf_adapter::{
    IndependentPdfValidator, PdfImporter, PdfOxideImporter, PdfTextMaterializer, SourceRef,
    WindowsAtomicReplacer,
};
use criterion::{black_box, criterion_group, criterion_main, BatchSize, Criterion};

fn source() -> SourceRef {
    SourceRef::from_path(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../test_fixtures/editing_corpus/generated/standard-latin.pdf"),
    )
    .unwrap()
}

fn snapshot(source: &SourceRef) -> DocumentModel {
    let imported = PdfOxideImporter.inspect_page(source, 1).unwrap();
    DocumentModel::new(
        DocumentId::from_source_key("save-latency"),
        source.fingerprint().into(),
        vec![imported.page],
    )
    .unwrap()
}

fn save_latency(c: &mut Criterion) {
    let source = source();
    let snapshot = snapshot(&source);
    let materializer = PdfTextMaterializer::new(source.clone());
    c.bench_function("save/materialization", |b| {
        b.iter_batched(
            || {
                let directory = tempfile::tempdir().unwrap();
                let output = directory.path().join("materialized.pdf");
                (directory, output)
            },
            |(_directory, output)| {
                black_box(
                    materializer
                        .materialize_snapshot(black_box(&snapshot), &output)
                        .unwrap(),
                )
            },
            BatchSize::SmallInput,
        )
    });

    let validation_directory = tempfile::tempdir().unwrap();
    let validation_output = validation_directory.path().join("validation.pdf");
    materializer
        .materialize_snapshot(&snapshot, &validation_output)
        .unwrap();
    c.bench_function("save/independent_validation", |b| {
        b.iter(|| {
            black_box(
                IndependentPdfValidator
                    .validate_document(black_box(&validation_output), 1)
                    .unwrap(),
            )
        })
    });

    c.bench_function("save/atomic_move_setup", |b| {
        b.iter_batched(
            || {
                let directory = tempfile::tempdir().unwrap();
                let working = directory.path().join(".output.working.pdf");
                let target = directory.path().join("output.pdf");
                std::fs::copy(&validation_output, &working).unwrap();
                (directory, working, target)
            },
            |(_directory, working, target)| {
                WindowsAtomicReplacer
                    .replace(AtomicReplaceRequest {
                        working,
                        target,
                        backup: None,
                        replace_existing: false,
                    })
                    .unwrap()
            },
            BatchSize::SmallInput,
        )
    });
}

criterion_group!(benches, save_latency);
criterion_main!(benches);
