# PDF Text Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Acrobat-style editing of existing genuine PDF text, including inline replacement, formatting, block geometry, unified undo/redo, validated saving, and permission-controlled agent tools.

**Architecture:** Keep a pure-Dart immutable editing domain and make `PdfEditIntentDispatcher` the only mutation boundary for the UI and agents. Use the PDFium instance already owned by `pdfrx` through `PdfDocument.useNativeDocumentHandle`, render unsaved drafts in page overlays, and apply the final draft to a clean sibling copy before validated atomic replacement and viewer/index reload.

**Tech Stack:** Flutter/Dart, Riverpod 3.3.2, pdfrx 2.4.7, pdfium_flutter 0.2.3, pdfium_dart 0.2.5 bindings, ffi 2.2.0, SharedPreferences, flutter_test, Windows-first desktop filesystem behavior.

**Spec:** `docs/superpowers/specs/2026-08-13-pdf-text-editing-design.md`

## Global Constraints

- Saved edits must remain genuine selectable, searchable, and extractable PDF text objects; rasterized text, annotations, appearance-only overlays, and invisible search layers are invalid implementations.
- First release edits only existing genuine page text objects. OCR, vector-outline text, Type 3 fonts, linked cross-page boxes, and document-wide reflow remain out of scope.
- Manual actions and agent tools must dispatch the same typed intents through one dispatcher and one chronological command history.
- Text reflows only inside the active block, never pushes unrelated objects, never crosses pages, and never silently shrinks the font.
- Overflow blocks Save until the user changes the text, block size, or formatting.
- Preserve the original font when it can encode the replacement. Show any closest-installed-font substitution before Save and embed it only when embedding permissions permit.
- Work from a clean source revision, save non-incrementally to a sibling working file, validate it, and atomically replace the source. Failure must leave the source byte-for-byte unchanged and the session dirty.
- Continue serving the viewer from memory-backed bytes so Clarix does not hold the source path open on Windows.
- Edit-mode geometry is visible only in text-editing mode; reading mode retains normal selection, search, navigation, and annotation behavior.
- Use `package:pdfium_flutter/pdfium_flutter.dart` only behind the native-engine adapter. Presentation and domain files must not import PDFium bindings.
- Generated flutter_rust_bridge files are not edited for this feature; annotation persistence continues through the existing Rust bridge until it can be migrated behind the shared save transaction.

---

## File Structure

Create focused files instead of expanding `document_workspace.dart` or `workspace_notifier.dart` further:

- `lib/src/features/workspace/domain/pdf_text_types.dart` — immutable PDF geometry, locators, styled runs, blocks, selections, and typed errors.
- `lib/src/features/workspace/domain/pdf_edit_intent.dart` — sealed UI/agent intent contract and structured results.
- `lib/src/features/workspace/domain/pdf_edit_command.dart` — reversible command variants and command provenance.
- `lib/src/features/workspace/domain/pdf_edit_session.dart` — immutable document draft, chronological history, saved checkpoint, and typing coalescing.
- `lib/src/features/workspace/domain/pdf_text_case.dart` — deterministic replacement-case detection and transformation.
- `lib/src/features/workspace/domain/pdf_text_layout.dart` — fixed-boundary paragraph layout and overflow results using supplied font metrics.
- `lib/src/features/workspace/infrastructure/pdf_text_engine.dart` — platform-neutral engine contract and conditional factory.
- `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart` — PDFium object discovery, locator resolution, mutation, page regeneration, and encoding.
- `lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart` — typed unsupported result for web or a missing native backend.
- `lib/src/features/workspace/infrastructure/pdf_text_block_grouper.dart` — deterministic paragraph grouping independent of FFI.
- `lib/src/features/workspace/infrastructure/installed_font_catalog.dart` — installed-font discovery, compatibility scoring, and embedding-rights checks.
- `lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart` — source revision checks, working-copy lifecycle, validation, replacement, and save results.
- `lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart` — validation, permissions, command creation, and structured dispatch results.
- `lib/src/features/workspace/application/pdf_editing_controller.dart` — per-tab session ownership, visible-page discovery, save/reload coordination, and Riverpod-facing notifications.
- `lib/src/features/workspace/application/action_permission_service.dart` — agent edit policy, risk classification, scoped grants, and persisted workspace rules.
- `lib/src/features/workspace/application/ai_tool_registry.dart` — tool schemas and argument decoding into edit intents.
- `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart` — page-coordinate outlines, caret editor, selection, drag, resize, and overflow visuals.
- `lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart` — selection-aware format controls and substitution warnings.
- `test/support/pdf_text_fixture.dart` — small PDFs containing known native text objects and unsupported-object fixtures.

Existing integration points remain thin: `workspace_providers.dart` wires dependencies, `workspace_notifier.dart` delegates mutation and persistence, `document_workspace.dart` hosts page overlays, `workspace_body.dart` selects the Text Format panel, `workspace_screen.dart` routes Save/Undo/Redo, and `ai_agent_runtime.dart` delegates tools to the registry.

---

### Task 1: Establish the immutable PDF text domain

**Files:**
- Create: `lib/src/features/workspace/domain/pdf_text_types.dart`
- Create: `lib/src/features/workspace/domain/pdf_edit_intent.dart`
- Create: `lib/src/features/workspace/domain/pdf_edit_command.dart`
- Modify: `lib/src/features/workspace/domain/pdf_edit_session.dart`
- Modify: `test/workspace_pdf/pdf_edit_session_test.dart`
- Create: `test/workspace_pdf/pdf_edit_intent_test.dart`

**Interfaces:**
- Consumes: Existing `DocumentBookmark` and `DocumentAnnotation` values from `lib/src/core/models.dart` while migrating their history.
- Produces: `PdfBox`, `PdfTransform`, `PdfTextRange`, `PdfWritingDirection`, `PdfReadOnlyReason`, `PdfTextObjectSnapshot`, `PdfTextBlockLocator`, `PdfTextStyle`, `PdfTextRun`, `PdfTextBlock`, `PdfTextSelection`, `PdfEditingMode`, sealed `PdfEditIntent`, sealed `PdfEditCommand`, `PdfEditResult`, and `PdfEditingSession.applyCommand/undo/redo/markSaved`.

- [ ] **Step 1: Write failing value and history tests**

```dart
test('saved checkpoint survives undo and redo', () {
  final block = editableBlock(text: 'Revenue');
  final session = PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
      .withBlocks([block])
      .applyCommand(ReplacePdfTextCommand(
        id: 'c1',
        provenance: PdfCommandProvenance.manual,
        locator: block.locator,
        before: 'Revenue',
        after: 'Net revenue',
        range: const PdfTextRange(0, 7),
      ))
      .markSaved();

  expect(session.isDirty, isFalse);
  expect(session.undo().isDirty, isTrue);
  expect(session.undo().redo().isDirty, isFalse);
});

test('a new command after undo clears redo across command kinds', () {
  final session = sessionWithOneBlock()
      .applyCommand(replaceCommand('c1', 'A', 'B'))
      .applyCommand(formatCommand('c2', fontSize: 14))
      .undo()
      .applyCommand(resizeCommand('c3', width: 220));

  expect(session.canRedo, isFalse);
  expect(session.commands.map((c) => c.id), ['c1', 'c3']);
});
```

- [ ] **Step 2: Run the focused domain tests and confirm the missing types fail**

Run: `flutter test test/workspace_pdf/pdf_edit_session_test.dart test/workspace_pdf/pdf_edit_intent_test.dart`

Expected: FAIL with undefined `PdfEditingSession`, locator, intent, and command types.

- [ ] **Step 3: Define serialization-safe values and typed failures**

