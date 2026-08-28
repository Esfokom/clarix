# Live PDFium Text Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make caret navigation, text insertion/deletion, and text-only move/resize/rotate operations mutate and rerender the canonical live PDFium objects.

**Architecture:** A live editor page uses only path-derived PDFium identities. Rust validates semantic commands and emits forward/inverse text or matrix operations; Dart applies the prepared operations atomically to the one live PDFium document before Rust publishes the revision. Flutter owns invisible IME/keyboard input and visible interaction chrome, but never repaints existing PDF glyphs.

**Tech Stack:** Flutter/Dart, Flutter text input and hardware keyboard APIs, `characters`, Flutter Rust Bridge, Rust editing core, pdfrx, `pdfium_flutter` FFI.

**Spec:** `docs/superpowers/specs/2026-08-28-live-pdfium-text-interaction-design.md`

## Global Constraints

* Support physical editing and transforms for PDF text objects only.
* Keep one live PDFium document owner per editor tab and execute native operations on its worker.
* Preserve prepare -> physical apply -> semantic publish ordering.
* Never match legacy and live objects heuristically by text, geometry, or traversal order.
* Never fall back to semantic-only submission for a text command in a live-PDFium session.
* Never paint existing or deleted PDF text through `EditableText` or a Flutter text overlay.
* Navigation must not advance the document revision.
* Mutation ranges use UTF-16 offsets aligned to Unicode grapheme boundaries.
* Call `FPDFPage_GenerateContent` before closing the mutated `FPDF_PAGE`.
* Preserve nonzero recovered state when its projection is incompatible; return a typed migration error.
* Regenerate FRB bindings with `flutter_rust_bridge_codegen generate --no-build-runner --no-dart-fix --no-web`; do not run `cargo build`.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `rust/clarix_editing_core/src/model.rs` | Replace a conflicting page only under the explicit revision-zero live hydration policy. |
| `rust/clarix_editing_core/src/session.rs` | Enforce live hydration policy and create forward/inverse physical text-transform plans. |
| `rust/clarix_editing_core/src/ports.rs` | Define tagged physical replacement and transform operations. |
| `rust/clarix_pdf_oxide/src/editing_api.rs` | Expose canonical live hydration and physical operation DTOs through FRB. |
| `lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart` | Register accepted manifests and strictly route bound live text commands. |
| `lib/src/features/pdf_editor/presentation/text_navigation.dart` | Compute grapheme-safe movement, extension, and deletion edits. |
| `lib/src/features/pdf_editor/presentation/session_text_input.dart` | Translate hardware keys and platform input into selection changes or text deltas. |
| `lib/src/core/editing/editor_bridge_types.dart` | Represent tagged physical operations in Dart. |
| `lib/src/core/editing/frb_native_editor_port.dart` | Validate and map native physical operation payloads. |
| `lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart` | Define replacement and matrix operations for one atomic page plan. |
| `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart` | Resolve, validate, apply, roll back, regenerate, and invalidate live PDFium text operations. |
| `lib/src/core/editing/live_pdfium_editor_port.dart` | Convert Rust physical operations to locator-bound Dart operations and publish only after apply. |
| `lib/src/features/pdf_editor/presentation/object_transform_handles.dart` | Limit handles to editable live text and retain preview until acknowledgement. |

### Task 1: Canonicalize live hydration and prohibit silent routing fallback

**Files:**
- Modify: `rust/clarix_editing_core/src/model.rs:537`
- Modify: `rust/clarix_editing_core/src/session.rs:440`
- Modify: `rust/clarix_editing_core/src/actor.rs:290`
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs:709`
- Modify: `lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart:280-350`
- Test: `rust/clarix_editing_core/tests/command_session.rs`
- Test: `rust/clarix_pdf_oxide/tests/editing_bridge.rs`
- Test: `test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`

**Interfaces:**
- Consumes: `PageNode`, `DocumentRevision`, and `NativeLivePageImport`.
- Produces: `EditorSessionState::hydrate_live_page(page, expected_revision)` and typed errors `live_projection_migration_required` and `live_pdfium_binding_missing`.

- [ ] **Step 1: Write failing Rust tests for the hydration policy**

Add tests proving revision zero replaces a conflicting legacy page and a
nonzero session retains its existing page:

```rust
#[test]
fn live_hydration_replaces_a_conflicting_page_only_at_initial_revision() {
    let mut session = session_with_page(legacy_page());
    session
        .hydrate_live_page(live_page(), DocumentRevision::INITIAL)
        .unwrap();
    assert_eq!(session.model().page(1).unwrap(), &live_page());
}

