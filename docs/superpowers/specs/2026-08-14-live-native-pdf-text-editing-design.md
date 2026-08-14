# Live Native PDF Text Editing Design

## Status and precedence

This design replaces the Flutter glyph-overlay architecture described in
`2026-08-13-pdf-text-editing-design.md` and
`2026-08-14-native-pdf-object-editing-design.md`.

The earlier domain, permission, intent, agent-tool, transactional-save, and
generic object-transform decisions remain valid unless this document changes
them explicitly. In particular, this document supersedes native text
suppression plus `EditableText` glyph painting. Clarix must never display a
Flutter-rendered imitation of selected PDF text.

## Goal

Editing existing supported text must behave like paragraph editing in Foxit
PDF Editor:

- the user clicks genuine PDF text and places a caret in that content;
- typing changes the open in-memory PDF document, not a visual substitute;
- PDFium renders the edited glyphs in the page immediately;
- resizing the selected block changes its reflow boundary;
- moving and rotating the block update the genuine PDF objects;
- undo and redo change both the domain history and the visible native page;
- disk bytes remain untouched until Save or Save a Copy;
- saved text remains selectable, searchable, and extractable.

The first delivery is paragraph/block scoped. It does not link unrelated text
blocks, push surrounding objects, or reflow across pages. Foxit-style linked
blocks and full-document reflow remain separate future modes.

## Why the current approach is invalid

The current selection path suppresses the selected native text objects and
constructs a Flutter `EditableText` over their bounds. That widget paints the
draft with a platform font, Flutter metrics, Flutter shaping, and independently
calculated geometry. The PDF page and editor therefore have different font
fallback, baseline, spacing, line breaking, scaling, clipping, and rotation.
At high zoom the divergence becomes obvious, and a delayed page refresh can
temporarily show both layers.

Improving overlay coordinates cannot solve this. Two rendering engines remain
two authorities. The selected text must continue to be rendered by PDFium, and
the UI layer must stop painting glyphs.

## Product model

The open PDF has three distinct states:

1. **Source bytes** are the last bytes read from disk. They are immutable until
   a validated save transaction replaces the destination.
2. **Live native document** is the PDFium document used by the viewer. Accepted
   commands mutate it in memory and affected pages are regenerated and
   rerendered.
3. **Domain editing session** contains structured block states, selection,
   command history, saved checkpoint, source revision, and authorization data.

The domain session remains the semantic authority for undo, redo, agent tools,
dirty state, and save validation. The live native document is its rendered,
genuine-PDF projection. Every successful content command must leave both at
the same command revision.

The original file is not a live editing surface and must not remain locked.
Before Save, closing or cancelling an editing session can discard the native
document and reopen the unchanged source bytes.

## Architecture

### Native live-edit coordinator

Add a `PdfNativeEditCoordinator` per open document. It serializes native work,
owns the live native revision, and exposes typed operations:

- begin and end block editing;
- replace a text range;
- apply formatting to a range;
- resize and reflow a block;
- move or rotate a text/object block;
- apply a command's before or after state for undo/redo;
- restore the live document to the saved or opening checkpoint;
- encode the current live document for transactional save.

All PDFium access runs through `PdfiumWorkerExecutor` on pdfrx's PDFium-owning
worker isolate. No FPDF function may execute inside
`PdfDocument.useNativeDocumentHandle` on the Flutter isolate.

Each operation carries the document revision, block locator, domain command
revision, and desired final block state. Results return the applied revision,
new native object locators, visual line data, character geometry, overflow
state, warnings, and affected pages.

### Latest-state mutation queue

Input must not wait for page rendering. Each block has a monotonically
increasing edit revision. Native mutations execute in order, but obsolete
queued states may be skipped when a newer complete state exists. Results older
than the current domain revision are discarded.

After PDFium regenerates content, only affected pages are reloaded. Viewer
invalidations are coalesced so rapid typing or resize gestures do not enqueue
unbounded page renders. The visible page always converges on the newest
accepted domain state.

Failures do not advance the native revision. The coordinator returns a typed
failure and the controller rolls the domain command back or offers recovery;
it must never leave history claiming that unapplied content is visible.

## Genuine paragraph representation

A PDF has positioned text objects rather than a word-processor paragraph.
Clarix represents a supported paragraph as a `PdfTextBlock`, then materializes
its current state as genuine page text objects.

The native block snapshot contains:

- source object paths and content digests;
- complete text and UTF-16-to-glyph mapping;
- styled runs and font handles/identities;
- fill and rendering properties;
- block bounds and full affine transform;
- writing direction, alignment, baseline, line and character spacing;
- the native objects created for each visual line/run;
- enough supported properties to reconstruct the opening and saved states.

After a mutation, the coordinator validates the locator and removes only the
objects owned by that block. It lays out the desired state, creates replacement
text objects with the actual source or approved embedded font, positions them,
applies styles and transforms, inserts them into the page, calls
`FPDFPage_GenerateContent`, then re-inspects text and geometry.

