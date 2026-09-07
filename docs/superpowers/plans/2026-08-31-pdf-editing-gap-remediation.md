# PDF Editing & Vibe Editing — Critical Gap Analysis and Phased Remediation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan phase by phase. Steps use checkbox (`- [ ]`) syntax for tracking. Execute Phase A inline on `main` first; Phases B–D each get their own execution session.

**Goal:** Make manual PDF text editing actually mutate and re-render the PDF in real time (Phase 3), then close the Phase-4 gap so natural-language "vibe editing" can locate document positions and edit them in place through the agent harness.

**Architecture (as built, verified):** Three document instances coexist per editor tab. (1) The pdfrx viewer document (`reader_viewer_pane.dart:396`) renders the base page and is never mutated. (2) The Dart-owned `LivePdfiumSession` PDFium document (`live_pdfium_session.dart:52`) is the only physically mutated document — `FPDFText_SetText`, `FPDFPageObj_SetMatrix`, `FPDFPage_GenerateContent` run on pdfrx's worker via `PdfiumWorkerExecutor`; its re-rendered RGBA tiles are composited over the base page. (3) The Rust editing session (`clarix_pdf_oxide` → `clarix_editing_core`) is the semantic authority: commands, revisions, undo/redo, SQLite durability, physical edit plans (`ReplaceText`, `SetTextTransform`) — Rust holds no PDFium handles. Command flow: Flutter keypress → `SessionTextInput` → `EditorSessionController.applyLocalDelta` → `EditorSessionGateway._submitRouted` → `LivePdfiumEditorPort.submit` (Rust `prepare_live_command` → Dart `LivePdfiumSession.apply` → Rust `publish_prepared_live_command`) → tile invalidation → repaint. Save writes `liveSession.saveBytes()` (`document.encodePdf()`) through Rust's 9-stage `SaveCoordinator`.

**Tech Stack:** Flutter/Dart 3.12, pdfrx 2.4.7 (stock, unpatched), pdfium_flutter 0.2.3 FFI, flutter_rust_bridge 2.12, Rust (clarix_editing_core, clarix_agent_core, clarix_editing_store, clarix_pdf_adapter, clarix_pdf_oxide), SQLite sidecar.

---

## Part 1 — Ground truth: what is implemented

- **Phase 1–2 (reader + RAG chat):** done and working. pdfrx reader, local RAG (fastembed/usearch), OpenAI-compatible agent runtime, conversation history, citations.
- **Phase 3 (selection-aware conversational agent):** largely implemented. Rust agent core (`run.rs` engine, `tool_registry.rs`, `policy.rs`, `proposal.rs`, `openai_stream.rs`, `audit.rs`), editing tool gateway (`tools.rs`, `selection_context.rs`), agent API over FRB (`agent_api.rs`), Dart layer under `lib/src/features/ai/` (`agent_run_controller.dart`, `ai_side_pane.dart`, `selection_ai_toolbar.dart`, `agent_disclosure_dialog.dart`, `agent_approval_card.dart`, `agent_diff_overlay.dart`, `native_conversation_migrator.dart`), SQLite audit (`agent_repository.rs`), deterministic evaluations (`phase3_evaluations.rs`).
- **Live PDFium editing stack:** implemented end-to-end but never exercised interactively. Live session, hydration, locator registry, strict routing, physical text replacement/transforms, undo/redo routing, tile renderer with LRU cache, live save bytes, recovery-state isolation (`11cbc57`).
- **Known-incomplete by design:** full viewer unification (all tiles from the live document) was deferred; tiles are never re-rendered at new zoom; the 2026-08-28 plan's Task 6 (Windows interactive acceptance) was never executed; Phase 1 was accepted with a **runtime-evidence waiver** — the keystroke/IME/frame behavior was never empirically verified.

## Part 2 — Critical gap register

