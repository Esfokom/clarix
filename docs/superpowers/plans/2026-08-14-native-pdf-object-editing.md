# Native PDF Object Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove doubled text in edit mode by suppressing selected native glyphs in an in-memory preview, and add genuine move, resize, and rotation for safe top-level PDF text, image, and path objects.

**Architecture:** A generic immutable page-object model and matrix commands extend the existing PDF edit session. A native preview controller mutates only the open in-memory PDFium document and reloads affected pages; the source path remains untouched until the existing transactional save applies and validates the same commands.

**Tech Stack:** Flutter/Dart, Riverpod, `pdfrx`, `pdfium_flutter`/PDFium FFI, Flutter widget tests, native round-trip tests.

**Spec:** `docs/superpowers/specs/2026-08-14-native-pdf-object-editing-design.md`

## Global Constraints

- Edit only genuine existing PDF objects; never rasterize a page to simulate an edit.
- Top-level text, image, and vector-path objects may be transformed; nested/shared form objects remain read-only.
- Keep the source file unchanged until transactional Save or Save a Copy succeeds.
- Store exact before/after affine matrices so undo and redo are lossless.
- Manual UI actions and AI tools must use the same intents, dispatcher, permissions, and command history.
- Typing and pointer gestures must not encode or reparse the PDF.
- Preview mutations must be reversible and reload only affected pages.
- Preserve existing text replacement, formatting, annotations, save recovery, and reading behavior.

---

### Task 1: Define Generic PDF Page Objects and Affine Operations

**Files:**
- Create: `lib/src/features/workspace/domain/pdf_page_object.dart`
- Modify: `lib/src/features/workspace/domain/pdf_text_types.dart`
- Test: `test/workspace_pdf/pdf_page_object_test.dart`

**Interfaces:**
- Consumes: existing `PdfBox`, `PdfTransform`, and typed `PdfEditFailure` values.
- Produces: `PdfPageObjectType`, `PdfPageObjectCapability`, `PdfPageObjectLocator`, `PdfPageObject`, and affine helpers `translated`, `scaledAround`, `rotatedAround`, `inverseTransformPoint`.

- [ ] **Step 1: Write failing value and matrix tests**

```dart
test('rotation preserves scale and rotates around the requested center', () {
  const source = PdfTransform(2, 0, 0, 3, 20, 30);
  final rotated = source.rotatedAround(
    radians: math.pi / 2,
    center: const Offset(50, 60),
  );
  final fixedCenter = rotated.transformPoint(const Offset(50, 60));
  expect(fixedCenter.dx, closeTo(50, 0.0001));
  expect(fixedCenter.dy, closeTo(60, 0.0001));
  expect(rotated.determinant.abs(), closeTo(source.determinant.abs(), 0.0001));
});

test('nested form object is inspectable but not transformable', () {
  final object = fixturePageObject(
    type: PdfPageObjectType.form,
    nested: true,
  );
  expect(object.capabilities, contains(PdfPageObjectCapability.inspect));
  expect(object.capabilities, isNot(contains(PdfPageObjectCapability.move)));
  expect(object.readOnlyReason, PdfPageObjectReadOnlyReason.sharedFormObject);
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_page_object_test.dart`

Expected: compilation fails because generic page-object types and affine helpers do not exist.

- [ ] **Step 3: Implement immutable page-object values**

```dart
enum PdfPageObjectType { text, image, path, form }
enum PdfPageObjectCapability { inspect, editText, move, resize, rotate }
enum PdfPageObjectReadOnlyReason { sharedFormObject, unsupportedType, singularTransform }

final class PdfPageObjectLocator {
  PdfPageObjectLocator({
    required this.pageNumber,
    required List<int> objectPath,
    required this.type,
    required this.contentDigest,
    required this.geometryDigest,
    required this.sourceRevision,
  }) : objectPath = List<int>.unmodifiable(objectPath);
  // Value equality and immutable fields.
}

final class PdfPageObject {
  PdfPageObject({
    required this.locator,
    required this.bounds,
    required this.transform,
    required Set<PdfPageObjectCapability> capabilities,
    this.readOnlyReason,
  }) : capabilities = Set.unmodifiable(capabilities);

  final PdfPageObjectLocator locator;
  final PdfBox bounds;
  final PdfTransform transform;
  final Set<PdfPageObjectCapability> capabilities;
  final PdfPageObjectReadOnlyReason? readOnlyReason;
}
```

