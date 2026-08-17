use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex};

use clarix_agent_core::{
    AgentProviderConfig, AgentRunEngine, AgentRunId, AgentRunRequest, AgentRunStatus,
    CancellationToken, ConversationId, InMemoryAgentRunRepository, ModelProvider,
    ProviderCompletion, ProviderEventSink, ProviderRequest, ProviderToolCall, RunBudgets,
    SecretString,
};
use clarix_editing_core::{
    CommandResult, DocumentId, DocumentRevision, EditingError, EditingToolGateway, ObjectId,
    PageId, SelectionContext, SelectionKind, SelectionStyleSummary, TextRangeRef, ToolObservation,
    ToolRequest,
};

#[derive(Default)]
struct ScriptedProvider {
    completions: Mutex<VecDeque<ProviderCompletion>>,
    requests: Mutex<Vec<ProviderRequest>>,
}

impl ScriptedProvider {
    fn new(completions: Vec<ProviderCompletion>) -> Self {
        Self {
            completions: Mutex::new(completions.into()),
            requests: Mutex::new(vec![]),
        }
    }
}

impl ModelProvider for ScriptedProvider {
    fn complete(
        &self,
        request: ProviderRequest,
        _: &CancellationToken,
        _: &mut dyn ProviderEventSink,
    ) -> Result<ProviderCompletion, clarix_agent_core::AgentError> {
        self.requests.lock().unwrap().push(request);
        Ok(self.completions.lock().unwrap().pop_front().unwrap())
    }
}

struct ErrorProvider(clarix_agent_core::AgentError);

impl ModelProvider for ErrorProvider {
    fn complete(
        &self,
        _: ProviderRequest,
        _: &CancellationToken,
        _: &mut dyn ProviderEventSink,
    ) -> Result<ProviderCompletion, clarix_agent_core::AgentError> {
        Err(self.0.clone())
    }
}

struct TextGateway(Mutex<(DocumentRevision, String)>);

impl TextGateway {
    fn new(text: &str) -> Self {
        Self(Mutex::new((DocumentRevision::from_value(4), text.into())))
    }

    fn text(&self) -> String {
        self.0.lock().unwrap().1.clone()
    }

    fn set_revision(&self, revision: u64) {
        self.0.lock().unwrap().0 = DocumentRevision::from_value(revision);
    }
}

