use std::sync::Mutex;

use clarix_agent_core::AgentRunBoundary;
use clarix_editing_core::{
    DocumentRevision, EditingError, EditingToolGateway, ToolObservation, ToolRequest,
};

struct RecordingGateway {
    revision: DocumentRevision,
    requests: Mutex<Vec<ToolRequest>>,
}

impl RecordingGateway {
    fn new(revision: DocumentRevision) -> Self {
        Self {
            revision,
            requests: Mutex::new(Vec::new()),
        }
    }
}

impl EditingToolGateway for RecordingGateway {
    fn invoke(&self, request: ToolRequest) -> Result<ToolObservation, EditingError> {
        self.requests.lock().unwrap().push(request);
        Ok(ToolObservation::Document {
            revision: self.revision,
            page_count: 1,
            object_count: 3,
        })
    }
}

#[test]
fn agent_can_only_observe_or_submit_typed_tools() {
    let gateway = RecordingGateway::new(DocumentRevision::INITIAL);
    let boundary = AgentRunBoundary::new(gateway);
    let observation = boundary
        .invoke(ToolRequest::InspectDocument {
            revision: DocumentRevision::INITIAL,
        })
        .unwrap();
    assert_eq!(observation.revision(), DocumentRevision::INITIAL);
    assert_eq!(boundary.gateway().requests.lock().unwrap().len(), 1);
}