| # | Gap | Symptom it causes | Phase/Task |
|---|---|---|---|
| G1 | **Live-editing kill-switches are silent.** (a) `LivePdfiumSession._revision` starts at 0 and is never seeded from Rust (`live_pdfium_session.dart:64`); Rust increments its revision on every published command, including semantic-only ones (annotations, checkpoints, style, font-fallback approval). The next keystroke arrives with `plan.previousRevision > _revision` and throws `live PDFium revision conflict` (`live_pdfium_session.dart:137-142`) — typing dead until reopen. (b) `page_scene` silently falls back to the legacy span importer when live hydration is skipped/failed (`editing_api.rs:781-794`); those objects have no locator bindings → `live_pdfium_binding_missing` (`editor_session_gateway.dart:343`). (c) Every failure is swallowed into `errorCode` state (`editor_session_controller.dart:549-561`) that **nothing renders** — only `text_overflow` and save dialogs read it. | "Backspace/typing does nothing" | A1, A2, A4 |
| G2 | **The "overlay" is the fallback rendering path.** `usesLivePdfiumTiles` is a tile-*count* heuristic (`page_edit_scene.dart:108-111`): `liveTiles.length >= editableObjectIds.length`. On partial tiling the scene masks the object and paints semantic text via `EditorTextObjectLayer` over the **untouched base page** — original glyphs still visible underneath → reads as an overlay, not an edit. Live tiles are opaque white rects sized to pre-mutation bounds → longer text is clipped; tiles are never re-rendered after zoom changes. | "Anything is overlaid, PDF never edited" | B1, B2 |
| G3 | **Three document instances; unification half-done; contradictory docs; dead code.** The 2026-08-14 master architecture doc prescribes the opposite of what the 2026-08-27/28 live-PDFium docs (and the code) do. Legacy editor files (`PdfTextEditorOverlay`, `NativeTextEditor`, `PdfNativeTextInput`, `EditorShortcuts`) are still exported from the barrel with no call sites. | Confusion, drift, maintenance risk | B3, D1 |
| G4 | **Live imports are exempt from the Rust font contract** (`model.rs:839-858`), so glyph failures first surface inside PDFium at typing time: `FPDFText_SetText` returns 0 → whole transaction rolls back → swallowed. No live-path font fallback exists. | Typing silently fails on some characters | B5 (+A2 surfacing) |
| G5 | **Undo/redo are routed through the live port unconditionally** (`editor_session_gateway.dart:346-348`). History entries that are semantic-only (annotations, checkpoints) have no physical plan → `prepare_live_command` errors (`editing_api.rs:1038-1040`) → swallowed. | Undo stops working after an annotation | A3 |
| G6 | **Save can silently write an unchanged PDF.** `save_live_pdfium` writes whatever PDFium holds; if edits only reached the Rust model (any G1/G5 failure), Save succeeds with the original bytes. | Data loss masquerading as success | A5 |
| G7 | **Focus fragility.** `viewerKeyHandlerFor` consumes *all* keys in text-editing mode (`reader_viewer_components.dart:638-639`); `SessionTextInput` requests focus once, post-frame, on first mount (`session_text_input.dart:59-61`). Any focus steal turns the whole keyboard into a no-op — indistinguishable from G1. | "Nothing happens when I type" | A6 |
| G8 | **Caret precision.** Live imports may lack per-character boxes; hit-testing and the caret fall back to *synthesized proportional (uniform-width) boxes* (`editor_hit_test.dart:189-213`), which are wrong for proportional fonts and imprecise across multi-object blocks. | "Cursor position is not so efficient" | B4 |
| G9 | **No end-to-end verification.** No test proves keypress → PDF bytes change → extract text matches. Phase-1 runtime gate waived; 2026-08-28 Task 6 never run; no CI. | Bugs like G1–G7 ship unnoticed | A7, D2 |
| G10 | **Phase-4 (vibe editing) gaps.** (a) Agent tool commits execute inside Rust (`EditingToolGateway` → actor `publish`) and **bypass the live physical path entirely** — the agent edits the semantic model while the rendered PDF never changes. (b) No structural/spatial location tools: the agent can only `search_text` or use an existing selection — it cannot resolve "the second paragraph", "the title", "top of page 3". (c) No object insertion/deletion (unified-migration order item 3) and no reflow (item 5) — vibe edits that add/remove/reflow content are impossible. (d) Disclosure is selection-scoped; free-form document edits need document-scope disclosure. | Phase 4 cannot work even after A–B are fixed | C1–C6 |

---

## Phase A — Make manual live editing actually work

> Everything below is verified against current code. Tests are TDD: red first, minimal implementation, green, commit.

### Task A1: Seed and acknowledge the live PDFium revision

**Files:**
- Modify: `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart:64` (field), after `open` (add seed/acknowledge/getter)
- Modify: `lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart:215-235` (seed at open), `:321-350` (`_submitRouted`), `:423-449` (annotation paths), `:367-376` (`approveFontFallback`)
- Test: `test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart`
- Test: `test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`

**Interfaces:** `LivePdfiumSession` gains `int get appliedRevision`, `void seedRevision(int)`, `void acknowledgeRevision(int)`. The gateway acknowledges `result.committedRevision` after *every* publish (live or semantic) while a live session exists.

- [ ] **Step 1: Write the failing revision-sync tests**

```dart
test('a seeded session accepts a plan prepared at the seed revision', () async {
  final session = await LivePdfiumSession.open(fixturePath);
  session.seedRevision(3);
  final result = await session.apply(LivePdfiumEditPlan(
    replacements: <LivePdfiumTextReplacement>[
      LivePdfiumTextReplacement(locator: locator, replacement: 'x'),
    ],
    expectedRevision: 3,
    revision: 4,
  ));
  expect(result.revision, 4);
  expect(session.appliedRevision, 4);
});

test('acknowledgeRevision advances the applied revision and rejects receding values', () async {
  final session = await LivePdfiumSession.open(fixturePath);
  session.acknowledgeRevision(2);
  expect(session.appliedRevision, 2);
  expect(() => session.acknowledgeRevision(1), throwsStateError);
});
```

In `editor_session_gateway_live_pdfium_test.dart`:

```dart
test('a semantic-only publish acknowledges the live revision so the next edit applies', () async {
  await gateway.open(request);
  // checkpoint publishes semantically and bumps the Rust revision to 1
  final checkpoint = await gateway.submit(checkpointRequest());
  expect(checkpoint.committedRevision, 1);
  final applied = await gateway.submit(replaceTextRequest(baseRevision: 1));
  expect(applied.committedRevision, 2);
  expect(liveSession.appliedRevision, 2);
});
```

- [ ] **Step 2: Run the tests and verify the red state**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`
Expected: FAIL — `seedRevision`/`acknowledgeRevision` do not exist; the checkpoint test fails with `live PDFium revision conflict: expected 1, actual 0`.

- [ ] **Step 3: Implement seeding and acknowledgement**

In `live_pdfium_session.dart`:

```dart
int get appliedRevision => _revision;

/// Aligns this session with the Rust revision before any plan was applied.
void seedRevision(int revision) {
  _ensureOpen();
  _revision = revision;
}

