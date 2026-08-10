mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
flutter_rust_bridge::frb_generated_sse_codec!();

pub mod api;
#[cfg(feature = "ocr")]
pub mod ocr;
pub mod pdf_annotations;
pub mod pdf_compose;
#[cfg(feature = "rag")]
pub mod rag;

use std::collections::VecDeque;
use std::path::Path;

use pdf_oxide::PdfDocument;
use serde::{Deserialize, Serialize};

const MAX_CACHED_PAGES: usize = 32;
const MAX_CACHED_TEXT_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfDocumentMetadata {
    pub document_id: String,
    pub title: String,
    pub page_count: usize,
    pub is_encrypted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfTextChunk {
    pub id: String,
    pub document_id: String,
    pub title: String,
    pub page_number: usize,
    pub chunk_order: usize,
    pub text: String,
    pub section_title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfSearchMatch {
    pub page_number: usize,
    pub text: String,
    pub bounds: (f32, f32, f32, f32),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfExtractionError {
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfIndexingProgress {
    pub page_number: usize,
    pub total_pages: usize,
}

pub struct PdfDocumentSession {
    path: String,
    metadata: PdfDocumentMetadata,
    document: PdfDocument,
    search_document: pdf_oxide::api::Pdf,
    text_cache: VecDeque<(usize, String)>,
    cached_text_bytes: usize,
}

impl PdfDocumentSession {
    pub fn open(path: impl Into<String>) -> Result<Self, PdfExtractionError> {
        let path = path.into();
        let document = PdfDocument::open(&path).map_err(map_error)?;
        let metadata = PdfDocumentMetadata {
            document_id: slugify(&path),
            title: Path::new(&path)
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_else(|| "document.pdf".to_string()),
            page_count: document.page_count().map_err(map_error)?,
            is_encrypted: document.is_encrypted(),
        };
        let search_document = pdf_oxide::api::Pdf::open(&path).map_err(map_error)?;
        Ok(Self {
            path,
            metadata,
            document,
            search_document,
            text_cache: VecDeque::new(),
            cached_text_bytes: 0,
        })
    }

    pub fn metadata(&self) -> PdfDocumentMetadata {
        self.metadata.clone()
    }

    pub fn path(&self) -> &str {
        &self.path
    }

    pub fn extract_page_text(&mut self, page_number: usize) -> Result<String, PdfExtractionError> {
        if page_number == 0 || page_number > self.metadata.page_count {
            return Err(PdfExtractionError {
                message: format!(
                    "Page {page_number} is outside 1..={}",
                    self.metadata.page_count
                ),
            });
        }
        if let Some((_, text)) = self
            .text_cache
            .iter()
            .find(|(cached_page, _)| *cached_page == page_number)
        {
            return Ok(text.clone());
        }
        let text = self
            .document
            .extract_text(page_number - 1)
            .map_err(map_error)?;
        self.cache_page_text(page_number, text.clone());
        Ok(text)
    }

    pub fn search(&mut self, pattern: &str) -> Result<Vec<PdfSearchMatch>, PdfExtractionError> {
        if pattern.trim().is_empty() {
            return Ok(Vec::new());
        }
        let options = pdf_oxide::search::SearchOptions::case_insensitive().with_literal(true);
        let results = self
            .search_document
            .search_with_options(pattern, options)
            .map_err(map_error)?;
        Ok(results
            .into_iter()
            .map(|result| PdfSearchMatch {
                page_number: result.page + 1,
                text: result.text,
                bounds: (
                    result.bbox.x,
                    result.bbox.y,
                    result.bbox.x + result.bbox.width,
                    result.bbox.y + result.bbox.height,
                ),
            })
            .collect())
    }

    pub fn build_chunk_batches<F>(
        &mut self,
        max_chars_per_chunk: usize,
        batch_size: usize,
        mut emit: F,
    ) -> Result<(), PdfExtractionError>
    where
        F: FnMut(Vec<PdfTextChunk>) -> Result<(), PdfExtractionError>,
    {
        if max_chars_per_chunk == 0 || batch_size == 0 {
            return Err(PdfExtractionError {
                message: "Chunk and batch sizes must be greater than zero.".to_string(),
            });
        }
        let mut batch = Vec::with_capacity(batch_size);
        let mut chunk_order = 0usize;
        for page_number in 1..=self.metadata.page_count {
            let page_text = self.extract_page_text(page_number)?;
            for text in split_text_chunks(&page_text, max_chars_per_chunk) {
                batch.push(PdfTextChunk {
                    id: format!("{}:{page_number}:{chunk_order}", self.metadata.document_id),
                    document_id: self.metadata.document_id.clone(),
                    title: self.metadata.title.clone(),
                    page_number,
                    chunk_order,
                    text,
                    section_title: None,
                });
                chunk_order += 1;
                if batch.len() == batch_size {
                    emit(std::mem::take(&mut batch))?;
                    batch = Vec::with_capacity(batch_size);
                }
            }
        }
        if !batch.is_empty() {
            emit(batch)?;
        }
        Ok(())
    }

    fn cache_page_text(&mut self, page_number: usize, text: String) {
        let text_bytes = text.len();
        if text_bytes > MAX_CACHED_TEXT_BYTES {
            return;
        }
        while self.text_cache.len() >= MAX_CACHED_PAGES
            || self.cached_text_bytes + text_bytes > MAX_CACHED_TEXT_BYTES
        {
            if let Some((_, removed)) = self.text_cache.pop_front() {
                self.cached_text_bytes = self.cached_text_bytes.saturating_sub(removed.len());
            } else {
                break;
            }
        }
        self.cached_text_bytes += text_bytes;
        self.text_cache.push_back((page_number, text));
    }
}

pub fn open_document(path: &str) -> Result<PdfDocumentMetadata, PdfExtractionError> {
    PdfDocumentSession::open(path).map(|session| session.metadata())
}

pub fn extract_page_text(path: &str, page_number: usize) -> Result<String, PdfExtractionError> {
    PdfDocumentSession::open(path)?.extract_page_text(page_number)
}

pub fn extract_document_text(path: &str) -> Result<Vec<String>, PdfExtractionError> {
    let mut session = PdfDocumentSession::open(path)?;
    (1..=session.metadata.page_count)
        .map(|page| session.extract_page_text(page))
        .collect()
}

pub fn search_document(
    path: &str,
    pattern: &str,
) -> Result<Vec<PdfSearchMatch>, PdfExtractionError> {
    PdfDocumentSession::open(path)?.search(pattern)
}

pub fn build_chunks(
    path: &str,
    max_chars_per_chunk: usize,
) -> Result<Vec<PdfTextChunk>, PdfExtractionError> {
    let mut session = PdfDocumentSession::open(path)?;
    let mut chunks = Vec::new();
    session.build_chunk_batches(max_chars_per_chunk, 32, |mut batch| {
        chunks.append(&mut batch);
        Ok(())
    })?;
    Ok(chunks)
}

fn split_text_chunks(text: &str, max_chars_per_chunk: usize) -> Vec<String> {
    if max_chars_per_chunk == 0 {
        return Vec::new();
    }
    let mut chunks = Vec::new();
    let mut current = String::new();
    for word in text.split_whitespace() {
        let separator = usize::from(!current.is_empty());
        if !current.is_empty()
            && current.chars().count() + separator + word.chars().count() > max_chars_per_chunk
        {
            chunks.push(std::mem::take(&mut current));
        }
        if word.chars().count() > max_chars_per_chunk {
            if !current.is_empty() {
                chunks.push(std::mem::take(&mut current));
            }
            let mut piece = String::new();
            for ch in word.chars() {
                piece.push(ch);
                if piece.chars().count() == max_chars_per_chunk {
                    chunks.push(std::mem::take(&mut piece));
                }
            }
            current = piece;
            continue;
        }
        if !current.is_empty() {
            current.push(' ');
        }
        current.push_str(word);
    }
    if !current.is_empty() {
        chunks.push(current);
    }
    chunks
}

fn map_error(error: impl std::fmt::Display) -> PdfExtractionError {
    PdfExtractionError {
        message: error.to_string(),
    }
}

fn slugify(path: &str) -> String {
    Path::new(path)
        .file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_else(|| "document".to_string())
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() {
                ch.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::split_text_chunks;

    #[test]
    fn chunking_preserves_unicode_boundaries() {
        let chunks = split_text_chunks("αβγδε ζηθικ λμνξο", 5);
        assert_eq!(chunks, vec!["αβγδε", "ζηθικ", "λμνξο"]);
    }

    #[test]
    fn chunking_normalizes_whitespace_without_empty_chunks() {
        let chunks = split_text_chunks("  local\n\nPDF\treader  ", 9);
        assert_eq!(chunks, vec!["local PDF", "reader"]);
    }
}
