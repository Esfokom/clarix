pub const PDF_ADAPTER_SCHEMA_VERSION: u32 = 1;

mod contract;
mod pdf_oxide_importer;
mod qualification;

pub use contract::{
    CapabilityReport, CapabilityStatus, CleanPatchRequest, DocumentImport, DocumentSnapshot,
    PageImport, PdfAdapterError, PdfImporter, PdfMaterializer, PdfPreviewRenderer, PdfValidator,
    RasterAsset, SaveExpectation, SaveReport, SourceRef, ValidationReport,
};
pub use pdf_oxide_importer::PdfOxideImporter;
pub use qualification::QualificationCaseResult;
