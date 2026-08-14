use std::path::{Path, PathBuf};

use clarix_editing_core::{DocumentId, DocumentModel, DocumentRevision, PageId, PageNode, PdfBox};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceRef {
    fingerprint: String,
    path: PathBuf,
}

impl SourceRef {
    pub fn new(fingerprint: impl Into<String>, path: impl Into<PathBuf>) -> Self {
        Self {
            fingerprint: fingerprint.into(),
            path: path.into(),
        }
    }

    pub fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum CapabilityStatus {
    Supported,
    Unsupported(String),
}

impl CapabilityStatus {
    pub const fn is_supported(&self) -> bool {
        matches!(self, Self::Supported)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityReport {
    pub adapter_id: String,
    pub import: CapabilityStatus,
    pub clean_patch: CapabilityStatus,
    pub materialization: CapabilityStatus,
    pub validation: CapabilityStatus,
}

impl CapabilityReport {
    pub fn new(adapter_id: impl Into<String>) -> Self {
        let unavailable = || CapabilityStatus::Unsupported("not declared".into());
        Self {
            adapter_id: adapter_id.into(),
            import: unavailable(),
            clean_patch: unavailable(),
            materialization: unavailable(),
            validation: unavailable(),
        }
    }

    pub fn read_only(adapter_id: impl Into<String>) -> Self {
        Self::new(adapter_id)
            .with_import(CapabilityStatus::Supported)
            .with_clean_patch(CapabilityStatus::Unsupported(
                "clean patch rendering is not implemented".into(),
            ))
            .with_materialization(CapabilityStatus::Unsupported(
                "PDF materialization is not implemented".into(),
            ))
            .with_validation(CapabilityStatus::Unsupported(
                "materialized PDF validation is not implemented".into(),
            ))
    }

    pub fn with_import(mut self, status: CapabilityStatus) -> Self {
        self.import = status;
        self
    }

    pub fn with_clean_patch(mut self, status: CapabilityStatus) -> Self {
        self.clean_patch = status;
        self
    }

    pub fn with_materialization(mut self, status: CapabilityStatus) -> Self {
        self.materialization = status;
        self
    }

    pub fn with_validation(mut self, status: CapabilityStatus) -> Self {
        self.validation = status;
        self
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DocumentImport {
    pub source_fingerprint: String,
    pub page_count: u32,
    pub report: CapabilityReport,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PageImport {
    pub page: PageNode,
    pub report: CapabilityReport,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CleanPatchRequest {
    pub page_id: PageId,
    pub bounds: PdfBox,
    pub revision: DocumentRevision,
    pub dpi: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RasterAsset {
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DocumentSnapshot {
    pub model: DocumentModel,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SaveReport {
    pub output_sha256: String,
    pub bytes_written: u64,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SaveExpectation {
    pub document_id: DocumentId,
    pub revision: DocumentRevision,
    pub page_count: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValidationReport {
    pub valid: bool,
    pub page_count: u32,
    pub warnings: Vec<String>,
}

pub trait PdfImporter: Send + Sync {
    fn adapter_id(&self) -> &'static str;

    fn inspect_document(&self, source: &SourceRef) -> Result<DocumentImport, PdfAdapterError>;

    fn inspect_page(
        &self,
        source: &SourceRef,
        page_number: u32,
    ) -> Result<PageImport, PdfAdapterError>;
}

pub trait PdfPreviewRenderer: Send + Sync {
    fn render_clean_patch(
        &self,
        request: CleanPatchRequest,
    ) -> Result<RasterAsset, PdfAdapterError>;
}

pub trait PdfMaterializer: Send + Sync {
    fn materialize(
        &self,
        snapshot: &DocumentSnapshot,
        target: &Path,
    ) -> Result<SaveReport, PdfAdapterError>;
}

pub trait PdfValidator: Send + Sync {
    fn validate(
        &self,
        output: &Path,
        expectation: &SaveExpectation,
    ) -> Result<ValidationReport, PdfAdapterError>;
}

#[derive(Debug, Error)]
pub enum PdfAdapterError {
    #[error("invalid PDF: {0}")]
    InvalidPdf(String),
    #[error("page {requested} is outside 1..={page_count}")]
    PageOutOfRange { requested: u32, page_count: u32 },
    #[error("source fingerprint does not match the file")]
    FingerprintMismatch,
    #[error("operation is unsupported: {0}")]
    Unsupported(String),
    #[error("I/O failure: {0}")]
    Io(String),
    #[error("adapter failure: {0}")]
    Adapter(String),
}

impl PdfAdapterError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::InvalidPdf(_) => "invalid_pdf",
            Self::PageOutOfRange { .. } => "page_out_of_range",
            Self::FingerprintMismatch => "fingerprint_mismatch",
            Self::Unsupported(_) => "unsupported",
            Self::Io(_) => "io_error",
            Self::Adapter(_) => "adapter_error",
        }
    }
}
