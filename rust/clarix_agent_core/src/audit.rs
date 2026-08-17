use std::collections::HashMap;
use std::sync::Mutex;

use clarix_editing_core::{CommandId, DocumentId, DocumentRevision};
use serde::{Deserialize, Serialize};

use crate::{
    AgentError, AgentRunEvent, AgentRunId, AgentRunRequest, AgentRunStatus, ApprovalId, ProposalId,
    ToolCallId,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentRunAuditHeader {
    pub run_id: AgentRunId,
    pub document_id: DocumentId,
    pub starting_revision: DocumentRevision,
    pub provider_id: String,
    pub model_id: String,
    pub status: AgentRunStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommandAuditLink {
    pub tool_call_id: ToolCallId,
    pub proposal_id: Option<ProposalId>,
    pub approval_id: Option<ApprovalId>,
    pub command_id: CommandId,
    pub previous_revision: DocumentRevision,
    pub committed_revision: DocumentRevision,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentRunAudit {
    pub header: AgentRunAuditHeader,
    pub events: Vec<AgentRunEvent>,
    pub command_links: Vec<CommandAuditLink>,
}

pub trait AgentRunRepository: Send + Sync + 'static {
    fn create_run(&self, request: &AgentRunRequest) -> Result<(), AgentError>;
    fn append_event(&self, event: AgentRunEvent) -> Result<(), AgentError>;
    fn link_command(&self, run_id: AgentRunId, link: CommandAuditLink) -> Result<(), AgentError>;
    fn set_status(&self, run_id: AgentRunId, status: AgentRunStatus) -> Result<(), AgentError>;
    fn read_run_audit(&self, run_id: AgentRunId) -> Result<AgentRunAudit, AgentError>;
}

#[derive(Default)]
pub struct InMemoryAgentRunRepository {
    runs: Mutex<HashMap<AgentRunId, AgentRunAudit>>,
}

impl InMemoryAgentRunRepository {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn read_run_audit(&self, run_id: AgentRunId) -> Result<AgentRunAudit, AgentError> {
        <Self as AgentRunRepository>::read_run_audit(self, run_id)
    }
}

impl AgentRunRepository for InMemoryAgentRunRepository {
    fn create_run(&self, request: &AgentRunRequest) -> Result<(), AgentError> {
        self.runs.lock().expect("agent audit mutex").insert(
            request.run_id,
            AgentRunAudit {
                header: AgentRunAuditHeader {
                    run_id: request.run_id,
                    document_id: request.document_id,
                    starting_revision: request.starting_revision,
                    provider_id: request.provider.provider_id.clone(),
                    model_id: request.provider.model_id.clone(),
                    status: AgentRunStatus::Queued,
                },
                events: vec![],
                command_links: vec![],
            },
        );
        Ok(())
    }

    fn append_event(&self, event: AgentRunEvent) -> Result<(), AgentError> {
        let mut runs = self.runs.lock().expect("agent audit mutex");
        let audit = runs.get_mut(&event.run_id).ok_or_else(audit_not_found)?;
        if let Some(previous) = audit.events.last() {
            if !previous.precedes(&event) {
                return Err(AgentError::InvalidEventSequence);
            }
        }
        audit.events.push(event);
        Ok(())
    }

    fn link_command(&self, run_id: AgentRunId, link: CommandAuditLink) -> Result<(), AgentError> {
        self.runs
            .lock()
            .expect("agent audit mutex")
            .get_mut(&run_id)
            .ok_or_else(audit_not_found)?
            .command_links
            .push(link);
        Ok(())
    }

    fn set_status(&self, run_id: AgentRunId, status: AgentRunStatus) -> Result<(), AgentError> {
        self.runs
            .lock()
            .expect("agent audit mutex")
            .get_mut(&run_id)
            .ok_or_else(audit_not_found)?
            .header
            .status = status;
        Ok(())
    }

    fn read_run_audit(&self, run_id: AgentRunId) -> Result<AgentRunAudit, AgentError> {
        self.runs
            .lock()
            .expect("agent audit mutex")
            .get(&run_id)
            .cloned()
            .ok_or_else(audit_not_found)
    }
}

fn audit_not_found() -> AgentError {
    AgentError::ProposalOperation {
        code: "run_not_found".into(),
        message: "agent run audit was not found".into(),
    }
}