```dart
enum PdfEditingMode { reading, text }
enum PdfCommandProvenance { manual, agent }
enum PdfTextAlignment { left, center, right, justify }
enum PdfTextCapability { replace, format, move, resize }
enum PdfWritingDirection { leftToRight, rightToLeft, vertical }
enum PdfReadOnlyReason { imageOnly, type3Font, vectorOutline, sharedFormObject, complexRendering, encrypted }

final class PdfTextRange {
  const PdfTextRange(this.start, this.end);
  final int start, end;
  bool get isEmpty => start == end;
}

final class PdfBox {
  const PdfBox(this.left, this.bottom, this.right, this.top);
  final double left, bottom, right, top;
  double get width => right - left;
  double get height => top - bottom;
}

final class PdfTextBlockLocator {
  const PdfTextBlockLocator({
    required this.pageNumber,
    required this.objectPath,
    required this.textDigest,
    required this.geometryDigest,
    required this.fontFingerprint,
    required this.sourceRevision,
  });
  final int pageNumber;
  final List<int> objectPath;
  final String textDigest, geometryDigest, fontFingerprint, sourceRevision;
}

final class PdfTextObjectSnapshot {
  const PdfTextObjectSnapshot({
    required this.objectPath,
    required this.text,
    required this.bounds,
    required this.transform,
    required this.style,
    required this.baseline,
    required this.writingDirection,
  });
  final List<int> objectPath;
  final String text;
  final PdfBox bounds;
  final PdfTransform transform;
  final PdfTextStyle style;
  final double baseline;
  final PdfWritingDirection writingDirection;
}

sealed class PdfEditFailure implements Exception {
  const PdfEditFailure(this.code, this.message);
  final String code;
  final String message;
}
```

Make every domain collection unmodifiable, implement value equality without Flutter dependencies, use UTF-16 offsets consistently, and include explicit read-only reasons on `PdfTextBlock`.

- [ ] **Step 4: Implement reversible commands and checkpoint history**

```dart
final class PdfEditingSession {
  const PdfEditingSession._({
    required this.documentId,
    required this.sourceRevision,
    required this.mode,
    required this.blocks,
    required this.commands,
    required this.cursor,
    required this.savedCursor,
    required this.selection,
    required this.caseMatching,
  });

  PdfEditingSession applyCommand(PdfEditCommand command) {
    final kept = commands.take(cursor).toList(growable: true)..add(command);
    return _copy(commands: kept, cursor: kept.length, blocks: command.apply(blocks));
  }

  PdfEditingSession undo() => cursor == 0
      ? this
      : _copy(cursor: cursor - 1, blocks: commands[cursor - 1].revert(blocks));

  PdfEditingSession redo() => cursor == commands.length
      ? this
      : _copy(cursor: cursor + 1, blocks: commands[cursor].apply(blocks));

  PdfEditingSession markSaved() => _copy(savedCursor: cursor);
  bool get isDirty => cursor != savedCursor;
}
```

Add explicit command variants for text replacement, range formatting, movement, resizing, bookmark changes, highlight changes, and compound commands. A compound command applies children in order and reverts them in reverse order.

- [ ] **Step 5: Run tests and static analysis**

Run: `dart format lib/src/features/workspace/domain test/workspace_pdf/pdf_edit_session_test.dart test/workspace_pdf/pdf_edit_intent_test.dart`

Run: `flutter test test/workspace_pdf/pdf_edit_session_test.dart test/workspace_pdf/pdf_edit_intent_test.dart`

Run: `flutter analyze lib/src/features/workspace/domain test/workspace_pdf`

Expected: all commands exit 0.

- [ ] **Step 6: Commit the domain boundary**

```text
git add lib/src/features/workspace/domain/pdf_text_types.dart lib/src/features/workspace/domain/pdf_edit_intent.dart lib/src/features/workspace/domain/pdf_edit_command.dart lib/src/features/workspace/domain/pdf_edit_session.dart test/workspace_pdf/pdf_edit_session_test.dart test/workspace_pdf/pdf_edit_intent_test.dart
git commit -m "feat: define PDF text editing domain"
```

### Task 2: Add deterministic casing, grouping, and fixed-box layout

**Files:**
- Create: `lib/src/features/workspace/domain/pdf_text_case.dart`
- Create: `lib/src/features/workspace/domain/pdf_text_layout.dart`
- Create: `lib/src/features/workspace/infrastructure/pdf_text_block_grouper.dart`
- Create: `test/workspace_pdf/pdf_text_case_test.dart`
- Create: `test/workspace_pdf/pdf_text_layout_test.dart`
- Create: `test/workspace_pdf/pdf_text_block_grouper_test.dart`

**Interfaces:**
- Consumes: `PdfBox`, `PdfTransform`, `PdfTextStyle`, `PdfTextRun`, and raw `PdfTextObjectSnapshot` values from Task 1.
- Produces: `PdfReplacementCase.detect/apply`, `PdfTextLayoutEngine.layout`, `PdfTextLayoutResult`, and `PdfTextBlockGrouper.group`.

- [ ] **Step 1: Write failing casing tests**

```dart
for (final sample in <(String, String, String)>[
  ('TOTAL REVENUE', 'net income', 'NET INCOME'),
  ('total revenue', 'Net Income', 'net income'),
  ('Total Revenue', 'net income', 'Net Income'),
  ('Total revenue', 'net income', 'Net income'),
  ('iPhone Revenue', 'net income', 'net income'),
]) {
  test('matches ${sample.$1}', () {
    expect(matchReplacementCase(sample.$1, sample.$2), sample.$3);
  });
}
```

- [ ] **Step 2: Write failing grouping and overflow tests**

```dart
test('groups adjacent same-direction lines deterministically', () {
  final first = rawTextObject(path: [2], text: 'Quarterly', baseline: 700);
  final second = rawTextObject(path: [3], text: 'Revenue', baseline: 684);
  final groups = const PdfTextBlockGrouper().group([second, first]);
  expect(groups.single.objectPaths, [[2], [3]]);
});

test('reports overflow without reducing font size', () {
  final result = const PdfTextLayoutEngine().layout(
    text: 'A long replacement that cannot fit',
    bounds: const PdfBox(0, 0, 60, 12),
    style: testStyle(fontSize: 12),
    metrics: monospaceMetrics(advance: 6, lineHeight: 12),
  );
  expect(result.overflow, isTrue);
  expect(result.effectiveStyle.fontSize, 12);
});
```

- [ ] **Step 3: Run the tests and verify the missing algorithms fail**

Run: `flutter test test/workspace_pdf/pdf_text_case_test.dart test/workspace_pdf/pdf_text_layout_test.dart test/workspace_pdf/pdf_text_block_grouper_test.dart`

Expected: FAIL with missing matcher, layout engine, and grouper.

- [ ] **Step 4: Implement casing and deterministic grouping**

```dart
String matchReplacementCase(String source, String replacement) {
  return switch (PdfReplacementCase.detect(source)) {
    PdfReplacementCase.upper => replacement.toUpperCase(),
    PdfReplacementCase.lower => replacement.toLowerCase(),
    PdfReplacementCase.title => toTitleCase(replacement),
    PdfReplacementCase.sentence => toSentenceCase(replacement),
    PdfReplacementCase.mixed => replacement,
  };
}
```

Sort raw objects by page, writing direction, descending PDF baseline, and left edge before grouping. Use fixed tolerances expressed relative to median font size, preserve object paths in source order, and hash the ordered locator inputs so identical bytes always produce identical groups.

- [ ] **Step 5: Implement fixed-boundary layout**

```dart
final class PdfTextLayoutResult {
  const PdfTextLayoutResult({
    required this.lines,
    required this.usedBounds,
    required this.overflow,
    required this.effectiveStyle,
  });
  final List<PdfLaidOutLine> lines;
  final PdfBox usedBounds;
  final bool overflow;
  final PdfTextStyle effectiveStyle;
}
```

Break at explicit newlines and Unicode whitespace, fall back to character boundaries for a single overlong token, preserve alignment/spacing/scaling, and set `overflow` when laid-out height exceeds the fixed block. Do not modify neighboring block geometry.