/// Aligns this session after a Rust publish that had no physical apply
/// (semantic-only commands, agent commits). Rejecting a receding value
/// catches a misordered publish early instead of corrupting later edits.
void acknowledgeRevision(int revision) {
  _ensureOpen();
  if (revision < _revision) {
    throw StateError(
      'cannot acknowledge a receding revision: $revision < $_revision',
    );
  }
  _revision = revision;
}
```

In `editor_session_gateway.dart`, after `metadata` is available in `open()` (line 215):

```dart
final metadata = await semanticSession.metadata();
if (liveSession is LivePdfiumSession) {
  liveSession.seedRevision(metadata.revision);
}
```

Add a private wrapper and route every publish through it:

```dart
Future<EditorCommandResult> _acknowledgePublish(
  Future<EditorCommandResult> Function() publish,
) async {
  final result = await publish();
  final liveSession = _livePdfiumSession;
  if (liveSession is LivePdfiumSession) {
    try {
      liveSession.acknowledgeRevision(result.committedRevision);
    } on StateError {
      // Session closed concurrently; the close path owns cleanup.
    }
  }
  return result;
}
```

Rewrite `_submitRouted` to wrap all three branches:

```dart
Future<EditorCommandResult> _submitRouted(EditorCommandRequest request) {
  // ... existing isLiveTextCommand / hasLiveBinding / isHistoryCommand
  if (livePort != null && isLiveTextCommand) {
    if (!hasLiveBinding) throw StateError('live_pdfium_binding_missing');
    return _acknowledgePublish(() => livePort.submit(request));
  }
  if (isHistoryCommand && livePort != null) {
    return _acknowledgePublish(() => livePort.submit(request));
  }
  return _acknowledgePublish(() => _required().submit(request));
}
```

Wrap `createAnnotation` (line 427), `updateAnnotation` (438), `deleteAnnotation` (449), and `approveFontFallback` (369-376) with `_acknowledgePublish` as well.

- [ ] **Step 4: Run the tests and verify green**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart
git commit -m "fix: seed and acknowledge live PDFium revisions"
```

### Task A2: Surface every edit failure instead of swallowing it

**Files:**
- Modify: `lib/src/features/pdf_editor/application/editor_session_controller.dart:812-826` (`_errorCode` normalization)
- Modify: `lib/src/features/pdf_editor/presentation/page_edit_scene.dart:352-368` (generalize the error banner)
- Test: `test/pdf_editor/application_presentation/page_edit_scene_test.dart`
- Test: `test/pdf_editor/domain_infrastructure/editor_session_controller_error_test.dart`

**Interfaces:** `_errorCode` maps `StateError('live PDFium revision conflict: …')` → `live_pdfium_revision_conflict`; `PageEditScene` renders a dismissible, per-code message banner for `live_pdfium_binding_missing`, `live_pdfium_revision_conflict`, `live_pdfium_unsupported`, `glyph_unsupported`, and `live_hydration_failed`, with a retry action that calls `refreshPage(pageNumber, force: true)`.

- [ ] **Step 1: Write the failing widget test**

```dart
testWidgets('a live binding failure shows an actionable banner', (tester) async {
  final harness = await pumpPageEditScene(tester,
      errorCode: 'live_pdfium_binding_missing');
  expect(find.textContaining('not bound to the live document'), findsOneWidget);
  await tester.tap(find.byKey(const Key('editor-error-retry')));
  expect(harness.controller.refreshedPages, contains(1));
  await tester.tap(find.byKey(const Key('editor-error-dismiss')));
  expect(harness.controller.clearedError, isTrue);
});
```

- [ ] **Step 2: Run and verify red**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/page_edit_scene_test.dart`
Expected: FAIL — no banner renders for `live_pdfium_binding_missing`.

- [ ] **Step 3: Normalize error codes**

In `_errorCode` (controller line 812), before the generic fallback:

```dart
final message = error is StateError ? error.message : error.toString();
if (message.startsWith('live PDFium revision conflict')) {
  return 'live_pdfium_revision_conflict';
}
if (message.contains('glyph') || message.contains('FPDFText_SetText')) {
  return 'glyph_unsupported';
}
```

- [ ] **Step 4: Render the banner**

In `page_edit_scene.dart`, replace the `text_overflow`-only block (352-368) with a generic block:

```dart
if (activeSession != null && document.errorCode case final String code)
  if (_editFailureBanners.containsKey(code))
    Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Semantics(
        liveRegion: true,
        child: _EditorErrorBanner(
          key: const Key('editor-error-banner'),
          message: _editFailureBanners[code]!,
          onRetry: code == 'live_pdfium_binding_missing' ||
                  code == 'live_hydration_failed'
              ? () => unawaited(activeSession.refreshPage(
                  activeObject?.pageId == null ? 1 : _pageNumberOf(activeObject),
                  force: true))
              : null,
          onDismiss: activeSession.clearError,
        ),
      ),
    ),
```

`_editFailureBanners` maps codes to user-facing messages:

```dart
static const Map<String, String> _editFailureBanners = <String, String>{
  'text_overflow': 'Text does not fit this object. Shorten it or cancel the edit.',
  'live_pdfium_binding_missing': 'This text is not bound to the live document. Re-inspect the page to enable editing.',
  'live_pdfium_revision_conflict': 'Document state changed underneath the editor. Re-open edit mode to continue.',
  'live_pdfium_unsupported': 'This change cannot be applied to the PDF yet.',
  'glyph_unsupported': 'This character is not supported by the PDF font.',
  'live_hydration_failed': 'Live page import failed. Re-inspect the page or reopen the editor.',
};
```

`_EditorErrorBanner` is a small stateless widget with the message text, an optional `EditorErrorRetry` button (`Key('editor-error-retry')`) and a dismiss button (`Key('editor-error-dismiss')`); model it on the existing `OverflowIndicator` styling.

- [ ] **Step 5: Run and verify green**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/page_edit_scene_test.dart test/pdf_editor/domain_infrastructure/editor_session_controller_error_test.dart`
Expected: PASS. Also confirm the existing `text_overflow` test still passes unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/pdf_editor/application/editor_session_controller.dart lib/src/features/pdf_editor/presentation/page_edit_scene.dart test/pdf_editor/application_presentation/page_edit_scene_test.dart test/pdf_editor/domain_infrastructure/editor_session_controller_error_test.dart
git commit -m "fix: surface live PDFium edit failures"
```

### Task A3: Route undo/redo by history-entry physicality

**Files:**
- Modify: `rust/clarix_editing_core/src/command.rs:236-238` (add `physical_apply_required` to `PreparedCommand`)
- Modify: `rust/clarix_editing_core/src/session.rs` (`prepare` for Undo/Redo; `apply_undo` at 901 / `apply_redo` at 961)
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs:1017-1054` (allow `None` plan for semantic-only history entries)
- Modify: `flutter_rust_bridge.yaml` inputs if needed; regenerate `lib/src/core/ffi/*` and `rust/clarix_pdf_oxide/src/frb_generated.rs`
- Modify: `lib/src/core/editing/editor_bridge.dart:217-244` (validation accepts semantic-only prepared commands)
- Modify: `lib/src/core/editing/live_pdfium_editor_port.dart:128-191` (skip PDFium apply when not required)
- Test: `rust/clarix_editing_core/tests/command_session.rs`
- Test: `rust/clarix_pdf_oxide/tests/editing_bridge.rs`
- Test: `test/core/editing/live_pdfium_editor_port_test.dart`

