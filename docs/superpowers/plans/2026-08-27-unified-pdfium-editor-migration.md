# Unified PDFium Editor Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Clarix editing to one long-lived PDFium document per tab so visible rendering, physical mutation, undo/redo, and save share the same state.

**Architecture:** Dart owns `LivePdfiumSession` and serializes PDFium calls on pdfrx's worker. Rust continues to own semantic commands, transactions, and AI validation, emitting physical edit plans keyed by stable semantic IDs and PDFium locators. Flutter renders dirty tile images from the live session while retaining only interaction chrome as overlays.

**Tech Stack:** Flutter/Dart, pdfrx, pdfium_dart/pdfium_flutter FFI, Flutter Rust Bridge, Rust editing core, Flutter integration tests.

**Spec:** `docs/superpowers/specs/2026-08-27-unified-pdfium-editor-design.md`

## Global Constraints

* Keep exactly one live PDFium document owner for each editor tab.
* Run every PDFium operation on pdfrx's owning worker; never transfer native handles across isolates.
* Preserve existing UUID semantic object IDs, command schema, AI approval behavior, and monotonic revisions.
* A command is atomic: failed object resolution, font preparation, or mutation must retain the prior revision and raster state.
* Do not scan every page when edit mode starts; index visible pages plus adjacent pages first.
* Do not use Flutter replacement text or clean patches as the durable visual representation of an edit.
* Regenerate page content before releasing the loaded `FPDF_PAGE` that owns a
  mutation. The bundled PDFium runtime loses deferred text changes after that
  handle closes; debounce only inside a same-page transaction that retains the
  handle.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart` | Owns one `PdfDocument`, physical locators, tile cache, mutable PDFium state, commit, save, and disposal. |
| `lib/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart` | Renders and invalidates revision-keyed PDFium tiles without UI dependencies. |
| `lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart` | Resolves physical locators and applies atomic PDFium plans. |
| `lib/src/core/editing/live_pdfium_editor_port.dart` | Composes the Rust semantic port with the live Dart PDFium session behind `NativeEditorPort`. |
| `lib/src/core/editing/editor_bridge_types.dart` | Adds transport-safe physical locator, tile, and invalidation types. |
| `lib/src/features/pdf_editor/presentation/live_pdfium_tile_layer.dart` | Decodes and displays a dirty PDFium tile in page coordinates. |
| `lib/src/features/pdf_editor/presentation/page_edit_scene.dart` | Removes edited text/clean-patch rendering once live tiles are available; keeps selection chrome and controls. |
| `lib/src/features/pdf_editor/presentation/page_scene_host.dart` | Requests/reclaims visible live tiles rather than clean patches. |
| `lib/src/features/reader/presentation/reader_viewer_pane.dart` | Composites live tiles over pdfrx pages and routes viewport scale/rect changes. |
| `rust/clarix_editing_core/src/ports.rs` | Defines physical locator and edit-plan ports consumed by semantic transaction handling. |
| `rust/clarix_editing_core/src/session.rs` | Produces forward/inverse physical edit plans with transaction revisions. |
| `rust/clarix_pdf_oxide/src/editing_api.rs` | Exposes semantic plans/locator bindings over FRB; removes PDF materialization from supported save commands. |
| `lib/src/core/ffi/editing_api.dart`, `lib/src/core/ffi/frb_generated*.dart`, `rust/clarix_pdf_oxide/src/frb_generated.rs` | Generated and hand-authored Flutter Rust Bridge contract artifacts. |

## Task 1: Add transport-safe physical locator and tile contracts

**Files:**
- Modify: `lib/src/core/editing/editor_bridge_types.dart`
- Modify: `lib/src/core/ffi/editing_api.dart`
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs`
- Regenerate: `lib/src/core/ffi/frb_generated.dart`, `lib/src/core/ffi/frb_generated.io.dart`, `lib/src/core/ffi/frb_generated.web.dart`, `rust/clarix_pdf_oxide/src/frb_generated.rs`
- Test: `test/core/editing/editor_bridge_contract_test.dart`
- Test: `rust/clarix_pdf_oxide/tests/editing_bridge.rs`

