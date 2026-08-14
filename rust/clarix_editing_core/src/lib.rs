pub const EDITOR_CORE_SCHEMA_VERSION: u32 = 1;

mod actor;
mod command;
mod error;
mod geometry;
mod ids;
mod model;
mod session;
mod text;
mod tools;

pub use actor::{EditorEvent, EditorSessionActor};
pub use command::{ActorKind, CommandEnvelope, CommandResult, EditorCommand, ObjectPatch};
pub use error::EditingError;
pub use geometry::{AffineTransform, GeometryError, PdfBox};
pub use ids::{CommandId, DocumentId, DocumentRevision, ObjectId, PageId, SessionId};
pub use model::{
    AnnotationNode, DocumentModel, DocumentObject, EditCapability, GroupNode, ImageNode,
    ModelError, ObjectKind, OcrLayer, PageNode, SourceBinding, TextBlock, VectorNode,
};
pub use session::EditorSessionState;
pub use text::{validate_utf16_range, TextRangeError, TextRun, TextStyle, Utf16Range};
pub use tools::{EditingToolGateway, ObjectSummary, ToolObservation, ToolRequest, ToolRisk};