**Interfaces:** `PreparedCommand.physical_apply_required: bool` (default `true`). For Undo/Redo whose replayed entry changes no text object, `prepare` sets it `false` and leaves `physical_plan: None`. `prepare_live_command` returns `NativePreparedLiveCommand { physical_apply_required: false, plan: <empty plan with previous/revision filled> }` instead of the `live_pdfium_unsupported` error in that case. Text-command plans that are `None` still error.

- [ ] **Step 1: Write the failing Rust tests**

```rust
#[test]
fn undo_of_annotation_only_history_prepares_without_a_physical_plan() {
    let mut session = session_with_page(text_page());
    session
        .submit(create_annotation_command("note-1"))
        .unwrap();
    let prepared = session
        .prepare(undo_command(session.revision()))
        .unwrap();
    assert!(!prepared.physical_apply_required);
    assert!(prepared.physical_plan.is_none());
}

#[test]
fn undo_of_text_history_still_prepares_a_physical_plan() {
    let mut session = session_with_page(text_page());
    session
        .submit(replace_text_command("old", "new"))
        .unwrap();
    let prepared = session
        .prepare(undo_command(session.revision()))
        .unwrap();
    assert!(prepared.physical_apply_required);
    assert!(prepared.physical_plan.is_some());
}
```

In `editing_bridge.rs`:

```rust
#[test]
fn semantic_only_undo_prepares_and_publishes_without_a_physical_plan() {
    let session = fixture_native_session();
    session.create_annotation(fixture_annotation()).unwrap();
    let prepared = session
        .prepare_live_command(undo_request(1))
        .unwrap();
    assert!(!prepared.physical_apply_required);
    assert!(prepared.plan.operations.is_empty());
    assert!(session.publish_prepared_live_command(prepared.token).is_ok());
}
```

- [ ] **Step 2: Run and verify red**

Run: `cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core undo_physical -- --nocapture; cargo test --manifest-path rust/Cargo.toml -p clarix_pdf_oxide semantic_only_undo -- --nocapture`
Expected: FAIL — `physical_apply_required` does not exist; the oxide test fails with `live_pdfium_unsupported`.

- [ ] **Step 3: Implement the Rust side**

`command.rs`: add `pub physical_apply_required: bool` to `PreparedCommand`, set `true` in the constructor.

`session.rs` `prepare`: when the envelope command is `Undo`/`Redo`, inspect the history entry being replayed (`history.peek_undo()` / `peek_redo()`): if no entry in its affected object set is a text object, set `physical_apply_required = false` (the physical-plan machinery already leaves `physical_plan` as `None` for non-text changes via `physical_plan_from_changes`, lines 1022-1087).

`editing_api.rs` `prepare_live_command` (1017-1054): replace the `.ok_or_else(...)` hard error:

```rust
let physical_apply_required = prepared.physical_apply_required;
let plan = prepared.physical_plan.clone();
if plan.is_none() && physical_apply_required {
    return Err(
        "live_pdfium_unsupported: command has no physical PDFium edit plan".to_owned()
    );
}
let response = NativePreparedLiveCommand {
    token: token.clone(),
    command_id: prepared.envelope.command_id.to_string(),
    previous_revision: prepared.previous_revision.value(),
    committed_revision: prepared.committed_revision.value(),
    physical_apply_required,
    plan: native_physical_edit_plan(plan.as_ref(), prepared.previous_revision, prepared.committed_revision),
};
```

`native_physical_edit_plan` gains revision parameters so an absent plan still fills `previous_revision`/`revision` and an empty `operations` list.

- [ ] **Step 4: Regenerate FRB bindings**

Run: `flutter_rust_bridge_codegen generate --no-build-runner --no-dart-fix --no-web`
Expected: `NativePreparedLiveCommand.physicalApplyRequired` appears in `lib/src/core/ffi/editing_api.dart` and `frb_generated.rs`.

- [ ] **Step 5: Implement the Dart side**

`editor_bridge.dart` (238-241): relax the validation:

```dart
if (value.commandId != request.commandId ||
    value.previousRevision != request.baseRevision ||
    value.committedRevision <= value.previousRevision ||
    value.plan.previousRevision != value.previousRevision ||
    value.plan.revision != value.committedRevision ||
    (value.physicalApplyRequired && value.plan.operations.isEmpty)) {
  throw const EditorProtocolViolation(
    'prepared live command does not describe a valid uncommitted revision',
  );
}
```

`live_pdfium_editor_port.dart` `submit` (128-191):

```dart
Future<EditorCommandResult> submit(EditorCommandRequest request) async {
  final prepared = await _semantic.prepareLiveCommand(request);
  // ... existing debug logging ...
  LivePdfiumApplyResult? applied;
  if (prepared.physicalApplyRequired) {
    // ... existing replacement/transform mapping and _session.apply ...
    applied = await _session.apply(...);
  }
  final result = await _semantic.publishPreparedLiveCommand(prepared.token);
  if (applied != null) onApplied?.call(applied);
  return result;
}
```

- [ ] **Step 6: Run and verify green**

