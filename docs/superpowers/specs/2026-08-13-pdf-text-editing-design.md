# PDF Text Editing Design

## Goal

Add direct editing of genuine PDF text to the Clarix workspace. Users can enter a dedicated text-editing mode, edit selectable and searchable text in place, change its formatting from a right-side panel, undo or redo every mutation, and save the result back into the PDF. The same operations must be exposed as typed intents and permission-controlled tools for future autonomous agents.

## Product principles

- Saved edits must remain genuine PDF text objects. A rasterized page, appearance-only overlay, annotation, or invisible search layer does not satisfy this requirement.
- Reading mode stays visually clean. Text block outlines, editing handles, carets, and editing hit targets exist only in text-editing mode.
- Manual UI actions and autonomous tools use one mutation boundary and one history. Agent editing must not become a second implementation of PDF editing.
- The original file is never modified until a complete working copy passes structural and semantic validation.
- The first release edits PDFs that already contain genuine text objects. OCR and editing of image-only text are explicitly deferred.
- Editing is page- and block-scoped. It does not attempt word-processor-style document-wide reflow.

## Reference interaction model

Clarix follows the established Acrobat/Foxit paragraph-editing model:

- Text reflows within its selected text block.
- A text block remains independent from adjacent blocks and does not push unrelated page objects.
- Text does not flow automatically onto another page.
- Resizing a block changes its reflow boundary without implicitly changing font size.
- Users may move or resize a selected block.
- Linked text boxes and document-wide reflow are possible later extensions, not first-release behavior.

## Architecture

Each open document has a `PdfEditingSession` separate from persisted workspace/viewer state. It owns the current editing mode, discovered text blocks, selection and caret state, pending formatting, edit history, source revision, save checkpoint, and dirty state.

All mutations enter through `PdfEditIntentDispatcher`. Flutter widgets, keyboard shortcuts, application commands, and agent tools dispatch the same typed `PdfEditIntent` values. The dispatcher validates document identity and revision, evaluates permissions, resolves the target, and converts an accepted intent into a reversible `PdfEditCommand`.

PDFium is the content editing engine. It discovers and inspects genuine page text objects, supplies font and geometry metadata, applies approved patches to a clean working document, regenerates affected page content, embeds compatible fonts, and saves the resulting PDF. Clarix continues to use a memory-backed viewer source so the original path is not locked on Windows.

Flutter renders the active draft as an editor overlay. It does not mutate the underlying PDF for every keystroke. Save replays the ordered command result against a clean source revision, validates the output, atomically replaces the source, and reloads the viewer and editing model.

## Component boundaries

### Domain editing model

The domain layer defines:

- `PdfEditingMode`: `reading` or `text`.
- `PdfTextBlock`: stable locator, page, original revision, source text, styled runs, bounds, transform, paragraph metrics, capability flags, and read-only reason.
- `PdfTextSelection`: block locator and UTF-16 text range.
- `PdfTextStyle`: font identity, size, fill colour, weight, slant, underline, baseline shift, alignment, character spacing, line spacing, and horizontal scaling.
- `PdfEditIntent`: user/agent request to enter a mode, replace text, apply style, move or resize a block, change case matching, undo, redo, or save.
- `PdfEditCommand`: validated forward and inverse mutations plus provenance and a human-readable summary.
- `PdfEditingSession`: current blocks, active selection, commands, undo/redo stacks, saved checkpoint, and revision.

The domain layer has no Flutter, PDFium, filesystem, provider, or network dependency.

### Intent dispatcher

`PdfEditIntentDispatcher` is the only public mutation interface. It:

1. Checks that the requested document and revision match the active session.
2. Resolves block locators and text ranges.
3. Classifies risk and requests authorization from `ActionPermissionService`.
4. Validates font and edit capabilities.
5. Creates and applies one or more reversible commands.
6. Returns a structured result with revision, affected block IDs, warnings, dirty state, and undo command IDs.

Direct notifier methods may remain as thin compatibility adapters during migration, but they must dispatch intents instead of mutating document metadata themselves.

### Native text engine

The native editing boundary is divided into focused responsibilities:

- Text-object discovery and metadata extraction.
- Paragraph/block grouping.
- Stable object location and conflict resolution.
- Font inspection, matching, loading, and embedding.
- Text layout and reflow within a fixed block boundary.
- Patch application through PDFium page-object APIs.
- Output validation and atomic replacement.

The generated bridge carries data transfer objects only. Native editing rules live outside generated files.

### Presentation

The workspace viewer hosts a dedicated editor overlay component. The existing `document_workspace.dart` coordinates it but does not absorb its text layout, selection, or command logic. The right tool rail gains a Text Format tool with its own focused panel.

### Agent adapter

The agent adapter publishes tool schemas and translates validated tool arguments into `PdfEditIntent` values. It cannot call PDFium, mutate Riverpod state, or write files directly.

## Text discovery and stable locators

On entering text-editing mode, Clarix discovers visible pages first and nearby pages in the background. Discovery enumerates page objects recursively where safe and records text, character positions, object transforms, bounds, fill colour, font metadata, and rendering properties.

