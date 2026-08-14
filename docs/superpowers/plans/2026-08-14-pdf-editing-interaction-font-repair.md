# PDF Editing Interaction and Font Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Clarix edit genuine PDF text and transforms reliably in the live PDFium document while exposing a complete searchable Windows font catalog and desktop-style formatting controls.

**Architecture:** Keep the existing domain-intent and live-PDFium projection architecture. Add an explicit presentation editing state, make Edit mode exclusively own text gestures and serialized input, unify transform previews with native mutations, replace filename-derived font discovery with OpenType metadata plus Windows registration paths, and verify saved output by reopening it.

**Tech Stack:** Flutter 3.44, Dart 3.12, Riverpod, pdfrx 2.4.7, PDFium FFI through `pdfium_dart`, `flutter_test`, Windows Registry command adapter, OpenType binary parsing.

**Spec:** `docs/superpowers/specs/2026-08-14-pdf-editing-interaction-font-repair-design.md`

## Global Constraints

- Work directly on `main` in `C:\Users\S\StudioProjects\clarix`; do not create a worktree.
- PDFium paints all visible PDF glyphs; Flutter paints only selection, caret, bounds, and handles.
- pdfrx reader text selection is enabled in Reading mode and disabled in Edit mode.
- Every native mutation has an awaited owner, rollback behavior, and a visible error path.
- Font discovery lists `.ttf`, `.otf`, and every face in `.ttc` containers; font names and capabilities come from OpenType tables, not filenames.
- Unsupported PDF content stays visibly read-only.
- Follow red-green-refactor for every task and commit each independently testable deliverable.

## File Structure

- `lib/src/features/workspace/domain/pdf_edit_session.dart`: authoritative reading/object-selected/text-editing state.
- `lib/src/features/workspace/application/pdf_editing_controller.dart`: serialized intent projection, focus-independent selection transitions, rollback, and error reporting.
- `lib/src/features/workspace/presentation/widgets/document_workspace.dart`: mode-dependent pdfrx configuration and awaited UI callbacks.
- `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`: click-count, caret/range gestures, and transform chrome.
- `lib/src/features/workspace/presentation/widgets/pdf_native_text_input.dart`: Windows text input, keyboard commands, focus reacquisition, and value synchronization.
- `lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart`: ordered native projections and transform previews.
- `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`: genuine PDFium text/object mutation and returned geometry.
- `lib/src/features/workspace/infrastructure/opentype_font_parser.dart`: focused parser for names, OS/2 metadata, cmap coverage, embedding rights, and TTC face offsets.
- `lib/src/features/workspace/infrastructure/windows_font_source.dart`: registered and fallback Windows font paths behind an injectable interface.
- `lib/src/features/workspace/infrastructure/installed_font_catalog.dart`: catalog construction, deduplication, eligibility, and matching.
- `lib/src/features/workspace/presentation/widgets/pdf_font_family_picker.dart`: searchable, keyboard-accessible family picker.
- `lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart`: inspector composition and alignment toggle group.
- `lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart`: encoded-document validation and transactional replacement.

---

### Task 1: Explicit edit interaction state and pdfrx gesture ownership

**Files:**
- Modify: `lib/src/features/workspace/domain/pdf_edit_session.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Test: `test/workspace_pdf/pdf_edit_session_test.dart`
- Test: `test/workspace_pdf/pdf_live_edit_controller_test.dart`
- Test: `test/workspace_pdf/pdf_document_workspace_edit_mode_test.dart`

**Interfaces:**
- Produces: `PdfEditingInteraction { reading, objectSelected, textEditing }` and `PdfEditingSession.interaction`.
- Produces: `PdfEditingController.selectTextObject(...)`, `beginTextEditing(...)`, `leaveTextEditing(...)`, and `clearSelection(...)` transitions.
- Consumes: existing `PdfEditingMode`, discovered blocks, `PdfTextSelection`, and live `PdfDocument` registration.

- [ ] **Step 1: Write failing domain transition tests**

Add tests that build a session with one editable block and assert:

```dart
expect(session.interaction, PdfEditingInteraction.reading);
final selected = session.selectObject(block.locator);
expect(selected.interaction, PdfEditingInteraction.objectSelected);
expect(selected.selection?.range, const PdfTextRange(0, 0));
final editing = selected.beginTextEditing(const PdfTextRange(2, 5));
expect(editing.interaction, PdfEditingInteraction.textEditing);
expect(editing.selection?.range, const PdfTextRange(2, 5));
expect(editing.leaveTextEditing().interaction,
    PdfEditingInteraction.objectSelected);