The rebuilt objects are the live PDF content. They are not annotations,
appearance streams, raster patches, or invisible search layers.

## Text input without a glyph overlay

Replace `PdfInlineTextEditor` with a nonpainting text-input client. It exists
only to integrate with Windows keyboard input, IME composition, clipboard,
accessibility, and Flutter focus. It sends `TextEditingValue` deltas into the
intent pipeline but draws no characters, background, cursor, or selection.

The page interaction layer may paint only editor chrome:

- subtle block outlines;
- transformed resize and rotation handles;
- a caret derived from native character geometry;
- selection highlights derived from native character quads;
- composition underlines and overflow indicators;
- read-only and progress affordances.

PDFium paints every visible glyph. The caret may optimistically advance from
the latest native layout response while the next page image is rendering, but
no optimistic text glyphs may be painted.

Click-to-caret and drag selection convert viewer coordinates to PDF page
coordinates and resolve the nearest character through native character boxes.
The resulting UTF-16 range is stored in `PdfTextSelection` and shared by the
format panel and agent-facing intents.

## Native layout and reflow

Reflow operates within the selected block's bounds. Resizing changes the
available width and height; it does not scale the font unless the user changes
font size explicitly.

Layout uses the actual PDF font and native metrics:

- glyph widths and source character positions where available;
- font ascent, descent, and size;
- character and word spacing;
- horizontal scaling;
- line spacing and alignment;
- style-run boundaries;
- the block's affine transform and writing direction.

The result is split into genuine text objects per visual line and style run.
Text remains in logical reading order and round-trip extraction must reproduce
the block text. Overflow blocks Save until resolved.

Initial editable content is limited to horizontal left-to-right or
right-to-left text that can be reconstructed with reliable glyph mapping and
font metrics. Type 3 fonts, outlined text, shared form content, unsupported
encodings, vertical writing, clipping-dependent text, and scripts requiring
shaping not supported by the current native pipeline remain read-only.

Rust is not required for this architecture. PDFium already provides native
text objects, fonts, glyph metrics, transforms, and content generation. A
Rust/HarfBuzz shaping service may be introduced later behind the layout
interface for complex scripts, without changing intents or presentation.

## Editing interactions

### Entering edit mode

Clarix discovers genuine blocks and generic objects for the visible page and
nearby pages. It shows bounds only; entering edit mode does not hide or replace
any text.

### Selecting and typing

Clicking a supported block captures its native baseline snapshot, focuses the
nonpainting input client, and resolves a caret. A text delta becomes a normal
`ReplacePdfTextIntent`. After permission and validation, its command updates
the domain state and is projected to PDFium immediately. The regenerated page
shows the new genuine content.

Typing remains coalesced into meaningful undo units. Native projection may run
more frequently than command boundaries; coalescing history must not delay the
visible PDF update.

### Resize, move, and rotation

Resize handles change the paragraph boundary and request native reflow. Gesture
updates are latest-state previews; pointer-up emits one resize command. The
selected outline follows the requested geometry while the native page catches
up.

Moving and rotating apply affine transforms to the block's owned objects.
Their preview is also native and rerendered by PDFium. Generic image and path
object transforms continue to use the same worker and command boundary.

### Leaving or cancelling

Clicking another block ends the current input composition but retains accepted
document edits. Leaving edit mode removes all editor chrome but does not undo
the dirty session. Closing with discard, explicit revert, or a failed session
recovery restores/reopens the appropriate checkpoint.

## Undo and redo

Each command already stores semantic before and after state. Undo applies the
before state to the domain session and sends that complete block/object state
to the native coordinator. Redo sends the after state. Neither operation
replays keyboard events.

Native object paths may change whenever a paragraph is rebuilt. The
coordinator therefore returns refreshed locators and maintains a stable
session block identity separate from transient object paths. Subsequent
commands and agent results use the refreshed locator plus the current document
revision.

Undo/redo completion is reported only after the native projection succeeds.
The viewer may display a short progress state, but it must never resurrect the
Flutter glyph editor as a fallback.

## Save transaction

Save no longer reapplies the entire draft to a clean PDF, because the live
native document already contains the accepted final command state.

Save performs:

1. Verify the destination, permissions, and unchanged source revision.
2. Encode the current live PDFium document non-incrementally.
3. Write bytes to a sibling temporary file.
4. Reopen the temporary output in an independent validation document.
5. Validate page count, edited text extraction, block geometry/style,
   transformed object types, and unaffected-page invariants.
6. Atomically replace the destination or return Save a Copy recovery.
7. Reload the viewer from the validated bytes and rediscover affected blocks.
8. Rebase live locators and record the current history cursor as the saved
   checkpoint.

The source path is unchanged before step 6. A failure leaves the current live
draft available and the original bytes intact.

After Save, undo history remains available. Undo applies against rebased block
identities in the newly loaded live document and makes the session dirty
again.