- [ ] **Step 6: Run and commit the pure algorithms**

Run: `dart format lib/src/features/workspace/domain/pdf_text_case.dart lib/src/features/workspace/domain/pdf_text_layout.dart lib/src/features/workspace/infrastructure/pdf_text_block_grouper.dart test/workspace_pdf/pdf_text_case_test.dart test/workspace_pdf/pdf_text_layout_test.dart test/workspace_pdf/pdf_text_block_grouper_test.dart`

Run: `flutter test test/workspace_pdf/pdf_text_case_test.dart test/workspace_pdf/pdf_text_layout_test.dart test/workspace_pdf/pdf_text_block_grouper_test.dart`

Expected: PASS.

```text
git add lib/src/features/workspace/domain/pdf_text_case.dart lib/src/features/workspace/domain/pdf_text_layout.dart lib/src/features/workspace/infrastructure/pdf_text_block_grouper.dart test/workspace_pdf/pdf_text_case_test.dart test/workspace_pdf/pdf_text_layout_test.dart test/workspace_pdf/pdf_text_block_grouper_test.dart
git commit -m "feat: add PDF text grouping and layout"
```

### Task 3: Discover genuine text objects through the existing PDFium document

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/src/features/workspace/infrastructure/pdf_text_engine.dart`
- Create: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Create: `lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart`
- Create: `test/support/pdf_text_fixture.dart`
- Create: `test/workspace_pdf/pdfium_text_engine_test.dart`

**Interfaces:**
- Consumes: `PdfDocument.useNativeDocumentHandle`, `pdfiumBindings`, Task 1 locators/types, and Task 2 grouper.
- Produces: abstract `PdfTextEngine`, conditionally selected `createPdfTextEngine`, native `PdfiumTextEngine.inspectPages`, `PdfiumTextEngine.resolveLocator`, `PdfResolvedTextObject`, and capability/read-only classifications.

- [ ] **Step 1: Pin the binding packages already selected by pdfrx**

Add direct dependencies so imports are stable and analyzer-supported:

```yaml
dependencies:
  ffi: 2.2.0
  pdfium_flutter: 0.2.3
```

Run: `flutter pub get`

Expected: `pubspec.lock` retains `pdfium_dart` 0.2.5 and `pdfium_flutter` 0.2.3, matching pdfrx 2.4.7.

- [ ] **Step 2: Create a real-text fixture and failing inspection tests**

```dart
test('discovers selectable page text with stable locator data', () async {
  final file = await PdfTextFixture.singleBlock('Quarterly Revenue');
  final document = await PdfDocument.openFile(file.path);
  addTearDown(document.dispose);

  final blocks = await const PdfiumTextEngine().inspectPages(
    document: document,
    sourceRevision: await sha256File(file),
    pageNumbers: const [1],
  );

  expect(blocks.single.text, 'Quarterly Revenue');
  expect(blocks.single.locator.objectPath, isNotEmpty);
  expect(blocks.single.capabilities, contains(PdfTextCapability.replace));
});

test('classifies Type 3 and shared form text as read only', () async {
  final fixture = await PdfTextFixture.unsupportedObjects();
  final blocks = await inspectFixture(fixture);
  expect(blocks.map((b) => b.readOnlyReason), containsAll([
    PdfReadOnlyReason.type3Font,
    PdfReadOnlyReason.sharedFormObject,
  ]));
});
```

- [ ] **Step 3: Run the native test and verify it fails before the adapter exists**

Run: `flutter test test/workspace_pdf/pdfium_text_engine_test.dart`

Expected: FAIL because `PdfiumTextEngine` and fixture helpers are undefined.

- [ ] **Step 4: Implement scoped PDFium traversal**

```dart
abstract interface class PdfTextEngine {
  Future<List<PdfTextBlock>> inspectPages({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  });

  Future<PdfResolvedTextObject> resolveLocator({
    required PdfDocument document,
    required PdfTextBlockLocator locator,
  });
}
```

Keep that contract and its DTOs in `pdf_text_engine.dart`. Export `createPdfTextEngine` through a conditional import selecting `pdfium_text_engine_native.dart` when `dart.library.io` is available and `pdfium_text_engine_stub.dart` otherwise. The stub throws a typed `PdfNativeEditingUnavailableFailure`; it must not import `dart:ffi`, `pdfium_dart`, or `pdfium_flutter`.

Inside `useNativeDocumentHandle`, load only requested pages, enumerate with `FPDFPage_CountObjects`/`FPDFPage_GetObject`, recurse into forms with `FPDFFormObj_CountObjects`/`FPDFFormObj_GetObject`, and always close page/text-page handles in `finally`. Read text, bounds, matrix, fill color, font family/flags/weight, font size, render mode, and character geometry. Quantize geometry to 1/1000 PDF point before hashing. Record every nested object index in `objectPath`.

- [ ] **Step 5: Implement strict locator resolution**

Resolve the exact object path first, then verify page, normalized text digest, quantized geometry digest, transform, font fingerprint, and source revision. Permit a unique geometry/text fallback only when the object path changed during normalization; return `PdfStaleLocatorFailure` for zero matches and `PdfAmbiguousLocatorFailure` for multiple matches.

```dart
if (candidates.length != 1) {
  throw candidates.isEmpty
      ? PdfStaleLocatorFailure(locator)
      : PdfAmbiguousLocatorFailure(locator, candidates.length);
}
return candidates.single;
```

- [ ] **Step 6: Verify native discovery and commit**

Run: `dart format lib/src/features/workspace/infrastructure/pdf_text_engine.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart test/support/pdf_text_fixture.dart test/workspace_pdf/pdfium_text_engine_test.dart`

Run: `flutter test test/workspace_pdf/pdfium_text_engine_test.dart`

Run: `flutter analyze lib/src/features/workspace/infrastructure/pdf_text_engine.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart`

Expected: all commands pass and the fixture text is returned by PDFium extraction.

```text
git add pubspec.yaml pubspec.lock lib/src/features/workspace/infrastructure/pdf_text_engine.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart test/support/pdf_text_fixture.dart test/workspace_pdf/pdfium_text_engine_test.dart
git commit -m "feat: inspect native PDF text objects"
```

### Task 4: Route every edit through one dispatcher and history

**Files:**
- Create: `lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart`
- Create: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/features/workspace/domain/workspace_feature_state.dart`
- Create: `test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart`
- Modify: `test/workspace_ai/workspace_notifier_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3 types/engine and existing notifier annotation/bookmark operations.
- Produces: `PdfEditIntentDispatcher.dispatch(PdfEditIntent, {required PdfCommandProvenance})`, `PdfEditingController.sessionFor`, `sessionsByTabId`, and thin notifier adapters.

- [ ] **Step 1: Write failing dispatcher and unified-history tests**

```dart
test('rejects stale document revisions before mutation', () async {
  final dispatcher = dispatcherWith(sessionRevision: 'rev-2');
  final result = await dispatcher.dispatch(
    ReplacePdfTextIntent(
      documentId: 'doc',
      documentRevision: 'rev-1',
      locator: testLocator,
      range: const PdfTextRange(0, 3),
      replacement: 'New',
    ),
    provenance: PdfCommandProvenance.manual,
  );
  expect(result.failure, isA<PdfRevisionConflictFailure>());
  expect(dispatcher.session.blocks.single.text, 'Old');
});

