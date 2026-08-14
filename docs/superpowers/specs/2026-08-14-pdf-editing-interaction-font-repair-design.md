# PDF Editing Interaction and Font Repair Design

**Date:** 2026-08-14

**Status:** Approved for implementation planning

## Purpose

Repair Clarix's existing native PDF text editor so Edit mode behaves like a
desktop object editor: users can select genuine PDF text, enter text editing,
type or delete content with immediate native rendering, transform the actual
page object, choose from installed fonts, and save a PDF whose edited text
remains selectable and searchable.

This design is a corrective addendum to
`2026-08-13-pdf-text-editing-design.md`,
`2026-08-14-native-pdf-object-editing-design.md`, and
`2026-08-14-live-native-pdf-text-editing-design.md`. Where their interaction
or font-discovery details conflict with this document, this document wins.

## Root Causes

The current feature contains the native mutation primitives but does not join
them into a reliable desktop interaction:

1. `PdfViewer` keeps pdfrx reader text selection enabled in Edit mode. Its
   gesture recognizer can produce the normal blue selection instead of letting
   the editor own the pointer sequence.
2. The page overlay implements only single-tap block selection. It lacks
   explicit transitions for object selection, text-edit activation,
   select-word, select-block, and drag selection.
3. The nonpainting `TextInputClient` requests focus only when mounted. Pointer
   interaction and side-panel focus changes do not reliably restore the input
   connection, and asynchronous mutation errors are discarded by `unawaited`.
4. Text block movement and generic page-object transforms use separate preview
   paths. Some local preview geometry is not painted, so the outline can move
   independently of the live native object or appear not to move at all.
5. Installed fonts are inferred from filenames in two directories. The scan
   omits TrueType collections and Windows registration metadata, misidentifies
   many families and faces, and offers the result through a non-searchable
   dropdown.
6. Existing tests prove isolated callbacks but do not exercise pdfrx gesture
   arbitration, focus reacquisition, Windows font discovery, or a saved and
   reopened native document.

## Architectural Decision

Keep PDFium as the native editing engine and pdfrx as the viewer. Do not add a
Rust bridge for this repair.

PDFium already exposes the page objects, fonts, transforms, content generation,
encoding, and worker-isolate ownership required by the feature. A Rust and
HarfBuzz service remains a possible future layout implementation for scripts
that need shaping beyond the supported PDFium path, but it is not required to
make the existing supported text editable.

The domain session remains authoritative for commands, history, dirty state,
and permissions. The live PDFium document remains the rendered projection of
that session. Flutter paints only editor chrome; it never paints replacement
glyphs.

## Interaction State Machine

The editor has three explicit interaction states:

- **Reading:** pdfrx owns text selection and its normal context menu. No edit
  bounds or edit hit targets exist.
- **Object selected:** Clarix owns pointer interaction over editable page
  objects. The selected object has a bounding box and transform handles, but
  keyboard text input is inactive.
- **Text editing:** Clarix owns text gestures and keyboard input for one text
  block. PDFium continues to paint every glyph; Flutter paints native-derived
  caret and selection chrome.

Entering Edit mode disables pdfrx text selection while preserving viewer pan
and zoom. Leaving Edit mode restores reader selection.

Within Edit mode:

- One click selects the topmost editable block or page object.
- A second click or a double-click on selected text enters text editing and
  selects the word under the pointer.
- A triple-click selects the block's complete text.
- A click while editing places the caret using native character geometry.
- Pointer drag while editing creates a UTF-16 range from native character
  boxes.
- Shift+click extends the current range.
- Backspace, Delete, typing, paste, cut, arrow navigation, Home, End, and
  Ctrl+A operate on the active native selection.
- Escape leaves text editing and returns to object selection; a second Escape
  clears object selection.
- Clicking a different object commits accepted input, ends composition, and
  selects the new object.

Unsupported or read-only text can be selected as an object for inspection but
must display a lock reason and cannot enter text editing.

## Input and Native Projection

`PdfNativeTextInput` becomes a focusable editing endpoint with an explicit
`activate()`/focus contract controlled by the interaction state. Entering text
editing, clicking inside the active block, or returning from the format pane
must restore focus and a valid Windows text-input connection.

Text deltas become `ReplacePdfTextIntent` values as they do today. The
presentation layer awaits them through a serialized edit queue and reports
failures to the workspace error surface. It must not discard projection
failures in an `unawaited` future.

Each accepted state is projected to the live PDFium document on its owning
worker. Affected pages are regenerated and invalidated. Newer complete block
states may supersede queued older states, but ordering, history, and errors
remain observable. No Flutter replacement glyph layer or raster patch is
allowed.

Native projection returns the character boxes for the resulting state. The
controller ignores stale projection revisions and publishes only geometry that
matches the current block revision.

## Object Movement, Resize, and Rotation

Text and generic page objects share one transform-preview contract:

1. Pointer-down captures the authoritative domain transform and native object
   locator.
2. Pointer movement computes a transform in PDF page coordinates.
3. The overlay paints from that preview transform while the coordinator applies
   the same transform to the live native object.
4. Pointer-up emits one reversible intent containing the exact before and after
   state.
5. Success keeps the projected native state; failure restores both the domain
   state and native projection and presents the error.

