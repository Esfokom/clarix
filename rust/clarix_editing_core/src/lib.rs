pub const EDITOR_CORE_SCHEMA_VERSION: u32 = 1;

mod geometry;
mod ids;
mod model;
mod text;

pub use geometry::{AffineTransform, GeometryError, PdfBox};
pub use ids::{CommandId, DocumentId, DocumentRevision, ObjectId, PageId, SessionId};
pub use model::{
    AnnotationNode, DocumentModel, DocumentObject, EditCapability, GroupNode, ImageNode,
    ModelError, ObjectKind, OcrLayer, PageNode, SourceBinding, TextBlock, VectorNode,
};
pub use text::{validate_utf16_range, TextRangeError, TextRun, TextStyle, Utf16Range};