```

- [ ] **Step 2: Run the domain test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_edit_session_test.dart`

Expected: compilation fails because `PdfEditingInteraction` and transition methods do not exist.

- [ ] **Step 3: Implement the minimal domain state**

Add the enum, an `interaction` field defaulting to `reading`, copy/equality support, and pure transition methods. Enforce these invariants:

```dart
assert(interaction == PdfEditingInteraction.reading || selection != null);
assert(interaction != PdfEditingInteraction.textEditing ||
    selectedBlock?.isEditable == true);
```

`SetPdfEditingModeIntent(reading)` resets interaction and selection; entering object edit mode sets `interaction` to `objectSelected` only after a selection exists.

- [ ] **Step 4: Run the domain test and verify GREEN**

Run: `flutter test test/workspace_pdf/pdf_edit_session_test.dart`

Expected: all session tests pass.

- [ ] **Step 5: Write failing controller transition tests**

Assert that selecting a block primes geometry without entering text input, beginning text editing preserves the registered document and sets a requested range, Escape leaves text editing before clearing the object, and a read-only block cannot enter text editing.

```dart
await controller.selectTextObject('tab', document, editable.locator);
expect(controller.sessionFor('tab').interaction,
    PdfEditingInteraction.objectSelected);
await controller.beginTextEditing(
  'tab', document, editable.locator, const PdfTextRange(1, 4));
expect(controller.sessionFor('tab').interaction,
    PdfEditingInteraction.textEditing);
await controller.leaveTextEditing('tab');
expect(controller.sessionFor('tab').selection?.locator, editable.locator);
```

- [ ] **Step 6: Run the controller test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_live_edit_controller_test.dart`

Expected: compilation fails on the new transition methods.

- [ ] **Step 7: Implement controller transitions**

Replace the overloaded `selectTextBlock` behavior with explicit object selection and text editing entry. Keep read-only selection possible, but throw `PdfUnsupportedTextFailure` from `beginTextEditing` before creating a text-input state.

- [ ] **Step 8: Run the controller test and verify GREEN**

Run: `flutter test test/workspace_pdf/pdf_live_edit_controller_test.dart`

Expected: all live controller tests pass.

- [ ] **Step 9: Write a failing viewer configuration test**

Extract a pure helper from `document_workspace.dart`:

```dart
PdfTextSelectionParams textSelectionParamsFor(PdfEditingInteraction state)
```

Test that `enabled` is `true` for `reading` and `false` for both edit states.

- [ ] **Step 10: Run the viewer test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_document_workspace_edit_mode_test.dart`

Expected: compilation fails because `textSelectionParamsFor` does not exist.

- [ ] **Step 11: Implement mode-dependent pdfrx selection**

Pass the helper result to `PdfViewerParams.textSelectionParams`. Preserve the existing context menu only in Reading mode. Keep pan and Clarix cursor-locked zoom behavior unchanged.

- [ ] **Step 12: Run focused tests and commit**

Run: `flutter test test/workspace_pdf/pdf_edit_session_test.dart test/workspace_pdf/pdf_live_edit_controller_test.dart test/workspace_pdf/pdf_document_workspace_edit_mode_test.dart`

Expected: all tests pass.

Commit:

```powershell
git add lib/src/features/workspace/domain/pdf_edit_session.dart lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart test/workspace_pdf/pdf_edit_session_test.dart test/workspace_pdf/pdf_live_edit_controller_test.dart test/workspace_pdf/pdf_document_workspace_edit_mode_test.dart
git commit -m "fix: separate PDF object selection from text editing"
```

### Task 2: Desktop text gestures, keyboard input, and awaited projections

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_native_text_input.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Test: `test/workspace_pdf/pdf_text_editor_overlay_test.dart`
- Test: `test/workspace_pdf/pdf_text_selection_overlay_test.dart`
- Test: `test/workspace_pdf/pdf_native_text_input_test.dart`
- Test: `test/workspace_pdf/pdf_live_edit_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 interaction state and transition methods.
- Produces: `PdfTextGestureResolver.wordRange`, `blockRange`, and `rangeBetween` pure geometry helpers.
- Produces: `Future<void> Function(PdfEditIntent)` for awaited editor intents and `VoidCallback requestInputFocus` ownership.
- Produces: per-tab serialized projection queues in `PdfEditingController`.

- [ ] **Step 1: Write failing pure gesture tests**

Use a block containing `Quarterly revenue` and native character boxes. Assert that a double-click inside `Quarterly` returns `PdfTextRange(0, 9)`, a triple-click returns the whole block, and dragging from character 2 to 12 produces the normalized range `PdfTextRange(2, 12)` in either pointer direction.

- [ ] **Step 2: Run gesture tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_text_selection_overlay_test.dart`

