# Live Native PDF Text Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the painted Flutter text substitute with live, genuine PDFium text editing, native paragraph reflow, live undo/redo, and transactional persistence of the already-edited in-memory PDF.

**Architecture:** `PdfEditingSession` and `PdfEditIntentDispatcher` remain the semantic command authority. A per-document `PdfNativeEditCoordinator` projects each accepted block/object state onto the open PDFium document through `PdfiumWorkerExecutor`, returns refreshed native layout geometry, and reloads only affected pages. Flutter retains a nonpainting text-input client plus editor chrome; PDFium is the only glyph renderer.

**Tech Stack:** Flutter/Dart 3.12, pdfrx 2.4.7, pdfium_flutter 0.2.3, Dart FFI, Riverpod, flutter_test.

**Spec:** `docs/superpowers/specs/2026-08-14-live-native-pdf-text-editing-design.md`

## Global Constraints

- Work directly on `main`; do not create or use a Git worktree.
- Existing source PDF bytes remain unchanged until validated Save or Save a Copy replacement.
- PDFium is the only renderer of edited glyphs; Flutter may paint bounds, handles, selection, caret, composition, overflow, and progress only.
- Every FPDF call runs on pdfrx's owning worker through `PdfiumWorkerExecutor`.
- Only supported genuine text objects are editable; OCR, outlined text, Type 3 fonts, shared forms, vertical writing, and unsupported shaping remain read-only.
- Manual UI and autonomous tools share `PdfEditIntentDispatcher`, permission checks, commands, native projection, and undo/redo history.
- Use red-green-refactor for every task and commit each independently.

## File structure

- Create `lib/src/features/workspace/domain/pdf_native_edit_types.dart`: immutable native projection request/result, line, character, selection-geometry, and revision types.
- Create `lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart`: per-document serialized/latest-state projection and page reload orchestration.
- Create `lib/src/features/workspace/presentation/widgets/pdf_native_text_input.dart`: nonpainting `TextInputClient` and focus/IME bridge.
- Modify `lib/src/features/workspace/infrastructure/pdf_text_engine.dart`: replace suppression-only preview contract with typed live projection and live encoding APIs.
- Modify `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`: PDFium block reconstruction, real font metrics, refreshed locators, character geometry, and live encoding.
- Modify `lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart`: explicit unsupported implementations for the expanded interface.
- Modify `lib/src/features/workspace/application/pdf_editing_controller.dart`: dispatch-then-project transaction, live selection, undo/redo, discard, and save orchestration.
- Modify `lib/src/features/workspace/application/workspace_providers.dart`: construct coordinator and save encoded live bytes rather than replaying a draft.
- Modify `lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart`: accept an encoded live-document writer while preserving validation and atomic replacement.
- Modify `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`: remove glyph editor and host only editor chrome/input bridge.
- Delete `lib/src/features/workspace/presentation/widgets/pdf_inline_text_editor.dart` after all imports and geometry tests migrate.
- Add focused tests under `test/workspace_pdf/` for every boundary and preserve the existing round-trip suite.

---

### Task 1: Native projection domain contract

**Files:**
- Create: `lib/src/features/workspace/domain/pdf_native_edit_types.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdf_text_engine.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart`
- Test: `test/workspace_pdf/pdf_native_edit_types_test.dart`

**Interfaces:**
- Consumes: `PdfTextBlock`, `PdfTextBlockLocator`, `PdfTextRange`, `PdfBox`, `PdfTransform`, and `PdfEditingSession`.
- Produces: `PdfNativeBlockState`, `PdfNativeCharacterBox`, `PdfNativeLine`, `PdfNativeProjectionRequest`, `PdfNativeProjectionResult`, and the `PdfLiveDocumentMutator` interface.

- [ ] **Step 1: Write the failing immutable-contract test**

