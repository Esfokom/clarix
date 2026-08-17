mod agent_repository;
mod location;
mod repository;
mod schema;

use clarix_editing_core::{DocumentModel, DocumentRevision};
use thiserror::Error;

pub use location::ProjectLocation;
pub use repository::SqliteProjectRepository;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FaultPoint {
    BeforeBegin,
    AfterCommandInsert,
    AfterInverseInsert,
    AfterModelUpdate,
    BeforeCommit,
    AfterCommit,
    DuringWalCheckpoint,
}

#[derive(Debug, Clone)]
pub struct ProjectSeed {
    pub model: DocumentModel,
    pub undo_cursor: u64,
    pub materialized_revision: Option<DocumentRevision>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StoreTable {
    Commands,
    InverseOperations,
}

impl StoreTable {
    pub(crate) const fn sql_name(self) -> &'static str {
        match self {
            Self::Commands => "commands",
            Self::InverseOperations => "inverse_operations",
        }
    }
}

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("I/O failure: {0}")]
    Io(#[from] std::io::Error),
    #[error("SQLite failure: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("serialization failure: {0}")]
    Serialization(#[from] serde_json::Error),
    #[error("project schema version {0} is newer than supported")]
    SchemaTooNew(i64),
    #[error("project document ID does not match")]
    DocumentMismatch,
    #[error("project source fingerprint does not match")]
    SourceMismatch,
    #[error("integer value is outside SQLite range")]
    IntegerRange,
    #[error("repository lock is poisoned")]
    Poisoned,
}
pub use agent_repository::SqliteAgentRunRepository;
