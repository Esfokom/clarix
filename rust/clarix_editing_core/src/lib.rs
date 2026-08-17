pub const EDITOR_CORE_SCHEMA_VERSION: u32 = 1;

mod actor;
mod command;
mod compatibility;
mod error;
mod geometry;
mod history;
mod ids;
mod model;
mod page_service;
mod persistence;
mod ports;
mod save;
mod search;
mod selection;
mod session;
mod text;
mod tools;

pub use actor::{EditorEvent, EditorSessionActor};
pub use command::{
    ActorKind, AtomicEdit, CommandEnvelope, CommandResult, CommandWarning, EditorCommand,
    ObjectPatch, PreparedCommand, SelectionRebase,
};
pub use compatibility::{CompatibilityIssue, CompatibilityReport, CompatibilityReporter};
pub use error::EditingError;
pub use geometry::{AffineTransform, GeometryError, PdfBox};
pub use history::{InverseOperation, TypingGroup};
pub use ids::{CommandId, DocumentId, DocumentRevision, ObjectId, PageId, SessionId};
pub use model::{
    AnnotationNode, CapabilityReason, DocumentModel, DocumentObject, EditCapability, GroupNode,
    ImageNode, ModelError, ObjectKind, OcrLayer, PageNode, SourceBinding, TextBlock, VectorNode,
};
pub use page_service::{
    MemoryPressureLevel, PageImportState, PageIndexTask, PageScene, PageSceneError,
    PageSceneRequest, PageSceneService, ViewportPriority,
};
pub use persistence::{
    CheckpointKind, DurableCommit, DurableSnapshot, MaterializationRecord, PersistenceError,
    ProjectCheckpoint, ProjectRepository, RecoveredCommand, RecoveredProject, RecoveryRequest,
};
pub use ports::{
    AtomicReplaceRequest, AtomicReplacementPort, CleanPatchRequest, CleanPatchSource, ImportedPage,
    MaterializationPort, MaterializationReport, PageImportRequest, PageImportSource,
    PageIndexRepository, RasterAsset, SourceReference, ValidationExpectation, ValidationPort,
    ValidationReport,
};
pub use save::{
    SaveAssociation, SaveCoordinator, SaveError, SaveMode, SaveReport, SaveRequest, SaveStage,
    SaveStageGate,
};
pub use search::{
    ReplaceAllPreview, SearchError, SearchIndex, SearchMode, SearchPage, SearchRequest,
    TextRangeRef,
};
pub use selection::{SelectionKind, SelectionSet};
pub use session::EditorSessionState;
pub use text::{
    validate_utf16_range, FontFallbackApproval, FontRef, FontSource, OverflowPolicy,
    ParagraphStyle, SourceGlyph, TextAffinity, TextAlignment, TextAnchor, TextCharacterBox,
    TextLayoutRecipe, TextRangeError, TextRun, TextStyle, Utf16Range, WritingDirection,
};
pub use tools::{EditingToolGateway, ObjectSummary, ToolObservation, ToolRequest, ToolRisk};