testWidgets('bookmark then text replacement undo in chronological order', (tester) async {
  final controller = editingControllerWithOneBlock();
  await controller.dispatch(addBookmarkIntent('Methods'));
  await controller.dispatch(replaceIntent('Old', 'New'));
  await controller.undo();
  expect(controller.session.activeBlock!.text, 'Old');
  await controller.undo();
  expect(controller.session.bookmarks, isEmpty);
});
```

- [ ] **Step 2: Run focused tests and confirm the dispatcher is missing**

Run: `flutter test test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart test/workspace_ai/workspace_notifier_test.dart`

Expected: FAIL with missing dispatcher/controller APIs.

- [ ] **Step 3: Implement the mutation boundary**

```dart
Future<PdfEditResult> dispatch(
  PdfEditIntent intent, {
  required PdfCommandProvenance provenance,
}) async {
  final session = _sessions.require(intent.documentId);
  if (intent.documentRevision != session.revision) {
    return PdfEditResult.failure(PdfRevisionConflictFailure(
      expected: session.revision,
      actual: intent.documentRevision,
    ));
  }
  final command = _commandFactory.create(session, intent, provenance);
  _sessions.replace(session.applyCommand(command));
  return PdfEditResult.applied(
    revision: _sessions.require(intent.documentId).revision,
    commandIds: [command.id],
    affectedLocators: command.affectedLocators,
  );
}
```

Validate locator/range/capability/overflow before command creation. Add `PdfEditingSession` to `WorkspaceFeatureState` as a per-tab map or expose an immutable controller snapshot watched through a dedicated Riverpod notifier; do not put FFI handles in feature state.

- [ ] **Step 4: Migrate bookmarks, highlights, undo, and redo**

Replace `_undoMetadata`, `_redoMetadata`, and `_savedPdfMetadata` with dispatcher commands. Keep public `addBookmark`, `addHighlight`, `updateAnnotationNote`, `removeAnnotation`, `undoPdfEdit`, and `redoPdfEdit` methods as adapters that construct intents. Update `dirtyDocumentIds`, `canUndoActive`, and `canRedoActive` from the active editing session.

```dart
Future<void> undoPdfEdit() => ref.read(pdfEditingControllerProvider).undoActive();

Future<void> addBookmark({required String tabId, required int pageNumber, required String label}) =>
    _dispatchForTab(tabId, AddPdfBookmarkIntent(
      documentId: _documentIdFor(tabId),
      documentRevision: _revisionFor(tabId),
      bookmark: PdfBookmarkEdit(id: _newId(), title: label, pageNumber: pageNumber),
    ));
```

- [ ] **Step 5: Verify migration and commit**

Run: `dart format lib/src/features/workspace/application lib/src/features/workspace/domain/workspace_feature_state.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart test/workspace_ai/workspace_notifier_test.dart`

Run: `flutter test test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart test/workspace_ai/workspace_notifier_test.dart test/workspace_pdf/pdf_edit_session_test.dart`

Expected: existing bookmark/highlight behavior passes through the new history, and stale intents do not mutate state.

```text
git add lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/application/workspace_providers.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/domain/workspace_feature_state.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart test/workspace_ai/workspace_notifier_test.dart
git commit -m "refactor: unify PDF edit command history"
```

### Task 5: Add text-edit mode and accurate block overlays

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Create: `test/workspace_pdf/pdf_text_editor_overlay_test.dart`
- Create: `test/workspace_pdf/pdf_text_editor_overlay_golden_test.dart`

**Interfaces:**
- Consumes: `PdfEditingSession`, `PdfEditingController.enterTextMode/leaveTextMode/inspectVisiblePages`, pdfrx `pageOverlaysBuilder`, `PdfRect.toRect`, and page dimensions.
- Produces: `PdfTextEditorOverlay`, edit-mode toolbar toggle, block hover/selection events, and cancellable visible-page discovery.

- [ ] **Step 1: Write failing mode and visibility tests**

```dart
testWidgets('bounds exist only in text edit mode', (tester) async {
  await tester.pumpWidget(editorHarness(mode: PdfEditingMode.reading));
  expect(find.byKey(const Key('pdf-text-block-outline')), findsNothing);

  await tester.tap(find.byKey(const Key('pdf-text-edit-toggle')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('pdf-text-block-outline')), findsOneWidget);

  await tester.tap(find.byKey(const Key('pdf-text-edit-toggle')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('pdf-text-block-outline')), findsNothing);
});
```

- [ ] **Step 2: Run the widget test and verify missing UI fails**

Run: `flutter test test/workspace_pdf/pdf_text_editor_overlay_test.dart`

Expected: FAIL because the toggle and overlay keys do not exist.

- [ ] **Step 3: Host overlays per page rather than in the global viewer overlay**

Add `pageOverlaysBuilder` to `PdfViewerParams`. Convert each `PdfBox` to `PdfRect(left, bottom, right, top)` and then to the provided page rectangle so zoom, rotation, DPI, and scrolling use pdfrx’s coordinate transform.

```dart
pageOverlaysBuilder: (context, pageRect, page) => session.mode == PdfEditingMode.text
    ? [PdfTextEditorOverlay(
        page: page,
        pageRect: pageRect,
        blocks: session.blocksForPage(page.pageNumber),
        selection: session.selection,
        onIntent: _dispatchManualIntent,
      )]
    : const <Widget>[],
```

Set `textSelectionParams.enabled` and `panEnabled` to false only while a block editor owns the pointer. Reading mode must retain the current pdfrx selection configuration.

- [ ] **Step 4: Implement progressive cancellable discovery**

On entering text mode, inspect the current page first, then adjacent visible/cache pages. Cancel the previous token on tab change, mode exit, viewer reload, or source-revision change. Render a small per-page loading state without blocking scroll.

```dart
Future<void> enterTextMode(String tabId, PdfDocument document, int currentPage) async {
  _cancelDiscovery(tabId);
  _replaceSession(tabId, sessionFor(tabId).copyWith(mode: PdfEditingMode.text));
  await inspectPages(tabId, document, [currentPage]);
  unawaited(inspectPages(tabId, document, neighboringPages(currentPage)));
}
```

- [ ] **Step 5: Add overlay goldens and verify**

Capture normal, hover, selected, read-only, 200% zoom, and rotated-page cases. Use deterministic test colors: low-contrast neutral outline, stronger hover, accent selection, and warning overflow/read-only states.

Run: `flutter test test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_text_editor_overlay_golden_test.dart --update-goldens`

Inspect the generated goldens once, then run without `--update-goldens`.

Expected: PASS with no outlines in reading mode and page-aligned outlines in edit mode.

- [ ] **Step 6: Commit edit mode and overlays**

```text
git add lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/application/pdf_editing_controller.dart test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_text_editor_overlay_golden_test.dart test/goldens
git commit -m "feat: add PDF text edit mode overlays"
```

### Task 6: Support inline selection, typing, and case-matched replacement

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart`
- Modify: `lib/src/features/workspace/domain/pdf_edit_session.dart`
- Create: `test/workspace_pdf/pdf_text_inline_edit_test.dart`
- Modify: `test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart`

**Interfaces:**
- Consumes: Task 2 casing, `ReplacePdfTextIntent`, and session command coalescing.
- Produces: pure `PdfTextDelta.between`, caret/selection editing, clipboard operations, keyboard navigation, case-match toggle behavior, and deterministic typing command boundaries.

- [ ] **Step 1: Write failing inline behavior tests**

```dart
testWidgets('selected uppercase text adopts uppercase replacement', (tester) async {
  await tester.pumpWidget(activeEditorHarness(text: 'TOTAL REVENUE'));
  await selectText(tester, start: 0, end: 13);
  await tester.enterText(find.byKey(const Key('pdf-inline-text-editor')), 'net income');
  await tester.pump();
  expect(activeSession(tester).activeBlock!.text, 'NET INCOME');
});

test('typing coalesces until caret movement', () {
  final afterTyping = dispatchSequence(['a', 'b', 'c']);
  expect(afterTyping.commands, hasLength(1));
  final afterMoveAndType = afterTyping.moveCaret(-1).insert('x');
  expect(afterMoveAndType.commands, hasLength(2));
});
```

- [ ] **Step 2: Run tests and verify inline editing is absent**

Run: `flutter test test/workspace_pdf/pdf_text_inline_edit_test.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart`