#[test]
fn live_hydration_preserves_nonzero_recovered_state() {
    let mut session = session_with_committed_edit();
    let before = session.model().page(1).unwrap().clone();
    let error = session
        .hydrate_live_page(live_page(), session.revision())
        .unwrap_err();
    assert!(error.to_string().contains("live_projection_migration_required"));
    assert_eq!(session.model().page(1).unwrap(), &before);
}
```

- [ ] **Step 2: Run the Rust tests and verify the red state**

Run: `cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core live_hydration -- --nocapture`

Expected: FAIL because `hydrate_live_page` does not exist.

- [ ] **Step 3: Implement explicit live page replacement**

Add a model method that reconstructs the indexes through `from_parts`:

```rust
pub(crate) fn replace_page(&mut self, page: PageNode) -> Result<(), ModelError> {
    let mut pages = self.pages.clone();
    pages.retain(|candidate| candidate.page_number != page.page_number);
    pages.push(page);
    pages.sort_by_key(|candidate| candidate.page_number);
    *self = Self::from_parts(
        self.id,
        self.source_fingerprint.clone(),
        self.revision,
        pages,
    )?;
    Ok(())
}
```

Implement `hydrate_live_page` so it validates the expected revision, delegates
to ordinary hydration when no conflict exists, replaces only when the current
revision is `DocumentRevision::INITIAL`, and otherwise returns
`EditingError::InvalidCommand("live_projection_migration_required".into())`.
Expose a matching actor request and make `NativeEditorSession::import_live_page`
call this live-specific method.

- [ ] **Step 4: Write failing Dart routing tests**

Replace the existing legacy-fallback expectation with strict live behavior:

```dart
test('an unbound text edit in a live session fails without semantic fallback', () async {
  await gateway.open(request);
  await expectLater(
    gateway.submit(unboundReplacement),
    throwsA(isA<StateError>().having(
      (error) => error.message,
      'message',
      'live_pdfium_binding_missing',
    )),
  );
  expect(semantic.submitted, isEmpty);
  expect(live.submitted, isEmpty);
});
```

Extend the hydration conflict test to assert that the live page's object ID is
returned by `requestPage` and is present in `LivePdfiumLocatorRegistry`.

- [ ] **Step 5: Run the focused Dart test and verify the red state**

Run: `flutter test --no-pub test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`

Expected: FAIL because the gateway still catches the conflict and sends an
unbound replacement to `_required().submit`.

- [ ] **Step 6: Make live routing strict and register only accepted pages**

Delete the hydrated-page-conflict catch. Register the manifest only after
`importLivePage` succeeds. In `_submitRouted`, classify text mutations and
text transforms together:

```dart
final isLiveTextCommand = switch (request.payload.kind) {
  EditorCommandKind.replaceTextRange ||
  EditorCommandKind.moveObject ||
  EditorCommandKind.resizeObject ||
  EditorCommandKind.rotateObject => true,
  _ => false,
};
if (livePort != null && isLiveTextCommand) {
  if (objectId == null || registry == null || !registry.hasObject(objectId)) {
    throw StateError('live_pdfium_binding_missing');
  }
  return livePort.submit(request);
}
```

Keep undo/redo routed through `livePort`. Log the command kind, object ID,
binding state, source key when present, and chosen route.

- [ ] **Step 7: Run hydration and routing tests**

Run: `cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core live_hydration -- --nocapture; cargo test --manifest-path rust/Cargo.toml -p clarix_pdf_oxide live_page -- --nocapture; flutter test --no-pub test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit the canonical identity repair**