Expected: compilation fails because `PdfTextGestureResolver` does not exist.

- [ ] **Step 3: Implement pure gesture resolution**

Add a private/public-for-testing resolver that uses `PdfNativeTextGeometry.offsetNearest`, Unicode whitespace/punctuation boundaries, and UTF-16 offsets. Do not infer selection from painted Flutter text.

- [ ] **Step 4: Run gesture tests and verify GREEN**

Run: `flutter test test/workspace_pdf/pdf_text_selection_overlay_test.dart`

Expected: all gesture geometry tests pass.

- [ ] **Step 5: Write failing overlay interaction tests**

Pump the overlay with an explicit interaction state and asynchronous callbacks. Verify:

```dart
await tester.tap(find.byKey(const Key('pdf-text-block-outline')));
expect(selectedObjects, hasLength(1));
expect(find.byKey(const Key('pdf-native-text-input')), findsNothing);

await tester.tap(find.byKey(const Key('pdf-text-block-outline')));
await tester.pump(kDoubleTapMinTime);
await tester.tap(find.byKey(const Key('pdf-text-block-outline')));
expect(beginRanges.single, const PdfTextRange(0, 8));
```

Also cover triple-click, drag selection, Shift extension, read-only refusal, and Escape transitions.

- [ ] **Step 6: Run overlay tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_text_editor_overlay_test.dart`

Expected: failures show the current overlay enters input immediately after one selection and lacks range gestures.

- [ ] **Step 7: Implement overlay state-specific hit targets**

Make object-selected chrome handle selection and transform gestures without mounting `PdfNativeTextInput`. Mount the input only for the active text-editing block. Use pointer-down timestamps/counts plus Flutter gesture callbacks to distinguish single, double, and triple clicks without dispatching a late single-click that cancels the multi-click action.

- [ ] **Step 8: Run overlay tests and verify GREEN**

Run: `flutter test test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_text_selection_overlay_test.dart`

Expected: all interaction tests pass.

- [ ] **Step 9: Write failing text-input keyboard and focus tests**

Pump `PdfNativeTextInput`, focus another control, invoke its exposed `requestFocus`, and assert `tester.testTextInput.hasAnyClients`. Send Backspace, Delete, arrows, Home, End, Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, and Ctrl+Shift+Z. Assert emitted deltas or callbacks and the resulting `TextEditingValue.selection`.

- [ ] **Step 10: Run input tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_native_text_input_test.dart`

Expected: compilation or assertions fail because focus activation and the full shortcut set are absent.

- [ ] **Step 11: Implement focus and keyboard behavior**

Give the input a `PdfNativeTextInputController` with `requestFocus()` and `updateSelection(PdfTextRange)`. Keep the platform `TextInputClient` as the source for IME text deltas. Handle non-text navigation in `Focus.onKeyEvent`, update the connection editing state, and translate destructive edits into one `PdfTextDelta`.

- [ ] **Step 12: Run input tests and verify GREEN**

Run: `flutter test test/workspace_pdf/pdf_native_text_input_test.dart`

Expected: all input and focus tests pass.

- [ ] **Step 13: Write a failing serialized-projection test**

Use a mutator whose first projection completes after the second intent is submitted. Assert native calls remain ordered, the second complete state wins, stale geometry is not published, and the returned futures complete only after their matching projection or rollback.