impl EditingToolGateway for TextGateway {
    fn invoke(&self, request: ToolRequest) -> Result<ToolObservation, EditingError> {
        let mut state = self.0.lock().unwrap();
        match request {
            ToolRequest::ReplaceTextRange {
                command_id,
                selection,
                replacement,
                ..
            } => {
                assert_eq!(selection.revision, state.0);
                assert_eq!(selection.ranges[0].quoted_text, state.1);
                let previous_revision = state.0;
                state.0 = state.0.next().unwrap();
                state.1 = replacement;
                Ok(ToolObservation::Command {
                    result: CommandResult {
                        command_id,
                        previous_revision,
                        committed_revision: state.0,
                        object_patches: vec![],
                        removed_object_ids: vec![],
                        selection_rebase: None,
                        warnings: vec![],
                        durable: true,
                    },
                })
            }
            ToolRequest::SearchText { revision, .. } => Ok(ToolObservation::Search {
                revision,
                matches: vec![],
                total_matches: 0,
                indexed_pages: 1,
                page_count: 1,
                is_complete: true,
            }),
            ToolRequest::Undo {
                command_id,
                revision,
                ..
            } => {
                if revision != state.0 {
                    return Err(EditingError::RevisionConflict {
                        expected: revision,
                        actual: state.0,
                    });
                }
                let previous_revision = state.0;
                state.0 = state.0.next().unwrap();
                Ok(ToolObservation::Command {
                    result: CommandResult {
                        command_id,
                        previous_revision,
                        committed_revision: state.0,
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

fn selection_context() -> SelectionContext {
    SelectionContext {
        document_id: DocumentId::from_source_key("run/document"),
        document_revision: DocumentRevision::from_value(4),
        kind: SelectionKind::TextRanges,
        ranges: vec![TextRangeRef {
            object_id: ObjectId::from_source_key("run/object"),
            page_id: PageId::from_source_key("run/page"),
            page_number: 1,
            start_utf16: 0,
            end_utf16: 3,
            quoted_text: "old".into(),
        }],
        object_ids: vec![],
        primary_index: Some(0),
        page_ids: vec![PageId::from_source_key("run/page")],
        style_summary: SelectionStyleSummary {
            font_families: vec![],
            font_sizes: vec![],
            font_weights: vec![],
            italic_values: vec![],
            colors_rgba: vec![],
        },
        quads: vec![],
        nearby_text_before: "untrusted before".into(),
        nearby_text_after: "untrusted after".into(),
    }
}

fn request(max_tool_calls: u32) -> AgentRunRequest {
    let context = selection_context();
    AgentRunRequest {
        run_id: AgentRunId::new(),
        conversation_id: ConversationId::new(),
        document_id: context.document_id,
        starting_revision: context.document_revision,
        user_prompt: "rewrite this".into(),
        selection_context: Some(context),
        provider: AgentProviderConfig {
            provider_id: "scripted".into(),
            endpoint: "memory://provider".into(),
            model_id: "fixture".into(),
            headers: BTreeMap::new(),
            api_key: SecretString::new("never-persist-me"),
        },
        budgets: RunBudgets {
            max_tool_calls,
            ..RunBudgets::default()
        },
    }
}

fn completion_with(call: ProviderToolCall) -> ProviderCompletion {
    ProviderCompletion {
        text: String::new(),
        tool_calls: vec![call],
        usage: None,
    }
}

fn final_completion() -> ProviderCompletion {
    ProviderCompletion {
        text: "done".into(),
        tool_calls: vec![],
        usage: None,
    }
}

#[test]
fn safe_single_selection_rewrite_commits_and_links_the_command() {
    let context = selection_context();
    let provider = Arc::new(ScriptedProvider::new(vec![
        completion_with(ProviderToolCall {
            id: "rewrite-1".into(),
            name: "replace_text_range".into(),
            arguments: serde_json::json!({
                "document_id": context.document_id.to_string(),
                "replacement": "new"
            }),
        }),
        final_completion(),
    ]));
    let gateway = Arc::new(TextGateway::new("old"));
    let repository = Arc::new(InMemoryAgentRunRepository::new());
    let engine = AgentRunEngine::new(provider.clone(), gateway.clone(), repository.clone());
    let run_request = request(4);
    let run_id = run_request.run_id;

    let outcome = engine.start(run_request).unwrap();

    assert_eq!(outcome.status, AgentRunStatus::Completed);
    assert_eq!(gateway.text(), "new");
    assert_eq!(
        repository
            .read_run_audit(run_id)
            .unwrap()
            .command_links
            .len(),
        1
    );
    let first_request = &provider.requests.lock().unwrap()[0];
    let system = &first_request.messages[0].content;
    assert!(system.contains("<clarix_document_data>"));
    assert!(system.contains("untrusted"));
}

#[test]
fn bulk_or_history_tool_pauses_without_mutation_until_approved() {
    let context = selection_context();
    let provider = Arc::new(ScriptedProvider::new(vec![completion_with(
        ProviderToolCall {
            id: "undo-1".into(),
            name: "undo".into(),
            arguments: serde_json::json!({"document_id": context.document_id.to_string()}),
        },
    )]));
    let gateway = Arc::new(TextGateway::new("old"));
    let repository = Arc::new(InMemoryAgentRunRepository::new());
    let engine = AgentRunEngine::new(provider, gateway.clone(), repository);

    let paused = engine.start(request(4)).unwrap();

    assert_eq!(paused.status, AgentRunStatus::AwaitingApproval);
    assert!(paused.active_approval.is_some());
    assert_eq!(gateway.text(), "old");
}

#[test]
fn budget_exhaustion_pauses_instead_of_silently_continuing() {
    let context = selection_context();
    let search = || {
        completion_with(ProviderToolCall {
            id: "search".into(),
            name: "search_text".into(),
            arguments: serde_json::json!({
                "document_id": context.document_id.to_string(),
                "query": "old"
            }),
        })
    };
    let provider = Arc::new(ScriptedProvider::new(vec![search(), search(), search()]));
    let gateway = Arc::new(TextGateway::new("old"));
    let repository = Arc::new(InMemoryAgentRunRepository::new());
    let engine = AgentRunEngine::new(provider, gateway, repository);

    let paused = engine.start(request(2)).unwrap();

    assert_eq!(paused.status, AgentRunStatus::BudgetPaused);
    assert_eq!(paused.tool_calls, 2);
}

#[test]
fn approval_executes_once_and_resumes_the_same_provider_conversation() {
    let context = selection_context();
    let provider = Arc::new(ScriptedProvider::new(vec![
        completion_with(ProviderToolCall {
            id: "undo-approve".into(),
            name: "undo".into(),
            arguments: serde_json::json!({"document_id": context.document_id.to_string()}),
        }),
        final_completion(),
    ]));
    let gateway = Arc::new(TextGateway::new("old"));
    let repository = Arc::new(InMemoryAgentRunRepository::new());
    let engine = AgentRunEngine::new(provider.clone(), gateway, repository.clone());
    let run_request = request(4);
    let run_id = run_request.run_id;
    let paused = engine.start(run_request).unwrap();
    let approval = paused.active_approval.unwrap();

    let completed = engine.approve(run_id, approval.approval_id).unwrap();

    assert_eq!(completed.status, AgentRunStatus::Completed);
    assert_eq!(provider.requests.lock().unwrap().len(), 2);
    assert_eq!(
        repository
            .read_run_audit(run_id)
            .unwrap()
            .command_links
            .len(),
        1
    );
    assert_eq!(
        engine
            .approve(run_id, approval.approval_id)
            .unwrap_err()
            .code(),
        "approval_not_found"
    );
}

#[test]
fn rejection_reports_a_typed_tool_result_and_resumes_without_mutation() {
    let context = selection_context();
    let provider = Arc::new(ScriptedProvider::new(vec![
        completion_with(ProviderToolCall {
            id: "undo-reject".into(),
            name: "undo".into(),
            arguments: serde_json::json!({"document_id": context.document_id.to_string()}),
        }),
        final_completion(),
    ]));
    let gateway = Arc::new(TextGateway::new("old"));
    let repository = Arc::new(InMemoryAgentRunRepository::new());
    let engine = AgentRunEngine::new(provider.clone(), gateway.clone(), repository);
    let run_request = request(4);
    let run_id = run_request.run_id;
    let approval = engine.start(run_request).unwrap().active_approval.unwrap();

    let completed = engine.reject(run_id, approval.approval_id).unwrap();

    assert_eq!(completed.status, AgentRunStatus::Completed);
    assert_eq!(gateway.text(), "old");
    let requests = provider.requests.lock().unwrap();
    assert!(requests[1]
        .messages
        .iter()
        .any(|message| message.content.contains("rejected_by_user")));
}

#[test]
fn stale_approval_stays_pending_and_rebase_issues_fresh_ids() {
    let context = selection_context();
    let provider = Arc::new(ScriptedProvider::new(vec![
        completion_with(ProviderToolCall {
            id: "undo-rebase".into(),
            name: "undo".into(),
            arguments: serde_json::json!({"document_id": context.document_id.to_string()}),
        }),
        final_completion(),
    ]));
    let gateway = Arc::new(TextGateway::new("old"));
    let repository = Arc::new(InMemoryAgentRunRepository::new());
    let engine = AgentRunEngine::new(provider, gateway.clone(), repository);
    let run_request = request(4);
    let run_id = run_request.run_id;
    let original = engine.start(run_request).unwrap().active_approval.unwrap();
    gateway.set_revision(5);

    assert_eq!(
        engine
            .approve(run_id, original.approval_id)
            .unwrap_err()
            .code(),
        "tool_failure"
    );
    let rebased = engine
        .rebase(
            run_id,
            original.approval_id,
            DocumentRevision::from_value(5),
        )
        .unwrap()
        .active_approval
        .unwrap();
    assert_ne!(rebased.approval_id, original.approval_id);
    assert_ne!(rebased.proposal_id, original.proposal_id);
    assert_eq!(
        engine.approve(run_id, rebased.approval_id).unwrap().status,
        AgentRunStatus::Completed
    );
}

#[test]
fn provider_failure_and_cancellation_are_persisted_as_terminal_states() {
    let failed_repository = Arc::new(InMemoryAgentRunRepository::new());
    let failed_request = request(2);
    let failed_run_id = failed_request.run_id;
    let failed_engine = AgentRunEngine::new(
        Arc::new(ErrorProvider(clarix_agent_core::AgentError::Provider {
            code: "offline".into(),
            message: "provider unavailable".into(),
        })),
        Arc::new(TextGateway::new("old")),
        failed_repository.clone(),
    );
    assert!(failed_engine.start(failed_request).is_err());
    assert_eq!(
        failed_repository
            .read_run_audit(failed_run_id)
            .unwrap()
            .header
            .status,
        AgentRunStatus::Failed
    );

    let cancelled_repository = Arc::new(InMemoryAgentRunRepository::new());
    let cancelled_request = request(2);
    let cancelled_engine = AgentRunEngine::new(
        Arc::new(ErrorProvider(clarix_agent_core::AgentError::Cancelled)),
        Arc::new(TextGateway::new("old")),
        cancelled_repository.clone(),
    );
    let cancelled = cancelled_engine.start(cancelled_request).unwrap();
    assert_eq!(cancelled.status, AgentRunStatus::Cancelled);
}

#[test]
fn cancelling_a_paused_approval_is_terminal_and_prevents_later_execution() {
    let context = selection_context();
    let provider = Arc::new(ScriptedProvider::new(vec![completion_with(
        ProviderToolCall {
            id: "undo-cancel".into(),
            name: "undo".into(),
            arguments: serde_json::json!({"document_id": context.document_id.to_string()}),
        },
    )]));
    let gateway = Arc::new(TextGateway::new("old"));
    let repository = Arc::new(InMemoryAgentRunRepository::new());
    let engine = AgentRunEngine::new(provider, gateway.clone(), repository.clone());
    let run_request = request(4);
    let run_id = run_request.run_id;
    let approval = engine.start(run_request).unwrap().active_approval.unwrap();

    assert!(engine.cancel(run_id));
    assert_eq!(
        repository.read_run_audit(run_id).unwrap().header.status,
        AgentRunStatus::Cancelled
    );
    assert_eq!(
        engine
            .approve(run_id, approval.approval_id)
            .unwrap_err()
            .code(),
        "approval_not_found"
    );
    assert_eq!(gateway.text(), "old");
}
