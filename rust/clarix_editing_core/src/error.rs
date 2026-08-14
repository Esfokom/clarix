use thiserror::Error;

use crate::{DocumentRevision, ObjectId};

#[derive(Debug, Clone, PartialEq, Error)]
pub enum EditingError {
    #[error("revision conflict: expected {expected:?}, actual {actual:?}")]
    RevisionConflict {
        expected: DocumentRevision,
        actual: DocumentRevision,
    },
    #[error("command ID has already been committed")]
    DuplicateCommand,
    #[error("text range is not on valid UTF-16 boundaries")]
    InvalidTextBoundary,
    #[error("object {0} was not found")]
    ObjectNotFound(ObjectId),
    #[error("object {0} has the wrong kind for this command")]
    WrongObjectKind(ObjectId),
    #[error("object {0} is read-only")]
    ReadOnly(ObjectId),
    #[error("editor session is closed")]
    SessionClosed,
    #[error("there is no command to undo")]
    NothingToUndo,
    #[error("there is no command to redo")]
    NothingToRedo,
    #[error("document revision overflow")]
    RevisionOverflow,
    #[error("invalid command: {0}")]
    InvalidCommand(String),
    #[error("editor actor is unavailable")]
    ActorUnavailable,
}

impl EditingError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::RevisionConflict { .. } => "revision_conflict",
            Self::DuplicateCommand => "duplicate_command",
            Self::InvalidTextBoundary => "invalid_text_boundary",
            Self::ObjectNotFound(_) => "object_not_found",
            Self::WrongObjectKind(_) => "wrong_object_kind",
            Self::ReadOnly(_) => "read_only",
            Self::SessionClosed => "session_closed",
            Self::NothingToUndo => "nothing_to_undo",
            Self::NothingToRedo => "nothing_to_redo",
            Self::RevisionOverflow => "revision_overflow",
            Self::InvalidCommand(_) => "invalid_command",
            Self::ActorUnavailable => "actor_unavailable",
        }
    }
}