```dart
test('projection result carries refreshed locator and native character boxes', () {
  final result = PdfNativeProjectionResult(
    requestedRevision: 7,
    appliedRevision: 7,
    block: editedBlock(),
    lines: const <PdfNativeLine>[
      PdfNativeLine(range: PdfTextRange(0, 4), bounds: PdfBox(10, 20, 42, 32)),
    ],
    characters: const <PdfNativeCharacterBox>[
      PdfNativeCharacterBox(offset: 0, bounds: PdfBox(10, 20, 18, 32)),
    ],
    affectedPages: const <int>[1],
  );

  expect(result.appliedRevision, 7);
  expect(result.block.text, 'Edit');
  expect(result.characters.single.offset, 0);
  expect(result.affectedPages, const <int>[1]);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_native_edit_types_test.dart`

Expected: compilation fails because `PdfNativeProjectionResult` and related types do not exist.

- [ ] **Step 3: Add the immutable types and engine interface**

```dart
final class PdfNativeProjectionRequest {
  const PdfNativeProjectionRequest({
    required this.documentRevision,
    required this.editRevision,
    required this.block,
  });

  final String documentRevision;
  final int editRevision;
  final PdfTextBlock block;
}

abstract interface class PdfLiveDocumentMutator {
  Future<PdfNativeProjectionResult> projectTextBlock({
    required PdfDocument document,
    required PdfNativeProjectionRequest request,
  });

  Future<Uint8List> encodeLiveDocument({required PdfDocument document});
}
```

Make `PdfTextEngine` implement `PdfLiveDocumentMutator`. Stub methods throw `PdfNativeEditingUnavailableFailure`.

- [ ] **Step 4: Run tests and analyzer**

Run: `flutter test test/workspace_pdf/pdf_native_edit_types_test.dart && flutter analyze`