Implement matrix multiplication, determinant validation, point conversion,
translation, scaling around a center, and rotation around a center without
decomposing the source matrix.

- [ ] **Step 4: Run the domain tests**

Run: `flutter test test/workspace_pdf/pdf_page_object_test.dart test/workspace_pdf/pdf_edit_intent_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/domain/pdf_page_object.dart lib/src/features/workspace/domain/pdf_text_types.dart test/workspace_pdf/pdf_page_object_test.dart
git commit -m "feat: model native PDF page objects"
```

---

### Task 2: Discover and Resolve Top-Level Native Objects

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/pdf_text_engine.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart`
- Create: `test/workspace_pdf/pdf_page_object_engine_test.dart`
- Modify: `test/support/pdf_text_fixture.dart`

**Interfaces:**
- Consumes: Task 1 page-object types.
- Produces: `PdfTextEngine.inspectPageObjects(...)` and `resolvePageObject(...)` with stable native locators.

- [ ] **Step 1: Add failing native discovery tests**

```dart
test('discovers top-level text image and path objects by native type', () async {
  final fixture = await PdfTextFixture.mixedPageObjects();
  final document = await PdfDocument.openFile(fixture.path);
  final objects = await const PdfiumTextEngine().inspectPageObjects(
    document: document,
    sourceRevision: await sha256File(fixture),
    pageNumbers: const <int>[1],
  );
  expect(objects.map((item) => item.locator.type), containsAll(<PdfPageObjectType>{
    PdfPageObjectType.text,
    PdfPageObjectType.image,
    PdfPageObjectType.path,
  }));
});

