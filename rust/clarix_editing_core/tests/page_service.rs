use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc, Condvar, Mutex,
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
    assert_eq!(service.resident_scene_count(), 0);
    assert_eq!(service.indexed_page_count(), 1_000);
    assert_eq!(service.in_flight_count(), 0);
    for page_number in 1..=1_000 {
        assert_eq!(service.import_count(page_number), 1);
    }
}

#[test]
fn cold_page_releases_its_scene_and_reuses_indexed_metadata() {
    let importer = Arc::new(FixtureImporter::default());
    let service = service(importer);
    service
        .request(PageSceneRequest::visible(7, DocumentRevision::INITIAL))
        .unwrap();
    assert_eq!(service.resident_scene_count(), 1);

    service.mark_cold(7);

    assert_eq!(service.page_state(7), PageImportState::Cold);
    assert_eq!(service.resident_scene_count(), 0);
    let scene = service
        .request(PageSceneRequest::visible(7, DocumentRevision::INITIAL))
        .unwrap();
    assert_eq!(scene.page.page_number, 7);
    assert_eq!(service.import_count(7), 1);
}

#[test]
fn warm_scene_residency_obeys_the_configured_limit() {
    let importer = Arc::new(FixtureImporter::default());
    let service = service(importer).with_resident_scene_limit(5).unwrap();

    for page_number in 1..=20 {
        service
            .request(PageSceneRequest {
                page_number,
                expected_revision: DocumentRevision::INITIAL,
                priority: clarix_editing_core::ViewportPriority::Preload,
            })
            .unwrap();
    }

    assert_eq!(service.resident_scene_count(), 5);
    assert_eq!(service.indexed_page_count(), 20);
}

#[test]
fn critical_memory_pressure_evicts_warm_scenes_but_retains_visible_scenes() {
    let importer = Arc::new(FixtureImporter::default());
    let service = service(importer).with_resident_scene_limit(5).unwrap();
    service
        .request(PageSceneRequest::visible(1, DocumentRevision::INITIAL))
        .unwrap();
    for page_number in 2..=4 {
        service
            .request(PageSceneRequest {
                page_number,
                expected_revision: DocumentRevision::INITIAL,
                priority: clarix_editing_core::ViewportPriority::Preload,
            })
            .unwrap();
    }

    service.report_memory_pressure(clarix_editing_core::MemoryPressureLevel::Critical);

    assert_eq!(service.resident_scene_count(), 1);
    assert_eq!(service.page_state(1), PageImportState::Visible);
    for page_number in 2..=4 {
        assert_eq!(service.page_state(page_number), PageImportState::Cold);
    }
}

#[test]
fn background_task_indexes_pages_without_widget_requests() {
    let importer = Arc::new(FixtureImporter::default());
    let service = PageSceneService::new(
        DocumentId::from_source_key("background-task-document"),
        SourceReference::new("sha256:background-task", "background-task.pdf"),
        25,
        2,
        importer.clone(),
    )
    .unwrap();

    let task = service.start_background_indexing();
    task.wait().unwrap();

    assert_eq!(service.indexed_page_count(), 25);
    assert_eq!(service.resident_scene_count(), 0);
    assert!(importer.max_active.load(Ordering::Acquire) <= 2);
}

struct PriorityImporter {
    order: Mutex<Vec<u32>>,
    first_started: (Mutex<bool>, Condvar),
    release_first: (Mutex<bool>, Condvar),
}

impl PriorityImporter {
    fn new() -> Self {
        Self {
            order: Mutex::new(Vec::new()),
            first_started: (Mutex::new(false), Condvar::new()),
            release_first: (Mutex::new(false), Condvar::new()),
        }
    }

    fn wait_for_first(&self) {
        let (started, changed) = &self.first_started;
        let started = started.lock().unwrap();
        drop(changed.wait_while(started, |started| !*started).unwrap());
    }

    fn release_first(&self) {
        *self.release_first.0.lock().unwrap() = true;
        self.release_first.1.notify_all();
    }
}

impl PageImportSource for PriorityImporter {
    fn import_page(&self, request: PageImportRequest) -> Result<ImportedPage, String> {
        self.order.lock().unwrap().push(request.page_number);
        if request.page_number == 1 {
            *self.first_started.0.lock().unwrap() = true;
            self.first_started.1.notify_all();
            let released = self.release_first.0.lock().unwrap();
            drop(
                self.release_first
                    .1
                    .wait_while(released, |released| !*released)
                    .unwrap(),
            );
        }
        Ok(ImportedPage {
            page: PageNode::new(
                PageId::from_source_key(&format!("priority/page/{}", request.page_number)),
                request.page_number,
                612.0,
                792.0,
                Vec::new(),
            ),
            warnings: Vec::new(),
        })
    }
}

#[test]
fn visible_request_gets_the_next_slot_ahead_of_background_indexing() {
    let importer = Arc::new(PriorityImporter::new());
    let service = Arc::new(
        PageSceneService::new(
            DocumentId::from_source_key("priority-document"),
            SourceReference::new("sha256:priority", "priority.pdf"),
            4,
            1,
            importer.clone(),
        )
        .unwrap(),
    );
    let task = service.start_background_indexing();
    importer.wait_for_first();
    let visible_service = service.clone();
    let visible = std::thread::spawn(move || {
        visible_service
            .request(PageSceneRequest::visible(4, DocumentRevision::INITIAL))
            .unwrap()
    });
    std::thread::sleep(Duration::from_millis(20));
    importer.release_first();
    visible.join().unwrap();
    task.wait().unwrap();

    let order = importer.order.lock().unwrap().clone();
    assert_eq!(order[0], 1);
    assert_eq!(order[1], 4, "import order was {order:?}");
}

#[test]
fn queued_imports_follow_active_visible_preload_background_priority() {
    let importer = Arc::new(PriorityImporter::new());
    let service = Arc::new(
        PageSceneService::new(
            DocumentId::from_source_key("full-priority-document"),
            SourceReference::new("sha256:full-priority", "full-priority.pdf"),
            4,
            1,
            importer.clone(),
        )
        .unwrap(),
    );
    let background_service = service.clone();
    let background = std::thread::spawn(move || {
        background_service
            .request(PageSceneRequest::background(1, DocumentRevision::INITIAL))
            .unwrap()
    });
    importer.wait_for_first();
    let mut requests = Vec::new();
    for (page_number, priority) in [
        (2, clarix_editing_core::ViewportPriority::Preload),
        (3, clarix_editing_core::ViewportPriority::Visible),
        (4, clarix_editing_core::ViewportPriority::ActiveSelection),
    ] {
        let service = service.clone();
        requests.push(std::thread::spawn(move || {
            service
                .request(PageSceneRequest {
                    page_number,
                    expected_revision: DocumentRevision::INITIAL,
                    priority,
                })
                .unwrap()
        }));
        std::thread::sleep(Duration::from_millis(10));
    }
    importer.release_first();
    background.join().unwrap();
    for request in requests {
        request.join().unwrap();
    }

    let order = importer.order.lock().unwrap().clone();
    assert_eq!(order, vec![1, 4, 3, 2]);
}
