use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{AgentError, CancellationToken};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProviderRole {
    System,
    User,
    Assistant,
    Tool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderMessage {
    pub role: ProviderRole,
    pub content: String,
    pub tool_call_id: Option<String>,
    pub tool_calls: Vec<ProviderToolCall>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderToolDefinition {
    pub name: String,
    pub description: String,
    pub parameters: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderToolCall {
    pub id: String,
    pub name: String,
    pub arguments: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderRequest {
    pub messages: Vec<ProviderMessage>,
    pub tools: Vec<ProviderToolDefinition>,
    pub max_output_tokens: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderUsage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    pub total_tokens: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderCompletion {
    pub text: String,
    pub tool_calls: Vec<ProviderToolCall>,
    pub usage: Option<ProviderUsage>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProviderEvent {
    TextDelta(String),
}

pub trait ProviderEventSink {
    fn emit(&mut self, event: ProviderEvent) -> Result<(), AgentError>;
}

pub trait ModelProvider: Send + Sync {
    fn complete(
        &self,
        request: ProviderRequest,
        cancellation: &CancellationToken,
        sink: &mut dyn ProviderEventSink,
    ) -> Result<ProviderCompletion, AgentError>;
}