Dragging inside a selected object moves it. Dedicated edge and corner handles
resize only objects whose capabilities permit resizing. A rotation handle
rotates around the transformed object center. Text block resizing changes its
reflow boundary; it does not implicitly change font size.

The overlay must use transformed quadrilaterals for hit testing and chrome when
the source object is rotated or skewed. A local bounding box may not be treated
as proof that the PDF object moved.

## Font Discovery and Matching

Installed-font discovery is a Windows service with a platform-independent
catalog interface.

On Windows it reads the machine and current-user font registration keys, then
resolves registered paths against the system and per-user font directories. It
also scans those directories as a fallback. Supported containers are `.ttf`,
`.otf`, and `.ttc`.

Family, subfamily, PostScript name, weight, width, italic state, Unicode
coverage, and embedding rights come from OpenType name, OS/2, cmap, and related
tables—not filenames. Every face in a TrueType collection is represented.
Duplicate registrations are coalesced by normalized family, face, and source
identity. An unreadable or disappearing font is skipped without failing the
whole catalog.

The picker lists all discovered families, including non-embeddable families.
Faces that cannot legally or technically be embedded are visibly disabled for
PDF replacement and explain why. This distinguishes “installed” from “usable
for this edit” instead of silently omitting fonts.

Matching prefers the exact normalized family and compatible face, then script
coverage, embedding permission, weight, slant, and width. Substitution is never
silent: the panel names the chosen face before the mutation is committed.

## Format Panel

The right-side Text Format pane remains a restrained inspector rather than a
form made of large cards.

- Font family uses a searchable combobox with keyboard navigation and
  virtualized results.
- The current PDF font appears even when it is embedded-only and not installed;
  it is labelled as a document font.
- Font size remains an editable numeric field.
- Bold, italic, underline, superscript, and subscript remain toggle buttons.
- Left, center, right, and justify are mutually exclusive icon toggle buttons
  with tooltips and accessible selected state.
- Mixed selections show an indeterminate state rather than a false default.
- Choosing formatting restores focus to the native editor when appropriate.
- Font substitution, unsupported glyphs, overflow, and embedding restrictions
  are shown next to the affected control.

The visual thesis is a compact desktop inspector: neutral surfaces, one blue
selection accent, dense controls, and no ornamental chrome. The interaction
thesis is immediate state feedback: selected toggles change in place, search
filters as the user types, and native page refresh follows accepted edits
without decorative animation.

## Save and Validation

Save encodes the current live PDFium document transactionally. It does not
replay a second approximate mutation implementation against the source file.

Before replacing the destination, validation reopens the candidate and checks:

- the document and all pages load;
- edited text extracts to the expected Unicode content;
- edited text remains searchable and selectable;
- edited page objects have the committed transforms;
- required fonts are embedded or legally referenced as intended;
- unrelated page objects and page count remain intact.

Failure leaves the original file unchanged and the edit session dirty. A
successful save rebases locators and the source revision before further edits.

## Error Handling

All pointer, input, font, projection, and save operations have an awaited owner.
Errors are mapped to actionable workspace messages:

- unsupported or stale PDF object;
- native text encoding failure;
- unavailable glyph or font face;
- prohibited font embedding;
- text overflow;
- invalid transform;
- native projection or page regeneration failure;
- external source revision conflict;
- validation or atomic replacement failure.

On mutation failure the controller restores the previous domain state and
native projection. The editor remains usable, and the failure is not mistaken
for successful typing.

## Test Strategy

Implementation follows test-first development. Required regression coverage:

1. Viewer/widget tests prove reader selection is enabled only in Reading mode
   and editor gestures own the same text in Edit mode.
2. Interaction tests cover single-, double-, and triple-click, caret placement,
   drag and Shift selection, Backspace/Delete, typing, paste, focus loss and
   reacquisition, Escape, and keyboard navigation.
3. Controller tests prove every presentation mutation is awaited, serialized,
   projected, revision-checked, and rolled back on failure.
4. Native fixture tests type, delete, move, resize, rotate, format, encode,
   reopen, extract, search, and inspect transforms in the resulting PDF.
5. Font tests cover registry paths, per-user fonts, `.ttc` faces, OpenType
   metadata, duplicate families, embedding rights, Unicode coverage, and
   substitution ordering.
6. Format-panel tests cover searchable filtering, document-font labelling,
   disabled faces, mixed state, alignment toggle semantics, keyboard access,
   and focus restoration.
7. A Windows integration test exercises a real text-input connection and a
   representative installed-font catalog.

The full Flutter test suite, static analysis, Windows build, and a saved-file
round trip must pass before the repair is considered complete.

## Scope Boundaries

This repair supports genuine text objects for which Clarix can obtain reliable
Unicode mapping, glyph metrics, and a safe editable object path. OCR, outlined
text, arbitrary content-stream rewriting, linked-frame reflow, and new complex
script shaping are not introduced here. Unsupported content remains visibly
read-only rather than being edited approximately.

## Completion Criteria

The repair is complete when, on Windows, a user can enter Edit mode without
pdfrx's blue reader selection intercepting the gesture; select a supported text
block; double-click a word; type, paste, Backspace, or Delete and see the
PDFium-rendered text update; move or resize the actual object; search all
installed font families and apply a permitted face; toggle paragraph alignment;
undo and redo the operations; save; reopen the file; and select, search, and
extract the edited text with the committed object geometry intact.
