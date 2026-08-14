use crate::frb_generated::StreamSink;
use serde::{Deserialize, Serialize};
#[cfg(feature = "rag")]
use std::collections::HashMap;
#[cfg(feature = "rag")]
use std::path::Path;
#[cfg(feature = "rag")]
use std::sync::{Arc, Mutex, OnceLock};

use crate::{
    PdfDocumentMetadata, PdfDocumentSession, PdfIndexingProgress, PdfSearchMatch, PdfTextChunk,
};

#[derive(Debug, Clone)]
pub struct NativePdfSource {
    pub path: String,
    pub pages: Vec<usize>,
}

#[derive(Debug, Clone)]
pub struct NativePdfComposeRequest {
    pub sources: Vec<NativePdfSource>,
    pub output_path: String,
}

#[derive(Debug, Clone)]
pub struct NativePdfComposeResponse {
    pub output_path: String,
    pub page_count: usize,
    pub message: Option<String>,
}

pub fn compose_pdfs(request: NativePdfComposeRequest) -> NativePdfComposeResponse {
    crate::pdf_compose::compose_pdfs(request)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PdfIndexEvent {
    Progress(PdfIndexingProgress),
    ChunkBatch(Vec<PdfTextChunk>),
}

/// A persisted Dart chunk represented at the native RAG boundary. The
/// fingerprint and ids are supplied by Flutter so an index can never be used
/// for a different persisted document.
#[cfg(feature = "rag")]
#[derive(Debug, Clone)]
pub struct NativeRagChunk {
    pub id: String,
    pub text: String,
}

#[cfg(feature = "rag")]
#[derive(Debug, Clone)]
pub struct NativeRagIndexRequest {
    pub storage_directory: String,
    pub model_cache_directory: String,
    pub document_fingerprint: String,
    pub chunks: Vec<NativeRagChunk>,
}

#[cfg(feature = "rag")]
#[derive(Debug, Clone)]
pub struct NativeRagIndexResponse {
    pub status: String,
    pub message: Option<String>,
    pub outcome: Option<String>,
}

#[cfg(feature = "rag")]
#[derive(Debug, Clone)]
pub struct NativeRagQueryRequest {
    pub storage_directory: String,
    pub model_cache_directory: String,
    pub document_fingerprint: String,
    pub chunk_ids: Vec<String>,
    pub query: String,
    pub limit: usize,
}

#[cfg(feature = "rag")]
#[derive(Debug, Clone)]
pub struct NativeRagQueryResult {
    pub chunk_id: String,
    pub score: f32,
}

#[cfg(feature = "rag")]
#[derive(Debug, Clone)]
pub struct NativeRagQueryResponse {
    pub status: String,
    pub message: Option<String>,
    pub results: Vec<NativeRagQueryResult>,
}

#[cfg(feature = "rag")]
static RAG_BACKENDS: OnceLock<Mutex<HashMap<String, Arc<crate::rag::FastEmbedBackend>>>> =
    OnceLock::new();

#[cfg(feature = "rag")]
fn rag_backend(cache_directory: &str) -> Result<Arc<crate::rag::FastEmbedBackend>, String> {
    let backends = RAG_BACKENDS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut backends = backends
        .lock()
        .map_err(|_| "local RAG model registry lock was poisoned".to_string())?;
    if let Some(existing) = backends.get(cache_directory) {
        return Ok(Arc::clone(existing));
    }
    let backend = Arc::new(
        crate::rag::FastEmbedBackend::new(cache_directory).map_err(|error| error.to_string())?,
    );
    backends.insert(cache_directory.to_string(), Arc::clone(&backend));
    Ok(backend)
}

#[cfg(feature = "rag")]
pub fn local_rag_index(request: NativeRagIndexRequest) -> NativeRagIndexResponse {
    let result = (|| {
        let backend = rag_backend(&request.model_cache_directory)?;
        let engine = crate::rag::VectorRagEngine::new(backend.as_ref());
        let paths = crate::rag::RagIndexPaths::for_document(
            &request.storage_directory,
            &request.document_fingerprint,
        );
        let chunks = request
            .chunks
            .into_iter()
            .map(|chunk| crate::rag::RagChunk::new(chunk.id, chunk.text))
            .collect::<Vec<_>>();
        let outcome = match engine.index_or_load(&request.document_fingerprint, &paths, &chunks) {
            Ok(outcome) => Ok(outcome),
            // The document identity can remain stable while a saved chunk set
            // changes (for example after re-extraction). Rebuild atomically
            // instead of leaving an unusable stale vector index behind.
            Err(crate::rag::RagError::RebuildRequired { .. }) => {
                engine.rebuild(&request.document_fingerprint, &paths, &chunks)
            }
            Err(error) => Err(error),
        };
        outcome
            .map(|outcome| match outcome {
                crate::rag::RagIndexOutcome::Built => "built".to_string(),
                crate::rag::RagIndexOutcome::Loaded => "loaded".to_string(),
            })
            .map_err(|error| error.to_string())
    })();
    match result {
        Ok(outcome) => NativeRagIndexResponse {
            status: "ready".to_string(),
            message: None,
            outcome: Some(outcome),
        },
        Err(message) => NativeRagIndexResponse {
            status: "failed".to_string(),
            message: Some(message),
            outcome: None,
        },
    }
}

#[derive(Debug, Clone)]
pub struct NativePdfBookmark {
    pub id: String,
    pub title: String,
    pub page_number: usize,
}

#[derive(Debug, Clone)]
pub struct NativePdfHighlight {
    pub id: String,
    pub page_number: usize,
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
    pub red: f32,
    pub green: f32,
    pub blue: f32,
    pub opacity: f32,
    pub text: String,
    pub quad_points: Vec<f32>,
}

#[derive(Debug, Clone)]
pub struct NativePdfSaveRequest {
    pub path: String,
    pub output_path: Option<String>,
    pub bookmarks: Vec<NativePdfBookmark>,
    pub highlights: Vec<NativePdfHighlight>,
}

#[derive(Debug, Clone)]
pub struct NativePdfAnnotations {
    pub bookmarks: Vec<NativePdfBookmark>,
    pub highlights: Vec<NativePdfHighlight>,
}

pub fn read_pdf_annotations(path: String) -> Result<NativePdfAnnotations, String> {
    crate::pdf_annotations::read(&path)
}

pub fn save_pdf_annotations(request: NativePdfSaveRequest) -> Result<(), String> {
    crate::pdf_annotations::save(request)
}

#[cfg(feature = "rag")]
pub fn local_rag_validate(request: NativeRagIndexRequest) -> NativeRagIndexResponse {
    let paths = crate::rag::RagIndexPaths::for_document(
        &request.storage_directory,
        &request.document_fingerprint,
    );
    let chunks = request
        .chunks
        .into_iter()
        .map(|chunk| crate::rag::RagChunk::new(chunk.id, chunk.text))
        .collect::<Vec<_>>();
    match crate::rag::validate_existing_index(
        &request.document_fingerprint,
        &paths,
        crate::rag::MODEL_ID,
        crate::rag::MODEL_DIMENSIONS,
        &chunks,
    ) {
        Ok(()) => NativeRagIndexResponse {
            status: "ready".to_string(),
            message: None,
            outcome: Some("loaded".to_string()),
        },
        Err(crate::rag::RagError::RebuildRequired { .. }) => NativeRagIndexResponse {
            status: "idle".to_string(),
            message: None,
            outcome: None,
        },
        Err(error) => NativeRagIndexResponse {
            status: "failed".to_string(),
            message: Some(error.to_string()),
            outcome: None,
        },
    }
}

#[cfg(feature = "rag")]
pub fn local_rag_query(request: NativeRagQueryRequest) -> NativeRagQueryResponse {
    let result = (|| {
        let backend = rag_backend(&request.model_cache_directory)?;
        let engine = crate::rag::VectorRagEngine::new(backend.as_ref());
        let paths = crate::rag::RagIndexPaths::for_document(
            &request.storage_directory,
            &request.document_fingerprint,
        );
        // Query validation intentionally receives every persisted chunk id.
        // Text is not needed after indexing, and an empty value prevents this
        // boundary from duplicating the entire JSONL corpus in memory.
        let chunks = request
            .chunk_ids
            .into_iter()
            .map(|id| crate::rag::RagChunk::new(id, String::new()))
            .collect::<Vec<_>>();
        engine
            .query(
                &request.document_fingerprint,
                &paths,
                &chunks,
                &request.query,
                request.limit,
            )
            .map(|results| {
                results
                    .into_iter()
                    .map(|result| NativeRagQueryResult {
                        chunk_id: result.chunk_id,
                        score: result.score,
                    })
                    .collect::<Vec<_>>()
            })
            .map_err(|error| error.to_string())
    })();
    match result {
        Ok(results) => NativeRagQueryResponse {
            status: "ready".to_string(),
            message: None,
            results,
        },
        Err(message) => NativeRagQueryResponse {
            status: "failed".to_string(),
            message: Some(message),
            results: Vec::new(),
        },
    }
}

#[cfg(feature = "rag")]
pub fn local_rag_status(storage_directory: String, document_fingerprint: String) -> String {
    let paths = crate::rag::RagIndexPaths::for_document(storage_directory, &document_fingerprint);
    if paths.index_path.exists() && paths.manifest_path.exists() {
        "ready".to_string()
    } else if Path::new(&paths.index_path).exists() || Path::new(&paths.manifest_path).exists() {
        "failed".to_string()
    } else {
        "idle".to_string()
    }
}

pub struct NativePdfSession {
    inner: PdfDocumentSession,
}

impl NativePdfSession {
    pub fn open(path: String) -> Result<Self, String> {
        Ok(Self {
            inner: PdfDocumentSession::open(path).map_err(|error| error.message)?,
        })
    }

    pub fn metadata(&self) -> PdfDocumentMetadata {
        self.inner.metadata()
    }

    pub fn page_text(&mut self, page_number: usize) -> Result<String, String> {
        self.inner
            .extract_page_text(page_number)
            .map_err(|error| error.message)
    }

    pub fn search(&mut self, query: String) -> Result<Vec<PdfSearchMatch>, String> {
        self.inner.search(&query).map_err(|error| error.message)
    }

    pub fn index(
        &mut self,
        max_chars_per_chunk: usize,
        batch_size: usize,
        sink: StreamSink<String>,
    ) -> Result<(), String> {
        let total_pages = self.inner.metadata().page_count;
        self.inner
            .build_chunk_batches(max_chars_per_chunk, batch_size, |batch| {
                let page_number = batch.last().map(|chunk| chunk.page_number).unwrap_or(0);
                let chunks =
                    serde_json::to_string(&PdfIndexEvent::ChunkBatch(batch)).map_err(|error| {
                        crate::PdfExtractionError {
                            message: error.to_string(),
                        }
                    })?;
                sink.add(chunks)
                    .map_err(|error| crate::PdfExtractionError {
                        message: error.to_string(),
                    })?;
                let progress =
                    serde_json::to_string(&PdfIndexEvent::Progress(PdfIndexingProgress {
                        page_number,
                        total_pages,
                    }))
                    .map_err(|error| crate::PdfExtractionError {
                        message: error.to_string(),
                    })?;
                sink.add(progress)
                    .map_err(|error| crate::PdfExtractionError {
                        message: error.to_string(),
                    })
            })
            .map_err(|error| error.message)
    }
}
