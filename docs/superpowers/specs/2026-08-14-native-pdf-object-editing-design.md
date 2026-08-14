# Native PDF Object Editing Design

## Purpose

Clarix currently places a Flutter text field over text that the PDF viewer is
still rendering. The result is doubled glyphs, incorrect font scaling, and a
visual editing surface that does not line up with the genuine PDF object.

This change introduces an in-memory native preview document. Selecting text
hides only the corresponding native text objects in that preview while Clarix
draws a precisely transformed editor. The source file is not modified until a
validated transactional save. The same editing model also supports moving,
resizing, and rotating safe top-level text, image, and vector-path objects.

## Scope

The first object-editing release supports:

- direct editing of genuine existing PDF text objects;
- move, resize, and rotation of top-level text objects;
- move and rotation of top-level image and vector-path objects;
- resize where PDFium exposes a safe, type-preserving transform;
- subtle bounds and transform handles in object-edit mode;
- one chronological undo/redo history for text and object operations;
- identical manual and agent intent semantics;
- transactional save and genuine-object round-trip validation.

Nested or shared form objects are discovered for inspection but remain
read-only. OCR, image-to-text conversion, vector-outline text editing, linked
cross-page flow, and arbitrary content-stream rewriting remain out of scope.

## Root Cause

`PdfTextEditorOverlay` replaces a selected outline with a Flutter `TextField`,
but `PdfViewer` continues to paint the original page underneath it. The field
also uses PDF font points directly as Flutter logical pixels without applying
the page scale, native transform, or baseline mapping. Both layers therefore
remain visible and diverge as zoom, font size, or rotation increases.

The fix must remove the selected native glyphs from the preview render and map
the editor through the same PDF-to-view transform used by the page. Painting an
opaque rectangle over the original is rejected because it corrupts previews on
non-uniform backgrounds.

## Domain Model

Introduce a generic `PdfPageObject` model containing:

- a stable locator composed of page number, top-level object path, object type,
  geometry digest, content digest, and source revision;
- `PdfPageObjectType`: text, image, path, or form;
- native bounds and affine transform;
- a set of capabilities: inspect, editText, move, resize, rotate;
- an optional read-only reason.

`PdfTextBlock` remains the text-specific aggregate for grouped text objects,
text runs, styles, baselines, and replacement/reflow behavior. It references
the underlying page-object locators rather than replacing the generic model.

Transforms are represented as complete affine matrices. Commands store exact
before and after matrices so undo and redo preserve existing rotation, skew,
scale, and translation without decomposing and reconstructing them lossy.

## Native Preview Document

Add a `PdfPreviewDocumentController` per open tab. It owns temporary mutations
of the already-open in-memory PDF document and never writes the source path.

For an active text editor it:

1. resolves every native object in the selected text block;
2. records its original text render mode;
3. sets those objects to an invisible render mode;
4. regenerates and invalidates only the affected page;
5. restores or reapplies native content when editing ends, undo/redo runs, the
   selection changes, or object-edit mode closes.

For geometry previews it applies the draft affine matrix to the resolved
top-level object and invalidates only that page. Gesture updates may be
coalesced to one update per frame. The domain session remains authoritative;
preview state can always be discarded and rebuilt from it.

If native preview mutation fails, Clarix restores the last known preview,
keeps the draft and source file unchanged, and displays a typed recovery error.

## Transform-Aware Text Editor

Replace the selected-block `TextField` presentation with a focused editor whose
layout is derived from the page transform:

- font points are multiplied by the current PDF-to-view scale;
- the editor origin is aligned to the native baseline, not the bounds' top;
- the block affine transform is applied around the correct PDF origin;
- padding and Material decoration do not alter glyph placement;
- selection, caret, keyboard navigation, clipboard actions, and IME input
  remain available;
- mixed-style text uses the draft text-run model for painting and formatting.

Only the active block receives an editable glyph layer. Other page objects are
painted by PDFium. Leaving object-edit mode removes every bound, handle, and
Flutter glyph layer.

## Object Interaction

Object-edit mode displays subtle type-aware bounds on visible pages.

- Click selects the topmost safe object at the pointer.
- Drag inside the selected bounds moves the object.
- Edge and corner handles resize objects with resize capability.
- A rotation handle above the bounds rotates around the object's transformed
  center. Holding Shift snaps to 15-degree increments.
- Escape cancels the active gesture or text interaction.
- Clicking elsewhere finishes the current preview interaction and selects the
  next object when applicable.

Bounds and handles follow the transformed quadrilateral instead of assuming an
axis-aligned rectangle. Hit testing converts pointer coordinates back through
the page and object transforms.

## Commands, Undo, and Agent Tools

Extend the shared intent pipeline with generic object operations:

- `MovePdfPageObjectIntent`;
- `ResizePdfPageObjectIntent`;
- `RotatePdfPageObjectIntent`.

Their commands contain the object locator and exact before/after matrices.
Text-specific replace and format intents remain unchanged. Gesture updates are
preview-only until pointer-up, which emits one undoable command. Typing retains
its existing coalescing boundaries.

Expose inspect, move, resize, and rotate tools through `AiToolRegistry` using
strict schemas. Manual and agent calls pass through the same dispatcher,
capability validation, stale-revision checks, risk classification, permission
policy, and command history. Generic object transforms are classified as risky
because they alter page layout.

## Native Save

Save continues to use a working copy:

1. verify the source revision;
2. open a working copy;
3. resolve every changed object by stable locator;
4. apply text content/style changes and full affine matrices;
5. regenerate affected page content;
6. reopen and validate the output;
7. atomically replace the destination;
8. reload the viewer and establish a new saved checkpoint.

Validation confirms that edited text remains selectable, searchable, and
extractable. It also confirms that moved or rotated images and paths retain
their original PDF object type. A failed operation never marks the session
clean and never overwrites the original.

## Error Handling

Typed failures cover:

- stale or ambiguous object locator;
- unsupported or nested/shared object;
- preview mutation or page regeneration failure;
- invalid or singular transform;
- text overflow;
- font substitution or prohibited embedding;
- external source revision conflict;
- validation or atomic replacement failure.

Stale objects trigger page rediscovery before another mutation. Unsupported
objects remain visible with a lock indicator. Preview failure falls back to the
unchanged native page while preserving the domain draft.

## Performance

- Selection-to-hidden-native-preview should complete within one rendered frame
  after the page and object index are warm.
- Typing must not reparse the document or encode a PDF.
- Gesture previews invalidate only the affected page and coalesce to at most one
  native update per frame.
- Offscreen object discovery remains cancellable.
- Full encoding and validation occur only on Save or Save a Copy.

## Testing and Acceptance

Domain tests cover stable locators, capability validation, exact matrix
round-trips, gesture command coalescing, chronological undo/redo, and agent
permission classification.

Widget tests verify that selecting editable text requests native suppression
before showing the editor, uses scaled font and baseline geometry, displays a
rotation handle, snaps with Shift, and removes all editing UI in reading mode.

Native tests verify discovery and type classification for text, image, path,
and form objects; safe top-level transforms; nested-form rejection; preview
render-mode restoration; page regeneration; and preservation of unrelated
objects.

Round-trip tests save, reopen, select, search, and extract rotated edited text.
They also verify that transformed images and paths retain their object type and
that failed saves leave the source bytes unchanged.

Release acceptance uses a representative PDF with text over non-uniform page
content. Edit mode must show one glyph layer, typing must visually replace the
native text without a cover rectangle, and the saved result must reopen as
genuine selectable/searchable text in Clarix and an external PDF reader.
