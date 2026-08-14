use serde::{Deserialize, Serialize};

use crate::{
    CommandEnvelope, CommandResult, DocumentRevision, EditingError, ObjectId, ObjectKind, PdfBox,
};

pub trait EditingToolGateway: Send + Sync + 'static {
    fn invoke(&self, request: ToolRequest) -> Result<ToolObservation, EditingError>;
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ToolRequest {
    InspectDocument {
        revision: DocumentRevision,
    },
    InspectObject {
        revision: DocumentRevision,
        object_id: ObjectId,
    },
    SubmitCommand(CommandEnvelope),
}

impl ToolRequest {
    pub const fn risk(&self) -> ToolRisk {
        match self {
            Self::InspectDocument { .. } | Self::InspectObject { .. } => ToolRisk::ReadOnly,
            Self::SubmitCommand(_) => ToolRisk::ReversibleMutation,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ToolRisk {
    ReadOnly,
    ReversibleMutation,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ObjectSummary {
    pub object_id: ObjectId,
    pub kind: ObjectKind,
    pub bounds: PdfBox,
    pub text_preview: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ToolObservation {
    Document {
        revision: DocumentRevision,
        page_count: u32,
        object_count: u32,
    },
    Object {
        revision: DocumentRevision,
        summary: ObjectSummary,
    },
    Command {
        result: CommandResult,
    },
}

impl ToolObservation {
    pub const fn revision(&self) -> DocumentRevision {
        match self {
            Self::Document { revision, .. } | Self::Object { revision, .. } => *revision,
            Self::Command { result } => result.committed_revision,
        }
    }
}
