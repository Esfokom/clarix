# Reader, Annotations, and AI Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Leave Clarix as a reader, sidecar-backed annotation tool, PDF utility suite, and document-aware streamed AI chat, with no PDF editor or agent harness.

**Architecture:** Flutter owns the reader, annotation interaction/state, save UX, utilities, and chat presentation. A single \`clarix_native_core\` Rust crate owns document extraction/chunking, embeddings/index retrieval, OpenAI-compatible SSE, and sidecar persistence exposed through Flutter Rust Bridge. Source PDFs are never edited.

**Tech Stack:** Flutter/Dart, Riverpod, pdfrx/PDFium, Flutter Rust Bridge 2.12, Rust, reqwest, fastembed, usearch, serde.

**Spec:** \`docs/superpowers/specs/2026-08-26-reader-annotations-ai-simplification-design.md\`

## Global Constraints

- Keep PDF rendering/navigation view-only; remove editable text/object overlays and native editor sessions.
- Keep highlights, notes/comments, ink strokes, and bookmarks in Dart until the user selects Save.
- Persist only a \`<pdf>.clarix\` sidecar atomically; never rewrite the source PDF.
- Retain Rust extraction, chunking, embeddings, index/search, OpenAI-compatible SSE, and sidecar read/write.
- Do not expose agent loops, tool calls, mutation proposals, approval gates, or editing APIs via FRB.
- Keep PDF utilities independent of reader, annotations, RAG, and chat state.

---

## Planned file structure

| Path | Responsibility |
| --- | --- |
| \`lib/src/features/annotations/domain/document_annotations.dart\` | Immutable Dart records and JSON mapping for highlights, notes, ink, and bookmarks. |
| \`lib/src/features/annotations/application/annotation_controller.dart\` | In-memory state, dirty tracking, load/save. |
| \`lib/src/features/annotations/presentation/annotation_overlay.dart\` | View-only reader overlay and annotation gestures. |
| \`rust/clarix_native_core/src/sidecar.rs\` | Sidecar validation, read, atomic write. |
| \`rust/clarix_native_core/src/rag.rs\` | Retained extraction/chunking/embedding/index/query logic. |
| \`rust/clarix_native_core/src/chat.rs\` | OpenAI-compatible SSE request/parser. |
| \`rust/clarix_native_core/src/api.rs\` | Narrow FRB interface. |

### Task 1: Create Dart annotation state that stays in memory until Save

**Files:**

- Create: \`lib/src/features/annotations/domain/document_annotations.dart\`
- Create: \`lib/src/features/annotations/application/annotation_controller.dart\`
- Create: \`test/annotations/application/annotation_controller_test.dart\`
- Modify: \`lib/src/core/models.dart\`
- Modify: \`lib/src/features/workspace/application/workspace_notifier.dart\`
- Modify: \`lib/src/features/workspace/domain/workspace_feature_state.dart\`

**Interfaces:**

- Consumes: document path, document fingerprint, page number, \`Rect\`, and reader text selection.
- Produces: \`AnnotationDocumentState\`, \`AnnotationController\`, and \`AnnotationSidecarPort\`.

- [ ] **Step 1: Write the failing dirty-state test**

\`\`\`dart
test('changes remain dirty and unwritten until save succeeds', () async {
  final controller = AnnotationController(documentPath: pdfPath);
  controller.addHighlight(pageNumber: 1, rects: <Rect>[rect], text: 'hello');

  expect(controller.state.isDirty, isTrue);
  expect(sidecar.writes, isEmpty);

  await controller.save(sidecar);
  expect(controller.state.isDirty, isFalse);
  expect(sidecar.writes, hasLength(1));
});
\`\`\`

- [ ] **Step 2: Run the test**

Run: \`flutter test test/annotations/application/annotation_controller_test.dart\`

Expected: compile failure naming \`AnnotationController\`.

- [ ] **Step 3: Implement the records and controller**

\`\`\`dart
abstract class AnnotationSidecarPort {
  Future<List<DocumentAnnotation>> read(String pdfPath);
  Future<void> write(String pdfPath, List<DocumentAnnotation> annotations);
}

class AnnotationController extends StateNotifier<AnnotationDocumentState> {
  AnnotationController({required this.documentPath})
      : super(const AnnotationDocumentState.empty());

  final String documentPath;

  Future<void> save(AnnotationSidecarPort port) async {
    await port.write(documentPath, state.annotations);
    state = state.markSaved();
  }
}
\`\`\`

Move highlight, note, and bookmark records out of workspace metadata. Add \`InkAnnotation\` with page-space stroke points. Convert existing workspace mutations to annotation-controller mutations that set dirty state but do not call \`DocumentMetadataStore.write\`.

- [ ] **Step 4: Run focused tests**

Run: \`flutter test test/annotations/application/annotation_controller_test.dart\`

Expected: PASS for add/update/delete, no write before Save, successful save clearing dirty state, and failed save retaining dirty state.

- [ ] **Step 5: Commit**

\`\`\`bash
git add lib/src/features/annotations lib/src/core/models.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/domain/workspace_feature_state.dart test/annotations/application/annotation_controller_test.dart
git commit -m "feat: keep annotations in memory until save"
\`\`\`

### Task 2: Add atomic Rust sidecar persistence

**Files:**

- Create: \`rust/clarix_native_core/Cargo.toml\`
- Create: \`rust/clarix_native_core/src/lib.rs\`
- Create: \`rust/clarix_native_core/src/sidecar.rs\`
- Create: \`rust/clarix_native_core/tests/sidecar_contract.rs\`
- Modify: \`rust/Cargo.toml\`

**Interfaces:**

- Consumes: JSON-safe annotation records from Task 1.
- Produces: \`NativeAnnotationSidecar\`, \`read_annotation_sidecar\`, and \`save_annotation_sidecar\`.

- [ ] **Step 1: Write the failing Rust contract**

\`\`\`rust
#[test]
fn save_is_atomic_and_does_not_change_the_source_pdf() {
    let source = fixture_pdf();
    let original = std::fs::read(&source).unwrap();

    save_annotation_sidecar(sidecar_request(&source)).unwrap();

    assert_eq!(std::fs::read(&source).unwrap(), original);
    assert!(sidecar_path(&source).exists());
    assert_eq!(read_annotation_sidecar(source).unwrap().highlights.len(), 1);
}
\`\`\`

- [ ] **Step 2: Run the contract**

Run: \`cargo test -p clarix_native_core --test sidecar_contract\`

Expected: Cargo reports that \`clarix_native_core\` is missing.

- [ ] **Step 3: Implement the sidecar API**

\`\`\`rust
pub fn sidecar_path(pdf_path: &Path) -> PathBuf {
    PathBuf::from(format!("{}.clarix", pdf_path.display()))
}

pub fn save_annotation_sidecar(request: NativeAnnotationSidecar) -> Result<(), String> {
    let target = sidecar_path(Path::new(&request.pdf_path));
    let temporary = target.with_extension("clarix.tmp");
    std::fs::write(&temporary, serde_json::to_vec_pretty(&request).map_err(to_string)?)?;
    std::fs::rename(temporary, target)?;
    Ok(())
}
\`\`\`

Validate schema version, nonempty IDs, positive page numbers, finite geometry, and annotation-kind payloads. Missing sidecars load as an empty document. On write failure, remove the temporary sibling and retain an existing sidecar unmodified.

- [ ] **Step 4: Run sidecar contracts**

Run: \`cargo test -p clarix_native_core --test sidecar_contract\`

Expected: PASS for missing, valid, malformed, failed-write, and source-PDF preservation cases.

- [ ] **Step 5: Commit**

\`\`\`bash
git add rust/Cargo.toml rust/clarix_native_core
git commit -m "feat: add atomic annotation sidecars"
\`\`\`

### Task 3: Migrate RAG and provide a normal SSE chat stream

**Files:**

- Create: \`rust/clarix_native_core/src/rag.rs\`
- Create: \`rust/clarix_native_core/src/chat.rs\`
- Create: \`rust/clarix_native_core/src/api.rs\`
- Create: \`rust/clarix_native_core/tests/rag_contract.rs\`
- Create: \`rust/clarix_native_core/tests/chat_stream_contract.rs\`
- Modify: \`rust/clarix_native_core/src/lib.rs\`
- Modify: \`rust/clarix_native_core/Cargo.toml\`

**Interfaces:**

- Consumes: existing document chunks/index data, provider endpoint/model/headers/key, conversation messages.
- Produces: \`local_rag_index\`, \`local_rag_query\`, \`stream_chat\`, and \`NativeChatEvent\`.

- [ ] **Step 1: Write failing RAG and stream tests**

\`\`\`rust
#[test]
fn query_returns_ranked_chunk_ids_after_indexing() {
    let response = local_rag_query(indexed_request("Where is the warranty?"));
    assert_eq!(response.status, "ready");
    assert_eq!(response.results[0].chunk_id, "p2-c1");
}

#[test]
fn sse_emits_text_and_done_without_tool_events() {
    let events = parse_sse_fixture(
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\ndata: [DONE]\n"
    );
    assert_eq!(events, vec![
        NativeChatEvent::TextDelta { text: "Hi".into() },
        NativeChatEvent::Done,
    ]);
}
\`\`\`

- [ ] **Step 2: Run native tests**

Run: \`cargo test -p clarix_native_core --test rag_contract --test chat_stream_contract\`

Expected: compile failure until the RAG/chat interfaces exist.

- [ ] **Step 3: Migrate retained RAG and implement tool-free chat**

Copy retained extraction/chunking and the \`rag\` module from \`clarix_pdf_oxide\` without importing any editing or agent crate. Implement one OpenAI-compatible \`/chat/completions\` request with \`stream: true\`; do not send \`tools\`, \`tool_choice\`, selection, mutation, proposal, or budget fields.

\`\`\`rust
pub enum NativeChatEvent {
    TextDelta { text: String },
    Citation { page_number: usize, chunk_id: String },
    Error { message: String },
    Done,
}

pub fn stream_chat(request: NativeChatRequest, sink: StreamSink<NativeChatEvent>)
    -> Result<(), String> {
    let context = retrieve_context(&request)?;
    forward_sse(openai_stream(request.with_context(context))?, sink)
}
\`\`\`

Emit citations based on retrieved chunks. Provider/network/SSE failures emit \`Error\` then terminate; they do not affect reader or sidecar state.

- [ ] **Step 4: Run native tests**

Run: \`cargo test -p clarix_native_core --test rag_contract --test chat_stream_contract\`

Expected: PASS for index/query, SSE deltas, done, malformed events, and provider errors.

- [ ] **Step 5: Commit**

\`\`\`bash
git add rust/clarix_native_core
git commit -m "feat: add native RAG and streamed chat core"
\`\`\`

### Task 4: Regenerate the narrow FRB facade and replace agent runtime use

**Files:**

- Modify: FRB generation configuration used by this repository
- Create: \`lib/src/core/ffi/native_api.dart\`
- Modify: \`lib/src/core/ffi/frb_generated.dart\`, \`frb_generated.io.dart\`, and \`frb_generated.web.dart\`
- Modify: \`lib/src/core/clarix_rust_runtime.dart\`
- Modify: \`lib/src/core/pdf_oxide_bridge.dart\`
- Modify: \`lib/src/features/ai/application/ai_runtime_service.dart\`
- Create: \`test/ai/application/native_chat_runtime_service_test.dart\`
- Create: \`test/annotations/infrastructure/native_sidecar_port_test.dart\`

**Interfaces:**

- Consumes: Tasks 1–3 contracts.
- Produces: \`NativeSidecarPort\` and a direct-streaming \`AiRuntimeService\`; no \`AgentRunController\`.

- [ ] **Step 1: Write failing Dart boundary tests**

\`\`\`dart
test('normal chat forwards native deltas without agent state', () async {
  await service.sendPrompt(prompt: 'Summarize page one', onToken: tokens.add);

  expect(tokens.join(), 'The first page…');
  expect(service.runtimeKind, 'native-chat');
});

test('sidecar port writes the sidecar path only', () async {
  await port.write(pdfPath, annotations);
  expect(native.savedPaths.single, '$pdfPath.clarix');
});
\`\`\`

- [ ] **Step 2: Run tests**

Run: \`flutter test test/ai/application/native_chat_runtime_service_test.dart test/annotations/infrastructure/native_sidecar_port_test.dart\`

Expected: compile failure naming the new ports/service contract.

- [ ] **Step 3: Generate and adopt the new binding**

Run the repository FRB generator against \`clarix_native_core\`. Replace \`api.dart\`, \`agent_api.dart\`, and \`editing_api.dart\` with the generated narrow facade. Update \`ClarixRustRuntime\` to load the renamed library. Map \`TextDelta\` to \`onToken\`, \`Citation\` to \`AiReply.citations\`, and \`Error\` to \`StateError\`; remove \`AgentRunController\` subscriptions and status mapping.

- [ ] **Step 4: Run boundary tests**

Run: \`flutter test test/ai/application/native_chat_runtime_service_test.dart test/annotations/infrastructure/native_sidecar_port_test.dart\`

Expected: PASS for streamed text, citations, provider error mapping, and sidecar mapping.

- [ ] **Step 5: Commit**

\`\`\`bash
git add lib/src/core/ffi lib/src/core/clarix_rust_runtime.dart lib/src/core/pdf_oxide_bridge.dart lib/src/features/ai/application/ai_runtime_service.dart test/ai/application/native_chat_runtime_service_test.dart test/annotations/infrastructure/native_sidecar_port_test.dart
git commit -m "refactor: narrow native bridge to sidecars RAG and chat"
\`\`\`

### Task 5: Make the reader annotation-only and remove editor/agent interactions

**Files:**

- Create: \`lib/src/features/annotations/presentation/annotation_overlay.dart\`
- Modify: \`lib/src/features/reader/presentation/reader_viewer_pane.dart\`
- Modify: \`lib/src/features/reader/presentation/reader_viewer_interactions.dart\`
- Modify: \`lib/src/features/workspace/presentation/widgets/document_workspace.dart\`
- Modify: \`lib/src/features/workspace/application/workspace_providers.dart\`
- Create: \`test/reader/reader_annotation_overlay_test.dart\`

**Interfaces:**

- Consumes: \`AnnotationController\` and the reader’s page/selection geometry.
- Produces: ordinary highlight, note, ink, bookmark, and Save UI with no editing or agent dependency.

- [ ] **Step 1: Write the failing reader test**

\`\`\`dart
testWidgets('reader renders annotations but no PDF editor', (tester) async {
  await tester.pumpWidget(readerWith(highlight: fixtureHighlight));

  expect(find.byType(AnnotationOverlay), findsOneWidget);
  expect(find.text('Edit text'), findsNothing);
  expect(find.byType(NativeTextEditor), findsNothing);
});
\`\`\`

- [ ] **Step 2: Run the test**

Run: \`flutter test test/reader/reader_annotation_overlay_test.dart\`

Expected: failure because reader imports editor types or mounts an editor lifecycle.

- [ ] **Step 3: Implement the reader change**

Delete \`PageSceneLifecycle\`, editor session registry calls, \`EditorSelection\`, \`AgentSelection\`, agent disclosure dialogs, edit-mode toggles, and native text-editor imports from reader/workspace. Preserve PDF navigation, outline, text search, highlights, notes, bookmarks, and existing annotation hit testing. Render highlights and ink from page coordinates with \`AnnotationOverlay\`; route mutations to \`AnnotationController\`. Expose a document Save action that calls its controller.

- [ ] **Step 4: Run reader tests**

Run: \`flutter test test/reader/reader_annotation_overlay_test.dart test/reader\`

Expected: PASS for annotation interaction and absence of editing/agent UI.

- [ ] **Step 5: Commit**

\`\`\`bash
git add lib/src/features/annotations/presentation lib/src/features/reader lib/src/features/workspace/application/workspace_providers.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart test/reader
git commit -m "feat: annotate PDFs in the view-only reader"
\`\`\`

### Task 6: Delete editing and agent-harness implementation families

**Files:**

- Delete: \`lib/src/features/pdf_editor/\`, \`lib/src/core/editing/\`, \`lib/src/core/agent/\`
- Delete: \`lib/src/core/ffi/editing_api.dart\`, \`lib/src/core/ffi/agent_api.dart\`
- Delete: \`lib/src/features/ai/application/agent_run_controller.dart\`
- Delete: \`rust/clarix_editing_core/\`, \`rust/clarix_editing_store/\`, \`rust/clarix_pdf_adapter/\`, \`rust/clarix_agent_core/\`, \`rust/clarix_pdf_oxide/\`
- Delete: editing/agent tests, integration tests, and assets.
- Modify: \`rust/Cargo.toml\`, \`rust/Cargo.lock\`, \`lib/main.dart\`, barrel exports, imports, and architecture allowlists.

**Interfaces:**

- Consumes: Tasks 1–5 have replaced every supported legacy dependency.
- Produces: no Dart, Rust, test, Cargo, or FRB reference to editor or agent harness code.

- [ ] **Step 1: Add failing removal-fitness tests**

\`\`\`dart
test('production Dart has no editor or agent-harness imports', () {
  final source = readProductionDartFiles();
  expect(source, isNot(contains('/pdf_editor/')));
  expect(source, isNot(contains('/core/editing/')));
  expect(source, isNot(contains('/core/agent/')));
  expect(source, isNot(contains('AgentRunController')));
});
\`\`\`

Add a Rust assertion that the workspace members list contains only \`clarix_native_core\` and no remaining manifest names an editing or agent crate.

- [ ] **Step 2: Run fitness tests**

Run: \`flutter test test/architecture/simplified_product_boundary_test.dart; cargo test -p clarix_native_core simplified_workspace_boundary\`

Expected: failure while legacy implementations remain.

- [ ] **Step 3: Remove legacy code and dependencies**

Delete each listed version-controlled path. Update imports/barrels/providers/\`main.dart\` to retain only reader, annotations, utilities, workspace, settings, AI, and native core. Remove editor-only assets and tests. Remove Cargo members and dependencies used only by deleted crates, then allow Cargo to regenerate \`Cargo.lock\`.

- [ ] **Step 4: Run fitness tests**

Run: \`flutter test test/architecture/simplified_product_boundary_test.dart; cargo test -p clarix_native_core simplified_workspace_boundary\`

Expected: PASS without a compatibility shim.

- [ ] **Step 5: Commit**

\`\`\`bash
git add -A lib/src rust test integration_test assets
git commit -m "refactor: remove PDF editing and agent harness"
\`\`\`

### Task 7: Preserve utilities and run final product verification

**Files:**

- Modify: \`test/pdf_utilities/quickstart_surface_test.dart\`
- Modify: \`test/ai/application_presentation/ai_side_pane_test.dart\`
- Modify: \`test/architecture/architecture_allowlist.dart\`
- Create: \`integration_test/reader_annotations_chat_test.dart\`

**Interfaces:**

- Consumes: final reader/annotations, utilities, RAG, and chat behavior.
- Produces: regression evidence for the simplified product.

- [ ] **Step 1: Write the end-to-end test**

\`\`\`dart
testWidgets('reader annotation save and ordinary chat are independent', (tester) async {
  await openFixturePdf(tester);
  await addHighlightAndSave(tester);
  await sendChatPrompt(tester, 'What is this document about?');

  expect(sourcePdfBytes(), originalPdfBytes);
  expect(sidecarExists(), isTrue);
  expect(find.text('Approve edit'), findsNothing);
});
\`\`\`

- [ ] **Step 2: Run focused product tests**

Run: \`flutter test test/pdf_utilities/quickstart_surface_test.dart test/ai/application_presentation/ai_side_pane_test.dart integration_test/reader_annotations_chat_test.dart\`

Expected: failure until all final wiring is complete.

- [ ] **Step 3: Make only fixes exposed by the tests**

Keep utilities independent. Ensure RAG/SSE failure leaves reader and sidecar untouched. Update fixtures and exports to the final feature set; never restore editing or agent compatibility code.

- [ ] **Step 4: Run final verification**

Run:

\`\`\`bash
flutter analyze
flutter test
cargo test -p clarix_native_core
git diff --check
\`\`\`

Expected: all commands exit 0. An environment-dependent test may be ignored only when it states its prerequisite in the test name.

- [ ] **Step 5: Commit**

\`\`\`bash
git add test integration_test docs lib rust
git commit -m "test: cover simplified reader annotations and chat"
\`\`\`

## Plan self-review

- Tasks 1–2 cover temporary annotations and atomic sidecars.
- Tasks 3–4 retain native RAG/SSE and replace the broad FRB boundary.
- Task 5 retains a view-only reader and annotation UI.
- Task 6 removes editing and agent code completely.
- Task 7 proves utilities, reader annotations, and normal chat work together.