- [ ] **Step 14: Run controller test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_live_edit_controller_test.dart`

Expected: the current unawaited presentation path or unsynchronized projections violate ordering/visibility assertions.

- [ ] **Step 15: Implement serialized awaited projection**

Maintain `Map<String, Future<void>> _projectionTails` by tab. Add:

```dart
Future<PdfEditResult> dispatchAndProjectQueued({
  required String tabId,
  required PdfEditIntent intent,
  required PdfCommandProvenance provenance,
})
```

Chain each mutation after the prior tail, retain rollback from `dispatchAndProject`, publish only matching revisions, and route caught failures through the workspace notifier's existing PDF error mapping. Change overlay callbacks to `Future<void> Function(...)` and await them.

- [ ] **Step 16: Run focused tests and commit**

Run: `flutter test test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_text_selection_overlay_test.dart test/workspace_pdf/pdf_native_text_input_test.dart test/workspace_pdf/pdf_live_edit_controller_test.dart`

Expected: all tests pass with no uncaught asynchronous errors.

Commit:

```powershell
git add lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/presentation/widgets/pdf_native_text_input.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/application/pdf_editing_controller.dart test/workspace_pdf/pdf_text_editor_overlay_test.dart test/workspace_pdf/pdf_text_selection_overlay_test.dart test/workspace_pdf/pdf_native_text_input_test.dart test/workspace_pdf/pdf_live_edit_controller_test.dart
git commit -m "fix: activate native PDF text editing gestures"
```

### Task 3: Unified live transforms for text and page objects

**Files:**
- Modify: `lib/src/features/workspace/domain/pdf_page_object.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart`
- Modify: `lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_object_transform_overlay.dart`
- Test: `test/workspace_pdf/pdf_live_resize_reflow_test.dart`
- Test: `test/workspace_pdf/pdf_object_transform_overlay_test.dart`
- Test: `test/workspace_pdf/pdf_object_transform_round_trip_test.dart`

**Interfaces:**
- Consumes: Task 2 awaited controller queue.
- Produces: `PdfObjectTransformPreview` containing locator, before transform, after transform, and transformed bounds.
- Produces: `PdfNativeEditCoordinator.previewObjectTransform(...)` and `commitObjectTransform(...)` with shared semantics for text, image, and path objects.

- [ ] **Step 1: Write failing transform-preview tests**

For a text object, assert that a 20-point PDF-space drag changes both the overlay rect and the native inspected transform before pointer-up. Assert pointer-up emits one reversible move intent. Repeat for resize and rotation; verify cancellation restores the exact original transform.

- [ ] **Step 2: Run transform tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_object_transform_overlay_test.dart test/workspace_pdf/pdf_live_resize_reflow_test.dart`

Expected: text chrome does not paint `_previewBounds`, and text/generic objects do not share a preview result.

- [ ] **Step 3: Add the shared preview value**

Define an immutable `PdfObjectTransformPreview` with equality and conversion helpers. Move PDF/view coordinate conversion into pure functions used by both overlays. Reject singular transforms and unsupported resize capabilities before native mutation.

- [ ] **Step 4: Run value and overlay tests and verify GREEN**

Run: `flutter test test/workspace_pdf/pdf_object_transform_overlay_test.dart test/workspace_pdf/pdf_page_object_test.dart`

Expected: preview geometry tests pass.

- [ ] **Step 5: Write failing native transform round-trip tests**

Open a fixture, inspect a text object, apply translation/rotation/resize through the coordinator, encode, reopen, and assert the object type and matrix within `0.01`. Assert unrelated objects retain their original matrices.

- [ ] **Step 6: Run native round-trip test and verify RED**

Run: `flutter test test/workspace_pdf/pdf_object_transform_round_trip_test.dart`

Expected: at least the text transform persistence assertion fails on the current split path.

- [ ] **Step 7: Implement shared PDFium transform projection**

Resolve the locator on the worker, call the supported PDFium matrix API on the genuine page object, regenerate only the affected page, reinspect the object, and return its authoritative transform/bounds. Text resize continues through native reflow; text move/rotation use the page-object matrix without rebuilding unrelated glyph objects.

- [ ] **Step 8: Paint and commit the same preview**

Both overlays render from `PdfObjectTransformPreview.after`. Pointer-up submits the exact after state through `dispatchAndProjectQueued`; failure replaces the preview with the authoritative before state. Remove `_previewBounds` paths that are not connected to native projection.

- [ ] **Step 9: Run focused tests and commit**

Run: `flutter test test/workspace_pdf/pdf_object_transform_overlay_test.dart test/workspace_pdf/pdf_live_resize_reflow_test.dart test/workspace_pdf/pdf_object_transform_round_trip_test.dart test/workspace_pdf/pdf_page_object_engine_test.dart`

Expected: all tests pass and reopened matrices match.

Commit:

```powershell
git add lib/src/features/workspace/domain/pdf_page_object.dart lib/src/features/workspace/application/pdf_editing_controller.dart lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart lib/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart lib/src/features/workspace/presentation/widgets/pdf_object_transform_overlay.dart test/workspace_pdf/pdf_live_resize_reflow_test.dart test/workspace_pdf/pdf_object_transform_overlay_test.dart test/workspace_pdf/pdf_object_transform_round_trip_test.dart
git commit -m "fix: project PDF object transforms to native content"
```

### Task 4: Complete Windows font discovery from OpenType metadata

**Files:**
- Create: `lib/src/features/workspace/infrastructure/opentype_font_parser.dart`
- Create: `lib/src/features/workspace/infrastructure/windows_font_source.dart`
- Modify: `lib/src/features/workspace/infrastructure/installed_font_catalog.dart`
- Test: `test/workspace_pdf/opentype_font_parser_test.dart`
- Test: `test/workspace_pdf/windows_font_source_test.dart`
- Modify: `test/workspace_pdf/installed_font_catalog_test.dart`
- Test fixture: `test/fixtures/fonts/clarix_test_collection.ttc`

**Interfaces:**
- Produces: `OpenTypeFontParser.parse(Uint8List bytes) -> List<OpenTypeFaceMetadata>`.
- Produces: `WindowsFontSource.registeredPaths() -> Future<Set<String>>` and injectable `RegistryFontPathReader`.
- Produces: `InstalledFontCatalog.scan({WindowsFontSource? source, OpenTypeFontParser? parser})`.
- Consumes: existing `InstalledFontFace`, extended with `faceIndex`, `postScriptName`, `unicodeRanges`, and an explicit usability reason.

- [ ] **Step 1: Add a deterministic TTC fixture and failing parser tests**

The fixture contains two tiny faces with different family/subfamily names,
weights, cmap ranges, and OS/2 `fsType` values. Assert:

```dart
final faces = OpenTypeFontParser().parse(await fixture.readAsBytes());
expect(faces.map((face) => face.family), ['Clarix Sans', 'Clarix Serif']);
expect(faces.first.weight, 400);
expect(faces.last.weight, 700);
expect(faces.first.embeddingRights, FontEmbeddingRights.editable);
expect(faces.last.unicodeRanges, contains('Cyrillic'));
```

- [ ] **Step 2: Run parser tests and verify RED**

Run: `flutter test test/workspace_pdf/opentype_font_parser_test.dart`

Expected: compilation fails because the parser does not exist.

- [ ] **Step 3: Implement bounds-checked OpenType parsing**

Parse sfnt and `ttcf` headers, table directories, Windows/Unicode name records, OS/2 weight/width/fsType, and Unicode cmap formats 4 and 12. Every read checks buffer bounds and throws `FormatException` naming the table and offset. Return one metadata record per TTC face.

- [ ] **Step 4: Run parser tests and verify GREEN**

Run: `flutter test test/workspace_pdf/opentype_font_parser_test.dart`

Expected: all parser tests, including truncated/corrupt input cases, pass.

- [ ] **Step 5: Write failing registered-path source tests**

Inject registry output for machine and user font keys containing absolute paths, relative filenames, duplicates, missing files, `.ttf`, `.otf`, and `.ttc`. Assert paths resolve against `%WINDIR%\Fonts` and `%LOCALAPPDATA%\Microsoft\Windows\Fonts`, normalize case-insensitively, and retain only supported containers.

- [ ] **Step 6: Run source tests and verify RED**

Run: `flutter test test/workspace_pdf/windows_font_source_test.dart`

Expected: compilation fails because `WindowsFontSource` does not exist.

- [ ] **Step 7: Implement Windows font path discovery**

