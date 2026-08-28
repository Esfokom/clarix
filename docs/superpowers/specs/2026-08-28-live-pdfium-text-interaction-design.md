# Live PDFium Text Interaction and Transform Design

## Goal

Make text editing in the interactive PDF editor operate on the visible PDFium
text objects. A click places a caret without repainting existing glyphs;
keyboard navigation moves that caret; insertion and deletion mutate the live
PDF; and move, resize, and rotate handles transform the native text content as
well as the Flutter interaction chrome.

This design is a focused continuation of
`docs/superpowers/specs/2026-08-27-unified-pdfium-editor-design.md`.

## Scope

Supported objects are PDF text objects imported by the live PDFium owner.
Text replacement, movement, resizing, and rotation must affect those native
objects. Images, paths, annotations, and Form XObjects are outside this
delivery and must not expose text transform handles.

The existing PDF page remains the visual source. Flutter paints only the
caret, selection, bounding box, transform handles, and transient status UI;
it never paints the unchanged PDF text as an editor overlay.

## Diagnosed Gaps

The current session can contain two incompatible object identity domains. A
recovered page may contain span-derived `pdf-oxide` IDs while the live PDFium
manifest contains path-derived IDs. The gateway currently catches the
hydration conflict, registers the live manifest, and continues showing the
recovered semantic scene. Commands for that scene's object IDs are not in the
live locator registry and therefore fall through to the semantic-only port.
The caret moves in Flutter, but the rendered PDF never changes.

`SessionTextInput` is a manual `TextInputClient`. It handles platform editing
updates, Escape, and undo/redo, but it does not implement desktop navigation
and deletion shortcuts that `EditableText` normally supplies.

Rust represents semantic move, resize, and rotate commands, but its
`PhysicalEditOperation` contains only `ReplaceText`. The Dart live plan and
PDFium worker are likewise replacement-only. Transform handles consequently
update scene geometry without changing the PDF page object.

## Canonical Identity and Hydration

A live-PDFium editor session has exactly one editable identity domain:

```text
source fingerprint + recursive PDFium object paths
  -> stable source key
  -> stable UUIDv5 semantic object ID
  -> Rust scene object
  -> Flutter locator registry entry
```

Live page import becomes authoritative for editable text pages. Rust must
accept an explicit canonical-live hydration operation rather than treating a
different prior projection as an ordinary duplicate hydration.

At revision zero, a conflicting non-live projection can be replaced by the
live projection because no user command has committed against it. At a
nonzero recovered revision, Rust must return a typed
`live_projection_migration_required` error. It must not discard the recovered
state or guess object correspondence from text, coordinates, or ordering.

The gateway registers locator bindings only after Rust accepts the live page.
Once a session is live-PDFium backed, a text command without a binding fails
with `live_pdfium_binding_missing`; it never falls through to a legacy
semantic submission. Page-scene requests return the same live object IDs that
the registry contains.

## Caret and Keyboard Editing

`SessionTextInput` remains invisible and retains the system text-input
connection for IME, dead keys, and character insertion. Its `Focus` key
handler supplies desktop editing behavior without adding an `EditableText`
render object.

Supported keys are:

* Left and Right: collapse an expanded selection toward the pressed edge, or
  move by one Unicode grapheme cluster.
* Shift+Left and Shift+Right: extend the selection by one grapheme cluster
  while preserving its base.
* Home and End: move or extend to the beginning or end of the active text
  block.
* Backspace: delete the selection, or the grapheme cluster before the caret.
* Delete: delete the selection, or the grapheme cluster after the caret.
* Escape: close the text edit interaction.
* Ctrl+Z and Ctrl+Shift+Z: preserve undo and redo behavior.

Navigation updates only `EditorSelection` and the platform editing state. It
does not submit a document command or advance the revision. Deletion and
insertion use UTF-16 command ranges aligned to grapheme boundaries, update
the optimistic selection, and submit `ReplaceTextRange` through the live
transaction path.

