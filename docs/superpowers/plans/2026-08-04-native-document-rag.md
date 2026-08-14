# Native Document RAG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make active-PDF chat use a validated, cached Rust semantic index with lexical fallback and clearly separated document and general-knowledge answers.

**Architecture:** Flutter owns document lifecycle and persisted extracted chunks. Rust owns FastEmbed model loading, manifest/index validation, atomic rebuilding, and semantic queries. Flutter checks cached chunks and the native index on open, schedules only missing work in the background, and exposes per-document RAG state to the AI pane.

**Tech Stack:** Flutter/Dart, Riverpod, flutter_rust_bridge 2.12, Rust, fastembed, usearch, flutter_test, cargo test.

## Global Constraints

- Keep PDF text, vectors, and indexes local in app-support storage.
- Validate cache by SHA-256 fingerprint, model ID, dimensions, manifest version, and ordered chunk IDs.
- Do not add MarkItDown, Python, or a remote retrieval dependency.
- Native RAG failures must preserve PDF reading and lexical chat retrieval.
- Remote prompts must label evidence `From the document` and supplementary content `General knowledge (not from this document)`.
- Regenerate FRB bindings with `flutter_rust_bridge_codegen generate` after Rust API changes.

---

## File structure

- `rust/clarix_pdf_oxide/src/rag.rs`: persisted-index validation and Rust tests.
- `rust/clarix_pdf_oxide/src/api.rs`: FRB validation/index API.
- `lib/src/core/ffi/*`: generated bindings only.
- `lib/src/features/workspace/infrastructure/document_chunk_store.dart`: cached-chunk presence/read path.
- `lib/src/features/workspace/infrastructure/local_rag_native_retriever.dart`: single-flight validation/indexing and restart-safe status.
- `lib/src/features/workspace/application/workspace_notifier.dart`: cache-first open orchestration.
- `lib/src/core/models.dart` and `lib/src/features/workspace/domain/workspace_feature_state.dart`: non-persisted per-document RAG UI state.
- `lib/src/features/workspace/application/ai_agent_runtime.dart`: grounding contract/context construction.
- `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`: active-title and context-state UI.

### Task 1: Expose validated native cache status

**Files:**

- Modify: `rust/clarix_pdf_oxide/src/rag.rs`
- Modify: `rust/clarix_pdf_oxide/src/api.rs`
- Modify: generated `lib/src/core/ffi/*` via `flutter_rust_bridge_codegen generate`

**Interfaces:**

- Produce `local_rag_validate(request: NativeRagIndexRequest) -> NativeRagIndexResponse`.
- Extend `NativeRagIndexResponse` with `outcome`: `loaded`, `built`, or `null`.
- `local_rag_validate` must not embed, download, or write; it returns `loaded` only after full manifest/index validation.

- [ ] **Step 1: Write failing Rust tests**

Add to `rag.rs` tests: first `index_or_load` returns `Built`; a second call returns `Loaded`; an ordered chunk-ID change returns `RagError::RebuildRequired`; an incomplete index/manifest pair returns `RebuildRequired`.

```rust
assert_eq!(engine.index_or_load("fp", &paths, &chunks)?, RagIndexOutcome::Built);
assert_eq!(engine.index_or_load("fp", &paths, &chunks)?, RagIndexOutcome::Loaded);
```

- [ ] **Step 2: Verify RED**

Run: `cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml rag_`

Expected: new test fails only for missing validation/outcome behavior.

- [ ] **Step 3: Implement the validation boundary**

Extract existing index/manifest validation into `VectorRagEngine::validate_existing(document_fingerprint, paths, chunks)`. In `api.rs`, convert the request chunks to `RagChunk`, create the cached FastEmbed backend, and map results as follows: valid -> `{ status: "ready", outcome: "loaded" }`; `RebuildRequired` -> `{ status: "idle", outcome: null }`; all other errors -> `{ status: "failed", message }`. Update `local_rag_index` to report whether it loaded or built. Delete the filesystem-only `local_rag_status` API.

