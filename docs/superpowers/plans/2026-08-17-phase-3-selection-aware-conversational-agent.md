# Phase 3 Selection-Aware Conversational Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute inline on `main`; do not create a worktree or dispatch subagents.

**Goal:** Build a Rust-authoritative, selection-aware conversational agent that can inspect and safely edit exact PDF text through typed editing tools, with disclosure previews, approval enforcement, conflict rebase, cancellation, progress, and a complete audit trail.

**Architecture:** `clarix_agent_core` owns provider-independent conversations, runs, budgets, tool policy, approvals, cancellation, and audit records. It can reach document state only through `clarix_editing_core::EditingToolGateway`; `clarix_pdf_oxide` owns the concrete OpenAI-compatible transport and exposes a narrow FRB session API. Flutter retains provider-secret storage and presentation state, but it does not execute agent tools or decide whether a mutation is authorized.

**Tech Stack:** Rust 2021, `crossbeam-channel`, `serde`, `serde_json`, `rusqlite`, `reqwest` blocking client with Rustls, `flutter_rust_bridge` 2.12.0, Flutter/Dart 3.12, Riverpod 3, SQLite, `flutter_test`.

**Spec:** `docs/clarix-windows-editing-platform-architecture.md` — especially “Read-mode selection token,” “Agent harness,” “Safety and approval,” “Flutter/Rust bridge,” and “Phase 3 — Selection-aware conversational agent.”

## Global Constraints

- Work inline on `main`; do not create a worktree.
- Rust is authoritative for accepted document state, agent run state, tool execution, approvals, and audit records.
- The agent core depends only on public editing tools; it must never receive `&mut DocumentModel`, repository internals, PDFium handles, or Flutter callbacks that can mutate a document.
- Every selection and write carries the expected document revision, stable object IDs, UTF-16 ranges, and quoted text.
- Read-only tools execute automatically. Only a reversible, single-selection sidecar edit may execute automatically. Bulk, layout, destructive, history-wide, or ambiguous operations require a persisted preview approval.
- `request_save` may focus the Save UI but can never call Save or Save As. Saving always requires an explicit user action.
- Document content is untrusted data. It is delimited as data in provider messages and cannot alter tool policy, budgets, or permissions.
- Provider API keys remain in Flutter secure storage. A key may cross FRB once in an in-memory run request, but it must never enter a prompt, event, SQLite row, sidecar JSON, error string, log, or support diagnostic.
- Preserve current chat and provider behavior until Task 13 performs the single native-runtime cutover.
- Do not use live provider credentials in tests. Provider behavior uses scripted providers or a loopback HTTP server.
- Do not run a command expected to exceed 20 minutes. The default Phase 3 gate must remain practical on the current slow CPU; optional soak/evaluation commands are clearly separated.
- Use TDD for every task: add a focused failing test, observe the intended failure, implement the minimum contract, rerun the focused test, then commit.
- Generate and commit FRB bindings in the same commit as public native DTO changes.

## Fixed Phase 3 Policies

| Operation | Default policy | Reason |
|---|---|---|
| Inspect selection/object and search | Automatic | Read-only |
| Produce a rewrite or transaction preview | Automatic | Does not mutate canonical state |
| Replace or format exactly one validated selected range | Automatic | Reversible, local, revision-checked sidecar edit |
| Replace all, multi-range, multi-object, layout, or delete | Approval required | Bulk or structurally risky |
| Undo or redo | Approval required | May affect history beyond the current run |
| Save or Save As | Explicit UI action only | Writes the source or destination PDF |
| Rebase a stale proposal | Preview again and require approval | The user must see the new target and diff |

## File Structure

New Rust files keep each authority boundary small:

- `rust/clarix_editing_core/src/selection_context.rs` — exact selection context and nearby-text assembly.
- `rust/clarix_editing_core/src/tools.rs` — public agent-facing editing requests, observations, manifests, and actor gateway.
- `rust/clarix_agent_core/src/model.rs` — IDs, run/conversation state, events, budgets, outcomes, and errors.
- `rust/clarix_agent_core/src/provider.rs` — provider-neutral messages, tool calls, completion, and provider trait.
- `rust/clarix_agent_core/src/policy.rs` — deterministic risk and approval decisions.
- `rust/clarix_agent_core/src/tool_registry.rs` — typed tool catalog and execution adapter.
- `rust/clarix_agent_core/src/proposal.rs` — previews, approval tokens, acceptance/rejection, and rebase.
- `rust/clarix_agent_core/src/run.rs` — bounded plan/execute/observe actor and cancellation.
- `rust/clarix_agent_core/src/audit.rs` — repository trait and redacted audit records.
- `rust/clarix_pdf_oxide/src/agent_provider.rs` — OpenAI-compatible HTTP/SSE transport.
- `rust/clarix_pdf_oxide/src/agent_api.rs` — FRB-facing agent session DTOs and methods.
- `rust/clarix_editing_store/src/agent_repository.rs` — SQLite implementation for conversations, runs, approvals, events, and audit links.

Flutter additions remain adapters and views:

- `lib/src/core/agent/agent_bridge_types.dart` — stable Dart-facing value types.
- `lib/src/core/agent/agent_bridge.dart` — FRB validation, event sequencing, and secret-safe errors.
- `lib/src/features/workspace/agent/application/agent_run_controller.dart` — one active run per document tab.
- `lib/src/features/workspace/agent/presentation/selection_ai_toolbar.dart` — inline selection commands and disclosure entry point.
- `lib/src/features/workspace/agent/presentation/agent_disclosure_dialog.dart` — exact remote-context preview.
- `lib/src/features/workspace/agent/presentation/agent_approval_card.dart` — diff, approve, reject, and stale-rebase controls.
- `lib/src/features/workspace/agent/presentation/agent_diff_overlay.dart` — retained in-place proposal preview.
- Existing `ai_side_pane.dart`, `workspace_notifier.dart`, and provider-profile storage are adapted only at the final cutover.

---

### Task 1: Exact Selection Context in the Editing Core

**Files:**
- Create: `rust/clarix_editing_core/src/selection_context.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Modify: `rust/clarix_editing_core/src/actor.rs`
- Test: `rust/clarix_editing_core/tests/selection_context_contract.rs`

**Interfaces:**
- Consumes: `SelectionSet`, `DocumentModel`, `DocumentRevision`, stable page/object IDs, UTF-16 character boxes, and text styles.
- Produces: `SelectionContextBuilder::build(&DocumentModel, SelectionSet, ContextLimits) -> Result<SelectionContext, EditingError>` and `EditorSessionActor::selection_context(SelectionSet, ContextLimits)`.

- [ ] **Step 1: Write the failing selection-context contracts**

```rust
#[test]
fn context_preserves_exact_utf16_targets_and_bounded_nearby_text() {
    let model = fixture_document("Before selected after");
    let selection = text_selection(&model, 7, 15, "selected");
    let context = SelectionContextBuilder::build(
        &model,
        selection,
        ContextLimits { before_utf16: 7, after_utf16: 6, max_ranges: 8 },
    ).unwrap();

    assert_eq!(context.document_revision, DocumentRevision::INITIAL);
    assert_eq!(context.ranges[0].quoted_text, "selected");
    assert_eq!(context.nearby_text_before, "Before ");
    assert_eq!(context.nearby_text_after, " after");
    assert!(!context.style_summary.families.is_empty());
    assert!(!context.quads.is_empty());
}