```bash
git add rust/clarix_editing_core/src/model.rs rust/clarix_editing_core/src/session.rs rust/clarix_editing_core/src/actor.rs rust/clarix_pdf_oxide/src/editing_api.rs rust/clarix_editing_core/tests/command_session.rs rust/clarix_pdf_oxide/tests/editing_bridge.rs lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart
git commit -m "fix: canonicalize live PDFium page identity"
```

### Task 2: Add grapheme-safe caret navigation and deletion

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/src/features/pdf_editor/presentation/text_navigation.dart`
- Modify: `lib/src/features/pdf_editor/presentation/session_text_input.dart:103-122`
- Test: `test/pdf_editor/application_presentation/text_navigation_test.dart`
- Test: `test/pdf_editor/application_presentation/page_edit_scene_test.dart`

**Interfaces:**
- Consumes: `TextEditingValue`, `LogicalKeyboardKey`, and Shift state.
- Produces: `TextNavigationResult? editTextForKey(TextEditingValue value, LogicalKeyboardKey key, {required bool extendSelection})`, where the result contains the next value and whether text changed.

- [ ] **Step 1: Add `characters` as a direct dependency**

Add `characters: ^1.4.1` under `dependencies`, then run `flutter pub get` so
grapheme navigation does not depend on an undeclared transitive package.

- [ ] **Step 2: Write failing pure navigation tests**

Create table-driven tests for collapsed and expanded selections:

```dart
test('left and backspace do not split an emoji grapheme', () {
  const value = TextEditingValue(
    text: 'A👩🏽‍💻B',
    selection: TextSelection.collapsed(offset: 8),
  );
  final left = editTextForKey(
    value,
    LogicalKeyboardKey.arrowLeft,
    extendSelection: false,
  )!;
  expect(left.value.selection, const TextSelection.collapsed(offset: 1));
  final deleted = editTextForKey(
    left.value,
    LogicalKeyboardKey.delete,
    extendSelection: false,
  )!;
  expect(deleted.value.text, 'AB');
  expect(deleted.textChanged, isTrue);
});
```

Cover left, right, Shift+left/right, Home, End, Backspace, Delete, and deleting
an expanded selection.

- [ ] **Step 3: Run the navigation tests and verify the red state**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/text_navigation_test.dart`

Expected: FAIL because `text_navigation.dart` does not exist.

- [ ] **Step 4: Implement the pure key-editing function**

Use `Characters` to build the UTF-16 boundary list beginning with zero and
ending with `text.length`. Collapse an expanded selection to its start for
Left and its end for Right unless Shift is pressed. Preserve
`selection.baseOffset` while extending. For Backspace/Delete, return a new
`TextEditingValue` with a collapsed selection at the deletion start and
`composing: TextRange.empty`.

```dart
final class TextNavigationResult {
  const TextNavigationResult(this.value, {required this.textChanged});
  final TextEditingValue value;
  final bool textChanged;
}
```

- [ ] **Step 5: Write failing widget tests for hardware keys**

Use `tester.sendKeyEvent` and assert navigation changes selection without a
gateway request, while Backspace/Delete create exactly one replacement:

```dart
await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
expect(harness.controller.state.selection!.range.start, 5);
expect(harness.gateway.requests, isEmpty);

await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
await tester.pump();
expect(harness.gateway.requests.single.payload.replacement, '');
expect(harness.gateway.requests.single.payload.start, 4);
expect(harness.gateway.requests.single.payload.end, 5);
expect(find.byType(EditableText), findsNothing);
```

- [ ] **Step 6: Connect the key handler to the existing input pipeline**

Call `editTextForKey` after Escape and undo/redo handling. Set `_value`, send
it to `_connection`, and invoke `onSelectionChanged`. When `textChanged` is
true, feed the value through a private `_acceptEditingValue(previous, next)`
method shared with `updateEditingValue`; this preserves IME composition and
the existing `computeTextDelta` behavior.

- [ ] **Step 7: Run keyboard and IME regression tests**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/text_navigation_test.dart test/pdf_editor/application_presentation/page_edit_scene_test.dart test/pdf_editor/application_presentation/native_text_ime_test.dart test/pdf_editor/application_presentation/page_edit_scene_tap_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit caret navigation**

