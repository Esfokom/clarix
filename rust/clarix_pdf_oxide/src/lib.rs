use pdf_oxide::PdfDocument;
use serde::{Deserialize, Serialize};

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

pub fn open_document(path: &str) -> Result<PdfDocumentMetadata, PdfExtractionError> {
    let mut document = PdfDocument::open(path).map_err(map_error)?;
    Ok(PdfDocumentMetadata {
        document_id: slugify(path),
        title: std::path::Path::new(path)
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| "document.pdf".to_string()),
        page_count: document.pages().len(),
        is_encrypted: document.is_encrypted(),
    })
}

pub fn extract_page_text(path: &str, page_number: usize) -> Result<String, PdfExtractionError> {
    let mut document = PdfDocument::open(path).map_err(map_error)?;
    document.extract_text(page_number.saturating_sub(1)).map_err(map_error)
}

pub fn extract_document_text(path: &str) -> Result<Vec<String>, PdfExtractionError> {
    let mut document = PdfDocument::open(path).map_err(map_error)?;
    let mut pages = Vec::with_capacity(document.pages().len());
    for index in 0..document.pages().len() {
        pages.push(document.extract_text(index).map_err(map_error)?);
    }
    Ok(pages)
}

pub fn search_document(
    path: &str,
    pattern: &str,
) -> Result<Vec<PdfSearchMatch>, PdfExtractionError> {
    let mut pdf = pdf_oxide::api::Pdf::open(path).map_err(map_error)?;
    let results = pdf.search(pattern).map_err(map_error)?;
    Ok(results
        .into_iter()
        .map(|result| PdfSearchMatch {
            page_number: result.page,
            text: result.text,
            bounds: (
                result.bbox.x0 as f32,
                result.bbox.y0 as f32,
                result.bbox.x1 as f32,
                result.bbox.y1 as f32,
            ),
        })
        .collect())
}

pub fn build_chunks(
    path: &str,
    max_chars_per_chunk: usize,
) -> Result<Vec<PdfTextChunk>, PdfExtractionError> {
    let metadata = open_document(path)?;
    let pages = extract_document_text(path)?;
    let mut chunks = Vec::new();
    let mut chunk_order = 0usize;

    for (index, page_text) in pages.into_iter().enumerate() {
        let normalized = page_text.split_whitespace().collect::<Vec<_>>().join(" ");
        if normalized.is_empty() {
            continue;
        }

        let mut start = 0usize;
        while start < normalized.len() {
            let end = (start + max_chars_per_chunk).min(normalized.len());
            let text = normalized[start..end].trim().to_string();
            if !text.is_empty() {
                chunks.push(PdfTextChunk {
                    id: format!("{}:{}:{}", metadata.document_id, index + 1, chunk_order),
                    document_id: metadata.document_id.clone(),
                    title: metadata.title.clone(),
                    page_number: index + 1,
                    chunk_order,
                    text,
                    section_title: None,
                });
                chunk_order += 1;
            }
            start = end;
        }
    }

    Ok(chunks)
}

fn map_error(error: impl std::fmt::Display) -> PdfExtractionError {
    PdfExtractionError {
        message: error.to_string(),
    }
}

fn slugify(path: &str) -> String {
    std::path::Path::new(path)
        .file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_else(|| "document".to_string())
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch.to_ascii_lowercase() } else { '_' })
        .collect()
}