Run: `cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core -p clarix_pdf_oxide; flutter test --no-pub test/core/editing/live_pdfium_editor_port_test.dart test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add rust/clarix_editing_core rust/clarix_pdf_oxide flutter_rust_bridge.yaml lib/src/core/ffi lib/src/core/editing/editor_bridge.dart lib/src/core/editing/live_pdfium_editor_port.dart test/core/editing/live_pdfium_editor_port_test.dart
git commit -m "fix: route semantic-only history entries without PDFium apply"
```

### Task A4: Strict live hydration with retry and visible diagnostics

**Files:**
- Modify: `lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart:284-315` (`_hydrateLivePage`)
- Modify: `lib/src/features/pdf_editor/application/editor_session_controller.dart` (map hydration failure events to error state)
- Test: `test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`

**Interfaces:** `_hydrateLivePage` retries once when `metadata.revision != expectedRevision` (instead of silently returning, line 289), and records a structured failure (`live_hydration_failed`) that reaches `EditorDocumentState.errorCode` so the Task A2 banner shows. `requestPage` never serves a legacy fallback scene silently for a page that *has* live objects registered — a hydration failure must be observable.

- [ ] **Step 1: Write the failing tests**

```dart
test('hydration retries once after a revision move instead of silently skipping', () async {
  semantic.metadataRevision = 2;
  await gateway.requestPage(1, 0); // stale request revision
  expect(semantic.importLivePageCalls, 1); // retried at the current revision
});

test('a hydration failure surfaces a live_hydration_failed error', () async {
  semantic.failImportWith('live_projection_migration_required');
  await gateway.requestPage(1, 0);
  await expectLater(
    gateway.events,
    emits(isA<EditorEvent>().having(
      (event) => event.code, 'code', 'live_hydration_failed',
    )),
  );
});
```

- [ ] **Step 2: Run and verify red**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`
Expected: FAIL — hydration currently returns silently on revision moves and throws unrecorded on failures.

- [ ] **Step 3: Implement retry and diagnostics**

In `_hydrateLivePage`, replace `if (metadata.revision != expectedRevision) return;` with a single retry at the fresh revision:

```dart
var revision = expectedRevision;
for (var attempt = 0; attempt < 2; attempt++) {
  final metadata = await semanticSession.metadata();
  if (metadata.revision != revision) {
    revision = metadata.revision;
    continue;
  }
  // ... existing inspection/manifest/import/register flow ...
  _liveImportedPages.add(pageNumber);
  return;
}
throw StateError('live_hydration_revision_moved_repeatedly');
```

Wrap the whole body in `try { ... } catch (error, stackTrace) { _recordLiveHydrationFailure(pageNumber, _errorCode(error), stackTrace); rethrow; }`, where `_recordLiveHydrationFailure` adds a `HydrationFailed(pageNumber, code)` event to a new broadcast stream the controller subscribes to (or reuse `_liveTileInvalidations`-style pattern with a dedicated `StreamController<EditorEvent>`). In the controller, map that event to `_state.copyWith(errorCode: 'live_hydration_failed')`.

- [ ] **Step 4: Run and verify green**

Run: same command as Step 2, plus `flutter test --no-pub test/pdf_editor/application_presentation/page_edit_scene_test.dart` (banner integration).
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart lib/src/features/pdf_editor/application/editor_session_controller.dart test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart
git commit -m "fix: retry live hydration and surface its failures"
```

### Task A5: Refuse to save when the PDFium document diverged from Rust

**Files:**
- Modify: `lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart:391-400` (`save`)
- Test: `test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('save refuses when the live document lags the Rust revision', () async {
  await gateway.open(request);
  liveSession.acknowledgeRevision(2); // Rust at 2
  semantic.metadataRevision = 4;      // diverged
  await expectLater(
    gateway.save(saveRequest()),
    throwsA(isA<StateError>().having(
      (error) => error.message, 'message',
      contains('live_pdfium_save_revision_mismatch'),
    )),
  );
});
```

- [ ] **Step 2: Run and verify red**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`
Expected: FAIL — save succeeds with diverged bytes.

- [ ] **Step 3: Implement the guard**

```dart
@override
Future<EditorSaveResult> save(EditorSaveRequest request) async {
  final liveSession = _livePdfiumSession;
  if (liveSession is LivePdfiumSession) {
    final metadata = await _required().metadata();
    if (liveSession.appliedRevision != metadata.revision) {
      throw StateError(
        'live_pdfium_save_revision_mismatch: applied '
        '${liveSession.appliedRevision}, published ${metadata.revision}',
      );
    }
    return _required().saveLivePdfium(
      request,
      await liveSession.saveBytes(),
    );
  }
  return _required().save(request);
}
```

Wire the save UI so this `StateError` lands in the existing `save_conflict_dialog.dart` flow (code `validation_failed` already renders there; add a `live_pdfium_save_revision_mismatch` branch with message "Edits are out of sync with the saved document. Reopen the editor before saving.").

- [ ] **Step 4: Run and verify green**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart lib/src/features/pdf_editor/presentation/save_conflict_dialog.dart test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart
git commit -m "fix: refuse saves of a diverged live document"
```

### Task A6: Make SessionTextInput hold focus

**Files:**
- Modify: `lib/src/features/pdf_editor/presentation/session_text_input.dart:65-92` (`didUpdateWidget`)
- Modify: `lib/src/features/pdf_editor/presentation/page_edit_scene.dart` (re-request focus on tap-driven selection changes if needed)
- Test: `test/pdf_editor/application_presentation/page_edit_scene_tap_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
testWidgets('changing the active object refocuses the PDF text input', (tester) async {
  final harness = await pumpEditScene(tester);
  final input = tester.state<State<SessionTextInput>>(
    find.byType(SessionTextInput),
  );
  // Steal focus, then select another object.
  tester.binding.focusManager.primaryFocus?.unfocus();
  harness.selectObject('object-2');
  await tester.pump();
  expect(FocusManager.instance.primaryFocus?.debugLabel,
      'Session PDF text input');
});
```