```bash
git add pubspec.yaml pubspec.lock lib/src/features/pdf_editor/presentation/text_navigation.dart lib/src/features/pdf_editor/presentation/session_text_input.dart test/pdf_editor/application_presentation/text_navigation_test.dart test/pdf_editor/application_presentation/page_edit_scene_test.dart
git commit -m "feat: add caret-only PDF text navigation"
```

### Task 3: Extend Rust and FRB physical plans with text transforms

**Files:**
- Modify: `rust/clarix_editing_core/src/ports.rs:14-23`
- Modify: `rust/clarix_editing_core/src/session.rs:767-813,982-1016`
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs:498-515,1829-1848`
- Modify: `lib/src/core/ffi/editing_api.dart`
- Regenerate: `lib/src/core/ffi/frb_generated.dart`
- Regenerate: `lib/src/core/ffi/frb_generated.io.dart`
- Regenerate: `lib/src/core/ffi/frb_generated.web.dart`
- Regenerate: `rust/clarix_pdf_oxide/src/frb_generated.rs`
- Test: `rust/clarix_editing_core/tests/port_contract.rs`
- Test: `rust/clarix_pdf_oxide/tests/editing_bridge.rs`

**Interfaces:**
- Consumes: semantic `MoveObject`, `ResizeObject`, and `RotateObject` commands.
- Produces: `PhysicalEditOperation::SetTextTransform` and `NativePhysicalEditOperationKind::SetTextTransform` with complete forward/inverse matrices and bounds.

- [ ] **Step 1: Write failing physical-plan tests**

For move, resize, and rotate, prepare the command and assert the operation kind,
old/new matrices, bounds, and inverse symmetry:

```rust
let prepared = session.prepare(move_text_command(object_id, 12.0, -6.0)).unwrap();
let operation = prepared.physical_plan.unwrap().operations.remove(0);
let PhysicalEditOperation::SetTextTransform {
    expected_transform,
    transform,
    old_bounds,
    new_bounds,
    ..
} = operation else { panic!("expected text transform") };
assert_eq!(expected_transform, AffineTransform::IDENTITY);
assert_eq!((transform.e, transform.f), (12.0, -6.0));
assert_eq!(old_bounds, original_bounds());
assert_eq!(new_bounds, moved_bounds());
```

- [ ] **Step 2: Run the Rust tests and verify the red state**

Run: `cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core physical_text_transform -- --nocapture`

Expected: FAIL because `SetTextTransform` is undefined.

- [ ] **Step 3: Add the tagged Rust operation and plan generation**

Define the new enum variant exactly as specified in the design. Rewrite
`physical_plan_from_changes` to compare each before/after text object:

* emit `ReplaceText` when text changed;
* emit `SetTextTransform` when transform or bounds changed;
* emit both in deterministic replacement-then-transform order when both changed;
* build inverse operations in reverse order.

For resize, compose an anchor-preserving scale matrix with the existing
transform and update semantic bounds/character boxes consistently. Reject
zero-width, zero-height, non-finite, and non-invertible scale results.

- [ ] **Step 4: Add and test the native bridge DTO**

Use an operation kind plus optional variant payloads:

```rust
pub enum NativePhysicalEditOperationKind {
    ReplaceText,
    SetTextTransform,
}

