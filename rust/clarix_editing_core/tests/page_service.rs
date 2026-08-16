use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
use std::time::Duration;

use clarix_editing_core::{
    DocumentId, DocumentRevision, ImportedPage, PageId, PageImportRequest, PageImportSource,
    PageImportState, PageNode, PageSceneRequest, PageSceneService, SourceReference,
};

#[derive(Default)]
struct FixtureImporter {
    active: AtomicUsize,
    max_active: AtomicUsize,
}

impl PageImportSource for FixtureImporter {
    fn import_page(&self, request: PageImportRequest) -> Result<ImportedPage, String> {
        let active = self.active.fetch_add(1, Ordering::AcqRel) + 1;
        self.max_active.fetch_max(active, Ordering::AcqRel);
        std::thread::sleep(Duration::from_millis(5));
        self.active.fetch_sub(1, Ordering::AcqRel);
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

fn service(importer: Arc<FixtureImporter>) -> PageSceneService {
    PageSceneService::new(
        DocumentId::from_source_key("large-document"),
        SourceReference::new("sha256:large", "large.pdf"),
        500,
        2,
        importer,
    )
    .unwrap()
}

#[test]
fn visiting_page_137_publishes_its_scene_even_when_background_index_is_behind() {
    let importer = Arc::new(FixtureImporter::default());
    let service = service(importer);

    let scene = service
        .request(PageSceneRequest::visible(137, DocumentRevision::INITIAL))
        .unwrap();

    assert_eq!(scene.page.page_number, 137);
    assert_eq!(scene.state, PageImportState::Visible);
    assert!(service.max_observed_concurrency() <= 2);
}

#[test]
fn concurrent_visible_requests_are_deduplicated_and_bounded() {
    let importer = Arc::new(FixtureImporter::default());
    let service = Arc::new(service(importer.clone()));
    let mut workers = Vec::new();
    for page_number in [8, 8, 9, 10, 11, 12] {
        let service = service.clone();
        workers.push(std::thread::spawn(move || {
            service
                .request(PageSceneRequest::visible(
                    page_number,
                    DocumentRevision::INITIAL,
                ))
                .unwrap()
        }));
    }
    for worker in workers {
        worker.join().unwrap();
    }

    assert!(importer.max_active.load(Ordering::Acquire) <= 2);
    assert_eq!(service.import_count(8), 1);
}

#[test]
fn stale_revision_is_rejected_before_publication() {
    let service = service(Arc::new(FixtureImporter::default()));
    service.set_revision(DocumentRevision::INITIAL.next().unwrap());

    let error = service
        .request(PageSceneRequest::visible(1, DocumentRevision::INITIAL))
        .unwrap_err();

    assert_eq!(error.code(), "stale_page_scene");
}

#[test]
fn background_indexing_visits_every_page_with_the_same_bound() {
    let importer = Arc::new(FixtureImporter::default());
    let service = PageSceneService::new(
        DocumentId::from_source_key("background-document"),
        SourceReference::new("sha256:background", "background.pdf"),
        25,
        2,
        importer.clone(),
    )
    .unwrap();

    service.index_all_pages().unwrap();

    assert!(importer.max_active.load(Ordering::Acquire) <= 2);
    for page_number in 1..=25 {
        assert_eq!(service.import_count(page_number), 1);
        assert_eq!(service.page_state(page_number), PageImportState::Indexed);
    }
}

#[test]
fn thousand_page_visit_order_keeps_two_worker_bound_and_reports_residency() {
    let importer = Arc::new(FixtureImporter::default());
    let service = PageSceneService::new(
        DocumentId::from_source_key("thousand-page-document"),
        SourceReference::new("sha256:thousand", "thousand.pdf"),
        1_000,
        2,
        importer.clone(),
    )
    .unwrap();

    service.index_all_pages().unwrap();

    assert!(importer.max_active.load(Ordering::Acquire) <= 2);
    assert_eq!(service.resident_scene_count(), 1_000);
    assert_eq!(service.in_flight_count(), 0);
    for page_number in 1..=1_000 {
        assert_eq!(service.import_count(page_number), 1);
    }
}
