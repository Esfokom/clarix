use std::collections::BTreeMap;
use std::str::FromStr;

use clarix_agent_core::{
    AgentError, AgentProviderConfig, AgentRunEvent, AgentRunEventKind, AgentRunId, AgentRunRequest,
    AgentRunStatus, CancellationToken, ConversationId, RunBudgets, SecretString,
};
use clarix_editing_core::{DocumentId, DocumentRevision};

fn fixture_run_request(secret: &str) -> AgentRunRequest {
    AgentRunRequest {
        run_id: AgentRunId::new(),
        conversation_id: ConversationId::new(),
        document_id: DocumentId::from_source_key("agent-run-model"),
        starting_revision: DocumentRevision::from_value(7),
        user_prompt: "Rewrite the selected sentence.".into(),
        selection_context: None,
        provider: AgentProviderConfig {
            provider_id: "openai".into(),
            endpoint: "https://api.example.test/v1/".into(),
            model_id: "gpt-test".into(),
            headers: BTreeMap::from([
                ("X-Organization".into(), "private-org".into()),
                ("X-Trace".into(), "private-trace".into()),
            ]),
            api_key: SecretString::new(secret),
        },
        budgets: RunBudgets::default(),
    }
}

#[test]
fn run_ids_are_canonical_parseable_and_type_safe() {
    let run_id = AgentRunId::new();
    let conversation_id = ConversationId::new();

    assert_eq!(AgentRunId::from_str(&run_id.to_string()).unwrap(), run_id);
    assert_eq!(
        ConversationId::from_str(&conversation_id.to_string()).unwrap(),
        conversation_id
    );
    assert_ne!(run_id.to_string(), conversation_id.to_string());
}

#[test]
fn run_status_distinguishes_paused_and_terminal_states() {
    assert!(AgentRunStatus::Completed.is_terminal());
    assert!(AgentRunStatus::Cancelled.is_terminal());
    assert!(AgentRunStatus::Failed.is_terminal());
    assert!(!AgentRunStatus::AwaitingApproval.is_terminal());
    assert!(!AgentRunStatus::BudgetPaused.is_terminal());
    assert!(AgentRunStatus::Queued.can_transition_to(AgentRunStatus::AssemblingContext));
    assert!(!AgentRunStatus::Completed.can_transition_to(AgentRunStatus::CallingProvider));
}

#[test]
fn default_budgets_are_bounded_and_zero_values_are_rejected() {
    assert_eq!(
        RunBudgets::default(),
        RunBudgets {
            max_tool_calls: 12,
            max_provider_rounds: 6,
            max_elapsed_ms: 120_000,
            max_output_tokens: 8_192,
        }
    );
    assert_eq!(
        RunBudgets {
            max_tool_calls: 0,
            ..RunBudgets::default()
        }
        .validate()
        .unwrap_err(),
        AgentError::InvalidBudgets("max_tool_calls must be positive".into())
    );
}

#[test]
fn cancellation_is_cloneable_and_monotonic() {
    let token = CancellationToken::new();
    let worker = token.clone();

    token.cancel();
    token.cancel();

    assert!(token.is_cancelled());
    assert!(worker.is_cancelled());
    assert_eq!(worker.check().unwrap_err(), AgentError::Cancelled);
}

#[test]
fn provider_secrets_and_header_values_never_serialize_or_debug_with_a_run() {
    let request = fixture_run_request("sk-secret");

    let json = serde_json::to_string(&request.audit_view()).unwrap();
    let debug = format!("{:?}", request.provider);

    assert!(!json.contains("sk-secret"));
    assert!(!json.contains("private-org"));
    assert!(!json.contains("private-trace"));
    assert!(json.contains("X-Organization"));
    assert!(json.contains("X-Trace"));
    assert_eq!(format!("{:?}", request.provider.api_key), "[REDACTED]");
    assert!(!debug.contains("sk-secret"));
}

#[test]
fn run_events_require_positive_monotonic_sequences() {
    let request = fixture_run_request("secret");
    let first = AgentRunEvent::new(
        request.run_id,
        1,
        request.starting_revision,
        AgentRunEventKind::StatusChanged {
            status: AgentRunStatus::CallingProvider,
        },
    )
    .unwrap();
    let second = AgentRunEvent::new(
        request.run_id,
        2,
        request.starting_revision,
        AgentRunEventKind::TextDelta {
            text: "Hello".into(),
        },
    )
    .unwrap();

    assert!(first.precedes(&second));
    assert_eq!(
        AgentRunEvent::new(
            request.run_id,
            0,
            request.starting_revision,
            AgentRunEventKind::BudgetPaused {
                reason: "tool calls".into(),
            },
        )
        .unwrap_err(),
        AgentError::InvalidEventSequence
    );
}