pub struct NativePhysicalEditOperation {
    pub kind: NativePhysicalEditOperationKind,
    pub object_id: String,
    pub source_key: String,
    pub source_revision: String,
    pub expected_text: Option<String>,
    pub replacement: Option<String>,
    pub expected_transform: Option<NativeAffineTransform>,
    pub transform: Option<NativeAffineTransform>,
    pub old_bounds: NativePdfBox,
    pub new_bounds: NativePdfBox,
}
```

Add bridge tests for both variants and reject missing fields during Dart
conversion rather than substituting defaults.

- [ ] **Step 5: Regenerate FRB bindings**

Run: `flutter_rust_bridge_codegen generate --no-build-runner --no-dart-fix --no-web`

Expected: generated Dart and Rust bindings contain
`NativePhysicalEditOperationKind.setTextTransform` and nullable variant fields.

- [ ] **Step 6: Run Rust and bridge contract tests**

Run: `cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core physical_text_transform -- --nocapture; cargo test --manifest-path rust/Cargo.toml -p clarix_pdf_oxide physical_text_transform -- --nocapture`

Expected: PASS.

- [ ] **Step 7: Commit the physical protocol**

```bash
git add rust/clarix_editing_core/src/ports.rs rust/clarix_editing_core/src/session.rs rust/clarix_editing_core/tests/port_contract.rs rust/clarix_pdf_oxide/src/editing_api.rs rust/clarix_pdf_oxide/tests/editing_bridge.rs lib/src/core/ffi/editing_api.dart lib/src/core/ffi/frb_generated.dart lib/src/core/ffi/frb_generated.io.dart lib/src/core/ffi/frb_generated.web.dart rust/clarix_pdf_oxide/src/frb_generated.rs
git commit -m "feat: plan physical PDF text transforms"
```

### Task 4: Apply text replacements and transforms atomically in live PDFium

**Files:**
- Modify: `lib/src/core/editing/editor_bridge_types.dart:553-575`
- Modify: `lib/src/core/editing/frb_native_editor_port.dart:524-536`
- Modify: `lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart`
- Modify: `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart:134-322`
- Modify: `lib/src/core/editing/live_pdfium_editor_port.dart:130-160`
- Test: `test/core/editing/editor_bridge_contract_test.dart`
- Test: `test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart`
- Test: `test/core/editing/live_pdfium_editor_port_test.dart`

**Interfaces:**
- Consumes: tagged `EditorPhysicalEditOperation` values and `EditorPhysicalLocator` bindings.
- Produces: `LivePdfiumEditPlan({required List<LivePdfiumOperation> operations, int? expectedRevision, int? revision})` containing `LivePdfiumTextReplacement` and `LivePdfiumTextTransform`.

- [ ] **Step 1: Write failing Dart contract tests**

Assert that native replacement and transform operations map without losing
their variant fields, and incomplete payloads throw `StateError` containing
`invalid_physical_operation`.

- [ ] **Step 2: Introduce tagged Dart bridge operations**

Add `EditorPhysicalEditOperationKind { replaceText, setTextTransform }` and
make replacement/matrix fields nullable. `_physicalEditOperationFromNative`
must switch on `value.kind` and validate the fields required by that kind.

- [ ] **Step 3: Write failing live PDFium matrix tests**

Open the existing text fixture, read the original matrix, apply a translation
and rotation, render before/after tiles, save, reopen, and inspect the matrix:

```dart
final result = await session.apply(
  LivePdfiumEditPlan(
    operations: <LivePdfiumOperation>[
      LivePdfiumTextTransform(
        locator: locator,
        expectedTransform: original,
        transform: translated,
        oldBounds: originalBounds,
        newBounds: translatedBounds,
      ),
    ],
    expectedRevision: 0,
    revision: 1,
  ),
);
expect(result.invalidations.single.bounds, unionBounds);
expect(after.rgbaBytes, isNot(orderedEquals(before.rgbaBytes)));
```

Add a stale-matrix test that asserts the raster and revision remain unchanged.

- [ ] **Step 4: Generalize the live plan types**

Define:

```dart
sealed class LivePdfiumOperation {
  const LivePdfiumOperation({required this.locator, required this.oldBounds, required this.newBounds});
  final EditorPhysicalLocator locator;
  final EditorPdfBox oldBounds;
  final EditorPdfBox newBounds;
}

