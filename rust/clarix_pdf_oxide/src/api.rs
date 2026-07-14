use crate::StreamSink;
use serde::{Deserialize, Serialize};

use crate::{
    PdfDocumentMetadata, PdfDocumentSession, PdfIndexingProgress, PdfSearchMatch, PdfTextChunk,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PdfIndexEvent {
    Progress(PdfIndexingProgress),
    ChunkBatch(Vec<PdfTextChunk>),
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