#[test]
fn context_rejects_stale_quotes_before_any_provider_call() {
    let model = fixture_document("current");
    let stale = text_selection(&model, 0, 7, "previous");
    assert!(matches!(
        SelectionContextBuilder::build(&model, stale, ContextLimits::default()),
        Err(EditingError::SelectionQuoteMismatch { .. })
    ));
}
```

- [ ] **Step 2: Run the test and verify the intended red state**

Run: `cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml --test selection_context_contract`

Expected: compilation fails because `SelectionContextBuilder`, `SelectionContext`, and the actor request do not exist.

- [ ] **Step 3: Implement the exact, bounded context model**

Define these serializable types in `selection_context.rs`:

```rust
pub struct ContextLimits {
    pub before_utf16: u32,
    pub after_utf16: u32,
    pub max_ranges: u32,
}

pub struct SelectionContext {
    pub document_id: DocumentId,
    pub document_revision: DocumentRevision,
    pub selection: SelectionSet,
    pub page_ids: Vec<PageId>,
    pub style_summary: SelectionStyleSummary,
    pub quads: Vec<SelectionQuad>,
    pub nearby_text_before: String,
    pub nearby_text_after: String,
}
```

Validate through the existing selection validator first. Slice only on legal UTF-16 boundaries. Sort ranges by page number, object ID, and start offset; deduplicate page IDs; enforce `max_ranges`; clamp nearby text to the configured UTF-16 limits; derive quads from canonical character boxes rather than Flutter geometry. Do not create rendered crop assets in Phase 3.

- [ ] **Step 4: Add the actor request and run all selection contracts**

Run: `cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml --test selection_context_contract --test selection_contract`

Expected: all tests pass, including stale revision, stale quote, emoji boundary, multi-range ordering, style aggregation, and nearby-context truncation.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_editing_core/src/selection_context.rs rust/clarix_editing_core/src/lib.rs rust/clarix_editing_core/src/actor.rs rust/clarix_editing_core/tests/selection_context_contract.rs
git commit -m "feat: build stable agent selection context"
```

### Task 2: Agent Domain, Budgets, Events, and Cancellation

**Files:**
- Create: `rust/clarix_agent_core/src/model.rs`
- Create: `rust/clarix_agent_core/src/cancellation.rs`
- Modify: `rust/clarix_agent_core/src/lib.rs`
- Modify: `rust/clarix_agent_core/Cargo.toml`
- Test: `rust/clarix_agent_core/tests/run_model_contract.rs`

**Interfaces:**
- Consumes: stable document, revision, conversation, and selection identifiers.
- Produces: `AgentRunId`, `ConversationId`, `AgentRunRequest`, `AgentRunStatus`, `AgentRunEvent`, `RunBudgets`, `CancellationToken`, and `AgentError`.

- [ ] **Step 1: Write failing lifecycle and redaction tests**

```rust
#[test]
fn run_state_uses_explicit_terminal_and_paused_states() {
    assert!(AgentRunStatus::Completed.is_terminal());
    assert!(AgentRunStatus::Cancelled.is_terminal());
    assert!(!AgentRunStatus::AwaitingApproval.is_terminal());
    assert!(!AgentRunStatus::BudgetPaused.is_terminal());
}

#[test]
fn cancellation_is_cloneable_and_monotonic() {
    let token = CancellationToken::new();
    let worker = token.clone();
    token.cancel();
    assert!(worker.is_cancelled());
}

#[test]
fn provider_secrets_never_serialize_with_a_run_request() {
    let request = fixture_run_request(SecretString::new("sk-secret"));
    let json = serde_json::to_string(&request.audit_view()).unwrap();
    assert!(!json.contains("sk-secret"));
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test run_model_contract`

Expected: compilation fails because the run-domain types are absent.

- [ ] **Step 3: Implement the provider-independent run model**

Use UUID-backed IDs and these exact status values:

```rust
pub enum AgentRunStatus {
    Queued,
    AssemblingContext,
    CallingProvider,
    ExecutingTool,
    AwaitingApproval,
    BudgetPaused,
    Completed,
    Cancelled,
    Failed,
}

pub struct RunBudgets {
    pub max_tool_calls: u32,
    pub max_provider_rounds: u32,
    pub max_elapsed_ms: u64,
    pub max_output_tokens: u32,
}
```

Defaults are 12 tool calls, 6 provider rounds, 120,000 ms, and 8,192 output tokens. Define sequenced events for status, text delta, context disclosed, tool started/completed, approval requested/resolved, command committed, save requested, budget paused, and terminal outcome. `SecretString` implements redacted `Debug`, has no `Serialize`, and exposes its value only to the concrete provider call.

- [ ] **Step 4: Run focused tests**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test run_model_contract`

Expected: all ID, state-transition, budget, event-sequence, cancellation, and secret-redaction tests pass.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_agent_core/Cargo.toml rust/clarix_agent_core/src/lib.rs rust/clarix_agent_core/src/model.rs rust/clarix_agent_core/src/cancellation.rs rust/clarix_agent_core/tests/run_model_contract.rs
git commit -m "feat: define bounded agent run lifecycle"
```

### Task 3: Provider Abstraction and OpenAI Stream Normalization

**Files:**
- Create: `rust/clarix_agent_core/src/provider.rs`
- Create: `rust/clarix_agent_core/src/openai_stream.rs`
- Modify: `rust/clarix_agent_core/src/lib.rs`
- Test: `rust/clarix_agent_core/tests/provider_contract.rs`

**Interfaces:**
- Produces: `ModelProvider::complete(ProviderRequest, &CancellationToken, &mut dyn ProviderEventSink) -> Result<ProviderCompletion, AgentError>`.
- Produces normalized `ProviderMessage`, `ProviderToolDefinition`, `ProviderToolCall`, `ProviderUsage`, and `ProviderCompletion` types independent of OpenAI wire JSON.

- [ ] **Step 1: Write failing scripted-provider and SSE parser tests**

```rust
#[test]
fn fragmented_openai_tool_arguments_normalize_to_one_typed_call() {
    let mut decoder = OpenAiStreamDecoder::new();
    decoder.push_data(r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"search_text","arguments":"{\"query\":"}}]}}]}"#).unwrap();
    decoder.push_data(r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"termination\"}"}}]},"finish_reason":"tool_calls"}]}"#).unwrap();
    let completion = decoder.finish().unwrap();
    assert_eq!(completion.tool_calls[0].name, "search_text");
    assert_eq!(completion.tool_calls[0].arguments, serde_json::json!({"query":"termination"}));
}

#[test]
fn cancellation_stops_a_scripted_provider_before_the_next_delta() {
    let provider = ScriptedProvider::new(vec![text("one"), text("two")]);
    let token = CancellationToken::new();
    let mut sink = CancellingSink::after_first_delta(token.clone());
    assert!(matches!(provider.complete(request(), &token, &mut sink), Err(AgentError::Cancelled)));
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test provider_contract`

