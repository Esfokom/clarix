use std::sync::Arc;

use clarix_editing_core::{
    DocumentId, DocumentRevision, ImportedPage, PageId, PageImportRequest, PageImportSource,
    PageNode, PageSceneRequest, PageSceneService, SourceReference,
};
use criterion::{black_box, criterion_group, criterion_main, BatchSize, Criterion};

#[derive(Default)]
struct FixtureImporter;

impl PageImportSource for FixtureImporter {
    fn import_page(&self, request: PageImportRequest) -> Result<ImportedPage, String> {
        Ok(ImportedPage {
            page: PageNode::new(
                PageId::from_source_key(&format!("page/{}", request.page_number)),
                request.page_number,
                612.0,
                792.0,
                Vec::new(),
            ),
            warnings: Vec::new(),
        })
    }
}

fn service() -> PageSceneService {
    PageSceneService::new(
        DocumentId::from_source_key("page-scene-latency"),
        SourceReference::new("sha256:page-scene-latency", "fixture.pdf"),
        1,
        2,
        Arc::new(FixtureImporter),
    )
    .unwrap()
}

fn page_scene_latency(c: &mut Criterion) {
    c.bench_function("page_scene/unindexed_visible", |b| {
        b.iter_batched(
            service,
            |service| {
                black_box(
                    service
                        .request(PageSceneRequest::visible(1, DocumentRevision::INITIAL))
                        .unwrap(),
                )
            },
            BatchSize::SmallInput,
        )
    });

    let indexed = service();
    indexed
        .request(PageSceneRequest::background(1, DocumentRevision::INITIAL))
        .unwrap();
    c.bench_function("page_scene/indexed_visible", |b| {
        b.iter(|| {
            indexed.mark_cold(1);
            black_box(
                indexed
                    .request(PageSceneRequest::visible(1, DocumentRevision::INITIAL))
                    .unwrap(),
            )
        })
    });
}

criterion_group!(benches, page_scene_latency);
criterion_main!(benches);