final class LivePdfiumTextTransform extends LivePdfiumOperation {
  const LivePdfiumTextTransform({
    required super.locator,
    required super.oldBounds,
    required super.newBounds,
    required this.expectedTransform,
    required this.transform,
  });
  final EditorAffineTransform expectedTransform;
  final EditorAffineTransform transform;
}
```

Make `LivePdfiumTextReplacement` extend the same base and change
`LivePdfiumEditPlan` to require a nonempty same-page `operations` list.

- [ ] **Step 5: Implement atomic PDFium matrix application**

In one worker callback, resolve and validate all operations before mutation.
For each transform path:

1. read its `FS_MATRIX` with `FPDFPageObj_GetMatrix`;
2. verify it matches the expected matrix within `1e-6` per component;
3. compute `delta = desiredBlockMatrix * inverse(expectedBlockMatrix)`;
4. assign `delta * originalObjectMatrix` with `FPDFPageObj_SetMatrix`;
5. snapshot original matrices for reverse-order rollback.

Apply text and matrix operations in plan order, regenerate once, and return
deduplicated unions of old/new bounds. On any exception, restore text and
matrices in reverse order, regenerate the restored page, keep `_revision`
unchanged, and rethrow the typed failure.

- [ ] **Step 6: Convert prepared plans in `LivePdfiumEditorPort`**

Switch on each operation kind, resolve its locator using object ID, source key,
and source revision, construct the matching live operation, apply the plan,
then publish the prepared token. Preserve the existing abort-on-apply-failure
behavior.

- [ ] **Step 7: Run live operation tests**

Run: `flutter test --no-pub test/core/editing/editor_bridge_contract_test.dart test/core/editing/live_pdfium_editor_port_test.dart test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit atomic live operations**

```bash
git add lib/src/core/editing/editor_bridge_types.dart lib/src/core/editing/frb_native_editor_port.dart lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart lib/src/core/editing/live_pdfium_editor_port.dart test/core/editing/editor_bridge_contract_test.dart test/core/editing/live_pdfium_editor_port_test.dart test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart
git commit -m "feat: apply live PDF text transforms"
```

### Task 5: Align transform UI state with acknowledged PDF mutations

**Files:**
- Modify: `lib/src/features/pdf_editor/presentation/object_transform_handles.dart`
- Modify: `lib/src/features/pdf_editor/presentation/page_edit_scene.dart`
- Modify: `lib/src/features/pdf_editor/application/editor_session_controller.dart`
- Test: `test/pdf_editor/application_presentation/object_transform_handles_test.dart`
- Test: `test/pdf_editor/application_presentation/page_edit_scene_test.dart`
- Test: `test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`

**Interfaces:**
- Consumes: live-bound editable `EditorSceneObjectKind.text` objects and asynchronous `dispatchCommand` results.
- Produces: text-only handles whose previews settle on the acknowledged object patch or restore on failure.

- [ ] **Step 1: Write failing presentation tests**

Assert that non-text and unbound objects do not show transform handles. For a
text object, keep the preview visible while the fake command future is pending,
then assert success adopts the patched geometry and failure restores the
original box/caret.

- [ ] **Step 2: Expose asynchronous command acknowledgement**

Change the controller transform dispatch API to return
`Future<EditorCommandResult>`. In `ObjectTransformHandles`, keep a
`_pendingPreview` until the future completes:

```dart
setState(() => _pending = true);
try {
  await widget.session.dispatchCommand(command);
} finally {
  if (mounted) setState(() {
    _pending = false;
    _resetPreviewFields();
  });
}
```

Disable additional handle gestures while pending. Do not reset the preview
before dispatch.

- [ ] **Step 3: Gate transforms to live editable text**

Pass an explicit `canTransform` value derived from object kind, capability,
and live binding state. Render `ObjectTransformHandles` only when it is true.
An unsupported object remains selectable and displays its capability reason.

- [ ] **Step 4: Add structured boundary logs**

Add concise logs for hydration resolution, command route, prepared operation
kinds, PDFium validation/regeneration, invalidation bounds, and publish
revision. For text mismatches log only UTF-16 length and SHA-256 prefix.

- [ ] **Step 5: Run presentation and routing tests**

