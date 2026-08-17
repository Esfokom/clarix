use std::collections::BTreeMap;

use clarix_agent_core::{
    AgentProposalView, AgentProviderConfig, AgentRunEvent, AgentRunEventKind, AgentRunId,
    AgentRunRepository, AgentRunRequest, AgentRunStatus, ApprovalId, CommandAuditLink,
    ConversationId, ProposalId, RunBudgets, SecretString, ToolCallId,
};
use clarix_editing_core::{CommandId, DocumentId, DocumentRevision};
use clarix_editing_store::{
    ConversationImport, ConversationImportMessage, SqliteAgentRunRepository,
};
use tempfile::TempDir;

fn request(run_id: AgentRunId, status_secret: &str) -> AgentRunRequest {
    AgentRunRequest {
        run_id,
        conversation_id: ConversationId::new(),
        document_id: DocumentId::from_source_key("agent-store/document"),
        starting_revision: DocumentRevision::from_value(4),
        user_prompt: "edit the selection".into(),
        selection_context: None,
        provider: AgentProviderConfig {
            provider_id: "openai-compatible".into(),
            endpoint: "https://example.invalid/v1".into(),
            model_id: "fixture-model".into(),
            headers: BTreeMap::from([("Authorization".into(), format!("Bearer {status_secret}"))]),
            api_key: SecretString::new(status_secret),
        },
        budgets: RunBudgets::default(),
    }
}

#[test]
fn audit_reopens_with_complete_tool_approval_command_links() {
    let temp = TempDir::new().unwrap();
    let path = temp.path().join("project.clarix.sqlite");
    let run_id = AgentRunId::new();
    let tool_call_id = ToolCallId::new();
    let proposal_id = ProposalId::new();
    let approval_id = ApprovalId::new();
    let command_id = CommandId::new();
    {
        let repository = SqliteAgentRunRepository::open(&path).unwrap();
        repository
            .create_run(&request(run_id, "sk-never-store"))
            .unwrap();
        repository
            .append_event(
                AgentRunEvent::new(
                    run_id,
                    1,
                    DocumentRevision::from_value(4),
                    AgentRunEventKind::ToolStarted {
                        tool_call_id,
                        name: "undo".into(),
                    },
                )
                .unwrap(),
            )
            .unwrap();
        repository
            .append_event(
                AgentRunEvent::new(
                    run_id,
                    2,
                    DocumentRevision::from_value(4),
                    AgentRunEventKind::ApprovalRequested {
                        proposal: AgentProposalView {
                            proposal_id,
                            approval_id,
                            run_id,
                            tool_call_id,
                            base_revision: DocumentRevision::from_value(4),
                            digest_sha256: "digest".into(),
                            tool_name: "undo".into(),
                            targets: vec![],
                            reasons: vec!["history".into()],
                        },
                    },
                )
                .unwrap(),
            )
            .unwrap();
        repository
            .link_command(
                run_id,
                CommandAuditLink {
                    tool_call_id,
                    proposal_id: Some(proposal_id),
                    approval_id: Some(approval_id),
                    command_id,
                    previous_revision: DocumentRevision::from_value(4),
                    committed_revision: DocumentRevision::from_value(5),
                },
            )
            .unwrap();
        repository
            .set_status(run_id, AgentRunStatus::Completed)
            .unwrap();
    }

    let reopened = SqliteAgentRunRepository::open(&path).unwrap();
    let audit = reopened.read_run_audit(run_id).unwrap();
    assert_eq!(audit.events.len(), 2);
    assert_eq!(audit.command_links[0].approval_id, Some(approval_id));
    assert_eq!(audit.command_links[0].command_id, command_id);
    assert_eq!(
        audit.command_links[0].committed_revision,
        DocumentRevision::from_value(5)
    );
}

#[test]
fn sqlite_never_contains_provider_key_or_authorization_header_value() {
    let temp = TempDir::new().unwrap();
    let path = temp.path().join("secret-scan.sqlite");
    let repository = SqliteAgentRunRepository::open(&path).unwrap();
    let run_id = AgentRunId::new();
    repository
        .create_run(&request(run_id, "sk-super-secret-value"))
        .unwrap();
    repository
        .set_status(run_id, AgentRunStatus::Failed)
        .unwrap();
    repository.checkpoint().unwrap();
    drop(repository);

    let bytes = std::fs::read(path).unwrap();
    let raw = String::from_utf8_lossy(&bytes);
    assert!(!raw.contains("sk-super-secret-value"));
    assert!(!raw.contains("Bearer sk-super-secret-value"));
}

