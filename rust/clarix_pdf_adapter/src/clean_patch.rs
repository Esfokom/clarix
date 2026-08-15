use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};

use clarix_editing_core::PdfBox;
use lopdf::content::Content;
use serde::{Deserialize, Serialize};

use crate::{PdfAdapterError, SourceRef};

pub const DEFAULT_CLEAN_PATCH_BUDGET_BYTES: usize = 128 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CleanPatchKey {
    pub source_fingerprint: String,
    pub source_key: String,
    pub dpi_bucket: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CleanPatchRenderRequest {
    pub source: SourceRef,
    pub page_number: u32,
    pub source_key: String,
    pub bounds: PdfBox,
    pub dpi: u32,
}

impl CleanPatchRenderRequest {
    pub fn key(&self) -> CleanPatchKey {
        CleanPatchKey {
            source_fingerprint: self.source.fingerprint().to_owned(),
            source_key: self.source_key.clone(),
            dpi_bucket: dpi_bucket(self.dpi),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct CleanPatch {
    pub key: CleanPatchKey,
    pub bounds: PdfBox,
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: Vec<u8>,
    pub bleed_points: f64,
}

impl CleanPatch {
    #[doc(hidden)]
    pub fn solid_for_test(request: CleanPatchRenderRequest, width: u32, height: u32) -> Self {
        Self {
            key: request.key(),
            bounds: request.bounds,
            width,
            height,
            rgba_bytes: vec![255; width as usize * height as usize * 4],
            bleed_points: 1.0,
        }
    }

    fn decoded_size(&self) -> usize {
        self.rgba_bytes.len()
    }
}

pub trait CleanPatchBackend: Send + Sync {
    fn render(&self, request: CleanPatchRenderRequest) -> Result<CleanPatch, PdfAdapterError>;
}

#[derive(Debug, Default, Clone, Copy)]
pub struct CleanPatchRenderer;

impl CleanPatchBackend for CleanPatchRenderer {
    fn render(&self, mut request: CleanPatchRenderRequest) -> Result<CleanPatch, PdfAdapterError> {
        if request.dpi == 0 {
            return Err(PdfAdapterError::UnsafeCleanPatch(
                "DPI must be greater than zero".into(),
            ));
        }
        request.dpi = dpi_bucket(request.dpi);
        let expected_prefix = format!(
            "{}/page/{}/text/",
            request.source.fingerprint(),
            request.page_number
        );
        if !request.source_key.starts_with(&expected_prefix) {
            return Err(PdfAdapterError::UnsafeCleanPatch(
                "source locator does not match the requested source page".into(),
            ));
        }
        let occurrence = request
            .source_key
            .rsplit('/')
            .nth(1)
            .and_then(|value| value.parse::<usize>().ok())
            .ok_or_else(|| {
                PdfAdapterError::UnsafeCleanPatch(
                    "source locator has no deterministic text occurrence".into(),
                )
            })?;

        let source = lopdf::Document::load(request.source.path())
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
        let pages = source.get_pages();
        let page_id =
            pages
                .get(&request.page_number)
                .copied()
                .ok_or(PdfAdapterError::PageOutOfRange {
                    requested: request.page_number,
                    page_count: pages.len() as u32,
                })?;
        if source.get_page_contents(page_id).len() != 1 {
            return Err(PdfAdapterError::UnsafeCleanPatch(
                "page content is split across ambiguous streams".into(),
            ));
        }
        let bytes = source
            .get_page_content(page_id)
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
        let mut content = Content::decode(&bytes)
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
        if content
            .operations
            .iter()
            .any(|operation| operation.operator == "Do")
        {
            return Err(PdfAdapterError::UnsafeCleanPatch(
                "page uses external objects whose text ownership is ambiguous".into(),
            ));
        }
        let mut text_index = 0_usize;
        let mut removed = false;
        content.operations.retain(|operation| {
            if !matches!(operation.operator.as_str(), "Tj" | "TJ" | "'" | "\"") {
                return true;
            }
            let keep = text_index != occurrence;
            if !keep {
                removed = true;
            }
            text_index += 1;
            keep
        });
        if !removed {
            return Err(PdfAdapterError::UnsafeCleanPatch(
                "source text occurrence was not found".into(),
            ));
        }
        if content.operations.iter().any(is_painting_operation) {
            return Err(PdfAdapterError::UnsafeCleanPatch(
                "page background contains paint operations that cannot be safely reproduced".into(),
            ));
        }
        opaque_blank_patch(request)
    }
}

struct CacheEntry {
    patch: Arc<CleanPatch>,
    last_used: u64,
    visible: bool,
}

#[derive(Default)]
struct CacheState {
    entries: HashMap<CleanPatchKey, CacheEntry>,
    decoded_bytes: usize,
    clock: u64,
}

pub struct CleanPatchCache {
    backend: Arc<dyn CleanPatchBackend>,
    budget_bytes: usize,
    state: Mutex<CacheState>,
    cancelled: AtomicBool,
}

impl CleanPatchCache {
    pub fn for_document(backend: Arc<dyn CleanPatchBackend>) -> Self {
        Self::new(backend, DEFAULT_CLEAN_PATCH_BUDGET_BYTES)
    }

    pub fn new(backend: Arc<dyn CleanPatchBackend>, budget_bytes: usize) -> Self {
        Self {
            backend,
            budget_bytes,
            state: Mutex::new(CacheState::default()),
            cancelled: AtomicBool::new(false),
        }
    }

    pub fn get_or_render(
        &self,
        mut request: CleanPatchRenderRequest,
    ) -> Result<Arc<CleanPatch>, PdfAdapterError> {
        if self.cancelled.load(Ordering::Acquire) {
            return Err(PdfAdapterError::Cancelled);
        }
        request.dpi = dpi_bucket(request.dpi);
        let key = request.key();
        {
            let mut state = self
                .state
                .lock()
                .map_err(|_| PdfAdapterError::Adapter("clean patch cache poisoned".into()))?;
            state.clock += 1;
            let clock = state.clock;
            if let Some(entry) = state.entries.get_mut(&key) {
                entry.last_used = clock;
                return Ok(Arc::clone(&entry.patch));
            }
        }
        let patch = Arc::new(self.backend.render(request)?);
        let mut state = self
            .state
            .lock()
            .map_err(|_| PdfAdapterError::Adapter("clean patch cache poisoned".into()))?;
        state.clock += 1;
        let clock = state.clock;
        state.decoded_bytes += patch.decoded_size();
        state.entries.insert(
            key,
            CacheEntry {
                patch: Arc::clone(&patch),
                last_used: clock,
                visible: false,
            },
        );
        while state.decoded_bytes > self.budget_bytes && state.entries.len() > 1 {
            let Some(oldest) = state
                .entries
                .iter()
                .filter(|(_, entry)| !entry.visible)
                .min_by_key(|(_, entry)| entry.last_used)
                .map(|(key, _)| key.clone())
            else {
                break;
            };
            if let Some(removed) = state.entries.remove(&oldest) {
                state.decoded_bytes -= removed.patch.decoded_size();
            }
        }
        Ok(patch)
    }

    pub fn contains(&self, key: &CleanPatchKey) -> bool {
        self.state
            .lock()
            .map(|state| state.entries.contains_key(key))
            .unwrap_or(false)
    }

    pub fn set_visible(&self, key: &CleanPatchKey, visible: bool) {
        if let Ok(mut state) = self.state.lock() {
            if let Some(entry) = state.entries.get_mut(key) {
                entry.visible = visible;
            }
        }
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.clear();
    }

    pub fn clear(&self) {
        if let Ok(mut state) = self.state.lock() {
            state.entries.clear();
            state.decoded_bytes = 0;
        }
    }
}

fn opaque_blank_patch(request: CleanPatchRenderRequest) -> Result<CleanPatch, PdfAdapterError> {
    let bleed = 1.0_f64;
    let scale = f64::from(request.dpi) / 72.0;
    let left = request.bounds.left - bleed;
    let bottom = request.bounds.bottom - bleed;
    let right = request.bounds.right + bleed;
    let top = request.bounds.top + bleed;
    let width = ((right - left) * scale).ceil().max(1.0) as u32;
    let height = ((top - bottom) * scale).ceil().max(1.0) as u32;
    let rgba_bytes = vec![255; width as usize * height as usize * 4];
    Ok(CleanPatch {
        key: request.key(),
        bounds: PdfBox::new(left, bottom, right, top)
            .map_err(|error| PdfAdapterError::Adapter(error.to_string()))?,
        width,
        height,
        rgba_bytes,
        bleed_points: bleed,
    })
}

fn is_painting_operation(operation: &lopdf::content::Operation) -> bool {
    matches!(
        operation.operator.as_str(),
        "Tj" | "TJ"
            | "'"
            | "\""
            | "S"
            | "s"
            | "f"
            | "F"
            | "f*"
            | "B"
            | "B*"
            | "b"
            | "b*"
            | "sh"
            | "Do"
            | "BI"
    )
}

fn dpi_bucket(dpi: u32) -> u32 {
    const BUCKETS: [u32; 7] = [72, 96, 144, 192, 288, 384, 576];
    BUCKETS
        .into_iter()
        .rev()
        .find(|bucket| *bucket <= dpi)
        .unwrap_or(72)
}
