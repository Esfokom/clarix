use serde::{Deserialize, Serialize};

use crate::{ToolRiskClass, ValidatedToolCall};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PermissionDecision {
    Automatic,
    ApprovalRequired { reasons: Vec<String> },
    ExplicitUiAction,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct PermissionPolicy;

impl PermissionPolicy {
    pub const fn new() -> Self {
        Self
    }

    pub fn decide(&self, call: &ValidatedToolCall) -> PermissionDecision {
        match call.manifest.risk {
            ToolRiskClass::ReadOnly | ToolRiskClass::Preview => PermissionDecision::Automatic,
            ToolRiskClass::LocalMutation
                if call.affected.range_count == 1
                    && call.affected.object_count == 1
                    && !call.affected.bulk =>
            {
                PermissionDecision::Automatic
            }
            ToolRiskClass::LocalMutation => PermissionDecision::ApprovalRequired {
                reasons: vec!["changes more than one selected target".into()],
            },
            ToolRiskClass::BulkMutation => PermissionDecision::ApprovalRequired {
                reasons: vec!["changes multiple document targets".into()],
            },
            ToolRiskClass::HistoryMutation => PermissionDecision::ApprovalRequired {
                reasons: vec!["changes document history".into()],
            },
            ToolRiskClass::ExplicitSave => PermissionDecision::ExplicitUiAction,
        }
    }
}
