use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    CommandEnvelope, DocumentId, DocumentModel, DocumentObject, DocumentRevision, InverseOperation,
    PreparedCommand,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DurableCommit {
    pub envelope: CommandEnvelope,
    pub previous_revision: DocumentRevision,
    pub committed_revision: DocumentRevision,
    pub before_objects: Vec<DocumentObject>,
    pub after_objects: Vec<DocumentObject>,
    pub inverse: InverseOperation,
    pub resulting_model: DocumentModel,
}

impl DurableCommit {
    pub fn from_prepared(prepared: &PreparedCommand) -> Self {
        Self {
            envelope: prepared.envelope.clone(),
            previous_revision: prepared.previous_revision,
            committed_revision: prepared.committed_revision,
            before_objects: prepared.before_objects.clone(),
            after_objects: prepared.after_objects.clone(),
            inverse: prepared.inverse.clone(),
            resulting_model: prepared
                .next_state
                .snapshot()
                .expect("a prepared command retains an open next state"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DurableSnapshot {
    pub model: DocumentModel,
    pub revision: DocumentRevision,
    pub undo_cursor: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum CheckpointKind {
    OpeningSource,
    User,
    Recovery,
    Tombstone,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectCheckpoint {
    pub label: String,
    pub revision: DocumentRevision,
    pub kind: CheckpointKind,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecoveryRequest {
    pub document_id: DocumentId,
    pub source_fingerprint: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecoveredProject {
    pub model: DocumentModel,
    pub undo_cursor: u64,
    pub materialized_revision: Option<DocumentRevision>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MaterializationRecord {
    pub revision: DocumentRevision,
    pub output_sha256: String,
    pub target_path: String,
}

pub trait ProjectRepository: Send + Sync {
    fn recover(&self, request: RecoveryRequest) -> Result<RecoveredProject, PersistenceError>;
    fn append(&self, commit: &DurableCommit) -> Result<(), PersistenceError>;
    fn write_snapshot(&self, snapshot: &DurableSnapshot) -> Result<(), PersistenceError>;
    fn checkpoint(&self, checkpoint: &ProjectCheckpoint) -> Result<(), PersistenceError>;
    fn record_materialization(&self, record: MaterializationRecord)
        -> Result<(), PersistenceError>;
    fn close(&self) -> Result<(), PersistenceError>;
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum PersistenceError {
    #[error("project repository is unavailable: {0}")]
    Unavailable(String),
    #[error("project schema is newer than this Clarix version")]
    SchemaTooNew,
    #[error("project source fingerprint does not match")]
    SourceMismatch,
    #[error("project data is corrupt: {0}")]
    Corrupt(String),
    #[error("project transaction failed: {0}")]
    Transaction(String),
}

impl PersistenceError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::Unavailable(_) => "sidecar_unavailable",
            Self::SchemaTooNew => "sidecar_schema_too_new",
            Self::SourceMismatch => "sidecar_source_mismatch",
            Self::Corrupt(_) => "sidecar_corrupt",
            Self::Transaction(_) => "sidecar_commit_failed",
        }
    }
}