Compatible neighboring text objects are grouped into paragraph-level `PdfTextBlock` values using baseline proximity, writing direction, font compatibility, line spacing, geometric continuity, and reading order. Grouping must remain deterministic for identical document bytes.

A stable locator contains:

- Page number.
- Nested page-object path/index where available.
- Original text digest.
- Quantized geometry and transform.
- Font fingerprint.
- Document source revision.

Save resolves locators against the clean source. If a target cannot be resolved uniquely, Clarix reports a revision conflict and does not edit an uncertain object.

## Editing interaction

The reader toolbar gains a Text Edit toggle.

In text-editing mode:

- Editable blocks show subtle low-contrast bounds.
- Hover strengthens the bound; selection uses the accent colour.
- Clicking a block places a caret and supports typing, text selection, copy, cut, paste, Delete, Home/End, and arrow navigation.
- Escape completes the current block edit without leaving the overall mode.
- Clicking outside the block commits the current draft command unit.
- Block handles support move and resize.
- Unsupported blocks display a non-editable cursor and a concise reason when selected.

Returning to reading mode removes every editing-only visual and hit target. Existing PDF text selection and navigation resume normal behavior.

Typing is coalesced into meaningful undo units. Adjacent typing remains one command until the caret moves, selection changes, formatting changes, block focus changes, or an idle boundary expires. Paste, cut, replacement, formatting, move, and resize each create explicit commands.

## Paragraph reflow

Replacement text reflows only within the active block. The layout engine preserves the block's writing direction, alignment, font metrics, line spacing, character spacing, and transform where possible. Resizing changes the available boundary; it does not alter font size automatically.

Overflow is displayed clearly in the draft and blocks Save until the user enlarges the box, shortens the text, or explicitly changes formatting. Clarix does not silently shrink text or cover unrelated content.

## Case matching

Case matching is enabled by default for replacement operations. It detects:

- `UPPERCASE`
- `lowercase`
- `Title Case`
- Sentence case

For example, replacing `TOTAL REVENUE` with `net income` produces `NET INCOME`. Case matching applies when replacing a selected range, not during ordinary insertion. Ambiguous mixed casing is preserved exactly as typed. The user may disable case matching for the current operation or session.

## Text Format panel

The right tool rail gains a Text Format entry and opens it automatically when a text block becomes active. The panel contains:

- Searchable font-family picker.
- Font size.
- Fill colour.
- Bold and italic.
- Underline where representable.
- Superscript and subscript through baseline shift and size.
- Paragraph alignment.
- Case matching toggle.
- Advanced character spacing, line spacing, and horizontal scaling.
- Block position and dimensions.
- Reset selected formatting to original.

Controls apply to the current text selection or, when no range is selected, the entire block. Mixed-style selections show indeterminate values. New typing inherits style at the caret.

## Fonts and genuine searchable text

Clarix first attempts to preserve the original font. If it cannot encode replacement characters, Clarix chooses the closest installed compatible font based on family classification, weight, slant, width, script coverage, and metric similarity. The draft and Text Format panel show the substitution before Save.

The selected font is embedded in the saved PDF when its embedding permissions allow that use. PDFium generates the required encoding and Unicode mappings so edited content remains searchable and extractable. If no compatible embeddable font exists, Save fails with a precise message and leaves the session dirty.

Font substitution never happens invisibly. Under `askWhenRisky`, it requires permission before the command is accepted.

## Unsupported first-release content

The first release marks these objects read-only:

- Image-only or scanned text.
- Type 3 fonts.
- Text converted to vector outlines.
- Shared Form XObjects when changing one placement would change multiple uses.
- Unsupported clipping, masks, or complex positioning.
- Encrypted PDFs without modification permission.

Such content remains readable and selectable where the viewer supports it. Clarix explains the limitation rather than approximating the edit. OCR editing, linked text boxes, shared-form detachment, vertical writing refinement, and document-wide reflow are later capabilities.

## Undo, redo, and save checkpoints

All PDF mutations participate in a single chronological history, including bookmarks, highlights, text edits, formatting, movement, and agent operations. View navigation, selection, mode changes, and permission decisions do not create content history entries.

Commands store the minimum forward and inverse data necessary to restore the draft exactly. Undo moves a command to redo; a new mutation clears redo. Save records the current history position as the clean checkpoint without discarding undo history, so undoing a saved command makes the session dirty again.

## Save transaction

Save performs these steps:

1. Verify the source path, write permission, and source revision.
2. Create a sibling working PDF without modifying the source.
3. Open the working document through PDFium.
4. Resolve every edited block against its stable locator.
5. Apply the final command result to genuine PDF text objects.
6. Load and embed approved fallback fonts.
7. Regenerate affected page content.
8. Save a normalized, non-incremental output.
9. Reopen the output and validate structure and semantics.
10. Atomically replace the source where supported.
11. Reload the viewer, native text-block model, search index, and edit session.
12. Mark the current history position saved.

Validation checks page count, edited-text extraction, expected block geometry and style, unaffected-page fingerprints, font embedding/Unicode mapping, and successful reopen. A round-trip extraction must return the edited text.

