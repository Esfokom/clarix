use std::path::Path;
use std::str::FromStr;
use std::sync::{Mutex, MutexGuard};

use clarix_agent_core::{
    AgentError, AgentRunAudit, AgentRunAuditHeader, AgentRunEvent, AgentRunEventKind, AgentRunId,
    AgentRunRepository, AgentRunRequest, AgentRunStatus, CommandAuditLink,
};
use clarix_editing_core::{DocumentId, DocumentRevision};
use rusqlite::{params, Connection, OptionalExtension, Transaction};

use crate::{schema, StoreError};

pub struct SqliteAgentRunRepository {
    connection: Mutex<Connection>,
}

impl SqliteAgentRunRepository {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StoreError> {
        let connection = Connection::open(path)?;
        Self::from_connection(connection)
    }

    pub fn open_in_memory() -> Result<Self, StoreError> {
        Self::from_connection(Connection::open_in_memory()?)
    }

    fn from_connection(connection: Connection) -> Result<Self, StoreError> {
        schema::initialize(&connection)?;
        recover_interrupted(&connection)?;
        Ok(Self {
            connection: Mutex::new(connection),
        })
    }

    pub fn checkpoint(&self) -> Result<(), StoreError> {
        self.connection
            .lock()
            .map_err(|_| StoreError::Poisoned)?
            .execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
        Ok(())
    }

    pub fn read_run_audit(&self, run_id: AgentRunId) -> Result<AgentRunAudit, AgentError> {
        <Self as AgentRunRepository>::read_run_audit(self, run_id)
    }

    fn connection(&self) -> Result<MutexGuard<'_, Connection>, AgentError> {
        self.connection
            .lock()
            .map_err(|_| agent_store_error("repository lock is poisoned"))
    }
}

