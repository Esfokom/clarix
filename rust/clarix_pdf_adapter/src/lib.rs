pub const PDF_ADAPTER_SCHEMA_VERSION: u32 = 1;

mod contract;
mod qualification;

pub use contract::{
    CapabilityReport, CapabilityStatus, CleanPatchRequest, DocumentImport, DocumentSnapshot,
    PageImport, PdfAdapterError, PdfImporter, PdfMaterializer, PdfPreviewRenderer, PdfValidator,
    RasterAsset, SaveExpectation, SaveReport, SourceRef, ValidationReport,
};
pub use qualification::QualificationCaseResult;
