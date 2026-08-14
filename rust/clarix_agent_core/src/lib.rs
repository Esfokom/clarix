pub const AGENT_CORE_SCHEMA_VERSION: u32 = 1;

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