- [ ] **Step 2: Run and verify red**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/page_edit_scene_tap_test.dart`
Expected: FAIL — focus stays lost after the selection change.

- [ ] **Step 3: Refocus on object/selection change**

In `_SessionTextInputState.didUpdateWidget`, after the existing objectId change handling:

```dart
if (oldWidget.selection.range != widget.selection.range ||
    oldWidget.object.objectId != widget.object.objectId) {
  if (mounted && !_focusNode.hasFocus) {
    _focusNode.requestFocus();
  }
}
```

Keep `viewerKeyHandlerFor` as-is (it intentionally consumes viewer keys in edit mode); the input now reclaims focus on every selection/object change and on mount.

- [ ] **Step 4: Run and verify green**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/page_edit_scene_tap_test.dart test/pdf_editor/application_presentation/native_text_ime_test.dart`
Expected: PASS (IME regression included).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/pdf_editor/presentation/session_text_input.dart test/pdf_editor/application_presentation/page_edit_scene_tap_test.dart
git commit -m "fix: refocus PDF text input on selection changes"
```

### Task A7: End-to-end proof that typing changes the PDF

**Files:**
- Create: `integration_test/live_editing_round_trip_test.dart`
- Create: `tool/editing_phase3/run_live_round_trip.ps1`
- Modify: `docs/testing/editing-phase1-exit-gate.md` (record the previously-waived interactive items now covered)

- [ ] **Step 1: Write the integration test**

```dart
testWidgets('typing mutates saved PDF bytes and extracted text', (tester) async {
  final fixture = await copyFixtureToTemp('standard-latin.pdf');
  final harness = await openEditHarness(tester, fixture);
  await harness.enterEditMode();
  await harness.tapTextAt('alpha');
  await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('session-text-input')), 'x');
  await tester.pumpAndSettle();
  expect(harness.controller.state.errorCode, isNull); // no swallowed failure
  final savedPath = await harness.saveAs(tempSavePath());
  final reopened = await RustTextExtraction.extract(savedPath);
  expect(reopened.textOf('alphax'), isNotNull);
});
```

Run with `flutter drive -d windows --profile --driver test_driver/phase1_editing_test.dart --target integration_test/live_editing_round_trip_test.dart`.

- [ ] **Step 2: Run and verify red**

Run: `flutter drive -d windows --profile --driver test_driver/phase1_editing_test.dart --target integration_test/live_editing_round_trip_test.dart`
Expected: FAIL — text never changes in the saved PDF (pre-A1/A2 the error is swallowed; assert on `errorCode == null` catches regressions).

- [ ] **Step 3: Iterate until green on this machine**

This test is the empirical gate for all of Phase A. Any failure here must be fixed in the component under test before Phase A is declared complete. Record logs and screenshots per the exit-gate format.

- [ ] **Step 4: Commit**

```bash
git add integration_test/live_editing_round_trip_test.dart tool/editing_phase3/run_live_round_trip.ps1 docs/testing/editing-phase1-exit-gate.md
git commit -m "test: prove typing mutates saved PDF bytes"
```

**Phase A exit criteria:** typing, backspace, undo/redo, annotation+edit interleaving, and save/reopen all pass A7 on Windows; every failure mode from G1/G5/G6 renders a visible banner (A2/A4) instead of silently reverting.

---

## Phase B — Rendering correctness and unification

### Task B1: Per-object live-tile coverage instead of the count heuristic

**Files:**
- Modify: `lib/src/features/pdf_editor/presentation/page_scene_host.dart:142-181` (`_replaceLiveInvalidations` — compute coverage)
- Modify: `lib/src/features/pdf_editor/presentation/page_edit_scene.dart:98-111,141-183` (consume coverage)
- Test: `test/pdf_editor/application_presentation/page_edit_scene_test.dart`
- Test: `test/pdf_editor/domain_infrastructure/live_pdfium_tile_renderer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('a partially tiled page overlays only uncovered objects', (tester) async {
  final harness = await pumpPageEditScene(tester, liveTiles: [tileCovering('object-1')]);
  // object-1 is covered by a live tile; object-2 is not.
  expect(find.byKey(const Key('clean-patch-object-2')), findsOneWidget);
  expect(find.byKey(const Key('clean-patch-object-1')), findsNothing);
  expect(find.byKey(const Key('text-overlay-object-2')), findsOneWidget);
  expect(find.byKey(const Key('text-overlay-object-1')), findsNothing);
});
```

- [ ] **Step 2: Run and verify red**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/page_edit_scene_test.dart`
Expected: FAIL — the current heuristic suppresses or shows both objects together.

- [ ] **Step 3: Compute coverage from invalidation bounds**

In `PageSceneHost._replaceLiveInvalidations`, for each invalidation rect (in page coordinates), mark every editable object in the scene whose `bounds` intersects the inflated rect as covered at that revision, stored in a `Map<String objectId, bool> liveObjectCoverage` exposed on the scene model. `PageEditScene` replaces `usesLivePdfiumTiles` with: paint `LivePdfiumTileLayer` when `liveTiles.isNotEmpty`; paint clean-patch/mask/`EditorTextObjectLayer` only for objects with `liveObjectCoverage[objectId] != true`. Add the `Key`s used in the test to `CleanPatchLayer` and `EditorTextObjectLayer`.

- [ ] **Step 4: Run and verify green**