Expected: FAIL on missing editable control and command coalescer.

- [ ] **Step 3: Implement the editor using Flutter text input semantics**

Use an `EditableText`/`TextEditingController` per active block so IME, clipboard, selection, Delete, Home/End, and arrow behavior stay native. Convert `TextEditingValue.selection` to `PdfTextSelection`; dispatch only text deltas, not controller rebuild echoes. Escape finalizes the typing group and deselects the block; clicking elsewhere finalizes the group while remaining in text mode.

```dart
void _onChanged(String next) {
  final delta = PdfTextDelta.between(_lastValue.text, next);
  widget.onIntent(ReplacePdfTextIntent(
    documentId: widget.documentId,
    documentRevision: widget.revision,
    locator: widget.block.locator,
    range: delta.replacedRange,
    replacement: widget.caseMatching && delta.replacedRange.isNotEmpty
        ? matchReplacementCase(delta.replacedText, delta.insertedText)
        : delta.insertedText,
    coalescingKey: _typingGroupId,
  ));
}
```

- [ ] **Step 4: Enforce coalescing boundaries in the session**

Merge adjacent replacement commands only when document, locator, provenance, coalescing key, style, and contiguous range match. End a group on selection/caret movement, paste, cut, formatting, focus change, block change, Escape, or 750 ms idle. New typing after undo clears redo.

- [ ] **Step 5: Verify inline editing and commit**

Run: `dart format lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart lib/src/features/workspace/domain/pdf_edit_session.dart test/workspace_pdf/pdf_text_inline_edit_test.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart`

Run: `flutter test test/workspace_pdf/pdf_text_inline_edit_test.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart test/workspace_pdf/pdf_text_case_test.dart`

Expected: PASS for insertion, replacement, cut, paste, deletion, navigation, Escape, case matching, and undo grouping.

```text
git add lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart lib/src/features/workspace/domain/pdf_edit_session.dart test/workspace_pdf/pdf_text_inline_edit_test.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart
git commit -m "feat: edit PDF text inline"
```

### Task 7: Save edits as genuine PDF text with transactional validation

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Create: `lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Modify: `lib/src/core/pdf_oxide_bridge.dart`
- Modify: `lib/src/features/workspace/infrastructure/document_metadata_store.dart`
- Modify: `lib/src/features/workspace/infrastructure/document_chunk_store.dart`
- Modify: `lib/src/features/workspace/infrastructure/conversation_store.dart`
- Create: `test/workspace_pdf/pdf_edit_save_service_test.dart`
- Create: `test/workspace_pdf/pdf_text_round_trip_test.dart`
- Modify: `test/workspace_ai/workspace_notifier_test.dart`

**Interfaces:**
- Consumes: resolved locators, final session blocks, current annotation/bookmark state, memory-backed `pdfDocumentRefProvider`, and chunk indexer.
- Produces: `PdfTextEngine.applyDraft`, `PdfEditSaveService.save`, typed `PdfSaveOutcome`, progress events, conflict recovery choices, and reload callback.

- [ ] **Step 1: Write failure-safety and genuine-text round-trip tests**

```dart
test('validation failure leaves original bytes unchanged', () async {
  final file = await PdfTextFixture.singleBlock('Original');
  final before = await file.readAsBytes();
  final service = saveService(validator: (_) async => throw PdfValidationFailure('forced'));

  await expectLater(service.save(requestFor(file, replacement: 'Changed')), throwsA(isA<PdfValidationFailure>()));
  expect(await file.readAsBytes(), before);
  expect(service.session.isDirty, isTrue);
});

test('saved replacement is selectable searchable and extractable', () async {
  final file = await PdfTextFixture.singleBlock('Old revenue');
  await realSaveService().save(requestFor(file, replacement: 'Net revenue'));
  final document = await PdfDocument.openFile(file.path);
  addTearDown(document.dispose);
  final pageText = await document.pages.single.loadText();
  expect(pageText!.fullText, contains('Net revenue'));
  expect(await searchPdf(document, 'Net revenue'), isNotEmpty);
});
```

- [ ] **Step 2: Run save tests and confirm missing transaction fails**

Run: `flutter test test/workspace_pdf/pdf_edit_save_service_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart`

Expected: FAIL because the save service and PDFium mutation methods do not exist.

- [ ] **Step 3: Apply text-object patches under the pdfrx native-handle lock**

Open the sibling working copy with `PdfDocument.openFile`, call `useNativeDocumentHandle`, resolve every locator against that clean document, update supported objects with `FPDFText_SetText`, `FPDFPageObj_SetMatrix`, `FPDFPageObj_SetFillColor`, and font APIs, then call `FPDFPage_GenerateContent` for every affected page. Fail the entire operation if any API returns false.

```dart
Future<Uint8List> applyDraft(PdfDocument document, PdfEditingSession draft) async {
  await document.useNativeDocumentHandle((address) {
    final handle = FPDF_DOCUMENT.fromAddress(address);
    for (final patch in draft.textPatches) {
      _applyResolvedPatch(handle, patch);
    }
  });
  await document.reloadPages(pageNumbersToReload: draft.affectedPages);
  return document.encodePdf(incremental: false);
}
```

- [ ] **Step 4: Implement the complete working-copy transaction**

Compute the source SHA-256 revision and confirm write access, create `.name.clarix-edit-<nonce>.pdf` beside the source, copy source bytes, apply both text patches and current annotations/bookmarks to the working copy, encode non-incrementally, flush, reopen, validate, then replace. On Windows, close every `PdfDocument` before `File.rename`; if same-volume rename cannot replace the destination, use the existing validated backup/restore helper without ever deleting the only good copy.

```dart
Future<PdfSaveOutcome> save(PdfSaveRequest request) async {
  await _verifyRevision(request.path, request.sourceRevision);
  final working = await _createSiblingCopy(request.path);
  try {
    await _writeDraft(working.path, request);
    final validation = await _validator.validate(working.path, request);
    await _replaceAtomically(working.path, request.path);
    return PdfSaveOutcome.saved(validation.newRevision);
  } catch (_) {
    if (await working.exists()) await working.delete();
    rethrow;
  }
}
```

- [ ] **Step 5: Validate semantics and reload every consumer**

Validation must reopen successfully and compare page count, edited extraction, search results, expected geometry/style, Unicode mapping/font embedding, and fingerprints for unaffected pages. After replacement, invalidate `pdfDocumentRefProvider(path)`, reopen viewer bytes, rediscover text blocks, rebuild chunks/native RAG index, refresh search, and only then mark the session saved. Return Reload and Save a Copy actions for an external revision conflict.

`DocumentTabState.documentId` is currently the source-byte SHA-256, so a successful edit changes it. Re-identify the saved file and migrate the active tab, `documentMetadata` key and sidecar, chunk filename/records, native RAG fingerprint, and conversation `document_id` from the old fingerprint to the new fingerprint in one application update. Keep `DocumentTabState.id` as the stable open-tab identity and return both `documentId` and `documentRevision` from Save so subsequent agent requests cannot reuse stale identifiers.

```dart
final identity = await _identityService.identify(request.path);
await _metadataStore.move(oldFingerprint: request.documentId, metadata: metadata.copyWith(identity: identity));
await _chunkStore.remove(request.documentId);
await _conversationStore.reassignDocument(request.documentId, identity.fingerprint);
await _reloadSavedTab(tabId: request.tabId, newIdentity: identity, newRevision: identity.fingerprint);
```

- [ ] **Step 6: Test Windows lock recovery and commit**

Run: `dart format lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/application/workspace_providers.dart lib/src/core/pdf_oxide_bridge.dart lib/src/features/workspace/infrastructure/document_metadata_store.dart lib/src/features/workspace/infrastructure/document_chunk_store.dart lib/src/features/workspace/infrastructure/conversation_store.dart test/workspace_pdf/pdf_edit_save_service_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart test/workspace_ai/workspace_notifier_test.dart`

Run: `flutter test test/workspace_pdf/pdf_edit_save_service_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart test/workspace_pdf/pdf_document_ref_provider_test.dart test/workspace_ai/workspace_notifier_test.dart`

Expected: successful round trip, byte-identical original on injected failures, dirty state retained on failure, and no `os error 5` with the viewer open.

```text
git add lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/application/workspace_providers.dart lib/src/core/pdf_oxide_bridge.dart lib/src/features/workspace/infrastructure/document_metadata_store.dart lib/src/features/workspace/infrastructure/document_chunk_store.dart lib/src/features/workspace/infrastructure/conversation_store.dart test/workspace_pdf/pdf_edit_save_service_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart test/workspace_ai/workspace_notifier_test.dart
git commit -m "feat: save genuine PDF text transactionally"
```

### Task 8: Add installed-font matching and the Text Format panel

**Files:**
- Create: `lib/src/features/workspace/infrastructure/installed_font_catalog.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Create: `lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_body.dart`
- Modify: `lib/src/core/models.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Create: `test/workspace_pdf/installed_font_catalog_test.dart`
- Create: `test/workspace_pdf/pdf_text_format_panel_test.dart`
- Modify: `test/workspace_pdf/pdf_text_round_trip_test.dart`

**Interfaces:**
- Consumes: `FormatPdfTextIntent`, selected runs, PDFium font loading, and existing right tool rail.
- Produces: `InstalledFontCatalog.scan/match`, `FontMatch`, `RightToolWindow.textFormat`, mixed-style panel state, and embedded-font patches.

- [ ] **Step 1: Write failing font scoring and panel tests**

```dart
test('closest compatible font prefers family metrics and required script', () async {
  final catalog = fakeCatalog([
    font('Arial', weight: 400, scripts: {'Latin'}),
    font('Arial Bold', weight: 700, scripts: {'Latin'}),
    font('Noto Sans Arabic', weight: 400, scripts: {'Arabic'}),
  ]);
  final match = catalog.match(request(family: 'Helvetica', weight: 700, text: 'Revenue'));
  expect(match.font.family, 'Arial Bold');
  expect(match.requiresSubstitution, isTrue);
});

