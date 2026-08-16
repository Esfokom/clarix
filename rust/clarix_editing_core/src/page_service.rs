use std::collections::{HashMap, HashSet};
use std::sync::{
    atomic::{AtomicBool, AtomicU32, Ordering},
    Arc, Condvar, Mutex,
};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    DocumentId, DocumentRevision, ImportedPage, PageImportRequest, PageImportSource,
    PageIndexRepository, PageNode, SourceReference,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum ViewportPriority {
    Background,
    Preload,
    Visible,
    ActiveSelection,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PageImportState {
    Unseen,
    Indexed,
    Warm,
    Visible,
    Cold,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PageSceneRequest {
    pub page_number: u32,
    pub expected_revision: DocumentRevision,
    pub priority: ViewportPriority,
}

impl PageSceneRequest {
    pub const fn visible(page_number: u32, expected_revision: DocumentRevision) -> Self {
        Self {
            page_number,
            expected_revision,
            priority: ViewportPriority::Visible,
        }
    }

    pub const fn background(page_number: u32, expected_revision: DocumentRevision) -> Self {
        Self {
            page_number,
            expected_revision,
            priority: ViewportPriority::Background,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PageScene {
    pub document_id: DocumentId,
    pub revision: DocumentRevision,
    pub page: PageNode,
    pub state: PageImportState,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum PageSceneError {
    #[error("page {requested} is outside 1..={page_count}")]
    PageOutOfRange { requested: u32, page_count: u32 },
    #[error("page request revision is stale")]
    StaleRevision,
    #[error("page import failed: {0}")]
    Import(String),
    #[error("page service synchronization failed")]
    Unavailable,
    #[error("page service concurrency must be greater than zero")]
    InvalidConcurrency,
    #[error("page service resident scene limit must be greater than zero")]
    InvalidResidentLimit,
}

impl PageSceneError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::PageOutOfRange { .. } => "page_out_of_range",
            Self::StaleRevision => "stale_page_scene",
            Self::Import(_) => "page_import_failed",
            Self::Unavailable => "page_service_unavailable",
            Self::InvalidConcurrency => "invalid_page_concurrency",
            Self::InvalidResidentLimit => "invalid_resident_scene_limit",
        }
    }
}

#[derive(Clone)]
struct IndexedPage {
    page: PageNode,
    warnings: Vec<String>,
}

struct ServiceState {
    revision: DocumentRevision,
    active_imports: usize,
    waiters_by_priority: [usize; 4],
    max_observed: usize,
    in_flight: HashSet<u32>,
    scenes: HashMap<u32, PageScene>,
    indexed_pages: HashMap<u32, IndexedPage>,
    page_states: HashMap<u32, PageImportState>,
    scene_access: HashMap<u32, u64>,
    next_access: u64,
    import_counts: HashMap<u32, usize>,
}

impl Default for ServiceState {
    fn default() -> Self {
        Self {
            revision: DocumentRevision::INITIAL,
            active_imports: 0,
            waiters_by_priority: [0; 4],
            max_observed: 0,
            in_flight: HashSet::new(),
            scenes: HashMap::new(),
            indexed_pages: HashMap::new(),
            page_states: HashMap::new(),
            scene_access: HashMap::new(),
            next_access: 0,
            import_counts: HashMap::new(),
        }
    }
}

struct PageSceneServiceInner {
    document_id: DocumentId,
    source: SourceReference,
    page_count: u32,
    max_concurrency: usize,
    max_resident_scenes: usize,
    importer: Arc<dyn PageImportSource>,
    index_repository: Option<Arc<dyn PageIndexRepository>>,
    state: Mutex<ServiceState>,
    changed: Condvar,
    cancelled: AtomicBool,
}

#[derive(Clone)]
pub struct PageSceneService {
    inner: Arc<PageSceneServiceInner>,
}

impl PageSceneService {
    pub fn new(
        document_id: DocumentId,
        source: SourceReference,
        page_count: u32,
        max_concurrency: usize,
        importer: Arc<dyn PageImportSource>,
    ) -> Result<Self, PageSceneError> {
        if max_concurrency == 0 {
            return Err(PageSceneError::InvalidConcurrency);
        }
        Ok(Self {
            inner: Arc::new(PageSceneServiceInner {
                document_id,
                source,
                page_count,
                max_concurrency,
                max_resident_scenes: 8,
                importer,
                index_repository: None,
                state: Mutex::new(ServiceState::default()),
                changed: Condvar::new(),
                cancelled: AtomicBool::new(false),
            }),
        })
    }

    pub fn with_resident_scene_limit(mut self, limit: usize) -> Result<Self, PageSceneError> {
        if limit == 0 {
            return Err(PageSceneError::InvalidResidentLimit);
        }
        Arc::get_mut(&mut self.inner)
            .expect("a newly configured page service is not shared")
            .max_resident_scenes = limit;
        Ok(self)
    }

    pub fn with_index_repository(mut self, repository: Arc<dyn PageIndexRepository>) -> Self {
        Arc::get_mut(&mut self.inner)
            .expect("a newly configured page service is not shared")
            .index_repository = Some(repository);
        self
    }

    pub fn request(&self, request: PageSceneRequest) -> Result<PageScene, PageSceneError> {
        if request.page_number == 0 || request.page_number > self.inner.page_count {
            return Err(PageSceneError::PageOutOfRange {
                requested: request.page_number,
                page_count: self.inner.page_count,
            });
        }

        let mut registered_waiter = None;
        loop {
            let mut state = self
                .inner
                .state
                .lock()
                .map_err(|_| PageSceneError::Unavailable)?;
            if request.expected_revision != state.revision {
                if unregister_waiter(&mut state, &mut registered_waiter) {
                    self.inner.changed.notify_all();
                }
                return Err(PageSceneError::StaleRevision);
            }
            if state.scenes.contains_key(&request.page_number) {
                if unregister_waiter(&mut state, &mut registered_waiter) {
                    self.inner.changed.notify_all();
                }
                touch_scene(&mut state, request.page_number);
                let scene = {
                    let scene = state
                        .scenes
                        .get_mut(&request.page_number)
                        .expect("resident scene was checked above");
                    scene.state = promote_state(scene.state, state_for_priority(request.priority));
                    scene.clone()
                };
                state.page_states.insert(request.page_number, scene.state);
                return Ok(scene);
            }
            if let Some(indexed) = state.indexed_pages.get(&request.page_number).cloned() {
                if unregister_waiter(&mut state, &mut registered_waiter) {
                    self.inner.changed.notify_all();
                }
                let scene = PageScene {
                    document_id: self.inner.document_id,
                    revision: state.revision,
                    page: indexed.page,
                    state: state_for_priority(request.priority),
                    warnings: indexed.warnings,
                };
                state.page_states.insert(request.page_number, scene.state);
                if request.priority != ViewportPriority::Background {
                    insert_resident_scene(
                        &mut state,
                        request.page_number,
                        scene.clone(),
                        self.inner.max_resident_scenes,
                    );
                }
                return Ok(scene);
            }
            if state.in_flight.contains(&request.page_number)
                || state.active_imports >= self.inner.max_concurrency
                || has_higher_priority_waiter(&state, request.priority)
            {
                if registered_waiter.is_none() {
                    state.waiters_by_priority[priority_index(request.priority)] += 1;
                    registered_waiter = Some(request.priority);
                    self.inner.changed.notify_all();
                }
                drop(
                    self.inner
                        .changed
                        .wait(state)
                        .map_err(|_| PageSceneError::Unavailable)?,
                );
                continue;
            }
            unregister_waiter(&mut state, &mut registered_waiter);
            state.in_flight.insert(request.page_number);
            state.active_imports += 1;
            state.max_observed = state.max_observed.max(state.active_imports);
            break;
        }

        let persisted = self
            .inner
            .index_repository
            .as_ref()
            .map(|repository| {
                repository.load_indexed_page(
                    self.inner.document_id,
                    &self.inner.source.fingerprint,
                    request.page_number,
                )
            })
            .transpose()
            .map(|page| page.flatten())
            .map_err(|error| PageSceneError::Import(error.to_string()));
        let (imported, imported_from_source) = match persisted {
            Ok(Some(page)) => (Ok(page), false),
            Ok(None) => (
                self.inner.importer.import_page(PageImportRequest {
                    source: self.inner.source.clone(),
                    page_number: request.page_number,
                }),
                true,
            ),
            Err(error) => (Err(error.to_string()), false),
        };
        let imported = imported.and_then(|page| {
            if imported_from_source {
                if let Some(repository) = &self.inner.index_repository {
                    repository
                        .store_indexed_page(
                            self.inner.document_id,
                            &self.inner.source.fingerprint,
                            &page,
                        )
                        .map_err(|error| error.to_string())?;
                }
            }
            Ok(page)
        });
        let mut state = self
            .inner
            .state
            .lock()
            .map_err(|_| PageSceneError::Unavailable)?;
        state.active_imports -= 1;
        state.in_flight.remove(&request.page_number);
        if imported_from_source {
            *state.import_counts.entry(request.page_number).or_default() += 1;
        }

        let result = match imported {
            Ok(ImportedPage { page, warnings }) if state.revision == request.expected_revision => {
                let scene = PageScene {
                    document_id: self.inner.document_id,
                    revision: state.revision,
                    page,
                    state: state_for_priority(request.priority),
                    warnings,
                };
                state.indexed_pages.insert(
                    request.page_number,
                    IndexedPage {
                        page: scene.page.clone(),
                        warnings: scene.warnings.clone(),
                    },
                );
                state.page_states.insert(request.page_number, scene.state);
                if request.priority != ViewportPriority::Background {
                    insert_resident_scene(
                        &mut state,
                        request.page_number,
                        scene.clone(),
                        self.inner.max_resident_scenes,
                    );
                }
                Ok(scene)
            }
            Ok(_) => Err(PageSceneError::StaleRevision),
            Err(error) => Err(PageSceneError::Import(error)),
        };
        self.inner.changed.notify_all();
        result
    }

    pub fn set_revision(&self, revision: DocumentRevision) {
        if let Ok(mut state) = self.inner.state.lock() {
            state.revision = revision;
            state.scenes.clear();
            state.indexed_pages.clear();
            state.page_states.clear();
            state.scene_access.clear();
            self.inner.changed.notify_all();
        }
    }

    pub fn mark_cold(&self, page_number: u32) {
        if let Ok(mut state) = self.inner.state.lock() {
            state.scenes.remove(&page_number);
            state.scene_access.remove(&page_number);
            if state.indexed_pages.contains_key(&page_number) {
                state.page_states.insert(page_number, PageImportState::Cold);
            }
        }
    }

    pub fn page_state(&self, page_number: u32) -> PageImportState {
        self.inner
            .state
            .lock()
            .ok()
            .and_then(|state| state.page_states.get(&page_number).copied())
            .unwrap_or(PageImportState::Unseen)
    }

    pub fn index_all_pages(&self) -> Result<(), PageSceneError> {
        let next_page = Arc::new(AtomicU32::new(1));
        let errors = Arc::new(Mutex::new(Vec::new()));
        let worker_count = self
            .inner
            .max_concurrency
            .min(self.inner.page_count as usize);
        std::thread::scope(|scope| {
            for _ in 0..worker_count {
                let next_page = Arc::clone(&next_page);
                let errors = Arc::clone(&errors);
                scope.spawn(move || loop {
                    if self.inner.cancelled.load(Ordering::Acquire) {
                        break;
                    }
                    let page_number = next_page.fetch_add(1, Ordering::AcqRel);
                    if page_number > self.inner.page_count {
                        break;
                    }
                    let revision = match self.inner.state.lock() {
                        Ok(state) => state.revision,
                        Err(_) => {
                            if let Ok(mut errors) = errors.lock() {
                                errors.push(PageSceneError::Unavailable);
                            }
                            break;
                        }
                    };
                    if let Err(error) =
                        self.request(PageSceneRequest::background(page_number, revision))
                    {
                        if let Ok(mut errors) = errors.lock() {
                            errors.push(error);
                        }
                    }
                });
            }
        });
        let mut errors = errors.lock().map_err(|_| PageSceneError::Unavailable)?;
        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors.remove(0))
        }
    }

    pub fn start_background_indexing(&self) -> PageIndexTask {
        self.inner.cancelled.store(false, Ordering::Release);
        let service = self.clone();
        let worker = std::thread::Builder::new()
            .name(format!("clarix-page-index-{}", self.inner.document_id))
            .spawn(move || service.index_all_pages())
            .expect("failed to spawn page index worker");
        PageIndexTask {
            service: self.clone(),
            worker: Mutex::new(Some(worker)),
        }
    }

    pub fn max_observed_concurrency(&self) -> usize {
        self.inner
            .state
            .lock()
            .map(|state| state.max_observed)
            .unwrap_or_default()
    }

    pub fn import_count(&self, page_number: u32) -> usize {
        self.inner
            .state
            .lock()
            .ok()
            .and_then(|state| state.import_counts.get(&page_number).copied())
            .unwrap_or_default()
    }

    pub fn resident_scene_count(&self) -> usize {
        self.inner
            .state
            .lock()
            .map(|state| state.scenes.len())
            .unwrap_or_default()
    }

    pub fn indexed_page_count(&self) -> usize {
        self.inner
            .state
            .lock()
            .map(|state| state.indexed_pages.len())
            .unwrap_or_default()
    }

    pub fn in_flight_count(&self) -> usize {
        self.inner
            .state
            .lock()
            .map(|state| state.in_flight.len())
            .unwrap_or_default()
    }
}

pub struct PageIndexTask {
    service: PageSceneService,
    worker: Mutex<Option<std::thread::JoinHandle<Result<(), PageSceneError>>>>,
}

impl PageIndexTask {
    pub fn wait(&self) -> Result<(), PageSceneError> {
        self.join()
    }

    pub fn cancel_and_wait(&self) -> Result<(), PageSceneError> {
        self.service.inner.cancelled.store(true, Ordering::Release);
        self.service.inner.changed.notify_all();
        self.join()
    }

    fn join(&self) -> Result<(), PageSceneError> {
        let worker = self
            .worker
            .lock()
            .map_err(|_| PageSceneError::Unavailable)?
            .take();
        worker.map_or(Ok(()), |worker| {
            worker.join().map_err(|_| PageSceneError::Unavailable)?
        })
    }
}

impl Drop for PageIndexTask {
    fn drop(&mut self) {
        self.service.inner.cancelled.store(true, Ordering::Release);
        self.service.inner.changed.notify_all();
        if let Ok(worker) = self.worker.get_mut() {
            if let Some(worker) = worker.take() {
                let _ = worker.join();
            }
        }
    }
}

fn touch_scene(state: &mut ServiceState, page_number: u32) {
    state.next_access = state.next_access.wrapping_add(1);
    state.scene_access.insert(page_number, state.next_access);
}

fn unregister_waiter(state: &mut ServiceState, registered: &mut Option<ViewportPriority>) -> bool {
    let Some(priority) = registered.take() else {
        return false;
    };
    let index = priority_index(priority);
    state.waiters_by_priority[index] = state.waiters_by_priority[index].saturating_sub(1);
    true
}

fn has_higher_priority_waiter(state: &ServiceState, priority: ViewportPriority) -> bool {
    state.waiters_by_priority[priority_index(priority) + 1..]
        .iter()
        .any(|count| *count > 0)
}

const fn priority_index(priority: ViewportPriority) -> usize {
    match priority {
        ViewportPriority::Background => 0,
        ViewportPriority::Preload => 1,
        ViewportPriority::Visible => 2,
        ViewportPriority::ActiveSelection => 3,
    }
}

fn insert_resident_scene(
    state: &mut ServiceState,
    page_number: u32,
    scene: PageScene,
    limit: usize,
) {
    while state.scenes.len() >= limit && !state.scenes.contains_key(&page_number) {
        let coldest = state
            .scenes
            .iter()
            .filter(|(_, scene)| scene.state != PageImportState::Visible)
            .min_by_key(|(candidate, _)| state.scene_access.get(candidate).copied().unwrap_or(0))
            .map(|(candidate, _)| *candidate);
        let Some(coldest) = coldest else {
            break;
        };
        state.scenes.remove(&coldest);
        state.scene_access.remove(&coldest);
        state.page_states.insert(coldest, PageImportState::Cold);
    }
    state.scenes.insert(page_number, scene);
    touch_scene(state, page_number);
}

fn promote_state(current: PageImportState, requested: PageImportState) -> PageImportState {
    match (current, requested) {
        (PageImportState::Visible, _) | (_, PageImportState::Visible) => PageImportState::Visible,
        (PageImportState::Warm, _) | (_, PageImportState::Warm) => PageImportState::Warm,
        _ => requested,
    }
}

fn state_for_priority(priority: ViewportPriority) -> PageImportState {
    match priority {
        ViewportPriority::ActiveSelection | ViewportPriority::Visible => PageImportState::Visible,
        ViewportPriority::Preload => PageImportState::Warm,
        ViewportPriority::Background => PageImportState::Indexed,
    }
}