Expected: compilation fails because provider-neutral messages and the decoder are missing.

- [ ] **Step 3: Implement strict provider normalization**

The provider trait accepts normalized messages and tool definitions only. The OpenAI decoder accepts `data:` frames, accumulates tool-call fragments by index, rejects duplicate IDs with conflicting names, parses arguments into a JSON object, rejects non-object arguments, records usage when supplied, and maps `[DONE]` to one completion. Never include authorization headers or raw response bodies in `AgentError`.

- [ ] **Step 4: Run provider contracts**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test provider_contract`

Expected: all text delta, fragmented tool call, malformed JSON, duplicate call, usage, cancellation, and sanitized-error tests pass.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_agent_core/src/provider.rs rust/clarix_agent_core/src/openai_stream.rs rust/clarix_agent_core/src/lib.rs rust/clarix_agent_core/tests/provider_contract.rs
git commit -m "feat: normalize agent provider streams"
```

### Task 4: Public Editing Tool Gateway and Actor Adapter

**Files:**
- Modify: `rust/clarix_editing_core/src/tools.rs`
- Modify: `rust/clarix_editing_core/src/actor.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Test: `rust/clarix_editing_core/tests/agent_tool_gateway.rs`
- Modify test: `rust/clarix_agent_core/tests/tool_boundary.rs`

**Interfaces:**
- Consumes: `EditorSessionActor`, Task 1 `SelectionContext`, Phase 2 search/selection/transaction APIs.
- Produces: a complete `EditingToolGateway` implementation for `EditorSessionActor`.

- [ ] **Step 1: Write failing typed-gateway tests**

```rust
#[test]
fn actor_gateway_searches_and_commits_only_at_the_requested_revision() {
    let actor = fixture_actor("alpha beta alpha");
    let found = actor.invoke(ToolRequest::SearchText {
        revision: DocumentRevision::INITIAL,
        query: "alpha".into(),
        mode: SearchMode::Exact,
        limit: 20,
    }).unwrap();
    assert!(matches!(found, ToolObservation::Search { total_matches: 2, .. }));

    let stale = actor.invoke(stale_replace_request());
    assert!(matches!(stale, Err(EditingError::RevisionConflict { .. })));
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml --test agent_tool_gateway`

Expected: compilation fails because the expanded requests and actor implementation are missing.

- [ ] **Step 3: Expand the public typed tool boundary**

Replace the generic `SubmitCommand` escape hatch with explicit variants:

```rust
pub enum ToolRequest {
    InspectSelection { selection: SelectionSet, limits: ContextLimits },
    InspectTextObject { revision: DocumentRevision, object_id: ObjectId },
    SearchText { revision: DocumentRevision, query: String, mode: SearchMode, limit: u32 },
    PreviewTextRewrite { selection: SelectionSet, replacement: String },
    ReplaceTextRange { command_id: CommandId, selection: SelectionSet, replacement: String },
    PreviewReplaceAll { revision: DocumentRevision, query: String, replacement: String, mode: SearchMode },
    CommitReplaceAll { command_id: CommandId, preview_id: String },
    ApplyTextStyle { command_id: CommandId, selection: SelectionSet, style: TextStyle },
    PreviewTransaction { revision: DocumentRevision, edits: Vec<ProposedToolEdit> },
    CommitTransaction { command_id: CommandId, preview_id: String },
    Undo { command_id: CommandId, revision: DocumentRevision },
    Redo { command_id: CommandId, revision: DocumentRevision },
}
```

`ProposedToolEdit` is a serializable enum with `ReplaceText { selection, replacement }` and `SetTextStyle { selection, style }` variants. Every mutation routes through the actor’s existing durable command path. Preview variants return immutable proposal data but never advance revision. `CommitTransaction` is internal to the approval executor and is not advertised to the model. Limit search results to 200 per call. Keep concrete command internals private to the editing core.

- [ ] **Step 4: Run editing and boundary tests**

Run:

```powershell
cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml --test agent_tool_gateway --test command_session --test replace_all_contract
cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test tool_boundary
```

Expected: all explicit-tool, stale-revision, atomicity, and no-mutable-model-access tests pass.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_editing_core/src/tools.rs rust/clarix_editing_core/src/actor.rs rust/clarix_editing_core/src/lib.rs rust/clarix_editing_core/tests/agent_tool_gateway.rs rust/clarix_agent_core/tests/tool_boundary.rs
git commit -m "feat: expose typed editing tools to agent runs"
```

### Task 5: Tool Catalog, Schema Validation, and Deterministic Permission Policy

**Files:**
- Create: `rust/clarix_agent_core/src/tool_registry.rs`
- Create: `rust/clarix_agent_core/src/policy.rs`
- Modify: `rust/clarix_agent_core/src/lib.rs`
- Test: `rust/clarix_agent_core/tests/tool_policy_contract.rs`

**Interfaces:**
- Consumes: normalized provider tool calls and `EditingToolGateway`.
- Produces: `ToolRegistry::definitions()`, `ToolRegistry::validate_call`, `PermissionPolicy::decide`, and typed `ToolExecution` values.

- [ ] **Step 1: Write failing schema and policy matrix tests**

```rust
#[test]
fn policy_matches_the_phase_three_matrix() {
    assert_eq!(decision("inspect_selection", local_selection()), PermissionDecision::Automatic);
    assert_eq!(decision("replace_text_range", local_selection()), PermissionDecision::Automatic);
    assert_eq!(decision("preview_transaction", bulk_selection()), PermissionDecision::Automatic);
    assert!(matches!(decision("commit_replace_all", bulk_selection()), PermissionDecision::ApprovalRequired { .. }));
    assert!(matches!(decision("undo", local_selection()), PermissionDecision::ApprovalRequired { .. }));
    assert_eq!(decision("request_save", local_selection()), PermissionDecision::ExplicitUiAction);
}

#[test]
fn unknown_and_extra_arguments_are_rejected_before_execution() {
    let error = registry().validate_call(call("search_text", json!({"query":"x","surprise":true}))).unwrap_err();
    assert_eq!(error.code(), "invalid_tool_arguments");
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test tool_policy_contract`

Expected: compilation fails because the registry and policy are absent.

- [ ] **Step 3: Implement the fixed initial catalog**

Register versioned schemas for `inspect_selection`, `inspect_text_object`, `search_text`, `propose_text_rewrite`, `replace_text_range`, `preview_replace_all`, `commit_replace_all`, `apply_text_style`, `preview_transaction`, `undo`, `redo`, and `request_save`. Each manifest declares `scope`, `risk`, `approval`, `reversible`, `idempotent`, `revision_behavior`, and `supports_cancellation`. Reject unknown tools, missing fields, additional properties, invalid enum values, negative UTF-16 offsets, non-canonical UUIDs, and document IDs outside the active run. The internal `CommitTransaction` request has no provider schema and can be reached only after approval of the matching preview digest.

The permission decision is derived only from the manifest plus validated affected range/object counts. Provider text and PDF content are never policy inputs.

- [ ] **Step 4: Run tool-policy contracts**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test tool_policy_contract`

Expected: schema snapshots, every policy row, document allow-list, and prompt-injection attempts pass.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_agent_core/src/tool_registry.rs rust/clarix_agent_core/src/policy.rs rust/clarix_agent_core/src/lib.rs rust/clarix_agent_core/tests/tool_policy_contract.rs
git commit -m "feat: enforce agent tool schemas and permissions"
```

### Task 6: Proposal Diff, Approval, Reject, and Revision Rebase

**Files:**
- Create: `rust/clarix_agent_core/src/proposal.rs`
- Modify: `rust/clarix_agent_core/src/model.rs`
- Modify: `rust/clarix_agent_core/src/lib.rs`
- Test: `rust/clarix_agent_core/tests/proposal_contract.rs`

**Interfaces:**
- Consumes: immutable editing previews and permission decisions.
- Produces: `ChangeProposal`, `ProposalDiff`, `ApprovalToken`, `ProposalStore`, and explicit `approve`, `reject`, and `rebase` operations.

- [ ] **Step 1: Write failing approval and stale-rebase tests**

```rust
#[test]
fn approval_token_is_single_use_and_bound_to_run_proposal_revision_and_digest() {
    let mut store = fixture_store();
    let token = store.request_approval(fixture_proposal()).unwrap();
    store.approve(token.clone()).unwrap();
    assert_eq!(store.approve(token).unwrap_err().code(), "approval_already_resolved");
}

#[test]
fn stale_proposal_never_commits_and_rebase_creates_a_new_approval() {
    let mut store = fixture_store();
    let stale = store.request_approval(proposal_at(4)).unwrap();
    assert_eq!(store.approve_at(stale, DocumentRevision::new(5)).unwrap_err().code(), "proposal_revision_conflict");
    let rebased = store.rebase(fixture_gateway_at(5)).unwrap();
    assert_eq!(rebased.base_revision, DocumentRevision::new(5));
    assert_ne!(rebased.approval_token, stale);
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test proposal_contract`

Expected: compilation fails because proposal lifecycle types are absent.

- [ ] **Step 3: Implement immutable, digest-bound proposals**

A proposal records run ID, tool call ID, base revision, exact targets and quotes, before/after text or style, affected object/page counts, warnings, risk reasons, and SHA-256 digest. Approval tokens are random UUIDs and single-use. Reject changes status only. Approval revalidates revision and quotes immediately before invoking the editing tool. Rebase reruns the read/preview operation at the latest revision, records the old proposal as superseded, emits a fresh diff, and always returns to `AwaitingApproval`.

- [ ] **Step 4: Run proposal contracts**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test proposal_contract`

Expected: approve, reject, replay rejection, cross-run token rejection, quote mismatch, stale revision, rebase, and digest tampering tests pass.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_agent_core/src/proposal.rs rust/clarix_agent_core/src/model.rs rust/clarix_agent_core/src/lib.rs rust/clarix_agent_core/tests/proposal_contract.rs
git commit -m "feat: add revision-bound agent approvals"
```

### Task 7: Bounded Agent Run Engine

**Files:**
- Create: `rust/clarix_agent_core/src/audit.rs`
- Create: `rust/clarix_agent_core/src/run.rs`
- Modify: `rust/clarix_agent_core/src/lib.rs`
- Test: `rust/clarix_agent_core/tests/run_engine_contract.rs`

**Interfaces:**
- Consumes: `ModelProvider`, `ToolRegistry`, `PermissionPolicy`, `ProposalStore`, and `EditingToolGateway`.
- Produces: `AgentRunEngine::start`, `approve`, `reject`, `rebase`, `cancel`, `subscribe`, and bounded plan/execute/observe behavior.
- Produces: the `AgentRunRepository` trait plus an `InMemoryAgentRunRepository` used by deterministic tests; Task 8 supplies its SQLite implementation.

- [ ] **Step 1: Write failing deterministic run scenarios**

```rust
#[test]
fn safe_single_selection_rewrite_commits_and_links_the_command() {
    let fixture = RunFixture::single_selection("old", scripted_rewrite("new"));
    let outcome = fixture.run_to_terminal();
    assert_eq!(outcome.status, AgentRunStatus::Completed);
    assert_eq!(fixture.gateway.committed_text(), "new");
    assert_eq!(fixture.audit.command_links().len(), 1);
}

#[test]
fn bulk_tool_pauses_without_mutation_until_approved() {
    let fixture = RunFixture::bulk_replace(scripted_replace_all());
    let paused = fixture.run_until_pause();
    assert_eq!(paused.status, AgentRunStatus::AwaitingApproval);
    assert_eq!(fixture.gateway.revision(), paused.starting_revision);
}

#[test]
fn budget_exhaustion_pauses_instead_of_silently_continuing() {
    let fixture = RunFixture::repeating_tools(RunBudgets { max_tool_calls: 2, ..RunBudgets::default() });
    assert_eq!(fixture.run_to_pause().status, AgentRunStatus::BudgetPaused);
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test run_engine_contract`

Expected: compilation fails because the engine is missing.

- [ ] **Step 3: Implement the run loop and safe system boundary**

The loop is exactly:

```rust
while budgets.allow_next_round(&usage) {
    let completion = provider.complete(request, &cancel, &mut event_sink)?;
    if completion.tool_calls.is_empty() {
        return finish(completion);
    }
    for call in completion.tool_calls {
        let validated = tools.validate_call(call)?;
        match policy.decide(&validated, &context)? {
            PermissionDecision::Automatic => observe(tools.execute(validated, &cancel)?),
            PermissionDecision::ApprovalRequired { reasons } => return pause_for_approval(validated, reasons),
            PermissionDecision::ExplicitUiAction => return emit_save_request(),
        }
    }
}
pause_for_budget();
```

Provider messages delimit document text inside `<clarix_document_data>` and state that it is untrusted. A run has one worker, one monotonic event sequence, one cancellation token, and one active approval. Cancellation stops future provider/tool work and leaves canonical state at the last fully committed command. Never auto-resume a model loop after restart.

- [ ] **Step 4: Run the engine and concurrency contracts**

Run: `cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test run_engine_contract --test tool_policy_contract --test proposal_contract`

Expected: exact targeting, correct tool choice, automatic local edit, approval pause, explicit Save request, provider/tool failure, cancellation, budget pause, and manual-edit revision-conflict tests pass.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_agent_core/src/audit.rs rust/clarix_agent_core/src/run.rs rust/clarix_agent_core/src/lib.rs rust/clarix_agent_core/tests/run_engine_contract.rs
git commit -m "feat: run bounded selection-aware agents"
```

### Task 8: Durable Conversations, Approvals, and Audit Links

**Files:**
- Modify: `rust/clarix_agent_core/src/audit.rs`
- Modify: `rust/clarix_agent_core/src/run.rs`
- Modify: `rust/clarix_agent_core/src/lib.rs`
- Create: `rust/clarix_editing_store/src/agent_repository.rs`
- Modify: `rust/clarix_editing_store/src/schema.rs`
- Modify: `rust/clarix_editing_store/src/lib.rs`
- Modify: `rust/clarix_editing_store/Cargo.toml`
- Test: `rust/clarix_editing_store/tests/agent_repository_contract.rs`

**Interfaces:**
- Produces: `AgentRunRepository` with atomic `create_run`, `append_event`, `save_approval`, `resolve_approval`, `finish_run`, `list_conversations`, and `read_run_audit` methods.
- Produces complete links `conversation_id -> run_id -> provider_round_id -> tool_call_id -> proposal_id -> approval_id -> command_id -> document_revision`.

- [ ] **Step 1: Write failing recovery and secret-leak tests**

```rust
#[test]
fn audit_reopens_with_complete_tool_approval_command_links() {
    let repo = fixture_repository();
    persist_approved_run(&repo);
    drop(repo);
    let reopened = reopen_fixture_repository();
    let audit = reopened.read_run_audit(run_id()).unwrap();
    assert_eq!(audit.tool_calls[0].approval_id, Some(approval_id()));
    assert_eq!(audit.tool_calls[0].command_id, Some(command_id()));
    assert_eq!(audit.tool_calls[0].committed_revision, Some(DocumentRevision::from_value(2)));
}

#[test]
fn sqlite_never_contains_provider_key_or_authorization_header() {
    persist_failed_provider_run("sk-secret", "Bearer sk-secret");
    let bytes = std::fs::read(database_path()).unwrap();
    let raw = String::from_utf8_lossy(&bytes);
    assert!(!raw.contains("sk-secret"));
    assert!(!raw.contains("Bearer"));
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_editing_store --manifest-path rust/Cargo.toml --test agent_repository_contract`

Expected: compilation fails because agent tables and repository APIs do not exist.

- [ ] **Step 3: Add schema version 3 and transactional persistence**

Add tables `agent_conversations`, `agent_messages`, `agent_runs`, `agent_events`, `agent_tool_calls`, `agent_proposals`, and `agent_approvals`, with foreign keys and unique `(run_id, sequence)` event ordering. Store redacted provider/model identifiers, timing, status, JSON payloads, digests, IDs, and revisions. Do not store the API key, authorization headers, full HTTP bodies, or raw rendered crops. On reopen, mark `Queued`, `CallingProvider`, and `ExecutingTool` runs as `Failed(interrupted)`; preserve `AwaitingApproval` for review but never resume it automatically.

- [ ] **Step 4: Run store and existing recovery contracts**

Run: `cargo test -p clarix_editing_store --manifest-path rust/Cargo.toml --test agent_repository_contract --test repository_contract`

Expected: migration, atomic append, reopen, interrupted-run handling, pending approval preservation, deletion cascade, event ordering, full audit links, and secret scans pass.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_agent_core/src/audit.rs rust/clarix_agent_core/src/run.rs rust/clarix_agent_core/src/lib.rs rust/clarix_editing_store/Cargo.toml rust/clarix_editing_store/src/agent_repository.rs rust/clarix_editing_store/src/schema.rs rust/clarix_editing_store/src/lib.rs rust/clarix_editing_store/tests/agent_repository_contract.rs
git commit -m "feat: persist agent runs and audit links"
```

### Task 9: Concrete OpenAI-Compatible Rust Provider

**Files:**
- Modify: `rust/Cargo.toml`
- Create: `rust/clarix_pdf_oxide/src/agent_provider.rs`
- Modify: `rust/clarix_pdf_oxide/src/lib.rs`
- Modify: `rust/clarix_pdf_oxide/Cargo.toml`
- Test: `rust/clarix_pdf_oxide/tests/agent_provider_contract.rs`

**Interfaces:**
- Consumes: Task 3 `ModelProvider` contract and an in-memory endpoint/model/API key configuration.
- Produces: `OpenAiCompatibleRustProvider` using a bounded blocking HTTP client on the agent worker thread.

- [ ] **Step 1: Write failing loopback transport tests**

```rust
#[test]
fn provider_sends_standard_stream_request_and_redacts_auth() {
    let server = ScriptedSseServer::start(success_frames());
    let provider = provider_for(&server, "sk-secret");
    let completion = provider.complete(request(), &CancellationToken::new(), &mut sink()).unwrap();
    assert_eq!(completion.text, "Done");
    let received = server.received_request();
    assert_eq!(received.header("authorization"), Some("Bearer sk-secret"));
    assert!(received.json()["stream"].as_bool().unwrap());
    assert!(!format!("{provider:?}").contains("sk-secret"));
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --no-default-features --test agent_provider_contract`

Expected: compilation fails because the concrete provider is absent.

- [ ] **Step 3: Implement bounded HTTP/SSE transport**

Add workspace `reqwest = { version = "0.12", default-features = false, features = ["blocking", "json", "rustls-tls"] }`. Permit HTTPS endpoints plus HTTP only for `localhost` and `127.0.0.1`. Set connect timeout to 10 seconds and per-request timeout to the remaining run budget, capped at 120 seconds. Send `Authorization: Bearer`, profile headers except `Authorization`, normalized messages, tool schemas, and `stream: true`. Feed SSE frames to Task 3’s decoder. Map 401, 403, 429, 5xx, malformed SSE, timeout, and cancellation to sanitized stable codes.

- [ ] **Step 4: Run provider and native compile checks**

Run:

```powershell
cargo test -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --no-default-features --test agent_provider_contract
cargo check -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --lib --no-default-features
```

Expected: loopback success/tool-call/error/cancellation tests pass and the native library compiles without RAG.

- [ ] **Step 5: Commit**

```powershell
git add rust/Cargo.toml rust/Cargo.lock rust/clarix_pdf_oxide/Cargo.toml rust/clarix_pdf_oxide/src/agent_provider.rs rust/clarix_pdf_oxide/src/lib.rs rust/clarix_pdf_oxide/tests/agent_provider_contract.rs
git commit -m "feat: add native OpenAI-compatible provider"
```

### Task 10: Native Agent Session API and Generated FRB Bindings

**Files:**
- Create: `rust/clarix_pdf_oxide/src/agent_api.rs`
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs`
- Modify: `rust/clarix_pdf_oxide/src/lib.rs`
- Modify: `flutter_rust_bridge.yaml`
- Generated: `rust/clarix_pdf_oxide/src/frb_generated.rs`
- Generated: `lib/src/core/ffi/agent_api.dart`
- Generated: `lib/src/core/ffi/frb_generated.dart`
- Generated: `lib/src/core/ffi/frb_generated.io.dart`
- Test: `rust/clarix_pdf_oxide/tests/agent_bridge_contract.rs`

**Interfaces:**
- Produces methods on the existing native editor session: `selection_context`, `test_agent_provider`, `start_agent_run`, `agent_events`, `approve_agent_proposal`, `reject_agent_proposal`, `rebase_agent_proposal`, `cancel_agent_run`, `compact_agent_conversation`, `list_agent_conversations`, `read_agent_conversation`, and `read_agent_audit`.

- [ ] **Step 1: Write failing native facade tests**

```rust
#[test]
fn native_run_uses_the_same_editor_actor_and_streams_monotonic_events() {
    let session = fixture_native_session();
    let run = session.start_agent_run(fixture_native_request()).unwrap();
    let events = collect_until_terminal(session.agent_events(run.run_id.clone()).unwrap());
    assert!(events.windows(2).all(|pair| pair[0].sequence < pair[1].sequence));
    assert_eq!(session.metadata().unwrap().revision, 1);
}

#[test]
fn closed_editor_session_rejects_late_agent_actions() {
    let session = fixture_native_session();
    session.close().unwrap();
    assert_eq!(session.cancel_agent_run("run").unwrap_err(), "session_closed");
}
```

- [ ] **Step 2: Verify red**

Run: `cargo test -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --no-default-features --test agent_bridge_contract`

Expected: compilation fails because the native agent API is missing.

- [ ] **Step 3: Implement narrow DTOs and session ownership**

All public DTOs carry `schema_version = 1`. Events include session ID, run ID, sequence, document revision, kind, and one typed payload. `NativeStartAgentRunRequest` carries provider endpoint/model/headers/API key, conversation ID, user prompt, validated selection, disclosure acknowledgement digest, and budgets. `test_agent_provider` performs a bounded no-tool request without persisting a conversation. `compact_agent_conversation` summarizes only the explicitly supplied message range, persists the summary and compacted-through sequence, and uses the same redacted provider configuration. Mark every API key field as secret in `Debug` and never echo it. Closing the editor session cancels active runs, closes event streams, and joins workers before releasing the repository.

- [ ] **Step 4: Generate bindings and validate a clean generation diff**

Run:

```powershell
flutter_rust_bridge_codegen generate --no-build-runner --no-dart-fix --no-web
cargo fmt --all --manifest-path rust/Cargo.toml -- --check
cargo test -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --no-default-features --test agent_bridge_contract
```

Expected: code generation completes, formatting is clean, and native run/event/approval/cancel/close tests pass. If default RAG makes generation impractical, temporarily set `clarix_pdf_oxide` default features to `[]`, generate, and restore `default = ["rag"]` before committing; verify `git diff` contains no feature change.

- [ ] **Step 5: Commit**

```powershell
git add flutter_rust_bridge.yaml rust/clarix_pdf_oxide/src/agent_api.rs rust/clarix_pdf_oxide/src/editing_api.rs rust/clarix_pdf_oxide/src/lib.rs rust/clarix_pdf_oxide/src/frb_generated.rs lib/src/core/ffi
git commit -m "feat: bridge native agent sessions"
```

### Task 11: Validating Dart Agent Bridge and Per-Tab Controller

**Files:**
- Create: `lib/src/core/agent/agent_bridge_types.dart`
- Create: `lib/src/core/agent/agent_bridge.dart`
- Create: `lib/src/features/workspace/agent/application/agent_run_controller.dart`
- Modify: `lib/src/features/workspace/editing/application/editor_session_registry.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Test: `test/core/agent/agent_bridge_contract_test.dart`
- Test: `test/workspace_agent/agent_run_controller_test.dart`

**Interfaces:**
- Consumes: generated Task 10 bindings and the existing per-tab `EditorSessionController` registry.
- Produces: immutable Dart `AgentConversationMessage`, `AgentRunView`, `AgentRunEvent`, `AgentProposal`, `AgentDisclosure`, and controller methods `testProvider`, `start`, `approve`, `reject`, `rebase`, `cancel`, and `compactConversation`.

- [ ] **Step 1: Write failing bridge/controller protocol tests**

```dart
test('bridge rejects duplicate or decreasing agent event sequences', () async {
  final native = FakeNativeAgentPort(events: <AgentRunEvent>[event(1), event(1)]);
  final bridge = AgentBridgeSession.forTest(native);
  await expectLater(bridge.events, emitsError(isA<AgentProtocolViolation>()));
});

test('controller keeps one active run per tab and rejects cross-run approval', () async {
  final controller = fixtureController();
  final run = await controller.start(fixtureRequest());
  await expectLater(controller.approve(proposalForDifferentRun()), throwsA(isA<StateError>()));
  expect(controller.state.activeRunId, run.runId);
});
```

- [ ] **Step 2: Verify red**

Run: `flutter test test/core/agent/agent_bridge_contract_test.dart test/workspace_agent/agent_run_controller_test.dart`

Expected: tests fail because the bridge and controller are absent.

- [ ] **Step 3: Implement strict Dart protocol validation**

Validate schema, canonical UUIDs, non-negative revisions, increasing event sequences, matching session/run IDs, proposal digest, approval token ownership, terminal-state finality, and closed-session behavior. The controller derives UI state only from native events. It never marks a mutation committed before receiving a native `commandCommitted` event. It serializes approve/reject/rebase/cancel operations and refreshes affected page scenes through the existing editor controller after a commit.

- [ ] **Step 4: Run focused Dart checks**

Run:

```powershell
dart format lib/src/core/agent lib/src/features/workspace/agent test/core/agent test/workspace_agent
flutter analyze lib/src/core/agent lib/src/features/workspace/agent
flutter test test/core/agent test/workspace_agent
```

Expected: formatting and analysis are clean; bridge sequencing, close, protocol mismatch, controller lifecycle, scene refresh, and concurrent action tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/core/agent lib/src/features/workspace/agent/application lib/src/features/workspace/editing/application/editor_session_registry.dart lib/src/features/workspace/application/workspace_providers.dart test/core/agent test/workspace_agent
git commit -m "feat: control native agent runs from Flutter"
```

### Task 12: Inline Selection Commands and Disclosure Preview

**Files:**
- Create: `lib/src/features/workspace/agent/presentation/selection_ai_toolbar.dart`
- Create: `lib/src/features/workspace/agent/presentation/agent_disclosure_dialog.dart`
- Modify: `lib/src/features/workspace/editing/presentation/page_edit_scene.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Test: `test/workspace_agent/selection_ai_surface_test.dart`

**Interfaces:**
- Consumes: native `SelectionContext`, selected provider profile, and `AgentRunController`.
- Produces quick actions Rewrite, Shorten, Expand, Translate, Summarize, and Ask Clarix, plus an exact remote disclosure confirmation.

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('selection toolbar appears only for a validated nonempty selection', (tester) async {
  await tester.pumpWidget(harness(selection: validatedSelection('selected')));
  expect(find.byKey(const Key('selection-ai-toolbar')), findsOneWidget);
  await tester.pumpWidget(harness(selection: null));
  expect(find.byKey(const Key('selection-ai-toolbar')), findsNothing);
});

testWidgets('remote run shows exact disclosed text and does not start before confirmation', (tester) async {
  await tester.pumpWidget(harness(selection: validatedSelection('private text')));
  await tester.tap(find.text('Rewrite'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('agent-disclosure-preview')), findsOneWidget);
  expect(find.textContaining('private text'), findsOneWidget);
  expect(fakeController.startCount, 0);
  await tester.tap(find.text('Share and continue'));
  await tester.pump();
  expect(fakeController.startCount, 1);
});
```

- [ ] **Step 2: Verify red**

Run: `flutter test test/workspace_agent/selection_ai_surface_test.dart`

Expected: tests fail because the selection AI surface is absent.

- [ ] **Step 3: Implement the inline surface and disclosure gate**

Anchor the toolbar to canonical selection quads and dismiss it on revision change, selection change, scroll offscreen, Escape, or session close. The disclosure dialog lists provider label, selected quoted text, bounded nearby-before/after text, page numbers, and whether conversation history is included. Do not show object UUIDs as user content. If `shareRetrievedPassages` is false, disable selection-aware remote actions with the message “Enable document sharing for this provider to use selected text.” Compute and send a SHA-256 acknowledgement digest over the exact disclosure packet.

- [ ] **Step 4: Run widget and selection regression tests**

Run: `flutter test test/workspace_agent/selection_ai_surface_test.dart test/workspace_pdf/pdf_text_selection_overlay_test.dart`

Expected: toolbar lifecycle, quick-action prompt, disclosure contents, consent blocking, digest stability, and existing selection behavior pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/agent/presentation/selection_ai_toolbar.dart lib/src/features/workspace/agent/presentation/agent_disclosure_dialog.dart lib/src/features/workspace/editing/presentation/page_edit_scene.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart test/workspace_agent/selection_ai_surface_test.dart
git commit -m "feat: add selection-aware AI command surface"
```

### Task 13: Approval Cards, In-Place Diffs, Progress, and Chat Cutover

**Files:**
- Create: `lib/src/features/workspace/agent/presentation/agent_approval_card.dart`
- Create: `lib/src/features/workspace/agent/presentation/agent_diff_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/core/models.dart`
- Modify: `lib/src/features/workspace/application/ai_runtime_service.dart`
- Test: `test/workspace_agent/agent_approval_ui_test.dart`
- Modify test: `test/workspace_ai/ai_side_pane_test.dart`

**Interfaces:**
- Consumes: Task 11 run events and proposals.
- Produces: streaming assistant text, progress timeline, approval/rejection/rebase controls, retained diff overlays, cancellation, and chat continuation through the native agent runtime.

- [ ] **Step 1: Write failing UI state tests**

```dart
testWidgets('risky proposal paints a diff but does not change accepted text', (tester) async {
  final harness = await pumpAgentWorkspace(tester, proposal: riskyProposal(before: 'old', after: 'new'));
  expect(find.byKey(const Key('agent-diff-overlay')), findsOneWidget);
  expect(harness.editor.state.visibleText(harness.objectId), 'old');
  expect(find.byKey(const Key('agent-approve')), findsOneWidget);
});

testWidgets('revision conflict offers rebase and never reuses stale approval', (tester) async {
  await pumpAgentWorkspace(tester, proposal: staleProposal());
  expect(find.text('Document changed'), findsOneWidget);
  expect(find.byKey(const Key('agent-rebase')), findsOneWidget);
  expect(find.byKey(const Key('agent-approve')), findsNothing);
});
```

- [ ] **Step 2: Verify red**

Run: `flutter test test/workspace_agent/agent_approval_ui_test.dart test/workspace_ai/ai_side_pane_test.dart`

Expected: tests fail because native run states and proposal UI are not rendered.

- [ ] **Step 3: Implement the native-runtime cutover**

Make `AiRuntimeService` a thin adapter over `AgentRunController`; remove tool execution and provider calls from Dart. Provider connection testing delegates to `testProvider`, and conversation compaction delegates to `compactConversation`. Preserve provider-profile and secure-key storage, current conversation history controls, citations, and chat copy. Add `activeRun`, progress label, pending proposal, audit summary, and cancellation state to `AiWorkspaceState`. `AiSidePane` subscribes to native text/progress events and displays approval cards inline. `AgentDiffOverlay` paints before/after text or style over the retained page scene but never updates canonical `EditorDocumentState`. On commit event, clear the preview and refresh only affected pages. On reject/cancel, remove the preview without changing revision.

- [ ] **Step 4: Run workspace agent and existing chat regressions**

Run:

```powershell
flutter analyze lib/src/features/workspace lib/src/core/agent
flutter test test/workspace_agent test/workspace_ai/ai_side_pane_test.dart test/workspace_ai/workspace_ai_migration_test.dart
```

Expected: streaming continuation, progress, approval, reject, rebase, cancellation, exact diff lifecycle, provider settings, conversation history, and existing chat layout tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/agent/presentation lib/src/features/workspace/presentation/widgets/ai_side_pane.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/application/ai_runtime_service.dart lib/src/core/models.dart test/workspace_agent test/workspace_ai/ai_side_pane_test.dart test/workspace_ai/workspace_ai_migration_test.dart
git commit -m "feat: surface agent previews and approvals"
```

### Task 14: Conversation Migration and Removal of Dart Agent Authority

**Files:**
- Create: `lib/src/features/workspace/infrastructure/native_conversation_migrator.dart`
- Modify: `lib/src/features/workspace/application/conversation_context.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/features/workspace/infrastructure/conversation_store.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Delete: `lib/src/features/workspace/application/ai_agent_runtime.dart`
- Delete: `lib/src/features/workspace/application/ai_tool_registry.dart`
- Delete: `lib/src/features/workspace/infrastructure/openai_compatible_provider.dart`
- Delete: `test/workspace_ai/ai_agent_runtime_test.dart`
- Delete: `test/workspace_ai/openai_compatible_provider_test.dart`
- Test: `test/workspace_agent/native_conversation_migration_test.dart`

**Interfaces:**
- Consumes: legacy `clarix_conversations.sqlite` and native conversation import DTOs.
- Produces: idempotent one-time migration and a single Rust authority for runs/tools/audit.

- [ ] **Step 1: Write failing idempotent migration tests**

```dart
test('legacy conversations import once with stable IDs and ordering', () async {
  await legacy.saveThread(threadWithMessages());
  await migrator.run();
  await migrator.run();
  final imported = await native.readConversation(threadId);
  expect(imported.messages.map((message) => message.sequence), <int>[1, 2]);
  expect(native.importCalls, 1);
});

test('failed import keeps the legacy database and retries next launch', () async {
  native.failNextImport = true;
  await expectLater(migrator.run(), throwsA(isA<Exception>()));
  expect(await legacy.exists(), isTrue);
  await migrator.run();
  expect((await native.readConversation(threadId)).messages, isNotEmpty);
});
```

- [ ] **Step 2: Verify red**

Run: `flutter test test/workspace_agent/native_conversation_migration_test.dart`

Expected: tests fail because the migrator is absent.

- [ ] **Step 3: Migrate then delete duplicate authority**

Import thread/message IDs, document IDs, titles, timestamps, roles, content, citations, summaries, compacted flags, and sequence numbers through one native transaction. Record migration completion only after native verification. Keep the legacy database intact for one release as a read-only recovery copy; stop opening it during normal startup after successful migration. Move conversation-history call sites from the old `AiChatMessage` type to Task 11's `AgentConversationMessage`. Delete the Dart agent loop, Dart tool registry, Dart HTTP provider, and their superseded unit tests only after all production call sites use the native bridge and equivalent Rust provider/run tests are green. Retain provider profile/key storage and Dart value types used only for settings.

- [ ] **Step 4: Run migration, secret, and dependency scans**

Run:

```powershell
flutter test test/workspace_agent/native_conversation_migration_test.dart test/workspace_ai/workspace_ai_migration_test.dart
rg -n "AiAgentRuntime|AiToolRegistry|OpenAiCompatibleProvider" lib test
rg -n "apiKey|authorization" rust/clarix_agent_core rust/clarix_editing_store
```

Expected: tests pass; the first search returns no production call sites; the secret scan returns only redaction/validation code and tests, never serialization or logging.

- [ ] **Step 5: Commit**

```powershell
git add -A lib/src/features/workspace test/workspace_ai test/workspace_agent
git commit -m "refactor: make Rust the sole agent authority"
```

### Task 15: Phase 3 Deterministic Evaluations and Layered Exit Gate

**Files:**
- Create: `rust/clarix_agent_core/tests/phase3_evaluations.rs`
- Create: `test/workspace_agent/phase3_integration_test.dart`
- Create: `tool/editing_phase3/run_phase3_checks.ps1`
- Create: `docs/testing/editing-phase3-exit-gate.md`

**Interfaces:**
- Consumes: all Phase 3 contracts.
- Produces: a fast required gate plus optional native fixture and live-provider qualification layers.

- [ ] **Step 1: Add failing deterministic evaluation cases**

Create a table-driven scripted-provider suite with these named cases and exact assertions:

```rust
let cases = [
    eval("exact-target-rewrite", exact_target_fixture(), Expect::CommittedOnce),
    eval("stale-selection", stale_selection_fixture(), Expect::ConflictNoMutation),
    eval("read-tool-choice", search_question_fixture(), Expect::Tool("search_text")),
    eval("bulk-approval", replace_all_fixture(), Expect::ApprovalNoMutation),
    eval("save-is-explicit", save_request_fixture(), Expect::SaveUiEventNoMutation),
    eval("cancel-provider", slow_provider_fixture(), Expect::Cancelled),
    eval("cancel-tool", slow_tool_fixture(), Expect::CancelledNoPartialCommit),
    eval("prompt-injection", hostile_pdf_fixture(), Expect::PolicyUnchanged),
    eval("rebase", concurrent_manual_edit_fixture(), Expect::FreshApproval),
    eval("audit-links", approved_edit_fixture(), Expect::CompleteAuditChain),
];
for case in cases { case.run_and_assert(); }
```

- [ ] **Step 2: Verify the gate fails before the integration script exists**

Run: `.\tool\editing_phase3\run_phase3_checks.ps1`

Expected: PowerShell reports that the script does not exist.

- [ ] **Step 3: Implement the lightweight required gate**

The default script runs:

```powershell
cargo fmt --all --manifest-path rust/Cargo.toml -- --check
cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml --test selection_context_contract --test agent_tool_gateway
cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test run_model_contract --test provider_contract --test tool_policy_contract --test proposal_contract --test run_engine_contract --test phase3_evaluations
cargo test -p clarix_editing_store --manifest-path rust/Cargo.toml --test agent_repository_contract
cargo check -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --lib --no-default-features
flutter analyze lib/src/core/agent lib/src/features/workspace/agent lib/src/features/workspace/application/ai_runtime_service.dart
flutter test test/core/agent test/workspace_agent/agent_run_controller_test.dart test/workspace_agent/selection_ai_surface_test.dart test/workspace_agent/agent_approval_ui_test.dart test/workspace_agent/phase3_integration_test.dart
```

Add switches `-IncludeBindingGeneration`, `-IncludeNativeFixture`, and `-IncludeLiveProviderQualification`. Binding generation must assert a clean generated diff. The native fixture uses a tiny local PDF and loopback SSE server. Live-provider qualification is manual, never uses committed credentials, and is not part of the slow-machine default gate.

- [ ] **Step 4: Run the required gate and record honest evidence**

Run: `.\tool\editing_phase3\run_phase3_checks.ps1`

Expected: all deterministic evaluations, Rust contracts, native compile, Dart analysis, and focused Flutter integration tests pass in a practical development-time budget. Do not claim optional layers passed unless they were actually run.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_agent_core/tests/phase3_evaluations.rs test/workspace_agent/phase3_integration_test.dart tool/editing_phase3/run_phase3_checks.ps1 docs/testing/editing-phase3-exit-gate.md
git commit -m "test: add phase three agent exit gate"
```

## Exit Gate

Phase 3 is ready for implementation handoff when every task above has its focused test passing and the default `run_phase3_checks.ps1` succeeds. Phase 3 implementation is complete when the following evidence is present:

- Exact targeting: a validated selection’s document ID, revision, object IDs, UTF-16 ranges, quotes, style summary, and geometry survive context assembly and tool execution unchanged.
- Correct tool choice: deterministic scripted-provider evaluations select read/search/rewrite/format/undo/redo tools as expected and reject unknown or malformed calls.
- Approval enforcement: no bulk, layout, history-wide, destructive, or stale proposal advances the document revision before an approval tied to its exact digest.
- Conflict handling: a concurrent manual edit causes a revision conflict; rebase creates a new preview and approval token rather than silently retargeting.
- Cancellation: provider and tool cancellation stop future work, leave no partial transaction, close streams, and persist a terminal audit state.
- Explicit Save: the agent can emit a Save UI request but no agent code path invokes PDF materialization.
- Complete audit: every provider round, tool call, proposal, approval decision, command ID, and resulting revision is linked and recoverable without provider secrets.
- UI integration: inline selection actions, disclosure preview, streaming continuation, progress, diff overlay, approval/reject/rebase, and cancellation are covered by focused Flutter tests.
- Resource bounds: one worker per active run, one active run per document tab, bounded event queues, 6 provider rounds, 12 tool calls, 120 seconds, and 8,192 output tokens by default.
- Honest qualification: the lightweight gate is mandatory on this machine; binding regeneration, native PDF fixture, and live-provider qualification remain explicit opt-in layers and are reported separately.

## Execution Rules for the Implementing Agent

1. Read the architecture spec and this entire plan before editing.
2. Confirm `git branch --show-current` is `main`; do not create a branch or worktree.
3. Confirm `git status --short` and preserve unrelated user changes.
4. Execute tasks strictly in order. Do not combine commits across tasks.
5. For each task, write the named failing test first and run only the focused command until green.
6. Use `apply_patch` for edits. Use generators and formatters only for mechanical output.
7. Never weaken a test, permission rule, revision check, or redaction assertion to make it pass.
8. If a public FRB DTO changes, regenerate bindings in the same task and run the bridge contract.
9. Stop any command approaching 20 minutes. Record it as deferred and continue with the focused gate where safe.
10. Before declaring Phase 3 complete, run the default exit gate, inspect `git diff --check`, confirm the worktree is clean, and report which optional layers were not run.
