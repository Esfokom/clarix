use std::path::PathBuf;
use std::sync::Arc;

use clarix_pdf_adapter::{
    CleanPatchCache, CleanPatchRenderRequest, CleanPatchRenderer, PdfImporter, PdfOxideImporter,
    SourceRef,
};
use criterion::{black_box, criterion_group, criterion_main, BatchSize, Criterion};

fn clean_patch(c: &mut Criterion) {
    let source = SourceRef::from_path(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../test_fixtures/editing_corpus/generated/standard-latin.pdf"),
    )
    .unwrap();
    let page = PdfOxideImporter.inspect_page(&source, 1).unwrap();
    let object = &page.page.objects[0];
    let request = CleanPatchRenderRequest {
        source,
        page_number: 1,
        source_key: object.source_binding().unwrap().source_key.clone(),
        bounds: object.bounds(),
        dpi: 144,
    };
    c.bench_function("clean_patch/cold/standard_latin/144dpi", |b| {
        b.iter_batched(
            || CleanPatchCache::for_document(Arc::new(CleanPatchRenderer)),
            |cache| cache.get_or_render(black_box(request.clone())).unwrap(),
            BatchSize::SmallInput,
        )
    });

    let warm_cache = CleanPatchCache::for_document(Arc::new(CleanPatchRenderer));
    warm_cache.get_or_render(request.clone()).unwrap();
    c.bench_function("clean_patch/warm/standard_latin/144dpi", |b| {
        b.iter(|| {
            warm_cache
                .get_or_render(black_box(request.clone()))
                .unwrap()
        })
    });
}

criterion_group!(benches, clean_patch);
criterion_main!(benches);