test('marks objects inside a form as shared and read-only', () async {
  final objects = await inspectFixture(PdfTextFixture.sharedForm());
  expect(
    objects.where((item) => item.locator.objectPath.length > 1),
    everyElement(
      predicate<PdfPageObject>((item) =>
        item.readOnlyReason == PdfPageObjectReadOnlyReason.sharedFormObject),
    ),
  );
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_page_object_engine_test.dart`

Expected: compilation fails because the engine methods and fixtures are absent.

- [ ] **Step 3: Add engine contracts and PDFium discovery**

```dart
abstract interface class PdfTextEngine {
  Future<List<PdfPageObject>> inspectPageObjects({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  });

  Future<PdfPageObject> resolvePageObject({
    required PdfDocument document,
    required PdfPageObjectLocator locator,
  });
}
```

Use `FPDFPage_CountObjects`, `FPDFPage_GetObject`,
`FPDFPageObj_GetType`, `FPDFPageObj_GetBounds`, and
`FPDFPageObj_GetMatrix`. Recurse through forms only to expose locked inspection
objects. Hash type-specific stable content plus quantized geometry. Do not
grant transform capabilities to nested paths.

- [ ] **Step 4: Run native discovery and existing text tests**

Run: `flutter test test/workspace_pdf/pdf_page_object_engine_test.dart test/workspace_pdf/pdfium_text_engine_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdf_text_engine.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart test/support/pdf_text_fixture.dart test/workspace_pdf/pdf_page_object_engine_test.dart
git commit -m "feat: discover native PDF page objects"
```

---

### Task 3: Add Generic Transform Intents and Lossless History

**Files:**
- Modify: `lib/src/features/workspace/domain/pdf_edit_intent.dart`
- Modify: `lib/src/features/workspace/domain/pdf_edit_command.dart`
- Modify: `lib/src/features/workspace/domain/pdf_edit_session.dart`
- Modify: `lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart`
- Test: `test/workspace_pdf/pdf_page_object_command_test.dart`
- Modify: `test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart`

**Interfaces:**
- Consumes: Task 1 object locator and matrix values.
- Produces: `MovePdfPageObjectIntent`, `ResizePdfPageObjectIntent`, `RotatePdfPageObjectIntent`, and `TransformPdfPageObjectCommand`.

- [ ] **Step 1: Write failing exact-matrix history tests**

```dart
test('rotate undo and redo restore exact affine matrices', () async {
  final controller = controllerWithObject(transform: skewedTransform);
  final result = await controller.dispatch(
    RotatePdfPageObjectIntent(
      documentId: 'doc',
      documentRevision: 'rev',
      locator: objectLocator,
      radians: math.pi / 6,
    ),
    provenance: PdfCommandProvenance.manual,
  );
  expect(result.isSuccess, isTrue);
  final rotated = controller.sessionFor('tab').pageObjects.single.transform;
  await controller.undo('tab');
  expect(controller.sessionFor('tab').pageObjects.single.transform, skewedTransform);
  await controller.redo('tab');
  expect(controller.sessionFor('tab').pageObjects.single.transform, rotated);
});

test('nested form transform fails before history mutation', () async {
  final result = await dispatchMove(nestedFormLocator);
  expect(result.failure, isA<PdfReadOnlyPageObjectFailure>());
  expect(session.commands, isEmpty);
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_page_object_command_test.dart`

Expected: compilation fails for missing intents, command, and `pageObjects` session state.

- [ ] **Step 3: Extend the session and dispatcher**

Add `List<PdfPageObject> pageObjects` to `PdfEditingSession`. Implement one
generic command:

```dart
final class TransformPdfPageObjectCommand extends PdfEditCommand {
  const TransformPdfPageObjectCommand({
    required super.id,
    required super.provenance,
    required this.locator,
    required this.before,
    required this.after,
    required super.summary,
  });
  final PdfPageObjectLocator locator;
  final PdfTransform before;
  final PdfTransform after;
}
```

The dispatcher resolves the object, validates the relevant capability, derives
the exact target matrix, rejects non-finite or singular matrices, and emits one
command per completed gesture. Retain old text move/resize intents temporarily
as adapters so existing callers remain source-compatible until Task 7.

- [ ] **Step 4: Run history and existing session tests**

Run: `flutter test test/workspace_pdf/pdf_page_object_command_test.dart test/workspace_pdf/pdf_edit_session_test.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/domain/pdf_edit_intent.dart lib/src/features/workspace/domain/pdf_edit_command.dart lib/src/features/workspace/domain/pdf_edit_session.dart lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart test/workspace_pdf/pdf_page_object_command_test.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart
git commit -m "feat: add PDF object transform history"
```

---

### Task 4: Build the Reversible Native Preview Controller

**Files:**
- Create: `lib/src/features/workspace/infrastructure/pdf_preview_document_controller.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdf_text_engine.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart`
- Test: `test/workspace_pdf/pdf_preview_document_controller_test.dart`
- Create: `test/workspace_pdf/pdf_native_text_suppression_test.dart`

**Interfaces:**
- Consumes: Task 2 object resolution and Task 3 session matrices.
- Produces: `PdfPreviewDocumentController.suppressText`, `restoreSuppressedText`, `previewTransform`, `rebuildFromSession`, and `clear`.

- [ ] **Step 1: Write failing controller-order tests**

```dart
test('suppression reloads the affected page before editor visibility', () async {
  final events = <String>[];
  final controller = PdfPreviewDocumentController(
    mutate: fakeMutator(events),
    reloadPages: (pages) async => events.add('reload:${pages.single}'),
  );
  await controller.suppressText(document, block);
  expect(events, <String>['hide-native', 'generate:1', 'reload:1']);
});

test('changing selection restores the previous render modes', () async {
  await controller.suppressText(document, firstBlock);
  await controller.suppressText(document, secondBlock);
  expect(nativeRenderMode(firstObject), originalRenderMode);
  expect(nativeRenderMode(secondObject), FPDF_TEXTRENDERMODE_INVISIBLE);
});
```

- [ ] **Step 2: Run controller tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_preview_document_controller_test.dart`

Expected: compilation fails because the preview controller is absent.

- [ ] **Step 3: Implement native preview primitives**

Add engine methods that execute inside `useNativeDocumentHandle`:

```dart
Future<List<int>> setTextObjectsVisible({
  required PdfDocument document,
  required PdfTextBlock block,
  required bool visible,
});

Future<void> setPageObjectPreviewTransform({
  required PdfDocument document,
  required PdfPageObjectLocator locator,
  required PdfTransform transform,
});
```

Record every original text render mode before setting
`FPDF_TEXTRENDERMODE_INVISIBLE`. Restore exact modes rather than assuming fill.
Call `FPDFPage_GenerateContent`, then `document.reloadPages` for only the
affected page numbers. Serialize preview mutations per document to prevent
overlapping native writes.

- [ ] **Step 4: Add native render-mode restoration test**

The test opens a real text fixture, suppresses a block, confirms invisible
render mode through PDFium, restores it, and confirms the original mode and
extractable text remain unchanged. It must not write fixture bytes.

- [ ] **Step 5: Run preview and native tests**

Run: `flutter test test/workspace_pdf/pdf_preview_document_controller_test.dart test/workspace_pdf/pdf_native_text_suppression_test.dart test/workspace_pdf/pdfium_text_engine_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdf_preview_document_controller.dart lib/src/features/workspace/infrastructure/pdf_text_engine.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_stub.dart test/workspace_pdf/pdf_preview_document_controller_test.dart test/workspace_pdf/pdf_native_text_suppression_test.dart
git commit -m "feat: preview native PDF edits in memory"
```

---

### Task 5: Coordinate Preview State with Editing Sessions

**Files:**
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Test: `test/workspace_pdf/pdf_editing_preview_lifecycle_test.dart`

**Interfaces:**
- Consumes: Task 4 preview controller.
- Produces: asynchronous selection APIs `selectTextBlock`, `selectPageObject`, `clearSelection`, plus preview rebuild after undo/redo and cleanup on mode exit/save/tab close.

- [ ] **Step 1: Write failing lifecycle tests**

```dart
test('selecting text suppresses native glyphs before publishing selection', () async {
  final events = <String>[];
  final controller = editingController(previewEvents: events);
  await controller.selectTextBlock('tab', document, block.locator);
  expect(events, <String>['suppress', 'selection-published']);
});

test('undo rebuilds preview from the authoritative session', () async {
  await controller.previewTransform('tab', document, movedObject);
  await controller.undo('tab', document: document);
  expect(preview.lastMatrix, originalMatrix);
});

test('leaving edit mode restores all native objects', () async {
  await controller.leaveObjectMode('tab', document);
  expect(preview.isClear, isTrue);
});
```

- [ ] **Step 2: Run lifecycle tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_editing_preview_lifecycle_test.dart`

Expected: compilation fails because current selection and undo APIs do not coordinate preview state.

- [ ] **Step 3: Implement lifecycle orchestration**

Inject `PdfPreviewDocumentController` into `PdfEditingController`. Convert
selection and clearing methods to futures and ensure preview mutation finishes
before notifying listeners. On undo/redo, rebuild changed page previews from
the new session. Before Save, restore native preview mutations so the save
engine applies commands once to a clean working copy. After save/reload, clear
preview bookkeeping.

- [ ] **Step 4: Run controller and workspace tests**

Run: `flutter test test/workspace_pdf/pdf_editing_preview_lifecycle_test.dart test/workspace_pdf/pdf_edit_shortcuts_test.dart test/workspace_pdf/pdf_edit_save_service_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/application/workspace_providers.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_pdf/pdf_editing_preview_lifecycle_test.dart
git commit -m "feat: coordinate PDF preview edit lifecycle"
```

---

### Task 6: Replace the Doubled Text Field with a Transform-Aware Editor

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/pdf_inline_text_editor.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Create: `test/workspace_pdf/pdf_inline_text_geometry_test.dart`
- Modify: `test/workspace_pdf/pdf_text_editor_overlay_test.dart`
- Modify: `test/workspace_pdf/pdf_text_inline_edit_test.dart`

**Interfaces:**
- Consumes: Task 5 async selection lifecycle and native suppression status.
- Produces: `PdfInlineTextGeometry.resolve(...)` and `PdfInlineTextEditor` that appears only after native suppression succeeds.

- [ ] **Step 1: Write failing geometry and ordering tests**

```dart
test('maps PDF font points baseline and rotation into page overlay space', () {
  final geometry = PdfInlineTextGeometry.resolve(
    block: rotatedBlock,
    pageSize: const Size(612, 792),
    overlaySize: const Size(1224, 1584),
  );
  expect(geometry.fontSize, closeTo(24, 0.01));
  expect(geometry.angleRadians, closeTo(rotatedBlock.transform.rotation, 0.01));
  expect(geometry.baselineY, closeTo(expectedBaselineY, 0.01));
});

testWidgets('does not show editor until native glyph suppression completes', (tester) async {
  final suppression = Completer<void>();
  await tester.pumpWidget(editorHarness(onSelect: () => suppression.future));
  await tester.tap(find.byKey(const Key('pdf-text-block-outline')));
  await tester.pump();
  expect(find.byKey(const Key('pdf-inline-text-editor')), findsNothing);
  suppression.complete();
  await tester.pump();
  expect(find.byKey(const Key('pdf-inline-text-editor')), findsOneWidget);
});
```

- [ ] **Step 2: Run widget tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_inline_text_geometry_test.dart test/workspace_pdf/pdf_text_editor_overlay_test.dart`

Expected: fails because the current editor appears immediately and uses raw PDF points.

- [ ] **Step 3: Implement the editor without Material layout offsets**

Use `EditableText` rather than a decorated `TextField`. Resolve page X/Y scale,
baseline, and affine rotation. Apply `Transform` with an explicit origin and a
tight clip matching the transformed block. Keep caret, selection, clipboard,
IME, escape, and Ctrl+Z/Ctrl+Shift+Z behavior. Do not paint an opaque
background or cover rectangle.

- [ ] **Step 4: Gate editor visibility on preview readiness**

Await `selectTextBlock` in `document_workspace.dart`. Publish selected state
only after Task 4 reloads the page. On suppression failure, keep the original
page visible, show the typed failure, and do not create an editor.

- [ ] **Step 5: Run editor and screenshot-relevant tests**

Run: `flutter test test/workspace_pdf/pdf_inline_text_geometry_test.dart test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_text_inline_edit_test.dart test/workspace_pdf/pdf_edit_shortcuts_test.dart`

Expected: PASS; selected text has one editable glyph layer and reading mode has
none.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/presentation/widgets/pdf_inline_text_editor.dart lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart test/workspace_pdf/pdf_inline_text_geometry_test.dart test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_text_inline_edit_test.dart
git commit -m "fix: render one aligned PDF text edit layer"
```

---

### Task 7: Add Oriented Move, Resize, and Rotation Handles

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/pdf_object_transform_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Create: `test/workspace_pdf/pdf_object_transform_overlay_test.dart`
- Modify: `test/workspace_pdf/pdf_text_geometry_edit_test.dart`

**Interfaces:**
- Consumes: generic Task 3 intents and Task 5 preview lifecycle.
- Produces: oriented selection quadrilateral, move area, resize handles, rotation handle, and Shift snapping.

- [ ] **Step 1: Write failing interaction tests**

```dart
testWidgets('rotation handle emits one snapped rotate intent', (tester) async {
  final intents = <PdfEditIntent>[];
  await tester.pumpWidget(transformHarness(object: rotatedImage, onIntent: intents.add));
  await tester.drag(
    find.byKey(const Key('pdf-rotate-handle')),
    const Offset(30, 20),
  );
  expect(intents, hasLength(1));
  expect(intents.single, isA<RotatePdfPageObjectIntent>());
});

testWidgets('locked nested form shows no transform handles', (tester) async {
  await tester.pumpWidget(transformHarness(object: nestedForm));
  expect(find.byKey(const Key('pdf-object-locked')), findsOneWidget);
  expect(find.byKey(const Key('pdf-rotate-handle')), findsNothing);
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_object_transform_overlay_test.dart`

Expected: compilation fails because the generic overlay is absent.

- [ ] **Step 3: Implement oriented geometry and hit testing**

Transform all four native bounds corners into overlay coordinates. Paint the
quadrilateral and position handles at corners, edge midpoints, and above the
north edge. Inverse-transform pointer positions for hit testing. Calculate
rotation using `atan2(pointer - center)`, preserve the gesture-start matrix,
and snap to `math.pi / 12` when Shift is held.

- [ ] **Step 4: Separate preview updates from command commit**

During pointer movement call `previewTransform` at most once per frame. On
pointer-up emit one generic intent with the final matrix. Escape restores the
gesture-start preview without adding history.

- [ ] **Step 5: Run transform and existing geometry tests**

Run: `flutter test test/workspace_pdf/pdf_object_transform_overlay_test.dart test/workspace_pdf/pdf_text_geometry_edit_test.dart test/workspace_pdf/pdf_page_object_command_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/presentation/widgets/pdf_object_transform_overlay.dart lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart test/workspace_pdf/pdf_object_transform_overlay_test.dart test/workspace_pdf/pdf_text_geometry_edit_test.dart
git commit -m "feat: transform PDF objects with oriented handles"
```

---

### Task 8: Persist Generic Object Transforms Natively

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart`
- Modify: `test/workspace_pdf/pdf_text_round_trip_test.dart`
- Create: `test/workspace_pdf/pdf_object_transform_round_trip_test.dart`

**Interfaces:**
- Consumes: Task 3 transform commands and Task 2 stable resolution.
- Produces: genuine type-preserving text/image/path matrix persistence and post-save validation.

- [ ] **Step 1: Write failing native round-trip tests**

```dart
test('rotated edited text remains searchable and has the saved matrix', () async {
  final output = await editRotateSaveReopen(textFixture);
  expect(output.extractedText, contains('Changed'));
  expect(output.object.locator.type, PdfPageObjectType.text);
  expect(output.object.transform, approximately(expectedMatrix));
});

for (final type in <PdfPageObjectType>[PdfPageObjectType.image, PdfPageObjectType.path]) {
  test('$type retains type after move and rotation', () async {
    final output = await transformSaveReopen(type);
    expect(output.object.locator.type, type);
    expect(output.object.transform, approximately(expectedMatrix));
  });
}
```

- [ ] **Step 2: Run round-trip tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_object_transform_round_trip_test.dart`

Expected: fails because save applies only text-block geometry commands.

- [ ] **Step 3: Apply exact matrices to clean working-copy objects**

Group active `TransformPdfPageObjectCommand` values by page, resolve their
locators, call `FPDFPageObj_SetMatrix`, then `FPDFPage_GenerateContent` once per
page. Text reconstruction must use the command's final object matrix instead of
re-deriving translation from axis-aligned bounds.

- [ ] **Step 4: Extend validation**

After reopening the working file, inspect each changed object and compare type
and matrix within a quantization tolerance. Continue validating edited text by
extraction. Throw `PdfValidationFailure` before replacement on any mismatch.

- [ ] **Step 5: Run save and round-trip suites**

Run: `flutter test test/workspace_pdf/pdf_object_transform_round_trip_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart test/workspace_pdf/pdf_edit_save_service_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart test/workspace_pdf/pdf_text_round_trip_test.dart test/workspace_pdf/pdf_object_transform_round_trip_test.dart
git commit -m "feat: save genuine PDF object transforms"
```

---

### Task 9: Expose Generic Object Tools and Permissions

**Files:**
- Modify: `lib/src/features/workspace/application/ai_tool_registry.dart`
- Modify: `lib/src/features/workspace/application/action_permission_service.dart`
- Modify: `test/workspace_ai/ai_tool_registry_test.dart`
- Modify: `test/workspace_ai/action_permission_service_test.dart`

**Interfaces:**
- Consumes: Task 3 generic intents and object locators.
- Produces: `inspect_pdf_page_objects`, `move_pdf_page_object`, `resize_pdf_page_object`, and `rotate_pdf_page_object` strict AI tools.

- [ ] **Step 1: Write failing schema and execution tests**

```dart
test('exposes strict generic object transform schemas', () {
  expect(AiToolRegistry.names, containsAll(<String>{
    'inspect_pdf_page_objects',
    'move_pdf_page_object',
    'resize_pdf_page_object',
    'rotate_pdf_page_object',
  }));
  expect(schema('rotate_pdf_page_object').additionalProperties, isFalse);
});

test('agent rotation uses dispatcher and is classified risky', () async {
  final result = await registry.execute(rotationCall, allowedDocumentIds: {'doc'});
  expect(result['permission'], 'required');
  expect(permissionPreview, contains('rotates page content'));
});
```

- [ ] **Step 2: Run AI tests and verify RED**

Run: `flutter test test/workspace_ai/ai_tool_registry_test.dart test/workspace_ai/action_permission_service_test.dart`

Expected: fails because the new tools and risk descriptions are absent.

- [ ] **Step 3: Implement strict tool contracts**

Use the full generic object locator schema. Move/resize accept an exact six
component `matrix`; rotate accepts `radians` and optional center coordinates.
Reject unknown keys and non-finite values. Return updated revision, command IDs,
and the resulting matrix.

- [ ] **Step 4: Mark every generic layout transform risky**

Update risk classification and human-readable permission previews for move,
resize, and rotate. Existing workspace/document/session grant semantics remain
unchanged.

- [ ] **Step 5: Run AI and dispatcher suites**

Run: `flutter test test/workspace_ai/ai_tool_registry_test.dart test/workspace_ai/action_permission_service_test.dart test/workspace_pdf/pdf_edit_intent_dispatcher_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/application/ai_tool_registry.dart lib/src/features/workspace/application/action_permission_service.dart test/workspace_ai/ai_tool_registry_test.dart test/workspace_ai/action_permission_service_test.dart
git commit -m "feat: expose native PDF object transform tools"
```

---

### Task 10: Integrate Object Mode, Recovery, and Cleanup

**Files:**
- Modify: `lib/src/features/workspace/domain/pdf_text_types.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_body.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Create: `test/workspace_pdf/pdf_object_mode_test.dart`
- Modify: `test/workspace_pdf/pdf_edit_conflict_dialog_test.dart`

**Interfaces:**
- Consumes: Tasks 4–9 complete object-editing stack.
- Produces: user-visible object mode, locked-object feedback, typed preview recovery, and deterministic cleanup on tab/mode/app lifecycle events.

- [ ] **Step 1: Write failing mode and recovery tests**

```dart
testWidgets('reading mode removes every object bound and handle', (tester) async {
  await tester.pumpWidget(workspaceHarness(mode: PdfEditingMode.reading));
  expect(find.byKey(const Key('pdf-page-object-outline')), findsNothing);
  expect(find.byKey(const Key('pdf-rotate-handle')), findsNothing);
});

testWidgets('preview failure leaves native page visible and offers retry', (tester) async {
  await tester.pumpWidget(workspaceHarness(previewFailure: previewFailure));
  await tester.tap(find.byKey(const Key('pdf-page-object-outline')));
  await tester.pumpAndSettle();
  expect(find.text('Could not prepare the PDF edit preview.'), findsOneWidget);
  expect(find.text('Retry'), findsOneWidget);
  expect(find.byKey(const Key('pdf-inline-text-editor')), findsNothing);
});
```

- [ ] **Step 2: Run integration widget tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_object_mode_test.dart test/workspace_pdf/pdf_edit_conflict_dialog_test.dart`

Expected: fails because object mode and preview failure presentation are not integrated.

- [ ] **Step 3: Rename and integrate object-edit mode**

Replace the text-only mode label with object editing while retaining a
deprecated enum adapter for persisted state. Discover both text blocks and page
objects on visible pages. Display type-aware locked reasons. Ensure tab close,
mode exit, reload, save, source conflict, and widget disposal all call preview
cleanup before disposing the PDF document.

- [ ] **Step 4: Add typed preview recovery**

Map preview failures to retry, rediscover object, or leave edit mode. Recovery
must preserve draft commands and must not mark the document clean.

- [ ] **Step 5: Run object-mode and workspace tests**

Run: `flutter test test/workspace_pdf/pdf_object_mode_test.dart test/workspace_pdf/pdf_edit_conflict_dialog_test.dart test/workspace_pdf/pdf_edit_shortcuts_test.dart test/workspace_ai/desktop_window_chrome_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/domain/pdf_text_types.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_pdf/pdf_object_mode_test.dart test/workspace_pdf/pdf_edit_conflict_dialog_test.dart
git commit -m "feat: integrate native PDF object edit mode"
```

---

### Task 11: Qualify Performance and End-to-End Behavior

**Files:**
- Modify: `test/workspace_pdf/pdf_text_performance_test.dart`
- Create: `integration_test/pdf_object_editing_test.dart`
- Modify: `README.md`

**Interfaces:**
- Consumes: complete native object-editing stack.
- Produces: explicit preview latency budgets, full Windows acceptance, and user-facing supported-object documentation.

- [ ] **Step 1: Add failing performance assertions**

```dart
test('warm text suppression and one-page reload meets one-frame budget', () async {
  await warmPreview(fixture);
  final stopwatch = Stopwatch()..start();
  await preview.suppressText(document, block);
  stopwatch.stop();
  expect(stopwatch.elapsedMicroseconds, lessThan(16667));
});

test('typing and gesture previews never encode the PDF', () async {
  await typeAndRotate(countingEngine);
  expect(countingEngine.encodeCalls, 0);
  expect(countingEngine.inspectCallsDuringTyping, 0);
});
```

- [ ] **Step 2: Run performance tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_text_performance_test.dart`

Expected: the new assertions fail until preview invalidation and coalescing are
fully wired.

- [ ] **Step 3: Add Windows interaction acceptance**

The integration test opens a mixed fixture, enters object mode, selects text,
asserts native suppression completes before the editor appears, replaces text,
rotates it, moves an image, rotates a path, undoes/redoes, saves, reopens, and
asserts genuine text extraction plus retained image/path types. It exits to
reading mode and asserts no bounds remain.

- [ ] **Step 4: Document supported and locked object types**

Update README to state that top-level text, image, and paths may be transformed,
nested/shared forms remain locked, the source is unchanged until validated
save, and text editing uses native glyph suppression rather than cover shapes.

- [ ] **Step 5: Run full verification**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter test integration_test/pdf_object_editing_test.dart -d windows
cargo fmt --check --manifest-path rust/clarix_pdf_oxide/Cargo.toml
cargo clippy --manifest-path rust/clarix_pdf_oxide/Cargo.toml -- -D warnings
cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml
```

Expected: every command exits 0. If the Windows integration build exceeds an
automation time limit, run the exact command interactively and retain its full
exit output as the release gate; do not treat timeout as success.

- [ ] **Step 6: Manually verify the reported fixture**

Open `Unit 6 - Foundations of Organisational Design.pdf`, select the question
block shown in the defect report, and confirm there is only one glyph layer at
151% zoom. Save a copy, reopen it in Clarix and one external reader, and confirm
the edited text is selectable/searchable and transformed objects retain type.

- [ ] **Step 7: Commit**

```powershell
git add test/workspace_pdf/pdf_text_performance_test.dart integration_test/pdf_object_editing_test.dart README.md
git commit -m "test: qualify native PDF object editing"
```

---

## Review Gates

- Tasks 1–3 establish the generic immutable domain and must pass before native
  preview work begins.
- Task 4 is the doubled-glyph feasibility gate: do not change the UI until a
  real native fixture proves suppression and exact restoration.
- Task 6 must demonstrate that editor visibility follows successful native
  suppression; a cover rectangle is not an acceptable fallback.
- Task 8 is the persistence gate: do not expose generic agent tools until
  genuine type-preserving native round trips pass.
- Task 11 is the release gate: the reported PDF must be manually checked at the
  reported zoom and the saved result must pass external-reader selection and
  search.