impl AgentRunRepository for SqliteAgentRunRepository {
    fn create_run(&self, request: &AgentRunRequest) -> Result<(), AgentError> {
        let mut connection = self.connection()?;
        let transaction = connection.transaction().map_err(map_sqlite)?;
        transaction
            .execute(
                "INSERT OR IGNORE INTO agent_conversations (conversation_id, document_id) VALUES (?1, ?2)",
                params![request.conversation_id.to_string(), request.document_id.to_string()],
            )
            .map_err(map_sqlite)?;
        transaction
            .execute(
                "INSERT INTO agent_runs
                 (run_id, conversation_id, document_id, starting_revision, provider_id, model_id, status)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    request.run_id.to_string(),
                    request.conversation_id.to_string(),
                    request.document_id.to_string(),
                    revision_to_i64(request.starting_revision)?,
                    request.provider.provider_id,
                    request.provider.model_id,
                    status_json(AgentRunStatus::Queued)?,
                ],
            )
            .map_err(map_sqlite)?;
        transaction.commit().map_err(map_sqlite)
    }

    fn append_event(&self, event: AgentRunEvent) -> Result<(), AgentError> {
        let mut connection = self.connection()?;
        let transaction = connection.transaction().map_err(map_sqlite)?;
        let last_sequence = transaction
            .query_row(
                "SELECT MAX(sequence) FROM agent_events WHERE run_id = ?1",
                [event.run_id.to_string()],
                |row| row.get::<_, Option<i64>>(0),
            )
            .map_err(map_sqlite)?;
        if last_sequence.is_some_and(|last| event.sequence <= last as u64) {
            return Err(AgentError::InvalidEventSequence);
        }
        let payload = serde_json::to_string(&event).map_err(map_json)?;
        transaction
            .execute(
                "INSERT INTO agent_events (run_id, sequence, document_revision, payload_json)
                 VALUES (?1, ?2, ?3, ?4)",
                params![
                    event.run_id.to_string(),
                    u64_to_i64(event.sequence)?,
                    revision_to_i64(event.document_revision)?,
                    payload,
                ],
            )
            .map_err(map_sqlite)?;
        apply_event_links(&transaction, &event)?;
        transaction.commit().map_err(map_sqlite)
    }

    fn link_command(&self, run_id: AgentRunId, link: CommandAuditLink) -> Result<(), AgentError> {
        let connection = self.connection()?;
        let changed = connection
            .execute(
                "UPDATE agent_tool_calls
                 SET proposal_id = COALESCE(?3, proposal_id),
                     approval_id = COALESCE(?4, approval_id), command_id = ?5,
                     previous_revision = ?6, committed_revision = ?7
                 WHERE run_id = ?1 AND tool_call_id = ?2",
                params![
                    run_id.to_string(),
                    link.tool_call_id.to_string(),
                    link.proposal_id.map(|id| id.to_string()),
                    link.approval_id.map(|id| id.to_string()),
                    link.command_id.to_string(),
                    revision_to_i64(link.previous_revision)?,
                    revision_to_i64(link.committed_revision)?,
                ],
            )
            .map_err(map_sqlite)?;
        if changed != 1 {
            return Err(agent_store_error(
                "tool call for command link was not found",
            ));
        }
        Ok(())
    }

    fn set_status(&self, run_id: AgentRunId, status: AgentRunStatus) -> Result<(), AgentError> {
        let connection = self.connection()?;
        let changed = connection
            .execute(
                "UPDATE agent_runs SET status = ?2 WHERE run_id = ?1",
                params![run_id.to_string(), status_json(status)?],
            )
            .map_err(map_sqlite)?;
        if changed != 1 {
            return Err(agent_store_error("agent run was not found"));
        }
        Ok(())
    }

    fn read_run_audit(&self, run_id: AgentRunId) -> Result<AgentRunAudit, AgentError> {
        let connection = self.connection()?;
        let header = connection
            .query_row(
                "SELECT document_id, starting_revision, provider_id, model_id, status
                 FROM agent_runs WHERE run_id = ?1",
                [run_id.to_string()],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, String>(3)?,
                        row.get::<_, String>(4)?,
                    ))
                },
            )
            .optional()
            .map_err(map_sqlite)?
            .ok_or_else(|| agent_store_error("agent run was not found"))?;
        let header = AgentRunAuditHeader {
            run_id,
            document_id: DocumentId::from_str(&header.0)
                .map_err(|error| agent_store_error(&error.to_string()))?,
            starting_revision: i64_to_revision(header.1)?,
            provider_id: header.2,
            model_id: header.3,
            status: serde_json::from_str(&header.4).map_err(map_json)?,
        };

        let mut event_statement = connection
            .prepare("SELECT payload_json FROM agent_events WHERE run_id = ?1 ORDER BY sequence")
            .map_err(map_sqlite)?;
        let events = event_statement
            .query_map([run_id.to_string()], |row| row.get::<_, String>(0))
            .map_err(map_sqlite)?
            .map(|payload| {
                payload
                    .map_err(map_sqlite)
                    .and_then(|payload| serde_json::from_str(&payload).map_err(map_json))
            })
            .collect::<Result<Vec<AgentRunEvent>, AgentError>>()?;

        let mut link_statement = connection
            .prepare(
                "SELECT tool_call_id, proposal_id, approval_id, command_id,
                        previous_revision, committed_revision
                 FROM agent_tool_calls
                 WHERE run_id = ?1 AND command_id IS NOT NULL
                 ORDER BY rowid",
            )
            .map_err(map_sqlite)?;
        let raw_links = link_statement
            .query_map([run_id.to_string()], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(5)?,
                ))
            })
            .map_err(map_sqlite)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_sqlite)?;
        let command_links = raw_links
            .into_iter()
            .map(|raw| {
                Ok(CommandAuditLink {
                    tool_call_id: parse_id(&raw.0)?,
                    proposal_id: raw.1.as_deref().map(parse_id).transpose()?,
                    approval_id: raw.2.as_deref().map(parse_id).transpose()?,
                    command_id: parse_id(&raw.3)?,
                    previous_revision: i64_to_revision(raw.4)?,
                    committed_revision: i64_to_revision(raw.5)?,
                })
            })
            .collect::<Result<Vec<_>, AgentError>>()?;

        Ok(AgentRunAudit {
            header,
            events,
            command_links,
        })
    }
}