Run: same command as Step 2, plus `flutter test --no-pub test/pdf_editor/application_presentation`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/pdf_editor/presentation/page_scene_host.dart lib/src/features/pdf_editor/presentation/page_edit_scene.dart test/pdf_editor/application_presentation/page_edit_scene_test.dart
git commit -m "fix: composite live tiles per object coverage"
```

### Task B2: Re-render live tiles at the current zoom

**Files:**
- Modify: `lib/src/features/pdf_editor/presentation/page_scene_host.dart` (track zoom; re-issue live tile requests on zoom change)
- Test: `test/pdf_editor/application_presentation/page_scene_host_test.dart`

**Contract:** the tile request DPI is `(144*zoom).clamp(72,576)` (`page_scene_host.dart:146`). On zoom change, invalidate every live-tile cache entry for the affected pages and re-render at the new DPI before the next frame. Test: change the fake viewport zoom, assert new `LivePdfiumTileRequest` values carry the new dpi.

### Task B3: Complete the unified-PDFium viewer (own sub-plan)

**Scope (write its own detailed plan before execution):** for pages registered in `_liveImportedPages`, render the full page from the live document (base + edits in one render) instead of compositing over the untouched reader page; retire `CleanPatchLayer`/`EditorTextObjectLayer` for live sessions; delete the dead legacy editor files (`pdf_text_editor_overlay.dart`, `native_text_editor.dart`, `pdf_native_text_input.dart`, their domain types and barrel exports) once no call sites remain; keep the legacy semantic overlay path only for non-live (legacy-span) sessions. Performance gate: visible-page render p95 ≤ 50 ms, LRU tile budget unchanged.

### Task B4: Per-glyph caret precision from PDFium

**Files:**
- Modify: `lib/src/features/pdf_editor/infrastructure/pdf_text_engine.dart` (emit per-character boxes from `FPDFText_GetCharBox` during inspection)
- Modify: `lib/src/features/pdf_editor/domain/pdf_text_types.dart` (carry character boxes on `PdfTextBlock`/runs)
- Modify: `lib/src/features/pdf_editor/infrastructure/live_pdfium_import_manifest_builder.dart` (populate `EditorTextCharacterBox` from inspection)
- Modify: `lib/src/features/pdf_editor/presentation/editor_hit_test.dart:189-213` (use real boxes; keep synthesis as last resort)
- Test: `test/pdf_editor/application_presentation/editor_hit_test_test.dart` (proportional-font fixture: clicking mid-glyph maps to the nearest real boundary, not uniform slices)

### Task B5: Live-path font fallback (G4)

**Files:**
- Modify: `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart` (`_applyTextPlanOrThrow` around 433-446: on `FPDFText_SetText == 0`, throw typed `glyph_unsupported` instead of generic rollback)
- Modify: `rust/clarix_editing_core/src/model.rs:839-858` (remove the live-import font-contract exemption only after the fallback exists)
- Modify: `lib/src/features/pdf_editor/application/editor_session_controller.dart:562-607` (route `glyph_unsupported` through `proposeFontFallback`; on approval, re-apply using `FPDFText_SetFont` with an `FPDFText_LoadFont`-loaded installed font — new worker helper in `live_pdfium_session.dart`)
- Test: `rust/clarix_editing_core/tests/text_layout_contract.rs` (live imports no longer exempt); Dart worker test with a fixture lacking glyph coverage

---

## Phase C — Vibe editing (Phase 4)

### Task C1: Physical-apply handshake for agent tool commits (G10a)

This is the architectural keystone of Phase 4: agent edits must mutate the rendered PDF, not only the Rust model.

**Files:**
- Modify: `rust/clarix_agent_core/src/model.rs` (event kind `ToolCommitPrepared { token, physical_plan }`; status `AwaitingPhysicalApply`)
- Modify: `rust/clarix_agent_core/src/run.rs` (loop: before executing a mutating tool on a live session, prepare the command, emit the event, pause; resume on confirm)
- Modify: `rust/clarix_pdf_oxide/src/agent_api.rs` (FRB methods `confirm_agent_tool_commit(token)` / `abort_agent_tool_commit(token)`; DTO for the plan reusing `NativePhysicalEditPlan`)
- Modify: `lib/src/core/agent/agent_bridge.dart`, `agent_bridge_types.dart` (validate events; expose plans)
- Modify: `lib/src/features/ai/application/agent_run_controller.dart` (on `ToolCommitPrepared`: call the gateway's live port apply; then `confirmAgentToolCommit`; on apply failure: `abortAgentToolCommit` and surface)
- Modify: `lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart` (expose `applyPreparedPhysicalPlan(NativePhysicalEditPlan)` used by both the manual and agent paths)
- Test: `rust/clarix_agent_core/tests/run_engine_contract.rs`, `rust/clarix_pdf_oxide/tests/agent_bridge_contract.rs`, `test/core/agent/agent_bridge_contract_test.dart`, `test/workspace_agent/agent_run_controller_test.dart`

**Contract:** a mutating tool call in a live session never reaches `EditingToolGateway` commit directly; the engine prepares it (revision-checked), pauses at `AwaitingPhysicalApply`, Dart applies through the same `LivePdfiumEditorPort` machinery, and only the confirm publishes. Cancellation or apply failure aborts with no revision advance. Rebase rules unchanged (a failed apply re-runs the proposal flow).

### Task C2: Structural and spatial location tools (G10b)

**Files:**
- Modify: `rust/clarix_editing_core/src/tools.rs` (new `ToolRequest::{ListPageParagraphs, InspectPageRegion}`; observations `ParagraphIndex` and `RegionObjects`)
- Modify: `rust/clarix_editing_core/src/selection_context.rs` (paragraph/region assembly using existing block geometry)
- Modify: `rust/clarix_agent_core/src/tool_registry.rs` (schemas; both read-only → policy `Automatic`)
- Test: `rust/clarix_editing_core/tests/agent_tool_gateway.rs`, `rust/clarix_agent_core/tests/tool_policy_contract.rs`, `rust/clarix_agent_core/tests/phase4_evaluations.rs`

**Schemas:** `list_page_paragraphs { revision, page_number }` returns ordered paragraphs (page region bounds + first-line text + object IDs); `inspect_page_region { revision, page_number, bounds }` returns intersecting text objects with IDs and quoted text. These give the model the vocabulary for "second paragraph", "the title", "top of page 3".

### Task C3: Object insertion and deletion (migration order item 3)

**Files:**
- Modify: `rust/clarix_editing_core/src/command.rs` (`InsertTextObject`, `DeleteObject` commands), `session.rs` (semantic apply), `ports.rs` (physical ops `CreateTextObject`, `RemoveObject`)
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs` (DTOs; regenerate FRB bindings)
- Modify: `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart` (worker helpers: `FPDFPageObj_CreateTextObj` + `FPDFText_SetText` + `FPDFPage_InsertObject`; `FPDFPage_RemoveObject`; post-apply single-page re-inspection and rebind per the 08-27 design step 3)
- Modify: `lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart` (plan variants)
- Test: Rust command/port contracts; Dart `live_pdfium_session_test.dart` insert/delete round-trip incl. undo

