use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{
    AffineTransform, DocumentId, DocumentModel, DocumentRevision, ObjectId, PageId, PageNode,
    PdfBox, PersistenceError, SaveError,
};

/// A transport-only operation that a live PDFium owner can resolve against its
/// scene/object locator table. The editing core intentionally does not hold
/// PDFium handles or open a PDF while producing this plan.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum PhysicalEditOperation {
    ReplaceText {
        object_id: ObjectId,
        source_key: String,
        source_revision: String,
        expected_text: String,
        replacement: String,
        bounds: PdfBox,
    },
    SetTextTransform {
        object_id: ObjectId,
        source_key: String,
        source_revision: String,
        expected_transform: AffineTransform,
        transform: AffineTransform,
        old_bounds: PdfBox,
        new_bounds: PdfBox,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PhysicalEditPlan {
    pub previous_revision: DocumentRevision,
    pub revision: DocumentRevision,
    pub operations: Vec<PhysicalEditOperation>,
    pub inverse_operations: Vec<PhysicalEditOperation>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceReference {
    pub fingerprint: String,
    pub path: PathBuf,
}

impl SourceReference {
    pub fn new(fingerprint: impl Into<String>, path: impl Into<PathBuf>) -> Self {
        Self {
            fingerprint: fingerprint.into(),
            path: path.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PageImportRequest {
    pub source: SourceReference,
    pub page_number: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ImportedPage {
    pub page: PageNode,
    pub warnings: Vec<String>,
}

pub trait PageImportSource: Send + Sync {
    fn import_page(&self, request: PageImportRequest) -> Result<ImportedPage, String>;
}

pub trait PageIndexRepository: Send + Sync {
    fn load_indexed_page(
        &self,
        document_id: DocumentId,
        source_fingerprint: &str,
        page_number: u32,
    ) -> Result<Option<ImportedPage>, PersistenceError>;

    fn store_indexed_page(
        &self,
        document_id: DocumentId,
        source_fingerprint: &str,
        page: &ImportedPage,
    ) -> Result<(), PersistenceError>;
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CleanPatchRequest {
    pub source: SourceReference,
    pub page_id: PageId,
    pub source_key: String,
    pub bounds: PdfBox,
    pub revision: DocumentRevision,
    pub dpi: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RasterAsset {
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: Vec<u8>,
}

pub trait CleanPatchSource: Send + Sync {
    fn render_clean_patch(&self, request: CleanPatchRequest) -> Result<RasterAsset, String>;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MaterializationReport {
    pub output_sha256: String,
    pub bytes_written: u64,
    pub warnings: Vec<String>,
}

pub trait MaterializationPort: Send + Sync {
    fn materialize(
        &self,
        snapshot: &DocumentModel,
        target: &Path,
    ) -> Result<MaterializationReport, SaveError>;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValidationExpectation {
    pub document_id: crate::DocumentId,
    pub revision: DocumentRevision,
    pub page_count: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValidationReport {
    pub valid: bool,
    pub warnings: Vec<String>,
}

pub trait ValidationPort: Send + Sync {
    fn validate(
        &self,
        output: &Path,
        expectation: &ValidationExpectation,
    ) -> Result<ValidationReport, SaveError>;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AtomicReplaceRequest {
    pub working: PathBuf,
    pub target: PathBuf,
    pub backup: Option<PathBuf>,
    pub replace_existing: bool,
}

pub trait AtomicReplacementPort: Send + Sync {
    fn replace(&self, request: AtomicReplaceRequest) -> Result<(), SaveError>;
}