fn apply_event_links(
    transaction: &Transaction<'_>,
    event: &AgentRunEvent,
) -> Result<(), AgentError> {
    match &event.kind {
        AgentRunEventKind::ToolStarted { tool_call_id, name } => {
            transaction
                .execute(
                    "INSERT INTO agent_tool_calls (run_id, tool_call_id, name) VALUES (?1, ?2, ?3)",
                    params![event.run_id.to_string(), tool_call_id.to_string(), name],
                )
                .map_err(map_sqlite)?;
        }
        AgentRunEventKind::ToolCompleted {
            tool_call_id,
            success,
        } => {
            transaction
                .execute(
                    "UPDATE agent_tool_calls SET success = ?3 WHERE run_id = ?1 AND tool_call_id = ?2",
                    params![event.run_id.to_string(), tool_call_id.to_string(), i64::from(*success)],
                )
                .map_err(map_sqlite)?;
        }
        AgentRunEventKind::ApprovalRequested { proposal } => {
            let tool_call_id: String = transaction
                .query_row(
                    "SELECT tool_call_id FROM agent_tool_calls WHERE run_id = ?1 ORDER BY rowid DESC LIMIT 1",
                    [event.run_id.to_string()],
                    |row| row.get(0),
                )
                .map_err(map_sqlite)?;
            transaction
                .execute(
                    "INSERT INTO agent_proposals (proposal_id, run_id, tool_call_id, digest_sha256, payload_json) VALUES (?1, ?2, ?3, ?4, ?5)",
                    params![proposal.proposal_id.to_string(), event.run_id.to_string(), tool_call_id, proposal.digest_sha256, serde_json::to_string(proposal).map_err(map_json)?],
                )
                .map_err(map_sqlite)?;
            transaction
                .execute(
                    "INSERT INTO agent_approvals (approval_id, proposal_id, run_id, status) VALUES (?1, ?2, ?3, 'pending')",
                    params![proposal.approval_id.to_string(), proposal.proposal_id.to_string(), event.run_id.to_string()],
                )
                .map_err(map_sqlite)?;
            transaction
                .execute(
                    "UPDATE agent_tool_calls SET proposal_id = ?3, approval_id = ?4 WHERE run_id = ?1 AND tool_call_id = ?2",
                    params![event.run_id.to_string(), tool_call_id, proposal.proposal_id.to_string(), proposal.approval_id.to_string()],
                )
                .map_err(map_sqlite)?;
        }
        AgentRunEventKind::ApprovalResolved {
            approval_id,
            approved,
        } => {
            transaction
                .execute(
                    "UPDATE agent_approvals SET status = ?2 WHERE approval_id = ?1",
                    params![
                        approval_id.to_string(),
                        if *approved { "approved" } else { "rejected" }
                    ],
                )
                .map_err(map_sqlite)?;
        }
        _ => {}
    }
    Ok(())
}

fn recover_interrupted(connection: &Connection) -> Result<(), StoreError> {
    let failed = serde_json::to_string(&AgentRunStatus::Failed)?;
    for interrupted in [
        AgentRunStatus::Queued,
        AgentRunStatus::AssemblingContext,
        AgentRunStatus::CallingProvider,
        AgentRunStatus::ExecutingTool,
    ] {
        connection.execute(
            "UPDATE agent_runs SET status = ?1, failure_code = 'interrupted' WHERE status = ?2",
            params![failed, serde_json::to_string(&interrupted)?],
        )?;
    }
    Ok(())
}

fn status_json(status: AgentRunStatus) -> Result<String, AgentError> {
    serde_json::to_string(&status).map_err(map_json)
}

fn revision_to_i64(revision: DocumentRevision) -> Result<i64, AgentError> {
    u64_to_i64(revision.value())
}

fn u64_to_i64(value: u64) -> Result<i64, AgentError> {
    i64::try_from(value).map_err(|_| agent_store_error("integer is outside SQLite range"))
}

fn i64_to_revision(value: i64) -> Result<DocumentRevision, AgentError> {
    u64::try_from(value)
        .map(DocumentRevision::from_value)
        .map_err(|_| agent_store_error("negative document revision in agent audit"))
}

fn parse_id<T: FromStr>(value: &str) -> Result<T, AgentError>
where
    T::Err: std::fmt::Display,
{
    T::from_str(value).map_err(|error| agent_store_error(&error.to_string()))
}

fn map_sqlite(error: rusqlite::Error) -> AgentError {
    agent_store_error(&error.to_string())
}

fn map_json(error: serde_json::Error) -> AgentError {
    agent_store_error(&error.to_string())
}

fn agent_store_error(message: &str) -> AgentError {
    AgentError::Tool {
        code: "agent_store".into(),
        message: message.into(),
    }
}
