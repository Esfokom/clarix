use serde::{Deserialize, Serialize};

use crate::{
    AffineTransform, CommandId, DocumentRevision, ObjectId, PageId, PdfBox, TextStyle, Utf16Range,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ActorKind {
    User,
    Agent,
    System,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum EditorCommand {
    ReplaceTextRange {
        object_id: ObjectId,
        range: Utf16Range,
        replacement: String,
    },
    SetTextStyle {
        object_id: ObjectId,
        range: Utf16Range,
        style: TextStyle,
    },
    MoveObject {
        object_id: ObjectId,
        transform: AffineTransform,
    },
    ResizeObject {
        object_id: ObjectId,
        bounds: PdfBox,
    },
    RotateObject {
        object_id: ObjectId,
        radians: f64,
        center_x: f64,
        center_y: f64,
    },
    CreateCheckpoint {
        label: String,
    },
    Undo,
    Redo,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CommandEnvelope {
    pub command_id: CommandId,
    pub base_revision: DocumentRevision,
    pub transaction_id: Option<String>,
    pub actor: ActorKind,
    pub provenance_ids: Vec<String>,
    pub payload: EditorCommand,
}

impl CommandEnvelope {
    pub fn user(
        command_id: CommandId,
        base_revision: DocumentRevision,
        payload: EditorCommand,
    ) -> Self {
        Self {
            command_id,
            base_revision,
            transaction_id: None,
            actor: ActorKind::User,
            provenance_ids: Vec::new(),
            payload,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ObjectPatch {
    pub object_id: ObjectId,
    pub page_id: PageId,
    pub modified_revision: DocumentRevision,
    pub text: Option<String>,
    pub text_runs: Option<Vec<crate::TextRun>>,
    pub bounds: Option<PdfBox>,
    pub transform: Option<AffineTransform>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CommandResult {
    pub command_id: CommandId,
    pub committed_revision: DocumentRevision,
    pub object_patches: Vec<ObjectPatch>,
}