testWidgets('mixed selection shows indeterminate controls', (tester) async {
  await tester.pumpWidget(formatPanelHarness(mixedFontSize: true));
  expect(find.byKey(const Key('pdf-font-size-mixed')), findsOneWidget);
  await tester.enterText(find.byKey(const Key('pdf-font-size-input')), '14');
  expect(lastIntent(tester), isA<FormatPdfTextIntent>());
});
```

- [ ] **Step 2: Run tests and verify font/panel support is missing**

Run: `flutter test test/workspace_pdf/installed_font_catalog_test.dart test/workspace_pdf/pdf_text_format_panel_test.dart`

Expected: FAIL with missing catalog and panel.

- [ ] **Step 3: Implement the installed-font catalog and embedding checks**

Scan `%WINDIR%\Fonts` plus per-user `%LOCALAPPDATA%\Microsoft\Windows\Fonts`; cache path, family, face, weight, slant, width, Unicode coverage, and OS/2 `fsType`. Score family classification, weight, slant, width, script coverage, and metric similarity in that order. Treat restricted-license embedding and bitmap-only faces as ineligible.

```dart
final class FontMatch {
  const FontMatch({required this.font, required this.score, required this.requiresSubstitution});
  final InstalledFontFace font;
  final double score;
  final bool requiresSubstitution;
}
```

Load approved TrueType/OpenType bytes with `FPDFText_LoadFont`, retain the `FPDF_FONT` until document save completes, set the replacement text object’s font/size, and ensure generated ToUnicode mapping survives round-trip validation. Select real bold/italic faces instead of synthesizing them. Represent superscript/subscript with font size plus baseline shift. Represent underline as a companion PDF path object while keeping the characters themselves in the text object and track that path in the reversible command. If no compatible embeddable font exists, return `PdfFontUnavailableFailure` without altering the file.

- [ ] **Step 4: Add the Text Format tool and selection-aware controls**

Extend `RightToolWindow` with `textFormat`, render `PdfTextFormatPanel` in `WorkspaceBody`, and open it when a block becomes active. Include searchable family, size, fill color, bold, italic, underline, super/subscript, alignment, case matching, advanced spacing/scaling, geometry, and reset-to-original controls. Mixed selections display indeterminate values; new typing inherits the caret style.

```dart
void _applyStyle(PdfTextStylePatch patch) => onIntent(FormatPdfTextIntent(
  documentId: session.documentId,
  documentRevision: session.revision,
  locator: session.selection!.locator,
  range: session.selection!.rangeOrWholeBlock(activeBlock.text.length),
  patch: patch,
));
```

- [ ] **Step 5: Verify formatting and round trips**

Run: `dart format lib/src/features/workspace/infrastructure/installed_font_catalog.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/core/models.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_pdf/installed_font_catalog_test.dart test/workspace_pdf/pdf_text_format_panel_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart`

Run: `flutter test test/workspace_pdf/installed_font_catalog_test.dart test/workspace_pdf/pdf_text_format_panel_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart`

Expected: PASS for mixed values, selection/whole-block formatting, visible substitution warning, prohibited embedding failure, and reopened style/text extraction.

- [ ] **Step 6: Commit formatting**

```text
git add lib/src/features/workspace/infrastructure/installed_font_catalog.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/core/models.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_pdf/installed_font_catalog_test.dart test/workspace_pdf/pdf_text_format_panel_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart
git commit -m "feat: format and embed PDF text fonts"
```

### Task 9: Add block move, resize, reflow, and overflow enforcement

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/domain/pdf_text_layout.dart`
- Modify: `lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart`
- Create: `test/workspace_pdf/pdf_text_geometry_edit_test.dart`
- Modify: `test/workspace_pdf/pdf_text_round_trip_test.dart`

**Interfaces:**
- Consumes: `MovePdfTextBlockIntent`, `ResizePdfTextBlockIntent`, Task 2 layout, and PDFium matrices.
- Produces: eight resize handles, drag previews, fixed-block reflow, overflow state, and Save gating.

- [ ] **Step 1: Write failing geometry and overflow tests**

```dart
testWidgets('resize reflows text without changing font size', (tester) async {
  await tester.pumpWidget(activeEditorHarness(text: 'one two three four', width: 160));
  await dragHandle(tester, const Key('pdf-resize-east'), const Offset(-80, 0));
  final block = activeSession(tester).activeBlock!;
  expect(block.layout.lines.length, greaterThan(1));
  expect(block.styleAt(0).fontSize, 12);
});

test('overflow prevents save intent', () async {
  final result = await overflowDispatcher().dispatch(saveIntent, provenance: PdfCommandProvenance.manual);
  expect(result.failure, isA<PdfTextOverflowFailure>());
});
```

- [ ] **Step 2: Run tests and confirm geometry editing fails**

Run: `flutter test test/workspace_pdf/pdf_text_geometry_edit_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart`

Expected: FAIL because handles and save overflow validation are absent.

- [ ] **Step 3: Implement move/resize previews and commands**

Keep pointer deltas in viewer coordinates during drag, convert them to PDF points using the current page rectangle, constrain the block to page bounds, and dispatch one command at drag end. Keyboard nudging uses one PDF point per arrow and ten points with Shift.

```dart
onPanEnd: (_) => onIntent(ResizePdfTextBlockIntent(
  documentId: documentId,
  documentRevision: revision,
  locator: block.locator,
  bounds: previewBounds,
));
```

- [ ] **Step 4: Reflow and enforce overflow before Save**

Recompute layout after replacement, style, and resize commands. Paint overflow in warning color, expose `session.overflowingLocators`, disable Save UI, and return `PdfTextOverflowFailure` from the dispatcher so agent callers receive the same rule. Never reduce font size or move another block automatically.