#[test]
fn reopen_fails_interrupted_work_but_preserves_pending_approval() {
    let temp = TempDir::new().unwrap();
    let path = temp.path().join("recovery.sqlite");
    let interrupted_id = AgentRunId::new();
    let approval_id = AgentRunId::new();
    {
        let repository = SqliteAgentRunRepository::open(&path).unwrap();
        repository
            .create_run(&request(interrupted_id, "secret-a"))
            .unwrap();
        repository
            .set_status(interrupted_id, AgentRunStatus::CallingProvider)
            .unwrap();
        repository
            .create_run(&request(approval_id, "secret-b"))
            .unwrap();
        repository
            .set_status(approval_id, AgentRunStatus::AwaitingApproval)
            .unwrap();
    }

    let reopened = SqliteAgentRunRepository::open(&path).unwrap();
    assert_eq!(
        reopened
            .read_run_audit(interrupted_id)
            .unwrap()
            .header
            .status,
        AgentRunStatus::Failed
    );
    assert_eq!(
        reopened.read_run_audit(approval_id).unwrap().header.status,
        AgentRunStatus::AwaitingApproval
    );
}

#[test]
fn duplicate_or_non_monotonic_event_sequences_are_rejected() {
    let repository = SqliteAgentRunRepository::open_in_memory().unwrap();
    let run_id = AgentRunId::new();
    repository.create_run(&request(run_id, "secret")).unwrap();
    let event = AgentRunEvent::new(
        run_id,
        1,
        DocumentRevision::from_value(4),
        AgentRunEventKind::SaveRequested,
    )
    .unwrap();
    repository.append_event(event.clone()).unwrap();
    assert!(repository.append_event(event).is_err());

    repository
        .append_event(
            AgentRunEvent::new(
                run_id,
                3,
                DocumentRevision::from_value(4),
                AgentRunEventKind::SaveRequested,
            )
            .unwrap(),
        )
        .unwrap();
    assert!(repository
        .append_event(
            AgentRunEvent::new(
                run_id,
                2,
                DocumentRevision::from_value(4),
                AgentRunEventKind::SaveRequested,
            )
            .unwrap(),
        )
        .is_err());
}

#[test]
fn legacy_conversation_import_is_atomic_ordered_and_idempotent() {
    let repository = SqliteAgentRunRepository::open_in_memory().unwrap();
    let conversation_id = ConversationId::new().to_string();
    let import = ConversationImport {
        conversation_id: conversation_id.clone(),
        legacy_id: "thread_legacy".into(),
        document_id: DocumentId::from_source_key("agent-store/document").to_string(),
        title: "Draft".into(),
        created_at: "2026-08-17T00:00:00Z".into(),
        updated_at: "2026-08-17T00:01:00Z".into(),
        summary: Some("Earlier context".into()),
        summary_through_sequence: Some(1),
        messages: vec![
            ConversationImportMessage {
                external_id: "m1".into(),
                sequence: 1,
                role: "user".into(),
                content: "Hello".into(),
                citations_json: "[]".into(),
                created_at: "2026-08-17T00:00:00Z".into(),
                token_estimate: 2,
                is_compacted: true,
            },
            ConversationImportMessage {
                external_id: "m2".into(),
                sequence: 2,
                role: "assistant".into(),
                content: "Hi".into(),
                citations_json: "[]".into(),
                created_at: "2026-08-17T00:00:01Z".into(),
                token_estimate: 1,
                is_compacted: false,
            },
        ],
    };
    let first = repository.import_conversation(&import).unwrap();
    let second = repository.import_conversation(&import).unwrap();
    let read = repository
        .read_conversation(&conversation_id)
        .unwrap()
        .unwrap();
    assert!(!first.already_present);
    assert!(second.already_present);
    assert_eq!(first.digest_sha256, second.digest_sha256);
    assert_eq!(
        read.messages
            .iter()
            .map(|message| message.sequence)
            .collect::<Vec<_>>(),
        vec![1, 2]
    );
    assert_eq!(read.summary.as_deref(), Some("Earlier context"));
}
