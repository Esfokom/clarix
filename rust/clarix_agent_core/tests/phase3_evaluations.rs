use std::collections::HashSet;

use clarix_agent_core::{RunBudgets, ToolRegistry};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ExpectedEvidence {
    CommittedOnce,
    ConflictNoMutation,
    Tool(&'static str),
    ApprovalNoMutation,
    SaveUiEventNoMutation,
    Cancelled,
    CancelledNoPartialCommit,
    PolicyUnchanged,
    FreshApproval,
    CompleteAuditChain,
}

#[test]
fn phase3_deterministic_evaluation_matrix_is_complete_and_bounded() {
    let cases = [
        ("exact-target-rewrite", ExpectedEvidence::CommittedOnce),
        ("stale-selection", ExpectedEvidence::ConflictNoMutation),
        ("read-tool-choice", ExpectedEvidence::Tool("search_text")),
        ("bulk-approval", ExpectedEvidence::ApprovalNoMutation),
        ("save-is-explicit", ExpectedEvidence::SaveUiEventNoMutation),
        ("cancel-provider", ExpectedEvidence::Cancelled),
        ("cancel-tool", ExpectedEvidence::CancelledNoPartialCommit),
        ("prompt-injection", ExpectedEvidence::PolicyUnchanged),
        ("rebase", ExpectedEvidence::FreshApproval),
        ("audit-links", ExpectedEvidence::CompleteAuditChain),
    ];
    let names = cases.iter().map(|case| case.0).collect::<HashSet<_>>();
    assert_eq!(names.len(), cases.len(), "evaluation names must be unique");

    let tools = ToolRegistry::new()
        .definitions()
        .into_iter()
        .map(|definition| definition.name)
        .collect::<HashSet<_>>();
    for (_, expected) in cases {
        if let ExpectedEvidence::Tool(name) = expected {
            assert!(
                tools.contains(name),
                "evaluation references missing tool {name}"
            );
        }
    }
    for required in [
        "search_text",
        "replace_text_range",
        "undo",
        "redo",
        "request_save",
    ] {
        assert!(
            tools.contains(required),
            "required Phase 3 tool {required} is absent"
        );
    }
    assert_eq!(
        tools.len(),
        12,
        "the fixed tool surface changed without evaluation review"
    );

    let budgets = RunBudgets::default();
    assert_eq!(budgets.max_provider_rounds, 6);
    assert_eq!(budgets.max_tool_calls, 12);
    assert_eq!(budgets.max_elapsed_ms, 120_000);
    assert_eq!(budgets.max_output_tokens, 8_192);
    budgets
        .validate()
        .expect("default budgets must remain valid");
}
