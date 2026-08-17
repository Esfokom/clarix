use std::{collections::BTreeMap, fmt, str::FromStr};

use clarix_editing_core::{CommandId, DocumentId, DocumentRevision, SelectionContext};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

macro_rules! agent_uuid_id {
    ($name:ident) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
        #[serde(transparent)]
        pub struct $name(Uuid);

        impl $name {
            pub fn new() -> Self {
                Self(Uuid::new_v4())
            }
        }

        impl Default for $name {
            fn default() -> Self {
                Self::new()
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                self.0.hyphenated().fmt(formatter)
            }
        }

        impl FromStr for $name {
            type Err = uuid::Error;

            fn from_str(value: &str) -> Result<Self, Self::Err> {
                Uuid::parse_str(value).map(Self)
            }
        }
    };
}

agent_uuid_id!(AgentRunId);
agent_uuid_id!(ConversationId);
agent_uuid_id!(ProviderRoundId);
agent_uuid_id!(ToolCallId);
agent_uuid_id!(ProposalId);
agent_uuid_id!(ApprovalId);

#[derive(Clone, PartialEq, Eq)]
pub struct SecretString(String);

impl SecretString {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn expose_secret(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for SecretString {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("[REDACTED]")
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct AgentProviderConfig {
    pub provider_id: String,
    pub endpoint: String,
    pub model_id: String,
    pub headers: BTreeMap<String, String>,
    pub api_key: SecretString,
}

impl fmt::Debug for AgentProviderConfig {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AgentProviderConfig")
            .field("provider_id", &self.provider_id)
            .field("endpoint", &self.endpoint)
            .field("model_id", &self.model_id)
            .field("header_names", &self.headers.keys().collect::<Vec<_>>())
            .field("api_key", &self.api_key)
            .finish()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunBudgets {
    pub max_tool_calls: u32,
    pub max_provider_rounds: u32,
    pub max_elapsed_ms: u64,
    pub max_output_tokens: u32,
}

impl Default for RunBudgets {
    fn default() -> Self {
        Self {
            max_tool_calls: 12,
            max_provider_rounds: 6,
            max_elapsed_ms: 120_000,
            max_output_tokens: 8_192,
        }
    }
}

impl RunBudgets {
    pub fn validate(self) -> Result<Self, AgentError> {
        if self.max_tool_calls == 0 {
            return Err(AgentError::InvalidBudgets(
                "max_tool_calls must be positive".into(),
            ));
        }
        if self.max_provider_rounds == 0 {
            return Err(AgentError::InvalidBudgets(
                "max_provider_rounds must be positive".into(),
            ));
        }
        if self.max_elapsed_ms == 0 {
            return Err(AgentError::InvalidBudgets(
                "max_elapsed_ms must be positive".into(),
            ));
        }
        if self.max_output_tokens == 0 {
            return Err(AgentError::InvalidBudgets(
                "max_output_tokens must be positive".into(),
            ));
        }
        Ok(self)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AgentRunStatus {
    Queued,
    AssemblingContext,
    CallingProvider,
    ExecutingTool,
    AwaitingApproval,
    BudgetPaused,
    Completed,
    Cancelled,
    Failed,
}

impl AgentRunStatus {
    pub const fn is_terminal(self) -> bool {
        matches!(self, Self::Completed | Self::Cancelled | Self::Failed)
    }

    pub const fn can_transition_to(self, next: Self) -> bool {
        match self {
            Self::Queued => matches!(
                next,
                Self::AssemblingContext | Self::Cancelled | Self::Failed
            ),
            Self::AssemblingContext => {
                matches!(next, Self::CallingProvider | Self::Cancelled | Self::Failed)
            }
            Self::CallingProvider => matches!(
                next,
                Self::ExecutingTool
                    | Self::AwaitingApproval
                    | Self::BudgetPaused
                    | Self::Completed
                    | Self::Cancelled
                    | Self::Failed
            ),
            Self::ExecutingTool => matches!(
                next,
                Self::CallingProvider
                    | Self::AwaitingApproval
                    | Self::BudgetPaused
                    | Self::Completed
                    | Self::Cancelled
                    | Self::Failed
            ),
            Self::AwaitingApproval => matches!(
                next,
                Self::ExecutingTool | Self::CallingProvider | Self::Cancelled | Self::Failed
            ),
            Self::BudgetPaused => {
                matches!(next, Self::CallingProvider | Self::Cancelled | Self::Failed)
            }
            Self::Completed | Self::Cancelled | Self::Failed => false,
        }
    }
}

#[derive(Debug, Clone)]
pub struct AgentRunRequest {
    pub run_id: AgentRunId,
    pub conversation_id: ConversationId,
    pub document_id: DocumentId,
    pub starting_revision: DocumentRevision,
    pub user_prompt: String,
    pub selection_context: Option<SelectionContext>,
    pub provider: AgentProviderConfig,
    pub budgets: RunBudgets,
}

impl AgentRunRequest {
    pub fn audit_view(&self) -> AgentRunRequestAudit<'_> {
        AgentRunRequestAudit {
            run_id: self.run_id,
            conversation_id: self.conversation_id,
            document_id: self.document_id,
            starting_revision: self.starting_revision,
            user_prompt: &self.user_prompt,
            provider_id: &self.provider.provider_id,
            model_id: &self.provider.model_id,
            header_names: self.provider.headers.keys().map(String::as_str).collect(),
            budgets: self.budgets,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct AgentRunRequestAudit<'a> {
    pub run_id: AgentRunId,
    pub conversation_id: ConversationId,
    pub document_id: DocumentId,
    pub starting_revision: DocumentRevision,
    pub user_prompt: &'a str,
    pub provider_id: &'a str,
    pub model_id: &'a str,
    pub header_names: Vec<&'a str>,
    pub budgets: RunBudgets,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AgentRunOutcome {
    Completed,
    Cancelled,
    Failed { code: String },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum AgentRunEventKind {
    StatusChanged {
        status: AgentRunStatus,
    },
    TextDelta {
        text: String,
    },
    ContextDisclosed {
        disclosure_sha256: String,
    },
    ToolStarted {
        tool_call_id: ToolCallId,
        name: String,
    },
    ToolCompleted {
        tool_call_id: ToolCallId,
        success: bool,
    },
    ApprovalRequested {
        proposal_id: ProposalId,
        approval_id: ApprovalId,
    },
    ApprovalResolved {
        approval_id: ApprovalId,
        approved: bool,
    },
    CommandCommitted {
        command_id: CommandId,
        previous_revision: DocumentRevision,
        committed_revision: DocumentRevision,
    },
    SaveRequested,
    BudgetPaused {
        reason: String,
    },
    Finished {
        outcome: AgentRunOutcome,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentRunEvent {
    pub schema_version: u32,
    pub run_id: AgentRunId,
    pub sequence: u64,
    pub document_revision: DocumentRevision,
    pub kind: AgentRunEventKind,
}

impl AgentRunEvent {
    pub fn new(
        run_id: AgentRunId,
        sequence: u64,
        document_revision: DocumentRevision,
        kind: AgentRunEventKind,
    ) -> Result<Self, AgentError> {
        if sequence == 0 {
            return Err(AgentError::InvalidEventSequence);
        }
        Ok(Self {
            schema_version: crate::AGENT_CORE_SCHEMA_VERSION,
            run_id,
            sequence,
            document_revision,
            kind,
        })
    }

    pub fn precedes(&self, next: &Self) -> bool {
        self.run_id == next.run_id && self.sequence < next.sequence
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum AgentError {
    #[error("agent run was cancelled")]
    Cancelled,
    #[error("invalid run budgets: {0}")]
    InvalidBudgets(String),
    #[error("agent event sequence must be positive and monotonic")]
    InvalidEventSequence,
    #[error("invalid agent run status transition")]
    InvalidStatusTransition,
    #[error("unknown agent tool: {0}")]
    UnknownTool(String),
    #[error("invalid tool arguments: {0}")]
    InvalidToolArguments(String),
    #[error("document {0} is outside the active agent scope")]
    DocumentNotAllowed(DocumentId),
    #[error("approval token was not found")]
    ApprovalNotFound,
    #[error("approval was already resolved")]
    ApprovalAlreadyResolved,
    #[error("approval token does not match its proposal binding")]
    ApprovalBindingMismatch,
    #[error("proposal revision conflict: expected {expected:?}, actual {actual:?}")]
    ProposalRevisionConflict {
        expected: DocumentRevision,
        actual: DocumentRevision,
    },
    #[error("proposal quote no longer matches the document")]
    ProposalQuoteMismatch,
    #[error("proposal operation failed ({code}): {message}")]
    ProposalOperation { code: String, message: String },
    #[error("provider failure ({code}): {message}")]
    Provider { code: String, message: String },
    #[error("tool failure ({code}): {message}")]
    Tool { code: String, message: String },
}

impl AgentError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::Cancelled => "cancelled",
            Self::InvalidBudgets(_) => "invalid_budgets",
            Self::InvalidEventSequence => "invalid_event_sequence",
            Self::InvalidStatusTransition => "invalid_status_transition",
            Self::UnknownTool(_) => "unknown_tool",
            Self::InvalidToolArguments(_) => "invalid_tool_arguments",
            Self::DocumentNotAllowed(_) => "document_not_allowed",
            Self::ApprovalNotFound => "approval_not_found",
            Self::ApprovalAlreadyResolved => "approval_already_resolved",
            Self::ApprovalBindingMismatch => "approval_binding_mismatch",
            Self::ProposalRevisionConflict { .. } => "proposal_revision_conflict",
            Self::ProposalQuoteMismatch => "proposal_quote_mismatch",
            Self::ProposalOperation { .. } => "proposal_operation_failed",
            Self::Provider { .. } => "provider_failure",
            Self::Tool { .. } => "tool_failure",
        }
    }
}
