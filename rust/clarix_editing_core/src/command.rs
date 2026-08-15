use serde::{Deserialize, Serialize};

use crate::{
    AffineTransform, CommandId, DocumentRevision, InverseOperation, ObjectId, PageId,
    ParagraphStyle, PdfBox, TextStyle, TypingGroup, Utf16Range,
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
    SetParagraphStyle {
        object_id: ObjectId,
        style: ParagraphStyle,
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
    pub typing_group: Option<TypingGroup>,
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
            typing_group: None,
            payload,
        }
    }

    pub fn with_typing_group(mut self, typing_group: TypingGroup) -> Self {
        self.typing_group = Some(typing_group);
        self
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
    pub previous_revision: DocumentRevision,
    pub committed_revision: DocumentRevision,
    pub object_patches: Vec<ObjectPatch>,
    pub selection_rebase: Option<SelectionRebase>,
    pub warnings: Vec<CommandWarning>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SelectionRebase {
    pub object_id: ObjectId,
    pub replaced_range: Utf16Range,
    pub inserted_utf16_length: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommandWarning {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct PreparedCommand {
    pub envelope: CommandEnvelope,
    pub previous_revision: DocumentRevision,
    pub committed_revision: DocumentRevision,
    pub before_objects: Vec<crate::DocumentObject>,
    pub after_objects: Vec<crate::DocumentObject>,
    pub inverse: InverseOperation,
    pub result: CommandResult,
    pub(crate) next_state: Box<crate::EditorSessionState>,
}

impl PreparedCommand {
    pub fn object_id(&self) -> Option<ObjectId> {
        self.after_objects
            .first()
            .or_else(|| self.before_objects.first())
            .map(crate::DocumentObject::id)
    }
}