Run: `flutter test --no-pub test/pdf_editor/application_presentation/object_transform_handles_test.dart test/pdf_editor/application_presentation/page_edit_scene_test.dart test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit acknowledged transform interaction**

```bash
git add lib/src/features/pdf_editor/presentation/object_transform_handles.dart lib/src/features/pdf_editor/presentation/page_edit_scene.dart lib/src/features/pdf_editor/application/editor_session_controller.dart test/pdf_editor/application_presentation/object_transform_handles_test.dart test/pdf_editor/application_presentation/page_edit_scene_test.dart test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart
git commit -m "fix: synchronize text transform previews"
```

### Task 6: Verify the complete edit, history, and persistence story

**Files:**
- Modify: `integration_test/phase1_editing_test.dart`
- Modify: `integration_test/pdf_object_editing_test.dart`
- Modify: `test/pdf_editor/domain_infrastructure/pdf_object_transform_round_trip_test.dart`
- Modify: `test/pdf_editor/application_presentation/save_ui_test.dart`
- Modify: `docs/testing/editing-phase1-exit-gate.md`

**Interfaces:**
- Consumes: the canonical hydration, caret input, physical operation, tile invalidation, undo/redo, and live-save paths from Tasks 1-5.
- Produces: executable proof that the visible and saved PDF match the semantic revision without replacement text overlays.

- [ ] **Step 1: Add an end-to-end typing and deletion test**

Open the fixture through the production gateway, click a text bounding box,
move left, delete one grapheme, insert text, and assert:

* selection-only movement creates no command;
* deletion and insertion each publish one live revision;
* the dirty tile bytes change after each mutation;
* `EditableText` and `EditorTextObjectLayer` remain absent;
* extracted text from saved/reopened bytes equals the edited value.

- [ ] **Step 2: Add end-to-end move, resize, rotate, and history tests**

Apply each handle command to a text object, save/reopen, and compare the
reopened matrix within `1e-6`. Undo must restore the prior matrix and tile;
redo must reapply both. Assert invalidation intersects the original and final
bounds.

- [ ] **Step 3: Add recovery and atomicity tests**

Verify revision-zero legacy projection replacement, nonzero migration refusal,
missing live binding refusal, stale matrix refusal, and regeneration failure.
Each refusal must preserve the Rust revision, live PDFium revision, raster
bytes, and recovered sidecar state.

- [ ] **Step 4: Run focused Flutter and Rust suites**

Run: `flutter test --no-pub test/pdf_editor/application_presentation test/pdf_editor/domain_infrastructure test/core/editing`

Run: `cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core -p clarix_pdf_oxide`

Expected: PASS.

- [ ] **Step 5: Run analyzer and repository checks**

Run: `flutter analyze; git diff --check`

Expected: analyzer reports no diagnostics and diff check reports no whitespace errors. If the pre-existing architecture file-size test remains the only full-suite failure, record its exact unchanged baseline separately and do not describe it as caused by this feature.

- [ ] **Step 6: Perform the Windows interactive acceptance pass**

On a real editable PDF text block, verify click placement, Left/Right,
Shift+Left/Right, Home/End, Backspace/Delete, ordinary typing, IME commit,
move, resize, rotate, undo, redo, Save As, close, and reopen. Record logs and
screenshots in `docs/testing/editing-phase1-exit-gate.md`.

- [ ] **Step 7: Commit verification evidence**

```bash
git add integration_test/phase1_editing_test.dart integration_test/pdf_object_editing_test.dart test/pdf_editor/domain_infrastructure/pdf_object_transform_round_trip_test.dart test/pdf_editor/application_presentation/save_ui_test.dart docs/testing/editing-phase1-exit-gate.md
git commit -m "test: verify live PDF text interaction"
```

## Plan Self-Review

* Spec coverage: Task 1 covers canonical identity, recovery safety, and strict routing; Task 2 covers navigation, deletion, IME, and grapheme boundaries; Tasks 3-4 cover tagged forward/inverse physical transforms and atomic PDFium application; Task 5 covers text-only capability UI and acknowledgement; Task 6 covers tiles, history, save/reopen, failures, and manual acceptance.
* Placeholder scan: every implementation task names exact files, interfaces, test commands, expected red/green outcomes, and commit boundaries.
* Type consistency: Rust `SetTextTransform` maps to native `SetTextTransform`, Dart `EditorPhysicalEditOperationKind.setTextTransform`, and `LivePdfiumTextTransform`; all plan variants carry `oldBounds` and `newBounds`, and all live plans use a same-page `operations` collection.
