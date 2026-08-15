use std::path::PathBuf;

use clarix_pdf_adapter::{
    CleanPatchBackend, CleanPatchRenderRequest, CleanPatchRenderer, PdfImporter, PdfOxideImporter,
    SourceRef,
};
use criterion::{black_box, criterion_group, criterion_main, Criterion};

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
    c.bench_function("clean_patch/standard_latin/144dpi", |b| {
        b.iter(|| {
            CleanPatchRenderer
                .render(black_box(request.clone()))
                .unwrap()
        })
    });
}

criterion_group!(benches, clean_patch);
criterion_main!(benches);
