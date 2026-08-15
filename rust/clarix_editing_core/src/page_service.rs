use std::collections::{HashMap, HashSet};
use std::sync::{
    atomic::{AtomicU32, Ordering},
    Arc, Condvar, Mutex,
};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    DocumentId, DocumentRevision, ImportedPage, PageImportRequest, PageImportSource, PageNode,
    SourceReference,
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
}

impl PageSceneError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::PageOutOfRange { .. } => "page_out_of_range",
            Self::StaleRevision => "stale_page_scene",
            Self::Import(_) => "page_import_failed",
            Self::Unavailable => "page_service_unavailable",
            Self::InvalidConcurrency => "invalid_page_concurrency",
        }
    }
}

struct ServiceState {
    revision: DocumentRevision,
    active_imports: usize,
    max_observed: usize,
    in_flight: HashSet<u32>,
    scenes: HashMap<u32, PageScene>,
    import_counts: HashMap<u32, usize>,
}

impl Default for ServiceState {
    fn default() -> Self {
        Self {
            revision: DocumentRevision::INITIAL,
            active_imports: 0,
            max_observed: 0,
            in_flight: HashSet::new(),
            scenes: HashMap::new(),
            import_counts: HashMap::new(),
        }
    }
}

struct PageSceneServiceInner {
    document_id: DocumentId,
    source: SourceReference,
    page_count: u32,
    max_concurrency: usize,
    importer: Arc<dyn PageImportSource>,
    state: Mutex<ServiceState>,
    changed: Condvar,
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
                importer,
                state: Mutex::new(ServiceState::default()),
                changed: Condvar::new(),
            }),
        })
    }

    pub fn request(&self, request: PageSceneRequest) -> Result<PageScene, PageSceneError> {
        if request.page_number == 0 || request.page_number > self.inner.page_count {
            return Err(PageSceneError::PageOutOfRange {
                requested: request.page_number,
                page_count: self.inner.page_count,
            });
        }

        loop {
            let mut state = self
                .inner
                .state
                .lock()
                .map_err(|_| PageSceneError::Unavailable)?;
            if request.expected_revision != state.revision {
                return Err(PageSceneError::StaleRevision);
            }
            if let Some(scene) = state.scenes.get_mut(&request.page_number) {
                scene.state = state_for_priority(request.priority);
                return Ok(scene.clone());
            }
            if state.in_flight.contains(&request.page_number)
                || state.active_imports >= self.inner.max_concurrency
            {
                drop(
                    self.inner
                        .changed
                        .wait(state)
                        .map_err(|_| PageSceneError::Unavailable)?,
                );
                continue;
            }
            state.in_flight.insert(request.page_number);
            state.active_imports += 1;
            state.max_observed = state.max_observed.max(state.active_imports);
            break;
        }

        let imported = self.inner.importer.import_page(PageImportRequest {
            source: self.inner.source.clone(),
            page_number: request.page_number,
        });
        let mut state = self
            .inner
            .state
            .lock()
            .map_err(|_| PageSceneError::Unavailable)?;
        state.active_imports -= 1;
        state.in_flight.remove(&request.page_number);
        *state.import_counts.entry(request.page_number).or_default() += 1;

        let result = match imported {
            Ok(ImportedPage { page, warnings }) if state.revision == request.expected_revision => {
                let scene = PageScene {
                    document_id: self.inner.document_id,
                    revision: state.revision,
                    page,
                    state: state_for_priority(request.priority),
                    warnings,
                };
                state.scenes.insert(request.page_number, scene.clone());
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
            self.inner.changed.notify_all();
        }
    }

    pub fn mark_cold(&self, page_number: u32) {
        if let Ok(mut state) = self.inner.state.lock() {
            if let Some(scene) = state.scenes.get_mut(&page_number) {
                scene.state = PageImportState::Cold;
            }
        }
    }

    pub fn page_state(&self, page_number: u32) -> PageImportState {
        self.inner
            .state
            .lock()
            .ok()
            .and_then(|state| state.scenes.get(&page_number).map(|scene| scene.state))
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
}

fn state_for_priority(priority: ViewportPriority) -> PageImportState {
    match priority {
        ViewportPriority::ActiveSelection | ViewportPriority::Visible => PageImportState::Visible,
        ViewportPriority::Preload => PageImportState::Warm,
        ViewportPriority::Background => PageImportState::Indexed,
    }
}
