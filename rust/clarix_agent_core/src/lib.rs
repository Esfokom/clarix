pub const AGENT_CORE_SCHEMA_VERSION: u32 = 1;

mod cancellation;
mod model;
mod openai_stream;
mod policy;
mod provider;
mod tool_registry;

pub use cancellation::CancellationToken;
pub use model::{
    AgentError, AgentProviderConfig, AgentRunEvent, AgentRunEventKind, AgentRunId, AgentRunOutcome,
    AgentRunRequest, AgentRunRequestAudit, AgentRunStatus, ApprovalId, ConversationId, ProposalId,
    ProviderRoundId, RunBudgets, SecretString, ToolCallId,
};
pub use openai_stream::OpenAiStreamDecoder;
pub use policy::{PermissionDecision, PermissionPolicy};
pub use provider::{
    ModelProvider, ProviderCompletion, ProviderEvent, ProviderEventSink, ProviderMessage,
    ProviderRequest, ProviderRole, ProviderToolCall, ProviderToolDefinition, ProviderUsage,
};
pub use tool_registry::{
    AffectedScope, ToolApprovalRule, ToolExecution, ToolManifest, ToolRegistry,
    ToolRevisionBehavior, ToolRiskClass, ToolScope, ToolValidationContext, ValidatedToolCall,
};

use clarix_editing_core::{EditingError, EditingToolGateway, ToolObservation, ToolRequest};

pub struct AgentRunBoundary<G> {
    gateway: G,
}

impl<G> AgentRunBoundary<G>
where
    G: EditingToolGateway,
{
    pub fn new(gateway: G) -> Self {
        Self { gateway }
    }

    pub fn invoke(&self, request: ToolRequest) -> Result<ToolObservation, EditingError> {
        self.gateway.invoke(request)
    }

    pub fn gateway(&self) -> &G {
        &self.gateway
    }
}