Any failure preserves the original byte-for-byte and leaves the session dirty. External source changes produce a conflict with Reload and Save a Copy choices. Clarix never silently overwrites a changed source.

## Agent tools

The future agent surface exposes:

- `inspect_pdf_text_blocks`
- `get_pdf_text_block`
- `replace_pdf_text`
- `format_pdf_text`
- `move_pdf_text_block`
- `resize_pdf_text_block`
- `undo_pdf_edit`
- `redo_pdf_edit`
- `save_pdf_edits`

Every mutating request includes `documentId`, `documentRevision`, and a target locator. Bulk requests contain an explicit finite edit list. Results include affected blocks, new revision, warnings, permission state, dirty state, and undo command IDs. Stale revisions return a structured conflict.

## Permission layer

`ActionPermissionService` authorizes all agent-originated mutation intents. Supported policies are:

- `allow`: execute all operations inside the current grant scope.
- `askWhenRisky`: automatically execute reversible local edits; prompt for risky actions.
- `askAlways`: preview every mutation before applying it.

Grant scopes are one action, the current document, the current session, or a persistent workspace rule.

Risk classification is deterministic and inspectable. Inputs include edit count, affected page count, deletion ratio, font substitution, block movement, cross-page scope, and persistence to the source file. Bulk edits, substantial deletion, cross-page operations, font substitution, and Save are risky by default.

When approval is required, the tool returns `permission_required` with a structured preview. Permission events are logged separately from edit commands; undo never changes authorization.

## Error handling

Errors are typed and include the document, page, block, operation, and recovery action where applicable. Important categories are unsupported content, unavailable font, prohibited embedding, text overflow, stale locator, external revision conflict, encrypted document, validation failure, and atomic replacement failure.

No error path marks the session clean unless the validated output replaced the intended destination and reloaded successfully.

## Performance targets

- Entering edit mode outlines visible-page blocks within 250 ms after the page is already rendered on a typical desktop PDF.
- Keystroke-to-overlay latency remains below one frame at 60 Hz for an active paragraph of up to 10,000 characters.
- Offscreen discovery is cancellable and does not block scrolling.
- Undo and redo update the draft without reparsing the whole document.
- Save work runs off the UI isolate and reports progress for documents that take longer than 500 ms.

These are engineering budgets, not reasons to weaken correctness or validation.

## Testing

### Domain tests

- Intent validation and revision conflicts.
- Uppercase, lowercase, title-case, sentence-case, and ambiguous case matching.
- Typing command coalescing boundaries.
- Formatting ranges and mixed-style state.
- Move/resize commands and overflow state.
- Dirty checkpoints and undo/redo across saved positions.
- Chronological history containing manual and agent commands.
- Permission scopes and deterministic risk classification.

### Native tests

- Discovery and stable location of ordinary and nested text objects.
- Deterministic paragraph grouping.
- Standard, embedded, subset, unavailable, and Unicode fonts.
- Colour, size, style, spacing, transform, and geometry changes.
- Replacement, insertion, deletion, and paragraph reflow.
- Read-only classification of unsupported content.
- Malformed, encrypted, externally changed, and validation-failing PDFs.
- Preservation of unrelated page objects and byte-identical originals after failed saves.

### Contract and UI tests

- Manual and agent intents yield identical commands and results.
- Reading/edit mode transitions and editing-bound visibility.
- Inline caret, selection, typing, copy/cut/paste, and keyboard navigation.
- Text Format panel values, mixed states, and substitutions.
- Save/Undo/Redo shortcuts and enabled states.
- Permission previews and grant scopes.
- Overlay alignment at multiple zoom levels, rotations, and DPI settings.

### Round-trip acceptance

Saved edits must be reopened and verified as selectable, searchable, and extractable in Clarix. Release qualification also includes opening representative outputs in at least one external PDF reader and confirming the edited text remains genuine text.

## Delivery sequence

1. Native text-object inspection and stable block locators.
2. Domain intents, commands, unified history, and edit session.
3. Read/edit mode switching with block outlines.
4. Single-block inline replacement and case matching.
5. Save/reload with genuine PDF text and round-trip validation.
6. Text selection formatting and the Text Format panel.
7. Move, resize, and paragraph reflow.
8. Permission policies and agent tools.
9. Font substitution, conflicts, compatibility fixtures, and performance hardening.

Each slice must remain independently testable and preserve existing reading, bookmark, highlight, save, undo, and redo behavior.

## Non-goals

- OCR or editing image-only pages.
- Rasterizing pages to simulate edits.
- Word-processor-style document-wide layout.
- Automatic movement of unrelated page objects.
- Cross-page linked text flow in the first release.
- Editing vector-outline text as though it were text.
- Silently substituting or embedding fonts.

## Completion criteria

The feature is complete when a user can enter text-editing mode, see accurate editable bounds, replace and format supported genuine PDF text, use case matching, undo and redo the changes, save without corrupting unrelated content, reopen the PDF, and select/search/extract the edited text. Equivalent permission-authorized intents must be available to agent callers through the same command path.