Expected: test passes and analyzer reports no issues.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/domain/pdf_native_edit_types.dart lib/src/features/workspace/infrastructure/pdf_text_engine.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart test/workspace_pdf/pdf_native_edit_types_test.dart
git commit -m "feat: define live native PDF edit contract"
```

### Task 2: Serialized latest-state native coordinator

**Files:**
- Create: `lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart`
- Test: `test/workspace_pdf/pdf_native_edit_coordinator_test.dart`

**Interfaces:**
- Consumes: `PdfLiveDocumentMutator.projectTextBlock`, `PdfNativeProjectionRequest`, `PdfDocument.reloadPages`.
- Produces: `PdfNativeEditCoordinator.projectBlock`, `latestResult`, `encode`, and `forgetDocument`.

- [ ] **Step 1: Write failing ordering tests with a controlled fake mutator**

```dart
test('skips publication of an obsolete native projection result', () async {
  final mutator = ControlledLiveMutator();
  final coordinator = PdfNativeEditCoordinator(mutator: mutator);
  final first = coordinator.projectBlock(document, request(1, 'a'));
  final second = coordinator.projectBlock(document, request(2, 'ab'));

  mutator.complete(0, result(1, 'a'));
  mutator.complete(1, result(2, 'ab'));

  await Future.wait(<Future<void>>[first, second]);
  expect(coordinator.latestResult(document)!.block.text, 'ab');
  expect(document.reloadedPages, <List<int>>[<int>[1]]);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_native_edit_coordinator_test.dart`

Expected: compilation fails because `PdfNativeEditCoordinator` is absent.

- [ ] **Step 3: Implement per-document serialization and latest publication**

```dart
Future<void> projectBlock(
  PdfDocument document,
  PdfNativeProjectionRequest request,
) {
  _requestedRevision[document] = request.editRevision;
  return _serialized(document, () async {
    final result = await _mutator.projectTextBlock(
      document: document,
      request: request,
    );
    if (_requestedRevision[document] != result.appliedRevision) return;
    _latest[document] = result;
    await document.reloadPages(pageNumbersToReload: result.affectedPages);
  });
}
```

Coalesce identical page reload requests and remove all identity-map state in `forgetDocument`.

- [ ] **Step 4: Run coordinator tests**

Run: `flutter test test/workspace_pdf/pdf_native_edit_coordinator_test.dart`

Expected: ordering, stale-result, reload, encoding, and cleanup tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart test/workspace_pdf/pdf_native_edit_coordinator_test.dart
git commit -m "feat: coordinate live native PDF edits"
```

### Task 3: Project genuine text into the open PDFium document

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Test: `test/workspace_pdf/pdf_live_text_projection_test.dart`
- Test support: `test/support/pdf_text_fixture.dart`

**Interfaces:**
- Consumes: `PdfiumWorkerExecutor.run`, `PdfNativeProjectionRequest`, existing `_replaceFormattedBlock`, `_inspectPage`, and PDFium page-object APIs.
- Produces: `PdfiumTextEngine.projectTextBlock` and `encodeLiveDocument`.

- [ ] **Step 1: Write the failing native acceptance test**

```dart
test('projection changes open native extraction before save but not source bytes', () async {
  final file = await PdfTextFixture.singleBlock('Before');
  final sourceBytes = await file.readAsBytes();
  final document = await PdfDocument.openFile(file.path);
  final engine = const PdfiumTextEngine();
  final revision = await sha256File(file);
  final original = (await engine.inspectPages(
    document: document,
    sourceRevision: revision,
    pageNumbers: const <int>[1],
  )).single;

  final result = await engine.projectTextBlock(
    document: document,
    request: PdfNativeProjectionRequest(
      documentRevision: revision,
      editRevision: 1,
      block: original.copyWith(text: 'After'),
    ),
  );

  expect(result.block.text, 'After');
  expect((await document.pages.first.loadText()).fullText, contains('After'));
  expect(await file.readAsBytes(), sourceBytes);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_live_text_projection_test.dart`

Expected: failure because the live projection method is unimplemented.

- [ ] **Step 3: Implement worker-owned projection**

Add a top-level worker callback receiving only sendable data. Resolve the original paths, replace/rebuild the objects, call `FPDFPage_GenerateContent`, re-inspect the block, and return refreshed native geometry.

```dart
@override
Future<PdfNativeProjectionResult> projectTextBlock({
  required PdfDocument document,
  required PdfNativeProjectionRequest request,
}) => const PdfiumWorkerExecutor().run(
  document: document,
  callback: _projectTextBlockOnWorker,
  message: request,
);

@override
Future<Uint8List> encodeLiveDocument({required PdfDocument document}) =>
    document.encodePdf(incremental: false);
```

Do not call `applyDraft`; the request's complete block state is materialized exactly once.

- [ ] **Step 4: Run native projection and isolate tests**

Run: `flutter test test/workspace_pdf/pdf_live_text_projection_test.dart test/workspace_pdf/pdfium_worker_executor_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart`

Expected: live extraction changes, source bytes stay identical, worker ownership and saved genuine-text tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart test/workspace_pdf/pdf_live_text_projection_test.dart test/support/pdf_text_fixture.dart
git commit -m "feat: project live edits into genuine PDF text"
```

### Task 4: Dispatch-then-project controller transaction

**Files:**
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Test: `test/workspace_pdf/pdf_live_edit_controller_test.dart`

**Interfaces:**
- Consumes: `PdfEditIntentDispatcher.dispatch`, `PdfNativeEditCoordinator.projectBlock`, the resulting `PdfEditingSession`.
- Produces: `PdfEditingController.dispatchAndProject`, live `undo`, live `redo`, and document registration cleanup.

- [ ] **Step 1: Write failing controller transaction tests**

```dart
test('accepted replacement is projected before dispatch completes', () async {
  final coordinator = RecordingNativeCoordinator();
  final controller = controllerWithSession(coordinator: coordinator);

  final result = await controller.dispatchAndProject(
    tabId: 'tab',
    intent: replacementIntent('Before', 'After'),
    provenance: PdfCommandProvenance.manual,
  );

  expect(result.isSuccess, isTrue);
  expect(coordinator.requests.single.block.text, 'After');
  expect(controller.sessionFor('tab').blocks.single.text, 'After');
});
```

Add cases proving a native failure restores the prior session and undo/redo project complete before/after states.

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_live_edit_controller_test.dart`

Expected: compilation fails because `dispatchAndProject` is absent.

- [ ] **Step 3: Implement the transactional controller path**

```dart
Future<PdfEditResult> dispatchAndProject({
  required String tabId,
  required PdfEditIntent intent,
  required PdfCommandProvenance provenance,
}) async {
  final before = sessionFor(tabId);
  final result = await _dispatcher.dispatch(intent, provenance: provenance);
  if (!result.isSuccess || result.affectedLocators.isEmpty) return result;
  try {
    await _projectAffected(tabId, sessionFor(tabId), result.affectedLocators);
    return result;
  } catch (_) {
    replaceSession(tabId, before);
    rethrow;
  }
}
```

Route text replace/format/resize/move/rotate, undo, redo, and agent dispatch calls through this path. Selection and mode changes remain non-content operations.

- [ ] **Step 4: Run controller, dispatcher, and command tests**

Run: `flutter test test/workspace_pdf/pdf_live_edit_controller_test.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart test/workspace_pdf/pdf_edit_session_test.dart`

Expected: transaction rollback and live ordering tests pass with existing history behavior unchanged.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/application/workspace_providers.dart test/workspace_pdf/pdf_live_edit_controller_test.dart
git commit -m "feat: project PDF commands into the live document"
```

### Task 5: Remove the painted text layer and retain IME input

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/pdf_native_text_input.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Delete: `lib/src/features/workspace/presentation/widgets/pdf_inline_text_editor.dart`
- Replace test: `test/workspace_pdf/pdf_text_editor_overlay_test.dart`
- Delete obsolete test: `test/workspace_pdf/pdf_inline_text_geometry_test.dart`

**Interfaces:**
- Consumes: selected `PdfTextBlock`, `PdfTextSelection`, and `ReplacePdfTextIntent` callback.
- Produces: `PdfNativeTextInput` implementing `TextInputClient` without a glyph-rendering widget.

- [ ] **Step 1: Write the failing no-glyph-layer widget test**

```dart
testWidgets('selected block has an input client but paints no editable text', (tester) async {
  await tester.pumpWidget(editorHarness(selected: true));

  expect(find.byType(EditableText), findsNothing);
  expect(find.byType(TextField), findsNothing);
  expect(find.byKey(const Key('pdf-native-text-input')), findsOneWidget);
  expect(find.byKey(const Key('pdf-text-block-outline')), findsOneWidget);
});
```

Add a test that `updateEditingValue` dispatches the exact `PdfTextDelta` and that reading mode removes the input client and chrome.

- [ ] **Step 2: Run the widget test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_text_editor_overlay_test.dart`

Expected: fails because `EditableText` is still present for a selected block.

- [ ] **Step 3: Implement a nonpainting `TextInputClient`**

```dart
final class PdfNativeTextInputState extends State<PdfNativeTextInput>
    implements TextInputClient {
  TextInputConnection? _connection;
  late TextEditingValue _value;

  @override
  void updateEditingValue(TextEditingValue value) {
    final delta = PdfTextDelta.between(_value.text, value.text);
    _value = value;
    widget.onDelta(delta, value.selection, value.composing);
  }

  @override
  Widget build(BuildContext context) => const SizedBox(
    key: Key('pdf-native-text-input'),
    width: 1,
    height: 1,
  );
}
```

Implement all required `TextInputClient` members, attach with `TextInput.attach`, keep the connection synchronized with native selection, and close it on focus loss/dispose. The widget must contain no `Text`, `RichText`, `EditableText`, `TextField`, or `CustomPainter` that draws glyphs.

- [ ] **Step 4: Run overlay, shortcut, and analyzer checks**

Run: `flutter test test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_edit_shortcuts_test.dart && flutter analyze`

Expected: selected editing has no glyph widget, input/shortcuts work, and deleted imports are gone.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/presentation/widgets/pdf_native_text_input.dart lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_edit_shortcuts_test.dart
git rm lib/src/features/workspace/presentation/widgets/pdf_inline_text_editor.dart test/workspace_pdf/pdf_inline_text_geometry_test.dart
git commit -m "feat: edit native PDF text without painted glyph overlay"
```

### Task 6: Native character geometry, caret, and selection

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_native_text_input.dart`
- Test: `test/workspace_pdf/pdf_native_character_geometry_test.dart`
- Test: `test/workspace_pdf/pdf_text_selection_overlay_test.dart`

**Interfaces:**
- Consumes: `FPDFText_CountChars`, `FPDFText_GetCharBox`, refreshed `PdfNativeProjectionResult.characters`.
- Produces: `PdfNativeTextGeometry.caretForOffset`, `rangeQuads`, and pointer-to-offset hit testing.

- [ ] **Step 1: Write failing native geometry and widget tests**

```dart
test('native character boxes map every UTF-16 offset in edited text', () async {
  final result = await projectFixture('AB CD');
  expect(result.characters.map((box) => box.offset), <int>[0, 1, 2, 3, 4]);
  expect(result.characters.every((box) => box.bounds.width >= 0), isTrue);
});

testWidgets('caret and selection paint from native boxes only', (tester) async {
  await tester.pumpWidget(selectionHarness(range: const PdfTextRange(1, 3)));
  expect(find.byKey(const Key('pdf-native-caret')), findsOneWidget);
  expect(find.byKey(const Key('pdf-native-selection')), findsWidgets);
  expect(find.byType(EditableText), findsNothing);
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_native_character_geometry_test.dart test/workspace_pdf/pdf_text_selection_overlay_test.dart`

Expected: projection returns no character boxes and no caret/selection widgets exist.

- [ ] **Step 3: Extract native boxes and paint only chrome**

After content generation, load an FPDF text page, identify the rebuilt block's character range, call `FPDFText_GetCharBox`, and return page-space boxes. Add pure helpers:

```dart
int offsetNearest(Offset point, List<PdfNativeCharacterBox> boxes);
PdfBox caretForOffset(int offset, List<PdfNativeCharacterBox> boxes);
List<PdfBox> boxesForRange(PdfTextRange range, List<PdfNativeCharacterBox> boxes);
```

Map these boxes through pdfrx's page rectangle conversion and paint translucent rectangles/caret containers only.

- [ ] **Step 4: Run geometry, overlay, zoom, and analyzer tests**

Run: `flutter test test/workspace_pdf/pdf_native_character_geometry_test.dart test/workspace_pdf/pdf_text_selection_overlay_test.dart test/workspace_pdf/pdf_text_editor_overlay_test.dart && flutter analyze`

Expected: hit testing, caret, selection, and no-glyph assertions pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/presentation/widgets/pdf_native_text_input.dart test/workspace_pdf/pdf_native_character_geometry_test.dart test/workspace_pdf/pdf_text_selection_overlay_test.dart
git commit -m "feat: drive PDF caret and selection from native geometry"
```

### Task 7: Native-font paragraph layout and resize reflow

**Files:**
- Create: `lib/src/features/workspace/infrastructure/pdf_native_text_layout.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Modify: `lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart`
- Test: `test/workspace_pdf/pdf_native_text_layout_test.dart`
- Test: `test/workspace_pdf/pdf_live_resize_reflow_test.dart`

**Interfaces:**
- Consumes: actual FPDF font glyph widths/ascent/descent, `PdfTextStyle`, block bounds, and styled runs.
- Produces: `PdfNativeTextLayoutEngine.layout` returning `PdfNativeTextLayout` with lines, positioned runs, character boxes, and overflow.

- [ ] **Step 1: Write failing line-break and resize tests**

```dart
test('narrower bounds create more native lines without changing font size', () async {
  final before = await projectFixture('one two three four');
  final resized = before.block.copyWith(
    bounds: PdfBox(before.block.bounds.left, before.block.bounds.bottom,
        before.block.bounds.left + before.block.bounds.width / 2, before.block.bounds.top),
  );
  final after = await projectBlock(resized, revision: 2);

  expect(after.lines.length, greaterThan(before.lines.length));
  expect(after.block.runs.first.style.fontSize,
      before.block.runs.first.style.fontSize);
  expect(await extractLiveText(), contains('one two three four'));
});
```

Add unit cases for spaces, explicit newlines, alignment, multiple runs, RTL eligibility, and vertical/unsupported rejection.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_native_text_layout_test.dart test/workspace_pdf/pdf_live_resize_reflow_test.dart`

Expected: current monospace approximation yields incorrect line counts/metrics or projection does not reflow live.

- [ ] **Step 3: Implement actual-font layout and remove monospace overflow logic**

Introduce a `PdfNativeFontMetrics` callback supplied by the worker using `FPDFFont_GetGlyphWidth` and source character positions. Use greedy word wrapping with character fallback for overlong tokens, preserve explicit newlines, and compute baseline advancement from native ascent/descent plus line spacing.

```dart
PdfNativeTextLayout layout({
  required String text,
  required List<PdfTextRun> runs,
  required PdfBox bounds,
  required PdfNativeFontMetrics metrics,
  required PdfWritingDirection direction,
});
```

Replace `_reflow`'s `PdfMonospaceTextMetrics` overflow decision with the projection result's native `overflow` value.

- [ ] **Step 4: Run layout, geometry, resize, and round-trip tests**

Run: `flutter test test/workspace_pdf/pdf_native_text_layout_test.dart test/workspace_pdf/pdf_live_resize_reflow_test.dart test/workspace_pdf/pdf_text_geometry_edit_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart`

Expected: native line count, unchanged size, logical extraction, command geometry, and saved reflow pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdf_native_text_layout.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart test/workspace_pdf/pdf_native_text_layout_test.dart test/workspace_pdf/pdf_live_resize_reflow_test.dart
git commit -m "feat: reflow PDF paragraphs with native font metrics"
```

### Task 8: Live move, rotation, undo, redo, and discard

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `lib/src/features/workspace/domain/pdf_edit_session.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Test: `test/workspace_pdf/pdf_live_history_test.dart`
- Test: `test/workspace_pdf/pdf_text_geometry_edit_test.dart`

**Interfaces:**
- Consumes: complete before/after `PdfTextBlock` and `PdfPageObject` states from commands.
- Produces: `PdfEditingSession.atCursor`, native-consistent `undo`, `redo`, `discardChanges`, and gesture completion behavior.

- [ ] **Step 1: Write failing live history tests**

```dart
test('undo and redo immediately change open native extraction', () async {
  await controller.dispatchAndProject(
    tabId: 'tab',
    intent: replacementIntent('Before', 'After'),
    provenance: PdfCommandProvenance.manual,
  );
  expect(await extract(document), contains('After'));

  await controller.undo('tab', document: document);
  expect(await extract(document), contains('Before'));

  await controller.redo('tab', document: document);
  expect(await extract(document), contains('After'));
});
```

Add transform matrix and discard-to-checkpoint cases.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_live_history_test.dart test/workspace_pdf/pdf_text_geometry_edit_test.dart`

Expected: current preview rebuild handles transforms only and text extraction does not follow undo/redo.

- [ ] **Step 3: Project complete history states**

Replace suppression restoration with `projectSessionDifference(before, after)`. Add:

```dart
PdfEditingSession atCursor(int target) {
  RangeError.checkValueInInterval(target, 0, commands.length, 'target');
  var result = this;
  while (result.cursor > target) result = result.undo();
  while (result.cursor < target) result = result.redo();
  return result;
}

Future<void> discardChanges(String tabId, PdfDocument document) async {
  final session = sessionFor(tabId);
  final checkpoint = session.atCursor(session.savedCursor);
  await _projectChangedBlocks(document, session, checkpoint);
  replaceSession(tabId, checkpoint.withSelection(null));
}
```

Gesture updates remain latest-state native previews; pointer-up dispatches one command. Escape cancels the active gesture state, not accepted typing history.

- [ ] **Step 4: Run history, object transform, and overlay tests**

Run: `flutter test test/workspace_pdf/pdf_live_history_test.dart test/workspace_pdf/pdf_text_geometry_edit_test.dart test/workspace_pdf/pdf_object_transform_overlay_test.dart test/workspace_pdf/pdf_object_transform_round_trip_test.dart`

Expected: extraction and matrices follow undo/redo/discard and gestures retain one command.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/domain/pdf_edit_session.dart lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart test/workspace_pdf/pdf_live_history_test.dart test/workspace_pdf/pdf_text_geometry_edit_test.dart
git commit -m "feat: apply PDF history to the live native document"
```

### Task 9: Save the current live native document transactionally

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdf_text_engine.dart`
- Test: `test/workspace_pdf/pdf_live_edit_save_test.dart`
- Test: `test/workspace_pdf/pdf_edit_save_service_test.dart`

**Interfaces:**
- Consumes: `PdfNativeEditCoordinator.encode(document)` and existing validator/replacer.
- Produces: `PdfLiveDocumentEncoder`, validated atomic save, refreshed source revision, and rebased editing session.

- [ ] **Step 1: Write failing save-source tests**

```dart
test('save writes encoded live bytes and never reapplies draft commands', () async {
  var encodeCalls = 0;
  final service = PdfEditSaveService(
    validate: validateEditedText,
    replace: replaceForTest,
  );

  await service.save(PdfSaveRequest(
    path: source.path,
    sourceRevision: await sha256File(source),
    encode: () async {
      encodeCalls++;
      return validEditedPdfBytes;
    },
  ));

  expect(encodeCalls, 1);
  expect(await extractFromFile(source), contains('After'));
});
```

Add source-conflict, validator-failure, replacement-access-denied, and undo-after-save cases.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_live_edit_save_test.dart test/workspace_pdf/pdf_edit_save_service_test.dart`

Expected: constructor/API mismatch because save still copies source and replays `applyDraft`.

- [ ] **Step 3: Replace draft replay with live encoding**

```dart
typedef PdfLiveDocumentEncoder = Future<Uint8List> Function();

final class PdfSaveRequest {
  const PdfSaveRequest({
    required this.path,
    required this.sourceRevision,
    required this.encode,
  });

  final String path;
  final String sourceRevision;
  final PdfLiveDocumentEncoder encode;
}
```

After verifying the source revision, the service awaits `request.encode()`, writes those bytes to the sibling working file, validates, and atomically replaces. The controller supplies `encode: () => coordinator.encode(document)` for the registered open document. Keep reopen validation and recovery messages. After success reload/reinspect affected pages and mark the current cursor saved.

- [ ] **Step 4: Run save, conflict, round-trip, and analyzer tests**

Run: `flutter test test/workspace_pdf/pdf_live_edit_save_test.dart test/workspace_pdf/pdf_edit_save_service_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart test/workspace_pdf/pdf_edit_conflict_dialog_test.dart && flutter analyze`

Expected: live bytes persist once, failures preserve source, and reopened extraction is genuine.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/application/workspace_providers.dart lib/src/features/workspace/infrastructure/pdf_text_engine.dart test/workspace_pdf/pdf_live_edit_save_test.dart test/workspace_pdf/pdf_edit_save_service_test.dart
git commit -m "feat: save the live native PDF document"
```

### Task 10: Agent parity, permissions, compatibility, and performance qualification

**Files:**
- Modify: `lib/src/features/workspace/application/ai_tool_registry.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart`
- Modify: `test/workspace_pdf/pdf_text_performance_test.dart`
- Modify: `test/workspace_pdf/pdf_text_compatibility_test.dart`
- Create: `test/workspace_pdf/pdf_live_edit_acceptance_test.dart`

**Interfaces:**
- Consumes: the completed shared dispatch/native projection/save boundary.
- Produces: agent results that observe live unsaved revisions, permission-safe native projection, and release acceptance evidence.

- [ ] **Step 1: Write failing parity and acceptance tests**

```dart
test('agent replacement returns only after live extraction changes', () async {
  final response = await tools.call('replace_pdf_text', replacementArguments);
  expect(response['status'], 'ok');
  expect(await extract(openDocument), contains('Agent edit'));
  expect(editing.sessionFor('tab').commands.last.provenance,
      PdfCommandProvenance.agent);
});

testWidgets('edit mode renders one PDF glyph layer and editor chrome', (tester) async {
  await tester.pumpWidget(realViewerHarness(fixture));
  await enterModeSelectAndType(tester, ' extra');
  expect(find.byType(EditableText), findsNothing);
  expect(find.byKey(const Key('pdf-text-block-outline')), findsOneWidget);
  expect(await extract(openDocument), contains(' extra'));
});
```

Add permission-denied/no-native-mutation, rapid latest-state, 10k-character/no-encode, font fallback, rotated block, unsupported-read-only, and source-byte-before-save cases.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_live_edit_acceptance_test.dart test/workspace_pdf/pdf_text_performance_test.dart test/workspace_pdf/pdf_text_compatibility_test.dart`

Expected: agent dispatch currently bypasses or returns before live projection and acceptance assertions fail.

- [ ] **Step 3: Route agent tools through controller projection and finish qualification behavior**

Have `AiToolRegistry` call `dispatchAndProject` for every PDF content mutation. Preserve inspection schemas, deterministic risk classification, persistent grant scopes, document/revision validation, and structured failures. Return `nativeRevision`, refreshed locators, dirty state, warning list, and undo command IDs only after projection completion.

Enforce read-only capability checks before native queueing and expose the exact reason in UI/tool results.

- [ ] **Step 4: Run the full verification matrix**

Run:

```powershell
flutter analyze
flutter test test/workspace_pdf --reporter compact
cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml
cargo clippy --manifest-path rust/clarix_pdf_oxide/Cargo.toml --all-targets -- -D warnings
git diff --check
```

Expected: analyzer clean; all workspace PDF tests pass; Rust tests and clippy pass from `rust/clarix_pdf_oxide/Cargo.toml`; diff check prints nothing.

Manually run the Windows app against the representative organisational-design PDF and verify: no second text layer on selection, typing changes the PDFium-rendered page, resize reflows within the block, move/rotation follow handles, undo/redo are live, source bytes change only on Save, and reopened text is selectable/searchable.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/application/ai_tool_registry.dart lib/src/features/workspace/application/pdf_editing_controller.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart test/workspace_pdf/pdf_text_performance_test.dart test/workspace_pdf/pdf_text_compatibility_test.dart test/workspace_pdf/pdf_live_edit_acceptance_test.dart
git commit -m "test: qualify live native PDF text editing"
```

## Final completion gate

- [ ] Confirm `git status --short` contains no unintended changes.
- [ ] Confirm every implementation task has its own commit on `main`.
- [ ] Re-run the full Task 10 verification matrix from a fresh shell.
- [ ] Report any pre-existing unrelated failures separately with exact commands and output.
- [ ] Provide the Windows build command: `flutter build windows --release`.
