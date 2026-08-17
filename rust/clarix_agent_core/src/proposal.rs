use std::collections::{HashMap, HashSet};

use clarix_editing_core::{
    CommandId, DocumentId, DocumentRevision, EditingError, EditingToolGateway, ObjectId, PageId,
    SelectionSet, ToolObservation, ToolRequest,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{AgentError, AgentRunId, ApprovalId, ProposalId, ToolCallId};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProposalStatus {
    AwaitingApproval,
    Approved,
    Rejected,
    Superseded,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProposalTargetDiff {
    pub object_id: ObjectId,
    pub page_id: PageId,
    pub page_number: u32,
    pub start_utf16: u32,
    pub end_utf16: u32,
    pub before_text: String,
    pub after_text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProposalDiff {
    pub targets: Vec<ProposalTargetDiff>,
    pub affected_object_count: u32,
    pub affected_page_count: u32,
    pub warnings: Vec<String>,
    pub risk_reasons: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
enum ProposalAction {
    TextRewrite {
        selection: SelectionSet,
        replacement: String,
    },
}

#[derive(Debug, Clone)]
pub struct ChangeProposalDraft {
    run_id: AgentRunId,
    tool_call_id: ToolCallId,
    document_id: DocumentId,
    base_revision: DocumentRevision,
    action: ProposalAction,
    diff: ProposalDiff,
}

impl ChangeProposalDraft {
    pub fn text_rewrite(
        run_id: AgentRunId,
        tool_call_id: ToolCallId,
        document_id: DocumentId,
        selection: SelectionSet,
        replacement: impl Into<String>,
        risk_reasons: Vec<String>,
    ) -> Self {
        let replacement = replacement.into();
        let diff = text_rewrite_diff(&selection, &replacement, vec![], risk_reasons);
        Self {
            run_id,
            tool_call_id,
            document_id,
            base_revision: selection.revision,
            action: ProposalAction::TextRewrite {
                selection,
                replacement,
            },
            diff,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApprovalToken {
    approval_id: ApprovalId,
    run_id: AgentRunId,
    proposal_id: ProposalId,
    base_revision: DocumentRevision,
    digest_sha256: String,
}

impl ApprovalToken {
    pub fn approval_id(&self) -> ApprovalId {
        self.approval_id
    }

    /// Creates an invalid binding for boundary tests and transport validation.
    #[doc(hidden)]
    pub fn for_run(&self, run_id: AgentRunId) -> Self {
        let mut token = self.clone();
        token.run_id = run_id;
        token
    }

    /// Creates an invalid binding for boundary tests and transport validation.
    #[doc(hidden)]
    pub fn for_digest(&self, digest_sha256: impl Into<String>) -> Self {
        let mut token = self.clone();
        token.digest_sha256 = digest_sha256.into();
        token
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChangeProposal {
    pub proposal_id: ProposalId,
    pub approval_id: ApprovalId,
    pub run_id: AgentRunId,
    pub tool_call_id: ToolCallId,
    pub document_id: DocumentId,
    pub base_revision: DocumentRevision,
    pub diff: ProposalDiff,
    pub digest_sha256: String,
    pub status: ProposalStatus,
    pub approval_token: ApprovalToken,
    action: ProposalAction,
}

#[derive(Serialize)]
struct DigestMaterial<'a> {
    proposal_id: ProposalId,
    run_id: AgentRunId,
    tool_call_id: ToolCallId,
    document_id: DocumentId,
    base_revision: DocumentRevision,
    diff: &'a ProposalDiff,
    action: &'a ProposalAction,
}

pub struct ProposalStore<G> {
    gateway: G,
    proposals: HashMap<ProposalId, ChangeProposal>,
    approvals: HashMap<ApprovalId, ProposalId>,
}

impl<G: EditingToolGateway> ProposalStore<G> {
    pub fn new(gateway: G) -> Self {
        Self {
            gateway,
            proposals: HashMap::new(),
            approvals: HashMap::new(),
        }
    }

    pub fn gateway(&self) -> &G {
        &self.gateway
    }

    pub fn proposal(&self, proposal_id: ProposalId) -> Option<&ChangeProposal> {
        self.proposals.get(&proposal_id)
    }

    pub fn request_approval(
        &mut self,
        draft: ChangeProposalDraft,
    ) -> Result<ChangeProposal, AgentError> {
        let proposal_id = ProposalId::new();
        let approval_id = ApprovalId::new();
        let digest_sha256 = proposal_digest(proposal_id, &draft)?;
        let approval_token = ApprovalToken {
            approval_id,
            run_id: draft.run_id,
            proposal_id,
            base_revision: draft.base_revision,
            digest_sha256: digest_sha256.clone(),
        };
        let proposal = ChangeProposal {
            proposal_id,
            approval_id,
            run_id: draft.run_id,
            tool_call_id: draft.tool_call_id,
            document_id: draft.document_id,
            base_revision: draft.base_revision,
            diff: draft.diff,
            digest_sha256,
            status: ProposalStatus::AwaitingApproval,
            approval_token,
            action: draft.action,
        };
        self.approvals.insert(approval_id, proposal_id);
        self.proposals.insert(proposal_id, proposal.clone());
        Ok(proposal)
    }

    pub fn approve(
        &mut self,
        token: ApprovalToken,
        current_revision: DocumentRevision,
    ) -> Result<ToolObservation, AgentError> {
        let proposal_id = self.validate_token(&token)?;
        let proposal = self.proposals.get(&proposal_id).expect("indexed proposal");
        ensure_awaiting(proposal.status)?;
        if current_revision != proposal.base_revision {
            return Err(AgentError::ProposalRevisionConflict {
                expected: proposal.base_revision,
                actual: current_revision,
            });
        }
        let request = commit_request(proposal);
        let observation = self.gateway.invoke(request).map_err(map_editing_error)?;
        self.proposals
            .get_mut(&proposal_id)
            .expect("indexed proposal")
            .status = ProposalStatus::Approved;
        Ok(observation)
    }

    pub fn reject(&mut self, token: ApprovalToken) -> Result<(), AgentError> {
        let proposal_id = self.validate_token(&token)?;
        let proposal = self
            .proposals
            .get_mut(&proposal_id)
            .expect("indexed proposal");
        ensure_awaiting(proposal.status)?;
        proposal.status = ProposalStatus::Rejected;
        Ok(())
    }

    pub fn rebase(
        &mut self,
        token: ApprovalToken,
        current_revision: DocumentRevision,
    ) -> Result<ChangeProposal, AgentError> {
        let proposal_id = self.validate_token(&token)?;
        let old = self.proposals.get(&proposal_id).expect("indexed proposal");
        ensure_awaiting(old.status)?;
        let draft = rebased_draft(old, current_revision);
        self.gateway
            .invoke(preview_request(&draft.action))
            .map_err(map_editing_error)?;
        self.proposals
            .get_mut(&proposal_id)
            .expect("indexed proposal")
            .status = ProposalStatus::Superseded;
        self.request_approval(draft)
    }

    fn validate_token(&self, token: &ApprovalToken) -> Result<ProposalId, AgentError> {
        let proposal_id = *self
            .approvals
            .get(&token.approval_id)
            .ok_or(AgentError::ApprovalNotFound)?;
        let proposal = self.proposals.get(&proposal_id).expect("indexed proposal");
        if token.proposal_id != proposal.proposal_id
            || token.run_id != proposal.run_id
            || token.base_revision != proposal.base_revision
            || token.digest_sha256 != proposal.digest_sha256
        {
            return Err(AgentError::ApprovalBindingMismatch);
        }
        Ok(proposal_id)
    }
}

fn proposal_digest(
    proposal_id: ProposalId,
    draft: &ChangeProposalDraft,
) -> Result<String, AgentError> {
    let bytes = serde_json::to_vec(&DigestMaterial {
        proposal_id,
        run_id: draft.run_id,
        tool_call_id: draft.tool_call_id,
        document_id: draft.document_id,
        base_revision: draft.base_revision,
        diff: &draft.diff,
        action: &draft.action,
    })
    .map_err(|error| AgentError::ProposalOperation {
        code: "digest_serialization".into(),
        message: error.to_string(),
    })?;
    Ok(format!("{:x}", Sha256::digest(bytes)))
}

fn text_rewrite_diff(
    selection: &SelectionSet,
    replacement: &str,
    warnings: Vec<String>,
    risk_reasons: Vec<String>,
) -> ProposalDiff {
    let targets = selection
        .ranges
        .iter()
        .map(|range| ProposalTargetDiff {
            object_id: range.object_id,
            page_id: range.page_id,
            page_number: range.page_number,
            start_utf16: range.start_utf16,
            end_utf16: range.end_utf16,
            before_text: range.quoted_text.clone(),
            after_text: replacement.into(),
        })
        .collect::<Vec<_>>();
    ProposalDiff {
        affected_object_count: targets
            .iter()
            .map(|target| target.object_id)
            .collect::<HashSet<_>>()
            .len() as u32,
        affected_page_count: targets
            .iter()
            .map(|target| target.page_id)
            .collect::<HashSet<_>>()
            .len() as u32,
        targets,
        warnings,
        risk_reasons,
    }
}

fn ensure_awaiting(status: ProposalStatus) -> Result<(), AgentError> {
    if status != ProposalStatus::AwaitingApproval {
        return Err(AgentError::ApprovalAlreadyResolved);
    }
    Ok(())
}

fn commit_request(proposal: &ChangeProposal) -> ToolRequest {
    let provenance_ids = vec![
        proposal.run_id.to_string(),
        proposal.tool_call_id.to_string(),
        proposal.proposal_id.to_string(),
        proposal.approval_id.to_string(),
    ];
    match &proposal.action {
        ProposalAction::TextRewrite {
            selection,
            replacement,
        } => ToolRequest::ReplaceTextRange {
            command_id: CommandId::new(),
            selection: selection.clone(),
            replacement: replacement.clone(),
            provenance_ids,
        },
    }
}

fn preview_request(action: &ProposalAction) -> ToolRequest {
    match action {
        ProposalAction::TextRewrite {
            selection,
            replacement,
        } => ToolRequest::PreviewTextRewrite {
            selection: selection.clone(),
            replacement: replacement.clone(),
        },
    }
}

fn rebased_draft(
    proposal: &ChangeProposal,
    current_revision: DocumentRevision,
) -> ChangeProposalDraft {
    match &proposal.action {
        ProposalAction::TextRewrite {
            selection,
            replacement,
        } => {
            let mut selection = selection.clone();
            selection.revision = current_revision;
            ChangeProposalDraft::text_rewrite(
                proposal.run_id,
                proposal.tool_call_id,
                proposal.document_id,
                selection,
                replacement,
                proposal.diff.risk_reasons.clone(),
            )
        }
    }
}

fn map_editing_error(error: EditingError) -> AgentError {
    match error {
        EditingError::RevisionConflict { expected, actual } => {
            AgentError::ProposalRevisionConflict { expected, actual }
        }
        EditingError::SelectionQuoteMismatch { .. } => AgentError::ProposalQuoteMismatch,
        other => AgentError::ProposalOperation {
            code: other.code().into(),
            message: other.to_string(),
        },
    }
}
