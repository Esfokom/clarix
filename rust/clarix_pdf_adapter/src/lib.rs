pub const PDF_ADAPTER_SCHEMA_VERSION: u32 = 1;

mod clean_patch;
mod contract;
mod materializer;
mod pdf_oxide_importer;
mod qualification;
mod validator;
mod windows_replace;

pub use clean_patch::{
    CleanPatch, CleanPatchBackend, CleanPatchCache, CleanPatchKey, CleanPatchRenderRequest,
    CleanPatchRenderer, DEFAULT_CLEAN_PATCH_BUDGET_BYTES,
};
pub use contract::{
    CapabilityReport, CapabilityStatus, CleanPatchRequest, DocumentImport, DocumentSnapshot,
    PageImport, PdfAdapterError, PdfImporter, PdfMaterializer, PdfPreviewRenderer, PdfValidator,
    RasterAsset, SaveExpectation, SaveReport, SourceRef, ValidationReport,
};
pub use materializer::PdfTextMaterializer;
pub use pdf_oxide_importer::PdfOxideImporter;
pub use qualification::QualificationCaseResult;
pub use validator::{DetailedValidationReport, IndependentPdfValidator, ValidationFailure};
pub use windows_replace::{map_windows_replace_error, WindowsAtomicReplacer};