**Interfaces:**
- Produces Dart `EditorPhysicalLocator`, `EditorDirtyTile`, and `EditorTileInvalidation`.
- Produces Rust `NativePhysicalLocator`, `NativeDirtyTile`, and `NativeTileInvalidation` as FRB-safe value types.
- `EditorSceneObject.physicalLocator` is nullable only during legacy fallback.

- [ ] **Step 1: Write the failing Dart contract test**

```dart
test('maps a recursive physical locator and dirty tile without loss', () {
  const locator = EditorPhysicalLocator(
    pageNumber: 4,
    objectPath: <int>[5, 12, 3],
    objectType: 'text',
    sourceFingerprint: 'a' * 64,
    objectRevision: 7,
  );
  expect(locator.objectPath, <int>[5, 12, 3]);
  expect(locator.objectRevision, 7);
});
```

- [ ] **Step 2: Run the Dart test to verify it fails**

Run: `flutter test --no-pub test/core/editing/editor_bridge_contract_test.dart`

Expected: FAIL because `EditorPhysicalLocator` is undefined.

- [ ] **Step 3: Write the failing Rust bridge round-trip test**

```rust
#[test]
fn native_scene_object_includes_recursive_physical_locator() {
    let locator = NativePhysicalLocator {
        page_number: 4,
        object_path: vec![5, 12, 3],
        object_type: "text".into(),
        source_fingerprint: "a".repeat(64),
        object_revision: 7,
    };
    assert_eq!(locator.object_path, vec![5, 12, 3]);
}
```

- [ ] **Step 4: Run the Rust test to verify it fails**

Run: `cargo test -p clarix_pdf_oxide native_scene_object_includes_recursive_physical_locator`

Expected: FAIL because `NativePhysicalLocator` is undefined.

- [ ] **Step 5: Implement the value types and map them through the bridge**

```dart
final class EditorPhysicalLocator {
  const EditorPhysicalLocator({
    required this.pageNumber,
    required this.objectPath,
    required this.objectType,
    required this.sourceFingerprint,
    required this.objectRevision,
  });
  final int pageNumber;
  final List<int> objectPath;
  final String objectType;
  final String sourceFingerprint;
  final int objectRevision;
}
```

Add the matching Rust struct, place it on `NativeSceneObject`, map it in
`_sceneObjectFromNative`, then run `flutter_rust_bridge_codegen generate` from
the repository root. Do not hand-edit generated FRB code except where the
project generator requires an explicit registration change.

- [ ] **Step 6: Run contract tests**

Run: `flutter test --no-pub test/core/editing/editor_bridge_contract_test.dart; cargo test -p clarix_pdf_oxide native_scene_object_includes_recursive_physical_locator`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/src/core/editing/editor_bridge_types.dart lib/src/core/ffi/editing_api.dart lib/src/core/ffi/frb_generated.dart lib/src/core/ffi/frb_generated.io.dart lib/src/core/ffi/frb_generated.web.dart rust/clarix_pdf_oxide/src/editing_api.rs rust/clarix_pdf_oxide/src/frb_generated.rs test/core/editing/editor_bridge_contract_test.dart rust/clarix_pdf_oxide/tests/editing_bridge.rs
git commit -m "feat: expose physical PDF object locators"
```

## Task 2: Build an isolated revision-keyed live PDFium tile renderer

**Files:**
- Create: `lib/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart`
- Test: `test/pdf_editor/domain_infrastructure/live_pdfium_tile_renderer_test.dart`
- Modify: `lib/src/features/pdf_editor/infrastructure/pdfium_worker_executor.dart`

**Interfaces:**
- Consumes `PdfDocument`, `EditorPdfBox`, page number, scale, and revision.
- Produces `LivePdfiumTile { pageNumber, revision, bounds, width, height, rgbaBytes }`.
- `invalidate(pageNumber, bounds, revision)` only discards cache entries whose rectangles intersect `bounds` on the same page.

- [ ] **Step 1: Write the failing tile-cache tests**

```dart
test('returns the cached tile for an identical revision key', () async {
  final first = await renderer.render(request);
  final second = await renderer.render(request);
  expect(second.rgbaBytes, orderedEquals(first.rgbaBytes));
  expect(renderer.renderCount, 1);
});