IME composition stays local until committed. A rejected physical edit
restores the last acknowledged semantic text and selection and exposes an
editor error rather than leaving the caret ahead of the PDF content.

## Physical Text Operations

Rust extends the physical plan with a tagged operation vocabulary:

```rust
enum PhysicalEditOperation {
    ReplaceText { /* existing fields */ },
    SetTextTransform {
        object_id: ObjectId,
        source_key: String,
        source_revision: String,
        expected_transform: AffineTransform,
        transform: AffineTransform,
        old_bounds: PdfBox,
        new_bounds: PdfBox,
    },
}
```

Move and rotate commands emit `SetTextTransform`. Resize also emits a matrix
transform for this delivery: it scales the native text object about the
opposite resize anchor and does not introduce paragraph reflow. Forward and
inverse plans carry complete matrices so undo/redo are lossless.

The FRB DTO uses an explicit operation kind and nullable payload fields, with
conversion rejecting incomplete combinations. Dart converts the transport
operation to either `LivePdfiumTextReplacement` or
`LivePdfiumTextTransform`.

All physical operations in a command target one page and execute in one
PDFium worker callback. Before mutation, the worker resolves every recursive
object path and validates the expected text or matrix. It snapshots original
text and matrices, applies the operations, calls
`FPDFPage_GenerateContent()` while the page handle is alive, and rolls back
all already-applied operations if any validation or mutation fails.

For a multi-object text block, the same delta matrix is composed with every
physical text object in `allObjectPaths`. Directly assigning one shared matrix
would collapse objects that have distinct original matrices.

## Rendering and Interaction Geometry

A successful physical apply returns invalidations covering the union of old
and new bounds. The live tile cache evicts every intersecting prior-revision
tile, and `PageSceneLifecycle` requests new tiles from the same PDFium
document.

Rust publishes the prepared semantic command only after PDFium regenerates
successfully. The returned object patch then updates the bounding box,
transform handles, character boxes, and caret geometry to the same revision
as the raster tile.

During drag, Flutter may preview the box and caret transform for responsiveness.
On pointer release, the preview remains pending until the physical command is
acknowledged. A failed command restores the last committed geometry.

## Error Handling and Diagnostics

Editor diagnostics log one structured line at each boundary:

* hydration: page, semantic revision, existing adapter, incoming adapter, and
  resolution (`accepted`, `replaced_revision_zero`, or `migration_required`);
* routing: command kind, object ID, whether a live binding exists, source key,
  and selected port;
* preparation: command ID, previous/new revision, and physical operation
  kinds;
* PDFium apply: page, resolved object paths, validation result, regeneration
  result, and old/new invalidation bounds;
* publish: command ID and committed revision.

Logs must not include entire document text. Expected/actual text mismatches
use length and a short hash.

Typed failures are surfaced for missing bindings, stale locators, stale
matrices, unsupported non-text objects, missing glyphs, PDFium mutation
failure, regeneration failure, and recovery migration requirements. No typed
failure may silently select the semantic-only path in a live session.

## Verification

Tests must cross the boundaries that the current suite misses:

* a recovered revision-zero page is replaced with the live identity and its
  scene object ID is registered;
* a nonzero conflicting recovery is preserved and rejected with the migration
  error;
* unbound live text commands fail instead of falling back;
* left/right, Shift+left/right, Home/End, Backspace, Delete, IME commit, and
  surrogate/grapheme behavior update the expected selection or command;
* text insertion and deletion alter a newly rendered live tile without any
  `EditableText` or replacement text overlay;
* move, resize, and rotate alter the PDFium object matrix, rerender both old
  and new bounds, and persist through save/reopen;
* failed transform validation leaves the PDFium raster and Rust revision
  unchanged;
* undo/redo applies inverse/forward text and transform plans to the live PDF.

## Non-Goals

This delivery does not add transforms for images, paths, annotations, or Form
XObjects. It does not implement paragraph reflow, arbitrary font replacement,
or heuristic migration from the legacy span-derived identity scheme. Those
objects and operations remain explicitly unsupported rather than being
silently approximated.
