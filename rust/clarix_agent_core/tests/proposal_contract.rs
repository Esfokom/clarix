use std::sync::Mutex;

use clarix_agent_core::{
    AgentRunId, ChangeProposalDraft, ProposalStatus, ProposalStore, ToolCallId,
};
use clarix_editing_core::{
    CommandResult, DocumentId, DocumentRevision, EditingError, EditingToolGateway, ObjectId,
    PageId, SelectionKind, SelectionSet, TextRangeRef, ToolObservation, ToolRequest,
};

struct FakeGateway {
    state: Mutex<FakeState>,
}

struct FakeState {
    revision: DocumentRevision,
    text: String,
}

impl FakeGateway {
    fn new(revision: u64, text: &str) -> Self {
        Self {
            state: Mutex::new(FakeState {
                revision: DocumentRevision::from_value(revision),
                text: text.into(),
            }),
        }
    }

    fn text(&self) -> String {
        self.state.lock().unwrap().text.clone()
    }
}

impl EditingToolGateway for FakeGateway {
    fn invoke(&self, request: ToolRequest) -> Result<ToolObservation, EditingError> {
        let mut state = self.state.lock().unwrap();
        match request {
            ToolRequest::PreviewTextRewrite {
                mut selection,
                replacement,
            } => {
                if selection.revision != state.revision {
                    return Err(EditingError::RevisionConflict {
                        expected: selection.revision,
                        actual: state.revision,
                    });
                }
                let range = &selection.ranges[0];
                if range.quoted_text != state.text {
                    return Err(EditingError::SelectionQuoteMismatch {
                        object_id: range.object_id,
                    });
                }
                selection.revision = state.revision;
                Ok(ToolObservation::RewritePreview {
                    revision: state.revision,
                    selection,
                    replacement,
                })
            }
            ToolRequest::ReplaceTextRange {
                command_id,
                selection,
                replacement,
                ..
            } => {
                if selection.revision != state.revision {
                    return Err(EditingError::RevisionConflict {
                        expected: selection.revision,
                        actual: state.revision,
                    });
                }
                if selection.ranges[0].quoted_text != state.text {
                    return Err(EditingError::SelectionQuoteMismatch {
                        object_id: selection.ranges[0].object_id,
                    });
                }
                let previous_revision = state.revision;
                state.revision = state.revision.next().unwrap();
                state.text = replacement;
                Ok(ToolObservation::Command {
                    result: CommandResult {
                        command_id,
                        previous_revision,
                        committed_revision: state.revision,
                        object_patches: vec![],
                        removed_object_ids: vec![],
                        selection_rebase: None,
                        warnings: vec![],
                        durable: true,
                    },
                })
            }
            other => panic!("unexpected request: {other:?}"),
        }
    }
}

fn selection(revision: u64, quote: &str) -> SelectionSet {
    SelectionSet {
        revision: DocumentRevision::from_value(revision),
        kind: SelectionKind::TextRanges,
        ranges: vec![TextRangeRef {
            object_id: ObjectId::from_source_key("proposal/object"),
            page_id: PageId::from_source_key("proposal/page"),
            page_number: 1,
            start_utf16: 0,
            end_utf16: quote.encode_utf16().count() as u32,
            quoted_text: quote.into(),
        }],
        object_ids: vec![],
        primary_index: Some(0),
    }
}

fn draft(run_id: AgentRunId, revision: u64, quote: &str) -> ChangeProposalDraft {
    ChangeProposalDraft::text_rewrite(
        run_id,
        ToolCallId::new(),
        DocumentId::from_source_key("proposal/document"),
        selection(revision, quote),
        "new",
        vec!["bulk-like wording".into()],
    )
}

#[test]
fn approval_token_is_single_use_and_bound_to_run_proposal_revision_and_digest() {
    let run_id = AgentRunId::new();
    let mut store = ProposalStore::new(FakeGateway::new(4, "old"));
    let proposal = store.request_approval(draft(run_id, 4, "old")).unwrap();
    let token = proposal.approval_token.clone();

    let result = store
        .approve(token.clone(), DocumentRevision::from_value(4))
        .unwrap();
    assert!(matches!(result, ToolObservation::Command { .. }));
    assert_eq!(store.gateway().text(), "new");
    assert_eq!(
        store
            .approve(token, DocumentRevision::from_value(5))
            .unwrap_err()
            .code(),
        "approval_already_resolved"
    );
}

#[test]
fn stale_proposal_never_commits_and_rebase_creates_a_new_approval() {
    let run_id = AgentRunId::new();
    let mut store = ProposalStore::new(FakeGateway::new(5, "old"));
    let stale = store.request_approval(draft(run_id, 4, "old")).unwrap();

    assert_eq!(
        store
            .approve(
                stale.approval_token.clone(),
                DocumentRevision::from_value(5)
            )
            .unwrap_err()
            .code(),
        "proposal_revision_conflict"
    );
    assert_eq!(store.gateway().text(), "old");

    let rebased = store
        .rebase(stale.approval_token, DocumentRevision::from_value(5))
        .unwrap();
    assert_eq!(rebased.base_revision, DocumentRevision::from_value(5));
    assert_ne!(rebased.approval_id, stale.approval_id);
    assert_ne!(rebased.digest_sha256, stale.digest_sha256);
    assert_eq!(rebased.status, ProposalStatus::AwaitingApproval);
    assert_eq!(
        store.proposal(stale.proposal_id).unwrap().status,
        ProposalStatus::Superseded
    );
}

#[test]
fn rejection_and_cross_run_tokens_never_execute() {
    let mut store = ProposalStore::new(FakeGateway::new(4, "old"));
    let first = store
        .request_approval(draft(AgentRunId::new(), 4, "old"))
        .unwrap();
    store.reject(first.approval_token.clone()).unwrap();
    assert_eq!(store.gateway().text(), "old");
    assert_eq!(
        store.reject(first.approval_token).unwrap_err().code(),
        "approval_already_resolved"
    );

    let second = store
        .request_approval(draft(AgentRunId::new(), 4, "old"))
        .unwrap();
    let forged = second.approval_token.for_run(AgentRunId::new());
    assert_eq!(
        store
            .approve(forged, DocumentRevision::from_value(4))
            .unwrap_err()
            .code(),
        "approval_binding_mismatch"
    );
    assert_eq!(store.gateway().text(), "old");
}

#[test]
fn quote_mismatch_is_detected_immediately_before_commit() {
    let mut store = ProposalStore::new(FakeGateway::new(4, "changed manually"));
    let proposal = store
        .request_approval(draft(AgentRunId::new(), 4, "old"))
        .unwrap();
    assert_eq!(
        store
            .approve(proposal.approval_token, DocumentRevision::from_value(4))
            .unwrap_err()
            .code(),
        "proposal_quote_mismatch"
    );
    assert_eq!(store.gateway().text(), "changed manually");
}

#[test]
fn displayed_diff_mutation_and_digest_tampering_cannot_change_the_commit() {
    let mut store = ProposalStore::new(FakeGateway::new(4, "old"));
    let mut displayed = store
        .request_approval(draft(AgentRunId::new(), 4, "old"))
        .unwrap();
    let token = displayed.approval_token.clone();
    displayed.diff.targets[0].after_text = "attacker value".into();

    let tampered = token.for_digest("00");
    assert_eq!(
        store
            .approve(tampered, DocumentRevision::from_value(4))
            .unwrap_err()
            .code(),
        "approval_binding_mismatch"
    );
    store
        .approve(token, DocumentRevision::from_value(4))
        .unwrap();
    assert_eq!(store.gateway().text(), "new");
}