## Formatting and fonts

The Text Format panel continues to emit typed formatting intents. Applying a
style projects the new state immediately to PDFium and refreshes the page.

Clarix preserves the source font when it can encode the new text. A fallback
font must be installed, script-compatible, embeddable, and explicitly surfaced
to the user before acceptance. The exact font selected for native projection
is the font encoded on Save; preview and saved output cannot use different
faces.

If no suitable font can encode the text, the command fails without changing
the domain or native revision.

## Permissions and agent tools

Manual UI and agent tools continue through `PdfEditIntentDispatcher` and the
same command/native-projection boundary. Agent results are returned only after
the live native state has accepted the command.

Permission grants remain scoped and persistent according to the existing
`allow`, `askWhenRisky`, and `askAlways` policies. Native preview is not a way
around permission: no mutation reaches PDFium before intent authorization.

Inspection tools may return the current live block text and revision, so an
agent sees unsaved accepted edits rather than stale source bytes.

## Error handling

New or refined typed failures cover:

- native/domain revision mismatch;
- stale or ambiguous rebuilt locator;
- unsupported native reflow;
- font encoding or embedding failure;
- native projection or content-generation failure;
- page refresh failure after a successful mutation;
- text overflow;
- validation, source conflict, or atomic replacement failure.

If page refresh fails after native mutation, the coordinator retains the
native revision and retries/invalidate-renders rather than applying the same
command twice. If native mutation itself fails, it restores the block's last
accepted snapshot before returning failure.

## Performance and responsiveness

- Keyboard and IME input must remain responsive while native work is pending.
- Warm single-block mutation plus page invalidation targets a p95 below 100 ms
  on representative desktop PDFs.
- Resize and transform gestures enqueue at most one current native state per
  frame and may skip obsolete intermediate states.
- A block of 10,000 characters must not trigger whole-document parsing or PDF
  encoding per keystroke.
- Only affected pages are regenerated and reloaded.
- Native work never runs on the Flutter isolate.

If profiling cannot meet the target, optimization happens behind the native
coordinator. A painted glyph overlay is not an acceptable performance fallback.

## Testing

### Required red-green regression tests

- Selecting a block never builds an `EditableText` or any glyph-painting text
  widget over the PDF page.
- A text delta changes extraction from the open in-memory native document
  before disk Save while source file bytes remain unchanged.
- The native page contains exactly one visible representation of the selected
  paragraph after selection and after typing.
- Resizing a block changes native line breaks without changing font size and
  preserves searchable logical text.
- Moving and rotating update genuine object matrices and survive page reload.
- Undo and redo change native extraction and rendering immediately.
- Discard restores the opening/saved checkpoint.
- Save reopens with genuine selectable/searchable/extractable text.
- Every FPDF operation executes on the pdfrx owning isolate.

### Interaction tests

- Click-to-caret at multiple zoom levels, page rotations, and DPI scales.
- Keyboard navigation, selection, clipboard, IME composition, and accessibility.
- Formatting selected ranges and inherited typing style.
- Rapid typing and resize latest-state ordering.
- Overflow, read-only content, font fallback, and failed native mutation.
- Bounds, handles, caret, and selection disappear in reading mode.

### Compatibility fixtures

Qualify standard fonts, embedded TrueType/OpenType fonts, subset fonts,
multiple style runs, RTL text supported by the current shaper, rotated blocks,
non-uniform page backgrounds, and mixed text/image/path pages. Unsupported
fixtures must be predictably read-only rather than approximately edited.

## Delivery sequence

1. Introduce native live-edit coordinator, revisions, and block snapshots.
2. Add native text replacement projection and in-memory extraction tests.
3. Replace the painted inline editor with a nonpainting input client and
   native-derived caret/selection chrome.
4. Wire typing, undo, redo, discard, and page refresh to live projection.
5. Replace approximate monospaced layout with native-font paragraph layout.
6. Wire resize reflow, then text move and rotation, to native projection.
7. Change Save to validate and persist the current live native document.
8. Rebase locators after rebuild/save and harden agent results and permissions.
9. Run compatibility, performance, external-reader, and accessibility
   qualification.

Each slice must preserve genuine text, source-file safety, and the shared
manual/agent command boundary.

## Non-goals

- OCR or editing image-only text.
- Painting replacement text with Flutter, Canvas, HTML, or an annotation.
- Linked blocks or document-wide reflow in this delivery.
- Automatically moving unrelated page objects when a paragraph grows.
- Silently substituting fonts.
- Editing unsupported complex content approximately.

## Completion criteria

The feature is complete when a user can click supported genuine PDF text,
type without seeing a second glyph layer, observe PDFium-rendered native text
change before Save, resize the block and see native paragraph reflow, move or
rotate it, undo and redo every operation live, save transactionally, reopen the
file, and select/search/extract the edited text in Clarix and an external PDF
reader.