- [ ] **Step 5: Apply transforms to genuine objects and verify**

Map moved/resized layout lines back to resolved text objects. Reuse an existing object when one line/run is sufficient; otherwise create text objects with `FPDFPageObj_CreateTextObj`/`FPDFText_LoadFont`, insert them with `FPDFPage_InsertObject`, remove superseded objects only after replacements are ready, and call `FPDFPage_GenerateContent`. Preserve clipping/render mode only for supported blocks.

Run: `flutter test test/workspace_pdf/pdf_text_geometry_edit_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart`

Expected: PASS for move, resize, multi-line reflow, overflow blocking, and reopened geometry.

- [ ] **Step 6: Commit geometry editing**

```text
git add lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/domain/pdf_text_layout.dart lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart test/workspace_pdf/pdf_text_geometry_edit_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart
git commit -m "feat: move resize and reflow PDF text"
```

### Task 10: Add permission-controlled agent edit tools

**Files:**
- Create: `lib/src/features/workspace/application/action_permission_service.dart`
- Create: `lib/src/features/workspace/application/ai_tool_registry.dart`
- Modify: `lib/src/features/workspace/application/ai_agent_runtime.dart`
- Modify: `lib/src/features/workspace/application/ai_runtime_service.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Create: `test/workspace_ai/action_permission_service_test.dart`
- Create: `test/workspace_ai/ai_tool_registry_test.dart`
- Modify: `test/workspace_ai/ai_agent_runtime_test.dart`
- Create: `test/workspace_pdf/pdf_edit_manual_agent_parity_test.dart`

**Interfaces:**
- Consumes: dispatcher, active document resolver, SharedPreferences, and current `search_document` tool.
- Produces: `ActionPermissionPolicy`, `PermissionScope`, `PdfEditRiskAssessment`, `PermissionDecision`, `AiToolRegistry.schemas/execute`, and nine PDF edit tool schemas.

- [ ] **Step 1: Write failing permission and parity tests**

```dart
test('askWhenRisky allows local replace but prompts for save', () async {
  final service = permissionService(policy: ActionPermissionPolicy.askWhenRisky);
  expect(await service.authorize(contextFor(replaceIntent('a', 'b'))), PermissionDecision.allowed);
  expect(await service.authorize(contextFor(saveIntent)), isA<PermissionRequired>());
});

test('persistent workspace grant survives service recreation', () async {
  final store = memoryPreferences();
  await permissionService(store: store).grant(
    policy: ActionPermissionPolicy.allow,
    scope: PermissionScope.workspace,
    workspaceId: 'default',
  );
  expect(permissionService(store: store).policyFor('default'), ActionPermissionPolicy.allow);
});

test('manual and agent replacement produce identical command state', () async {
  final manual = await dispatchManual(replaceIntent('Old', 'New'));
  final agent = await executeTool('replace_pdf_text', replaceArguments('Old', 'New'));
  expect(agent.session.blocks, manual.session.blocks);
  expect(agent.session.commands.single.provenance, PdfCommandProvenance.agent);
});
```

- [ ] **Step 2: Run tests and confirm permission/tool layers are missing**

Run: `flutter test test/workspace_ai/action_permission_service_test.dart test/workspace_ai/ai_tool_registry_test.dart test/workspace_pdf/pdf_edit_manual_agent_parity_test.dart`

Expected: FAIL with missing permission and registry types.

- [ ] **Step 3: Implement deterministic policy, scope, and risk classification**

```dart
enum ActionPermissionPolicy { allow, askWhenRisky, askAlways }
enum PermissionScope { action, document, session, workspace }

PdfEditRiskAssessment classify(PdfEditIntent intent) => PdfEditRiskAssessment(
  risky: intent is SavePdfEditsIntent ||
      intent.affectedPages.length > 1 ||
      intent.editCount > 10 ||
      intent.deletionRatio >= 0.25 ||
      intent.requiresFontSubstitution ||
      intent is MovePdfTextBlockIntent,
  reasons: riskReasonsFor(intent),
);
```

Store persistent workspace grants in SharedPreferences; hold action/document/session grants in memory. Return a structured preview instead of applying when approval is required. Permission events are logged separately and never enter undo history.

- [ ] **Step 4: Implement schemas and argument decoding**

Register `inspect_pdf_text_blocks`, `get_pdf_text_block`, `replace_pdf_text`, `format_pdf_text`, `move_pdf_text_block`, `resize_pdf_text_block`, `undo_pdf_edit`, `redo_pdf_edit`, and `save_pdf_edits`. Require `documentId` and `documentRevision` for every mutation and locator fields for targeted mutations. Reject unknown keys with a structured `invalid_arguments` result.

```dart
Future<Map<String, Object?>> execute(AiToolCall call) async {
  final decoded = _decodeStrict(call.argumentsJson, schemaFor(call.name));
  final intent = _intentDecoder.decode(call.name, decoded);
  final permission = await _permissions.authorize(contextFor(intent));
  if (permission case PermissionRequired required) return required.toJson();
  return (await _dispatcher.dispatch(intent, provenance: PdfCommandProvenance.agent)).toJson();
}
```

Tool results include affected locators, new revision, warnings, permission state, dirty state, and command IDs. Bulk replacements accept a finite array capped at 100 entries and dispatch one compound command.

- [ ] **Step 5: Integrate the registry with the AI runtime**

Inject `AiToolRegistry` into `AiAgentRuntime`; concatenate its schemas with `search_document`, delegate recognized edit calls, and retain the six-round limit. Scope tools to the documents supplied in `AiAgentRequest.documentIds`; reject attempts to mutate any other document.

- [ ] **Step 6: Verify tool contracts and commit**

Run: `dart format lib/src/features/workspace/application/action_permission_service.dart lib/src/features/workspace/application/ai_tool_registry.dart lib/src/features/workspace/application/ai_agent_runtime.dart lib/src/features/workspace/application/ai_runtime_service.dart lib/src/features/workspace/application/workspace_providers.dart test/workspace_ai/action_permission_service_test.dart test/workspace_ai/ai_tool_registry_test.dart test/workspace_ai/ai_agent_runtime_test.dart test/workspace_pdf/pdf_edit_manual_agent_parity_test.dart`

Run: `flutter test test/workspace_ai/action_permission_service_test.dart test/workspace_ai/ai_tool_registry_test.dart test/workspace_ai/ai_agent_runtime_test.dart test/workspace_pdf/pdf_edit_manual_agent_parity_test.dart`

Expected: PASS for all three policies, four scopes, risky classifications, stale revisions, document scoping, strict schemas, and manual/agent parity.

```text
git add lib/src/features/workspace/application/action_permission_service.dart lib/src/features/workspace/application/ai_tool_registry.dart lib/src/features/workspace/application/ai_agent_runtime.dart lib/src/features/workspace/application/ai_runtime_service.dart lib/src/features/workspace/application/workspace_providers.dart test/workspace_ai/action_permission_service_test.dart test/workspace_ai/ai_tool_registry_test.dart test/workspace_ai/ai_agent_runtime_test.dart test/workspace_pdf/pdf_edit_manual_agent_parity_test.dart
git commit -m "feat: expose permission controlled PDF edit tools"
```

### Task 11: Wire shortcuts, save progress, conflicts, and user-facing recovery

**Files:**
- Modify: `lib/src/features/workspace/presentation/screens/workspace_screen.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_body.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Create: `test/workspace_pdf/pdf_edit_shortcuts_test.dart`
- Create: `test/workspace_pdf/pdf_edit_conflict_dialog_test.dart`
- Modify: `test/workspace_ai/desktop_window_chrome_test.dart`