Use an injectable reader whose production implementation invokes `reg.exe query` for:

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts
HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts
```

Parse `REG_SZ` values without shell interpolation, merge directory fallback enumeration, and skip vanished/inaccessible files. On non-Windows platforms return directory fallback paths only.

- [ ] **Step 8: Run source tests and verify GREEN**

Run: `flutter test test/workspace_pdf/windows_font_source_test.dart`

Expected: all resolution and deduplication tests pass.

- [ ] **Step 9: Write failing catalog construction and matching tests**

Assert all TTC faces appear in `families`, restricted faces remain discoverable with `mayEmbed == false`, exact family wins before substitutes, script coverage uses cmap data, duplicate registrations collapse, and a restricted requested family yields an explicit disabled reason instead of disappearing.

- [ ] **Step 10: Run catalog tests and verify RED**

Run: `flutter test test/workspace_pdf/installed_font_catalog_test.dart`

Expected: the current filename parser and restricted-face filtering fail the assertions.

- [ ] **Step 11: Rebuild the catalog around parsed metadata**

Remove `_faceFromFile` filename heuristics and the fake all-script set. Build `InstalledFontFace` from parser metadata, retain restricted faces in the catalog, filter only within `match`, and return a structured `FontMatchUnavailable` reason when the exact family is installed but unusable.

- [ ] **Step 12: Run font tests and commit**

Run: `flutter test test/workspace_pdf/opentype_font_parser_test.dart test/workspace_pdf/windows_font_source_test.dart test/workspace_pdf/installed_font_catalog_test.dart`

Expected: all font tests pass.

Commit:

```powershell
git add lib/src/features/workspace/infrastructure/opentype_font_parser.dart lib/src/features/workspace/infrastructure/windows_font_source.dart lib/src/features/workspace/infrastructure/installed_font_catalog.dart test/workspace_pdf/opentype_font_parser_test.dart test/workspace_pdf/windows_font_source_test.dart test/workspace_pdf/installed_font_catalog_test.dart test/fixtures/fonts/clarix_test_collection.ttc
git commit -m "feat: discover complete Windows font metadata"
```

### Task 5: Searchable font picker and alignment toggle controls

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/pdf_font_family_picker.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_body.dart`
- Test: `test/workspace_pdf/pdf_font_family_picker_test.dart`
- Modify: `test/workspace_pdf/pdf_text_format_panel_test.dart`

**Interfaces:**
- Consumes: Task 4 `InstalledFontCatalog.faces`, families, embedding eligibility, and reasons.
- Produces: `PdfFontFamilyOption` and `PdfFontFamilyPicker` with search, selection, disabled state, and document-font labelling.
- Consumes: Task 2 focus restoration callback after formatting.

- [ ] **Step 1: Write failing searchable-picker tests**

Pump options for Arial, Calibri, a restricted family, and an embedded-only document font. Open the picker, enter `cal`, and assert only Calibri remains. Verify arrow/Enter selection, Escape dismissal, disabled restricted option with its reason, and the `Document font` label.

- [ ] **Step 2: Run picker tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_font_family_picker_test.dart`

Expected: compilation fails because the picker types do not exist.

- [ ] **Step 3: Implement the searchable picker**

Use a text field plus anchored Material overlay/list, case-insensitive family and PostScript-name filtering, deterministic alphabetical ordering, and bounded list height. Expose semantic selected/disabled state and keys `pdf-font-search`, `pdf-font-option-<normalized-family>`.

- [ ] **Step 4: Run picker tests and verify GREEN**

Run: `flutter test test/workspace_pdf/pdf_font_family_picker_test.dart`

Expected: all picker tests pass.

- [ ] **Step 5: Write failing format-panel tests**

Replace expectations for `DropdownButtonFormField` with the picker. Assert four alignment buttons exist, only the active alignment has `selected == true`, clicking Right emits `PdfTextStylePatch(alignment: PdfTextAlignment.right)`, mixed alignment has no selected button, and formatting invokes `onRestoreEditorFocus` after the awaited intent completes.

- [ ] **Step 6: Run panel tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_text_format_panel_test.dart`

Expected: alignment dropdown and synchronous callback behavior fail.

- [ ] **Step 7: Implement inspector controls**

Replace the family dropdown with `PdfFontFamilyPicker`. Replace alignment dropdown with four compact icon `_Toggle` controls using `Icons.format_align_left`, `format_align_center`, `format_align_right`, and `format_align_justify`, tooltips, and `Semantics(selected: ...)`. Change `_apply` to await `Future<void> Function(PdfEditIntent)`, then call `onRestoreEditorFocus` when text editing remains active.

- [ ] **Step 8: Wire catalog options and document font**

In `_TextFormatPane`, map every catalog family to its eligibility and reason, prepend the current embedded PDF family when absent, and await controller dispatch. Preserve substitution and overflow messages adjacent to their controls.

- [ ] **Step 9: Run panel tests and commit**

Run: `flutter test test/workspace_pdf/pdf_font_family_picker_test.dart test/workspace_pdf/pdf_text_format_panel_test.dart test/workspace_pdf/pdf_live_edit_controller_test.dart`