- [ ] **Step 4: Regenerate and verify**

Run: `flutter_rust_bridge_codegen generate`

Run: `cargo fmt --check --manifest-path rust/clarix_pdf_oxide/Cargo.toml`

Run: `cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml rag_`

Run: `flutter analyze lib/src/core/ffi`

Expected: all exit 0.

- [ ] **Step 5: Commit**

Run: `git add rust/clarix_pdf_oxide/src/rag.rs rust/clarix_pdf_oxide/src/api.rs lib/src/core/ffi; git commit -m "feat: validate cached native RAG indexes"`

### Task 2: Reuse valid index once per document and preserve lexical fallback

**Files:**

- Modify: `lib/src/features/workspace/infrastructure/document_chunk_store.dart`
- Modify: `lib/src/features/workspace/infrastructure/local_rag_native_retriever.dart`
- Modify: `lib/src/features/workspace/infrastructure/local_rag_service.dart`
- Test: `test/workspace_ai/local_rag_service_test.dart`
- Create: `test/workspace_ai/local_rag_native_retriever_test.dart`

**Interfaces:**

- Produce `Future<bool> DocumentChunkStore.hasChunks(String documentId)`.
- Produce `Future<LocalRagIndexStatus> NativeLocalRagRetriever.ensureReady(String documentId, List<PdfChunkRecord> chunks)`.
- Produce an injectable `NativeRagGateway` wrapping FRB validate/index/query calls.

- [ ] **Step 1: Write failing adapter tests**

Using a fake `NativeRagGateway`, test that a fresh retriever calls validation and becomes ready without indexing on a valid prior cache; that an idle validation indexes once; two concurrent `ensureReady` calls for a fingerprint share one future; and native failure sets failed while `LocalRagService` returns lexical results.

```dart
final values = await Future.wait(<Future<LocalRagIndexStatus>>[
  retriever.ensureReady(documentId, chunks),
  retriever.ensureReady(documentId, chunks),
]);
expect(values, everyElement(LocalRagIndexStatus.ready));
expect(gateway.indexCalls, 1);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/local_rag_native_retriever_test.dart`

Expected: FAIL because the gateway and `ensureReady` do not exist.

- [ ] **Step 3: Implement cache-aware single-flight readiness**

`hasChunks` checks JSONL or legacy JSON existence without parsing it. `ensureReady` initializes the Rust runtime, coalesces work in `Map<String, Future<LocalRagIndexStatus>>`, validates with the current chunks, and indexes only after an `idle` response. Native errors set `failed` without throwing. Keep `LocalRagService` semantic-first and lexical fallback; de-duplicate output by chunk ID before returning it.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/local_rag_native_retriever_test.dart test/workspace_ai/local_rag_service_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add lib/src/features/workspace/infrastructure/document_chunk_store.dart lib/src/features/workspace/infrastructure/local_rag_native_retriever.dart lib/src/features/workspace/infrastructure/local_rag_service.dart test/workspace_ai/local_rag_native_retriever_test.dart test/workspace_ai/local_rag_service_test.dart; git commit -m "feat: reuse cached local RAG indexes"`

### Task 3: Prepare RAG in the background when PDFs open

**Files:**

- Modify: `lib/src/core/models.dart`
- Modify: `lib/src/features/workspace/domain/workspace_feature_state.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Test: `test/workspace_ai/workspace_notifier_test.dart`

**Interfaces:**

- Produce `enum DocumentRagStatus { idle, preparing, ready, lexicalFallback, unavailable, failed }`.
- Produce `WorkspaceFeatureState.documentRagStatuses: Map<String, DocumentRagStatus>` keyed by fingerprint.

- [ ] **Step 1: Write failing notifier tests**

With overridden chunk storage, extraction, and native indexer, assert: cached chunks trigger validation without extraction; cache misses set `preparing`, stream extraction batches once, then index; zero chunks produces `unavailable`; and closing a tab before async completion prevents stale state resurrection.