test('invalidates only intersecting tiles on the changed page', () async {
  renderer.invalidate(pageNumber: 1, bounds: changed, revision: 2);
  expect(renderer.contains(page: 1, bounds: overlapping, revision: 1), isFalse);
  expect(renderer.contains(page: 2, bounds: overlapping, revision: 1), isTrue);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/live_pdfium_tile_renderer_test.dart`

Expected: FAIL because `LivePdfiumTileRenderer` is undefined.

- [ ] **Step 3: Implement PDFium-worker tile rendering and bounded LRU storage**

```dart
Future<LivePdfiumTile> render(LivePdfiumTileRequest request) =>
    _worker.run(document: _document, message: request, callback: _renderTile);

void invalidate({required int pageNumber, required EditorPdfBox bounds, required int revision}) {
  _cache.removeWhere((key, _) => key.pageNumber == pageNumber &&
      key.revision < revision && key.bounds.intersects(bounds));
}
```

Use PDFium bitmap rendering inside the owning worker, copy pixels to a Dart
`Uint8List`, and release every bitmap/page handle in `finally`. Enforce a
byte-budgeted LRU cache; cache keys are page, revision, scale, and PDF-space
tile rectangle.

- [ ] **Step 4: Run tile renderer tests**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/live_pdfium_tile_renderer_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart lib/src/features/pdf_editor/infrastructure/pdfium_worker_executor.dart test/pdf_editor/domain_infrastructure/live_pdfium_tile_renderer_test.dart
git commit -m "feat: render revision-keyed PDFium tiles"
```

## Task 3: Implement live PDFium session and atomic single-object replacement

**Files:**
- Create: `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart`
- Create: `lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart`
- Modify: `lib/src/features/pdf_editor/infrastructure/pdfium_text_engine_native.dart`
- Test: `test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart`
- Test: `integration_test/live_pdfium_text_editing_test.dart`

**Interfaces:**
- `LivePdfiumSession.open(String sourcePath)` owns a `PdfDocument` and `LivePdfiumTileRenderer`.
- `Future<LiveApplyResult> apply(LivePdfiumEditPlan plan)` returns `revision`, `dirtyTiles`, and refreshed scene objects.
- `Future<void> commit(Set<int> dirtyPages)` calls `FPDFPage_GenerateContent` exactly once per page.
- `Future<Uint8List> save()` commits dirty pages and returns PDF bytes.

- [ ] **Step 1: Write the failing live-render regression test**

```dart
test('a text replacement changes a live PDFium tile before commit', () async {
  final session = await LivePdfiumSession.open(fixture.path);
  final before = await session.renderTile(requestFor('Original'));
  final result = await session.apply(replaceWholeObject('Original', 'Changed'));
  final after = await session.renderTile(requestFor('Changed'));
  expect(after.rgbaBytes, isNot(orderedEquals(before.rgbaBytes)));
  expect(result.dirtyPages, {1});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart`

Expected: FAIL because `LivePdfiumSession` is undefined.

- [ ] **Step 3: Implement plan resolution and all-or-nothing mutation**

```dart
Future<LiveApplyResult> apply(LivePdfiumEditPlan plan) async {
  final resolved = await _resolveAll(plan.operations);
  final inverse = _captureInverse(resolved);
  try {
    await _applyResolved(resolved);
  } catch (_) {
    await _restore(inverse);
    rethrow;
  }
  return _advanceRevisionAndInvalidate(plan, resolved);
}
```

For the first slice accept only a single editable `FPDF_PAGEOBJ_TEXT` locator
with one object path and an existing reusable font. Call `FPDFText_SetText` on
the physical object, then `FPDFPage_GenerateContent` before closing that page
handle. Render the changed tile through the same native document and worker.

- [ ] **Step 4: Add the failing save/reopen test**

```dart
test('commit and save preserve searchable replacement text', () async {
  await session.apply(replaceWholeObject('Original', 'Changed'));
  final bytes = await session.save();
  final reopened = await PdfDocument.openData(bytes);
  expect((await reopened.pages.single.loadText())!.fullText, contains('Changed'));
});
```

- [ ] **Step 5: Implement commit/save and stale-locator rejection**

Commit every page in the session dirty set, encode only after successful page
generation, and clear the dirty set only after encoding succeeds. Compare page
number, object path, type, fingerprint, and revision before mutation. On a
stale locator, reinspect that page once; only rebind when its physical
fingerprint and semantic text match exactly.

- [ ] **Step 6: Run unit and integration tests**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart integration_test/live_pdfium_text_editing_test.dart`

Expected: PASS; the integration test must raster-diff before/after tiles and
verify no document reopen occurred before the first tile diff.

- [ ] **Step 7: Commit**

```bash
git add lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart lib/src/features/pdf_editor/infrastructure/pdfium_text_engine_native.dart test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart integration_test/live_pdfium_text_editing_test.dart
git commit -m "feat: apply text edits to a live PDFium session"
```

## Task 4: Connect Rust semantic transactions to Dart live edit plans

**Files:**
- Modify: `rust/clarix_editing_core/src/ports.rs`
- Modify: `rust/clarix_editing_core/src/session.rs`
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs`
- Create: `lib/src/core/editing/live_pdfium_editor_port.dart`
- Modify: `lib/src/core/editing/editor_bridge.dart`
- Test: `rust/clarix_editing_core/tests/command_session.rs`
- Test: `test/core/editing/live_pdfium_editor_port_test.dart`

**Interfaces:**
- Rust produces `PhysicalEditPlan { revision, operations, inverse_operations, affected_bounds }`.
- Dart `LivePdfiumEditorPort implements NativeEditorPort` sends commands to the semantic port, applies returned plans to `LivePdfiumSession`, and reports one durable command result.
- Legacy `FrbNativeEditorPort` remains selectable behind `EditorBackend.legacyMaterializer`.

- [ ] **Step 1: Write the failing semantic-plan test**

```rust
#[test]
fn replace_text_command_emits_forward_and_inverse_physical_plan() {
    let result = session.submit(replace_text_command());
    assert_eq!(result.physical_plan.operations.len(), 1);
    assert_eq!(result.physical_plan.inverse_operations.len(), 1);
}
```

- [ ] **Step 2: Run the Rust test to verify it fails**

Run: `cargo test -p clarix_editing_core replace_text_command_emits_forward_and_inverse_physical_plan`

Expected: FAIL because command results do not expose physical plans.

- [ ] **Step 3: Implement plan production without opening a PDF in Rust**

Add pure data plan types to `ports.rs`. In `session.rs`, produce the forward
and inverse plan from the already validated command and source binding. Do not
call `PdfTextMaterializer`, `lopdf`, or `pdf_oxide` from this path.

- [ ] **Step 4: Write the failing Dart composition test**

```dart
test('applies the semantic plan once and invalidates its affected tile', () async {
  final result = await port.submit(replaceRequest);
  expect(fakeLiveSession.appliedPlans, hasLength(1));
  expect(result.committedRevision, 1);
  expect(fakeLiveSession.invalidatedPages, {1});
});
```

- [ ] **Step 5: Implement `LivePdfiumEditorPort`**

`submit()` must: validate the incoming command via the FRB semantic session,
await `LivePdfiumSession.apply()`, publish object patches and tile invalidation,
then acknowledge the revision. If live application fails, submit the inverse
plan and leave the semantic command uncommitted; use an explicit prepare/apply
semantic port method rather than compensating a committed command.

- [ ] **Step 6: Run semantic and Dart port tests**

Run: `cargo test -p clarix_editing_core replace_text_command_emits_forward_and_inverse_physical_plan; flutter test --no-pub test/core/editing/live_pdfium_editor_port_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add rust/clarix_editing_core/src/ports.rs rust/clarix_editing_core/src/session.rs rust/clarix_editing_core/tests/command_session.rs rust/clarix_pdf_oxide/src/editing_api.rs lib/src/core/editing/live_pdfium_editor_port.dart lib/src/core/editing/editor_bridge.dart test/core/editing/live_pdfium_editor_port_test.dart
git commit -m "feat: route editor transactions through live PDFium"
```

## Task 5: Render live tiles in the production page scene

**Files:**
- Create: `lib/src/features/pdf_editor/presentation/live_pdfium_tile_layer.dart`
- Modify: `lib/src/features/pdf_editor/presentation/page_scene_host.dart`
- Modify: `lib/src/features/pdf_editor/presentation/page_edit_scene.dart`
- Modify: `lib/src/features/reader/presentation/reader_viewer_pane.dart`
- Test: `test/pdf_editor/application_presentation/page_scene_lifecycle_test.dart`
- Test: `test/pdf_editor/application_presentation/live_pdfium_tile_layer_test.dart`

**Interfaces:**
- `PageSceneLifecycle.liveTilesFor(pageNumber)` returns decoded dirty tiles for the current revision.
- `LivePdfiumTileLayer` paints tiles in PDF coordinates and disposes images when their revision leaves the viewport cache.
- `PageEditScene` receives `liveTiles`; when non-empty it must not create `CleanPatchLayer` or `EditorTextObjectLayer` for the same edited object.

- [ ] **Step 1: Write the failing widget test**

```dart
testWidgets('renders a live tile instead of a clean patch for an edited object', (tester) async {
  await tester.pumpWidget(sceneWithLiveTile());
  expect(find.byKey(const Key('live-pdfium-tile')), findsOneWidget);
  expect(find.byKey(const Key('clean-patch-object-1')), findsNothing);
});
```

- [ ] **Step 2: Run the widget test to verify it fails**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/live_pdfium_tile_layer_test.dart`

Expected: FAIL because `LivePdfiumTileLayer` is undefined.

- [ ] **Step 3: Implement tile lifecycle and compositing**

Decode each tile using the existing raw-image discipline from
`CleanPatchDecoder`; key images by `(page, revision, bounds, scale)`. Request
visible tiles at the current zoom, retain them only for visible pages, and
dispose old `ui.Image` objects on invalidation, memory pressure, lifecycle
release, and widget disposal.

- [ ] **Step 4: Remove duplicate edited-text painting for live-backed objects**

Modify `PageEditScene` so caret, selection, outlines, handles, menus, and text
input remain Flutter overlays while PDF glyphs beneath them come only from
`LivePdfiumTileLayer`.

- [ ] **Step 5: Run page lifecycle and widget tests**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/page_scene_lifecycle_test.dart test/pdf_editor/application_presentation/live_pdfium_tile_layer_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/pdf_editor/presentation/live_pdfium_tile_layer.dart lib/src/features/pdf_editor/presentation/page_scene_host.dart lib/src/features/pdf_editor/presentation/page_edit_scene.dart lib/src/features/reader/presentation/reader_viewer_pane.dart test/pdf_editor/application_presentation/page_scene_lifecycle_test.dart test/pdf_editor/application_presentation/live_pdfium_tile_layer_test.dart
git commit -m "feat: display live PDFium edit tiles"
```

## Task 6: Migrate commit/save, undo/redo, and fallback boundaries

**Files:**
- Modify: `lib/src/core/editing/live_pdfium_editor_port.dart`
- Modify: `lib/src/core/editing/editor_bridge.dart`
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs`
- Modify: `rust/clarix_pdf_adapter/src/materializer.rs`
- Modify: `lib/src/features/pdf_editor/application/editor_session_controller.dart`
- Test: `integration_test/phase1_editing_test.dart`
- Test: `test/pdf_editor/application_presentation/save_ui_test.dart`
- Test: `rust/clarix_pdf_oxide/tests/editing_bridge.rs`

**Interfaces:**
- `save()` on the live port commits dirty pages and writes PDFium bytes through the existing atomic-save/recovery destination flow.
- `undo()` and `redo()` apply inverse/forward plans to the same session and return tile invalidations.
- `EditorBackend.livePdfium` is default for supported commands; `legacyMaterializer` is used only after explicit compatibility classification.

- [ ] **Step 1: Write the failing persistence integration test**

```dart
testWidgets('typing then saving reopens with searchable text and no overlay dependency', (tester) async {
  await harness.typeIntoObject('Original', 'Changed');
  await harness.save();
  await harness.reopenSavedPdf();
  expect(await harness.extractedText(), contains('Changed'));
  expect(harness.usedCleanPatchForEditedObject, isFalse);
});
```

- [ ] **Step 2: Run the integration test to verify it fails**

Run: `flutter test --no-pub integration_test/phase1_editing_test.dart`

Expected: FAIL because save still calls the Rust materializer for supported live commands.

- [ ] **Step 3: Implement PDFium-backed save and inverse-plan undo/redo**

Route supported save requests through `LivePdfiumSession.commit()` then PDFium
encoding. Pass bytes to the existing atomic replacement/recovery mechanism so
save UI behavior remains unchanged. Apply undo/redo plans before exposing the
new revision; invalidate only their affected page bounds. Do not close/reopen
the live document in either path.

- [ ] **Step 4: Add the failing unsupported-object fallback test**

```dart
test('shared Form XObject remains read-only and does not choose legacy silently', () async {
  final report = await port.compatibilityReport(0);
  expect(report.issues.single.code, 'shared_form_object');
  await expectLater(port.submit(editSharedForm()), throwsA(isA<EditorReadOnlyFailure>()));
});
```

- [ ] **Step 5: Implement explicit fallback classification**

Classify each command before submission. Unsupported objects report the reason
and remain read-only. The legacy materializer is selectable only through an
explicit feature flag plus a compatibility result; never switch after a live
mutation has begun in a tab.

- [ ] **Step 6: Run save, undo/redo, and fallback tests**

Run: `flutter test --no-pub integration_test/phase1_editing_test.dart test/pdf_editor/application_presentation/save_ui_test.dart; cargo test -p clarix_pdf_oxide editing_bridge`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/src/core/editing/live_pdfium_editor_port.dart lib/src/core/editing/editor_bridge.dart lib/src/features/pdf_editor/application/editor_session_controller.dart rust/clarix_pdf_oxide/src/editing_api.rs rust/clarix_pdf_adapter/src/materializer.rs integration_test/phase1_editing_test.dart test/pdf_editor/application_presentation/save_ui_test.dart rust/clarix_pdf_oxide/tests/editing_bridge.rs
git commit -m "feat: persist live PDFium editor transactions"
```

## Task 7: Extend command parity and retire visual fallback for supported edits

**Files:**
- Modify: `lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart`
- Modify: `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart`
- Modify: `lib/src/features/pdf_editor/presentation/page_edit_scene.dart`
- Modify: `lib/src/features/pdf_editor/presentation/page_scene_host.dart`
- Test: `test/pdf_editor/domain_infrastructure/pdf_object_transform_round_trip_test.dart`
- Test: `test/pdf_editor/domain_infrastructure/pdf_text_compatibility_test.dart`
- Test: `integration_test/pdf_object_editing_test.dart`

**Interfaces:**
- Supports text color/size/transform and image/path transform plans in addition to whole text replacement.
- `FPDFPage_GenerateContent` is invoked by the owning same-page transaction
  before it closes its page handle, never by a tile render request.
- Pages containing only supported live edits render without `CleanPatchLayer` or `EditorTextObjectLayer`.

- [ ] **Step 1: Write failing parity tests for text transform and image/path transform**

```dart
test('move-object plan changes only its live tile and persists after save', () async {
  final result = await session.apply(moveObjectPlan(locator, dx: 12, dy: -6));
  expect(result.dirtyTiles, hasLength(1));
  await session.save();
  expect(await reopenedTransform(), closeTo(expectedTransform, 0.001));
});
```

- [ ] **Step 2: Run parity tests to verify they fail**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/pdf_object_transform_round_trip_test.dart test/pdf_editor/domain_infrastructure/pdf_text_compatibility_test.dart integration_test/pdf_object_editing_test.dart`

Expected: FAIL because the live applier supports only whole text replacement.

- [ ] **Step 3: Implement supported transform and style operations**

Use `FPDFPageObj_SetMatrix`, fill-color setters, and text-object style APIs.
Capture each original matrix/color/style before mutation so inverse plans are
lossless. Reject partial text edits, missing glyphs, shared Form XObjects, and
non-fill render modes with explicit compatibility codes.

- [ ] **Step 4: Run parity tests**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/pdf_object_transform_round_trip_test.dart test/pdf_editor/domain_infrastructure/pdf_text_compatibility_test.dart integration_test/pdf_object_editing_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart lib/src/features/pdf_editor/presentation/page_edit_scene.dart lib/src/features/pdf_editor/presentation/page_scene_host.dart test/pdf_editor/domain_infrastructure/pdf_object_transform_round_trip_test.dart test/pdf_editor/domain_infrastructure/pdf_text_compatibility_test.dart integration_test/pdf_object_editing_test.dart
git commit -m "feat: extend live PDFium command parity"
```

## Task 8: Performance, memory pressure, and full-story verification

**Files:**
- Modify: `lib/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart`
- Modify: `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart`
- Modify: `lib/src/features/pdf_editor/presentation/page_scene_host.dart`
- Test: `integration_test/phase1_large_document_test.dart`
- Test: `test/pdf_editor/domain_infrastructure/live_pdfium_tile_renderer_test.dart`
- Test: `test/architecture/production_dart_file_size_test.dart`

**Interfaces:**
- `prefetchVisiblePages(Set<int> visiblePages, {int radius = 2})` schedules only visible and nearby scene/tile work.
- `reportMemoryPressure` clears non-visible live tile images without discarding unsaved PDFium mutations.

- [ ] **Step 1: Write failing large-document and pressure tests**

```dart
test('visible-page prefetch does not inspect distant pages before idle', () async {
  await session.prefetchVisiblePages({250}, radius: 2);
  expect(fakeInspector.inspectedPages, containsAll(<int>[248, 249, 250, 251, 252]));
  expect(fakeInspector.inspectedPages, isNot(contains(1)));
});

test('critical memory pressure releases cold tiles but preserves dirty pages', () async {
  await session.reportMemoryPressure(EditorMemoryPressureLevel.critical);
  expect(renderer.cachedTileCount, 0);
  expect(session.dirtyPages, {250});
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test --no-pub integration_test/phase1_large_document_test.dart test/pdf_editor/domain_infrastructure/live_pdfium_tile_renderer_test.dart`

Expected: FAIL because visible-page scheduling and live-tile pressure handling are absent.

- [ ] **Step 3: Implement bounded prefetch and memory release**

Schedule visible page work synchronously, neighboring work at preload priority,
and all other indexing only on an idle/background queue. Cancel queued work on
viewport changes. Release decoded Flutter images and cold tile bytes under
pressure while retaining the PDFium document and dirty-page set.

- [ ] **Step 4: Run full verification**

Run: `flutter test --no-pub integration_test/phase1_editing_test.dart integration_test/phase1_large_document_test.dart integration_test/pdf_object_editing_test.dart; cargo test --workspace; dart analyze lib test`

Expected: PASS with no analyzer diagnostics.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart lib/src/features/pdf_editor/presentation/page_scene_host.dart integration_test/phase1_large_document_test.dart test/pdf_editor/domain_infrastructure/live_pdfium_tile_renderer_test.dart test/architecture/production_dart_file_size_test.dart
git commit -m "perf: bound live PDFium editor rendering"
```

## Plan Self-Review

* Spec coverage: Tasks 1–4 establish single ownership, semantic/physical mapping, atomic plans, and revisions; Tasks 2, 5, and 8 cover dirty tiles and lifecycle; Tasks 3, 6, and 7 cover mutation, commit/save, undo/redo, compatibility, and command parity.
* Completeness scan: each task identifies files, types, red test, implementation, verification, and commit steps.
* Type consistency: `EditorPhysicalLocator`, `LivePdfiumTile`, `LivePdfiumEditPlan`, `LiveApplyResult`, and `LivePdfiumSession` are introduced before later tasks consume them.