Expected: all picker, panel, and focus tests pass.

Commit:

```powershell
git add lib/src/features/workspace/presentation/widgets/pdf_font_family_picker.dart lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart test/workspace_pdf/pdf_font_family_picker_test.dart test/workspace_pdf/pdf_text_format_panel_test.dart
git commit -m "feat: add searchable PDF font formatting controls"
```

### Task 6: Saved-document validation and full regression qualification

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Modify: `test/workspace_pdf/pdf_edit_save_service_test.dart`
- Modify: `test/workspace_pdf/pdf_text_round_trip_test.dart`
- Modify: `integration_test/pdf_text_editing_test.dart`
- Create: `integration_test/pdf_editing_desktop_workflow_test.dart`

**Interfaces:**
- Consumes: live encoded PDF from Tasks 2-3 and embedded font choices from Tasks 4-5.
- Produces: `PdfEncodedValidationExpectation` with expected edited text and object transforms.
- Produces: transactional save that rebases the session only after reopen validation succeeds.

- [ ] **Step 1: Write failing transactional validation tests**

Pass encoded bytes whose PDF opens but contains the old text or old transform. Assert `saveEncoded` rejects the candidate, preserves the original file byte-for-byte, leaves the session dirty, and returns the validation failure. Add a passing candidate assertion that replaces the destination and returns a new revision.

- [ ] **Step 2: Run save tests and verify RED**

Run: `flutter test test/workspace_pdf/pdf_edit_save_service_test.dart`

Expected: current validation checks page loading but not expected content and transforms.

- [ ] **Step 3: Implement expectation-based reopen validation**

Add `PdfEncodedValidationExpectation` containing expected text by locator/page and expected matrices. Write candidate bytes to the existing temporary sibling, reopen with pdfrx/PDFium, extract text, inspect objects, compare matrices within `0.01`, then atomically replace. Delete only the known temporary sibling on failure.

- [ ] **Step 4: Run save tests and verify GREEN**

Run: `flutter test test/workspace_pdf/pdf_edit_save_service_test.dart`

Expected: all transactional and validation tests pass.

- [ ] **Step 5: Extend the native round-trip test**

In one fixture workflow: enter text editing, select a word, replace and delete text, apply an installed embeddable test font, right-align, move, resize, rotate, undo, redo, encode, reopen, and assert extracted Unicode, search match, font/style metadata where PDFium exposes it, and final transform.

- [ ] **Step 6: Run native round trip and verify RED then GREEN**

Run before final fixes: `flutter test test/workspace_pdf/pdf_text_round_trip_test.dart`

Expected RED: the first uncovered requirement fails with a precise assertion.

Apply only the minimal production correction required by that assertion, then rerun the same command.

Expected GREEN: the complete reopened-document workflow passes.

- [ ] **Step 7: Add the desktop workflow integration test**

Drive the real workspace with a fixture and assert Edit mode suppresses pdfrx reader selection, single-click selects, double-click activates native input, Backspace and typing change rendered/extracted text, the font search filters, alignment toggles, movement changes inspected geometry, and Save/reopen preserves the result. Guard Windows-only registry assertions with `Platform.isWindows` while keeping the document workflow cross-platform.

- [ ] **Step 8: Run focused integration tests**

Run: `flutter test integration_test/pdf_text_editing_test.dart integration_test/pdf_editing_desktop_workflow_test.dart -d windows`

Expected: both integration workflows pass on Windows.

- [ ] **Step 9: Run the complete verification suite**

Run:

```powershell
flutter test
flutter analyze
flutter build windows
```

Expected: tests report zero failures, analyzer reports `No issues found!`, and Windows build exits successfully.

- [ ] **Step 10: Review the final diff against the specification**

Check every completion criterion in `docs/superpowers/specs/2026-08-14-pdf-editing-interaction-font-repair-design.md`, run `git diff --check`, and confirm no generated build artifacts or unrelated user changes are staged.

- [ ] **Step 11: Commit the validated workflow**

```powershell
git add lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart lib/src/features/workspace/application/pdf_editing_controller.dart test/workspace_pdf/pdf_edit_save_service_test.dart test/workspace_pdf/pdf_text_round_trip_test.dart integration_test/pdf_text_editing_test.dart integration_test/pdf_editing_desktop_workflow_test.dart
git commit -m "test: verify native PDF editing workflow"
```