**Interfaces:**
- Consumes: active `PdfEditingSession`, `PdfSaveOutcome`, typed failures, and existing Ctrl+S/Ctrl+Z/Ctrl+Shift+Z bindings.
- Produces: correct shortcut focus behavior, save progress, Reload/Save a Copy recovery, unsupported-object messages, and clean close behavior.

- [ ] **Step 1: Write failing shortcut and recovery tests**

```dart
testWidgets('Ctrl+Z edits text while inline editor has focus', (tester) async {
  await tester.pumpWidget(workspaceWithEditedText());
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  expect(activeBlockText(tester), 'Before');
});

testWidgets('external change offers reload and save a copy', (tester) async {
  await tester.pumpWidget(workspaceWithSaveFailure(PdfExternalRevisionFailure()));
  await tester.tap(find.byKey(const Key('chrome-save')));
  await tester.pumpAndSettle();
  expect(find.text('Reload'), findsOneWidget);
  expect(find.text('Save a Copy'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests and verify recovery UI fails**

Run: `flutter test test/workspace_pdf/pdf_edit_shortcuts_test.dart test/workspace_pdf/pdf_edit_conflict_dialog_test.dart test/workspace_ai/desktop_window_chrome_test.dart`

Expected: FAIL on focus routing and recovery actions.

- [ ] **Step 3: Route shortcuts through active session state**

Ctrl+S dispatches Save only when dirty and not overflowing; Ctrl+Z/Ctrl+Shift+Z operate on the single command history even when `EditableText` owns focus. Disable buttons during a save transaction and expose progress after 500 ms. Closing the window prompts for every dirty tab and saves them explicitly rather than saving only the active tab.

- [ ] **Step 4: Present typed failures with concrete recovery actions**

Map unsupported content, unavailable/prohibited fonts, overflow, stale locator, external change, encryption, validation failure, and atomic replacement failure to concise messages. External change gets Reload and Save a Copy; overflow selects the first overflowing block; stale locator offers rediscovery; access-denied replacement keeps the draft and offers Save a Copy.

```dart
PdfFailurePresentation present(PdfEditFailure failure) => switch (failure) {
  PdfExternalRevisionFailure() => const PdfFailurePresentation(
      message: 'The PDF changed outside Clarix.',
      actions: [PdfRecoveryAction.reload, PdfRecoveryAction.saveCopy],
    ),
  PdfTextOverflowFailure(:final locator) => PdfFailurePresentation(
      message: 'Text does not fit its box.',
      actions: [PdfRecoveryAction.selectBlock],
      locator: locator,
    ),
  _ => PdfFailurePresentation(message: failure.message, actions: const []),
};
```

- [ ] **Step 5: Verify and commit the application shell integration**

Run: `dart format lib/src/features/workspace/presentation/screens/workspace_screen.dart lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_pdf/pdf_edit_shortcuts_test.dart test/workspace_pdf/pdf_edit_conflict_dialog_test.dart test/workspace_ai/desktop_window_chrome_test.dart`

Run: `flutter test test/workspace_pdf/pdf_edit_shortcuts_test.dart test/workspace_pdf/pdf_edit_conflict_dialog_test.dart test/workspace_ai/desktop_window_chrome_test.dart`

Expected: PASS for shortcut focus, enabled states, progress delay, close prompts, and all recovery actions.

```text
git add lib/src/features/workspace/presentation/screens/workspace_screen.dart lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_pdf/pdf_edit_shortcuts_test.dart test/workspace_pdf/pdf_edit_conflict_dialog_test.dart test/workspace_ai/desktop_window_chrome_test.dart
git commit -m "feat: integrate PDF edit save and recovery UI"
```

### Task 12: Harden compatibility, performance, and release acceptance

**Files:**
- Modify: `test/support/pdf_text_fixture.dart`
- Create: `test/workspace_pdf/pdf_text_compatibility_test.dart`
- Create: `test/workspace_pdf/pdf_text_performance_test.dart`
- Create: `integration_test/pdf_text_editing_test.dart`
- Modify: `README.md`

**Interfaces:**
- Consumes: the complete editing stack.
- Produces: compatibility fixtures, measurable budgets, full workflow acceptance, and user-facing scope documentation.

- [ ] **Step 1: Add the compatibility matrix**

Create fixtures for standard fonts, embedded fonts, subset fonts, Unicode scripts, nested forms, rotated text, clipped text, malformed PDFs, encrypted/no-modification PDFs, Type 3 fonts, shared forms, image-only pages, external source changes, and injected validation/replacement failures.

```dart
for (final fixture in supportedFixtures) {
  test('${fixture.name} stays searchable after editing', () async {
    final result = await editSaveReopen(fixture);
    expect(result.extractedText, contains(fixture.expectedReplacement));
    expect(result.searchMatches, isNotEmpty);
    expect(result.unaffectedPageFingerprints, fixture.originalUnaffectedPageFingerprints);
  });
}
```

- [ ] **Step 2: Add performance tests with explicit budgets**

```dart
test('visible page discovery meets the 250 ms warm-page budget', () async {
  final stopwatch = Stopwatch()..start();
  await engine.inspectPages(document: warmDocument, sourceRevision: revision, pageNumbers: const [1]);
  expect(stopwatch.elapsedMilliseconds, lessThan(250));
});

test('10k-character draft mutation does not reparse the document', () {
  final engine = CountingPdfTextEngine();
  dispatchReplace('x' * 10000, engine: engine);
  expect(engine.inspectCalls, 0);
});
```

Run performance tests in profile mode on Windows and record hardware/date in test output; do not weaken correctness if a budget fails.

- [ ] **Step 3: Add full interaction acceptance**

The integration test opens a fixture, enters edit mode, verifies subtle bounds, replaces text with case matching, changes font color/size/style/family, moves/resizes the block, undoes/redoes, saves, reopens, selects/searches/extracts the text, invokes the equivalent agent tool with a grant, and returns to reading mode with no edit bounds.

Run: `flutter test integration_test/pdf_text_editing_test.dart -d windows`

Expected: PASS on a Windows desktop with PDFium bundled by pdfrx.

- [ ] **Step 4: Document scope and recovery behavior**

Add a README section stating that first release edits genuine existing PDF text only, unsupported objects remain read-only, overflow blocks Save, fallback fonts are disclosed, agent actions obey the configured permission policy, and every failed save preserves the original.

- [ ] **Step 5: Run the full verification matrix**

Run: `dart format --output=none --set-exit-if-changed lib test integration_test`

Run: `flutter analyze`

Run: `flutter test`

Run: `flutter test integration_test/pdf_text_editing_test.dart -d windows`

Run: `cargo fmt --check --manifest-path rust/clarix_pdf_oxide/Cargo.toml`

Run: `cargo clippy --manifest-path rust/clarix_pdf_oxide/Cargo.toml -- -D warnings`

Run: `cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml`

Expected: every command exits 0. Manually open representative saved fixtures in Clarix and one external reader and confirm the edited text is selectable and searchable.

- [ ] **Step 6: Commit release hardening**

```text
git add test/support/pdf_text_fixture.dart test/workspace_pdf/pdf_text_compatibility_test.dart test/workspace_pdf/pdf_text_performance_test.dart integration_test/pdf_text_editing_test.dart README.md
git commit -m "test: qualify genuine PDF text editing"
```

---

## Implementation Order and Review Gates

- Tasks 1–2 establish pure deterministic behavior and may be reviewed without PDFium.
- Task 3 is the native feasibility gate. Do not proceed to interactive editing unless real fixture discovery and strict locator resolution pass.
- Task 7 is the persistence gate. Do not present formatting or agent mutation as complete until select/search/extract round trips and failure preservation pass.
- Tasks 8–9 expand supported edits while retaining the same dispatcher and save transaction.
- Task 10 exposes autonomy only after manual mutation semantics are stable.
- Tasks 11–12 complete product integration and release qualification.

At every gate, preserve unrelated working-tree changes, stage only the files named by that task, and inspect `git diff --cached --check` before committing.