```dart
await notifier.openPdfFiles(<String>[pdf.path]);
await pumpEventQueue();
expect(state.documentRagStatuses[fingerprint], DocumentRagStatus.ready);
expect(extraction.buildCalls, 0);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/workspace_notifier_test.dart`

Expected: FAIL because cache-first RAG preparation and statuses are absent.

- [ ] **Step 3: Implement open-time orchestration**

Replace `_indexDocument` with background preparation: check `hasChunks`; read and validate cached chunks if present; otherwise set `preparing`, stream `HybridPdfExtractionService.buildChunkBatches` into `replaceWithBatches`, then call `ensureReady`. Start after the tab/session commit using `unawaited`. Keep `DocumentIndexStatus` for extraction only and use `DocumentRagStatus` for semantic availability. On every async update, confirm the tab/document still exists in current state.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/workspace_notifier_test.dart test/workspace_ai/workspace_ai_migration_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add lib/src/core/models.dart lib/src/features/workspace/domain/workspace_feature_state.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_ai/workspace_notifier_test.dart; git commit -m "feat: prepare document RAG in background"`

### Task 4: Enforce grounded answer sections and show context status

**Files:**

- Modify: `lib/src/features/workspace/application/ai_agent_runtime.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Test: `test/workspace_ai/ai_agent_runtime_test.dart`
- Create: `test/workspace_ai/ai_side_pane_test.dart`

**Interfaces:**

- System prompt requires exact headings `From the document` and `General knowledge (not from this document)`.
- Pane consumes `documentRagStatuses[activeTab.documentId]` as a separate context indicator.

- [ ] **Step 1: Write failing runtime/widget tests**

Capture provider system messages and assert the two headings, page-citation requirement, prohibition against unsupported document claims, and explicit fallback when no retrieval is available. Render `AiSidePane` with an active tab and each relevant RAG status; assert its title plus `Preparing document context`, `Ready to search this document`, and lexical-fallback copy.

```dart
expect(systemPrompt, contains('From the document'));
expect(systemPrompt, contains('General knowledge (not from this document)'));
expect(find.text('contract.pdf'), findsOneWidget);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/ai_agent_runtime_test.dart test/workspace_ai/ai_side_pane_test.dart`

Expected: FAIL because the prompt and context indicator are not yet specific enough.

- [ ] **Step 3: Implement grounding and display behavior**

Make document passages authoritative only for `From the document`, require citations there, and require outside facts to appear only under the exact general-knowledge heading. When no passages are retrieved, tell the model to state insufficient document evidence. Retain existing six-passage/1,500-character limits and deduplicate citations. In the pane, retain the active document title and add a distinct context-state badge/row so generation/provider status is not overwritten.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/ai_agent_runtime_test.dart test/workspace_ai/ai_side_pane_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add lib/src/features/workspace/application/ai_agent_runtime.dart lib/src/features/workspace/presentation/widgets/ai_side_pane.dart test/workspace_ai/ai_agent_runtime_test.dart test/workspace_ai/ai_side_pane_test.dart; git commit -m "feat: label document-grounded AI answers"`

### Task 5: Verify the complete native RAG flow

**Files:**

- Modify only if a verification command exposes a defect in tasks 1-4.

- [ ] **Step 1: Run all RAG and workspace tests**

Run: `flutter test test/workspace_ai`

Run: `cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml`

Expected: both exit 0.

- [ ] **Step 2: Run static and build checks**

Run: `flutter analyze`

Run: `cargo fmt --check --manifest-path rust/clarix_pdf_oxide/Cargo.toml`

Run: `cargo clippy --manifest-path rust/clarix_pdf_oxide/Cargo.toml -- -D warnings`

Run: `flutter build windows`

Expected: all exit 0 with no analysis errors or Rust warnings.

- [ ] **Step 3: Inspect the final state**

Run: `git diff HEAD~4..HEAD --check`

Run: `git status --short`

Confirm cache validation, coalesced background indexing, lexical fallback, prompt headings, citations, active-title display, and context status are implemented. Commit only a verification-discovered fix; otherwise leave the worktree clean.