### Task C4: Bounded text reflow (migration order item 5) — separate sub-plan

Real "editing in place" for anything longer than a word requires wrapping changed text within its block using font metrics, and multi-object block reconstruction. This is a full plan of its own (metrics from `FPDFText_GetCharWidth`/`FPDFFont_GetGlyphWidth`, line-break algorithm, block geometry update, undo of reflow, RTL). Until then, the honest interim behavior is: keep single-object replacement as-is, surface `text_overflow` (already implemented) for length-changing edits, and let vibe edits be rejected by policy when the target cannot be edited without reflow.

### Task C5: Free-form vibe-edit UX (G10d)

**Files:**
- Modify: `lib/src/features/ai/presentation/selection_ai_toolbar.dart` or a sibling (`document_edit_entry.dart`) — a "Edit the document" entry that starts a run with no selection but with document scope
- Modify: `lib/src/features/ai/presentation/agent_disclosure_dialog.dart` — document-scope disclosure (page range, paragraph count, search index access)
- Modify: `lib/src/features/ai/application/ai_document_context.dart` — document-level context assembly
- Test: `test/workspace_agent/selection_ai_surface_test.dart`, disclosure digest tests

### Task C6: Phase-4 deterministic evaluations and exit gate

**Files:**
- Create: `rust/clarix_agent_core/tests/phase4_evaluations.rs` — table-driven scripted-provider cases: `locate-and-edit` (locate tool → replace → physical confirm), `denied-approval-no-mutation`, `stale-rebase`, `insert-then-undo`, `no-reflow-rejection`, `prompt-injection-policy-unchanged`
- Create: `tool/editing_phase4/run_phase4_checks.ps1` (default gate: cargo fmt/check, editing-core + agent-core tests, oxide no-default-features compile, flutter analyze on `lib/src/features/ai` + `lib/src/features/pdf_editor`, focused Flutter tests)
- Create: `docs/testing/editing-phase4-exit-gate.md`

---

## Phase D — Hardening

### Task D1: Reconcile the architecture documentation and remove dead code

- Rewrite `docs/clarix-windows-editing-platform-architecture.md`: record the live-PDFium architecture (three owners, prepare→apply→publish, tile compositing, save path) as current; move the old non-destructive/overlay master design to an appendix marked superseded.
- Delete dead legacy files and barrel exports after Task B3 (`pdf_text_editor_overlay.dart`, `native_text_editor.dart`, `pdf_native_text_input.dart`, `pdf_native_edit_types.dart` legacy types, `EditorShortcuts`); `rg` for remaining references first.

### Task D2: CI

- Create `.github/workflows/ci.yml`: `cargo fmt --check` + `cargo test` workspace (excluding RAG feature), `flutter analyze`, `flutter test test/pdf_editor test/core/editing test/core/agent test/workspace_agent`, and a weekly binding-generation diff check.

### Task D3: Live-edit performance gates

- Extend the phase-1 benchmark tooling for the live path: keystroke → `FPDFText_SetText`+`GenerateContent` → tile p95 ≤ 16 ms; caret placement p95 ≤ 32 ms; zero page reloads while typing; bounded tile-cache residency. Record in `docs/testing/editing-phase1-results.json` format.

---

## Part 4 — Execution notes

- **Order:** Phase A is the unblocker and must land first — Phases C and D assume its invariants. Within A: A1 → A2 (so remaining failures become visible) → A3/A4/A5/A6 (parallelizable) → A7 gate.
- **Sub-plans:** B3 (viewer unification) and C4 (reflow) each deserve their own `writing-plans` document written at their phase boundary, since they change rendering/layout architecture and need their own performance gates.
- **Regression risk:** every A-task touches the live-edit hot path. Run `flutter test --no-pub test/pdf_editor test/core/editing` and `cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core -p clarix_pdf_oxide` after each task; regenerate FRB bindings in the same commit as any public DTO change (`flutter_rust_bridge_codegen generate --no-build-runner --no-dart-fix --no-web`).
- **Do not:** reintroduce semantic fallback for live text commands, re-raise the live-import font exemption once B5 lands, or declare a phase complete without its exit gate passing on this machine.

## Plan Self-Review

- **Spec coverage:** the user's three asks — identify critical gaps, name architectural errors, scope phased work — map to Part 2 (G1–G10), Part 1 + D1 (the two-document/three-owner split, contradictory master doc, dead overlay stack), and Part 3 (Phases A–D). Every reported symptom ("backspace does nothing", "overlaid text", "caret imprecise") maps to at least one task (A1/A2/A6, B1, B4).
- **Placeholder scan:** Phase A tasks contain complete code, exact files, and exact commands. Phase B–D tasks name exact files, interfaces, and test contracts; B3/C4 are explicitly declared as needing their own detailed sub-plans, which is a scoping decision, not a placeholder.
- **Type consistency:** `physicalApplyRequired` is consistent across `PreparedCommand` (Rust), `NativePreparedLiveCommand` (FRB DTO), and `EditorPreparedLiveCommand` (Dart); `appliedRevision`/`seedRevision`/`acknowledgeRevision` are used identically in A1 and A5; error codes `live_pdfium_binding_missing`, `live_pdfium_revision_conflict`, `live_hydration_failed`, `glyph_unsupported` are defined in A2/A4 and consumed by the banner and save dialog consistently.
