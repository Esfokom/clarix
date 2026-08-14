# Clarix Windows Editing Platform Architecture

## Document status

- **Status:** Approved master architecture
- **Date:** 2026-08-14
- **Initial platform:** Windows desktop
- **UI shell:** Flutter
- **Authoritative editing core:** Rust
- **Authoritative agent orchestrator:** Rust
- **Persistence model:** Non-destructive Clarix sidecar with explicit PDF materialization on Save
- **First delivery:** Manual native-PDF text editing

This document defines the target architecture and phased delivery sequence for
Clarix's document editing platform. It supersedes the per-keystroke native PDF
mutation strategy in the earlier PDF editing specifications. Those documents
remain useful historical records, but they are not the target architecture.

The architecture is Windows-first. Interfaces must avoid unnecessary Windows
coupling, but macOS, Linux, Android, iOS, and web delivery are not Phase 1
requirements.

## Executive summary

Clarix will treat a PDF as an immutable source document during an editing
session. Rust imports supported PDF content into a canonical document model and
stores all accepted edits in a crash-safe sidecar project. Flutter displays the
source PDF as a stable background and composes editable objects in retained
overlays. Typing, caret movement, selection, and transforms never regenerate or
reload the PDF page.

The system has two separate cores:

1. The **Document Editing Core** is deterministic. It owns document objects,
   stable identities, commands, revisions, validation, history, search,
   persistence, import, and PDF materialization.
2. The **Agent Orchestration Core** is probabilistic at the planning boundary
   but deterministic at the tool boundary. It manages conversations, plans,
   model calls, tool loops, progress, approvals, and cancellation. It cannot
   mutate a document except through the editing core's typed command gateway.

Flutter is the interaction and rendering shell. It owns the viewport, focus,
IME, pointer gestures, immediate optimistic text composition, inspector panels,
diff previews, and user approvals. Rust remains the authority for anything that
must survive a restart or be executed by an agent.

Ctrl+S or the Save button materializes the accepted sidecar state into the
opened PDF. Save writes a validated sibling temporary file and atomically
replaces the destination on Windows, retaining a recoverable backup. Save As
writes a new PDF. Autosave writes the sidecar, never the source PDF.

## Product outcomes

The architecture must support these user journeys without changing its core
boundaries.

### Manual editing

- Click supported native PDF text and place a caret at the clicked character.
- Type, delete, select, paste, and use Windows IME without page movement or
  input lag.
- Preserve the source block's font, size, color, spacing, alignment, transform,
  and line-height where the PDF provides sufficient information.
- Apply formatting, move or resize blocks, undo, redo, and recover after a
  crash.
- Keep the source PDF untouched until Save.
- Save changes into the opened PDF or use Save As to create another file.

### Selection-aware AI

- Highlight text in read mode and invoke an inline AI action.
- Carry the exact document ID, stable object ID, UTF-16 range, quoted text,
  formatting, page geometry, document revision, and nearby semantic context
  into the agent request.
- Rewrite, shorten, expand, translate, summarize, or format the selected range.
- Preview the proposed replacement in place before committing when the action
  is risky or affects more than the local selection.

### Document-wide automation

- Find or replace all occurrences using deterministic search tools.
- Plan multi-step operations and call the correct tools autonomously.
- Inspect changes, recover from revision conflicts, report progress, and remain
  cancellable.
- Add OCR-derived text, images, generated assets, vectors, annotations, groups,
  and page operations in later phases without replacing the text architecture.

## Non-goals and constraints

### Initial non-goals

- Full word-processor reflow across unrelated blocks or pages.
- Editing every arbitrary PDF construct approximately.
- Mobile or cross-platform parity in the first release.
- Mutating PDF page objects on every keystroke.
- Treating an LLM response as an executable document mutation.
- Building a new PDF renderer before the retained-overlay model is proven.
- Replacing Flutter with Tauri.
- Depending on a commercial PDF editing SDK as the document authority.

### Correctness over apparent support

PDFs are page-description programs, not word-processing documents. An imported
object must declare an explicit capability level:

- `editable`: Clarix can map, render, and materialize it reliably.
- `overlayOnly`: Clarix can represent it non-destructively but cannot yet write
  an equivalent native PDF object safely.
- `readOnly`: Clarix can inspect or select it but must not claim it can edit it.

Clarix must reject an unsafe operation with a useful explanation. It must not
silently rasterize text, substitute a font, flatten a page, or approximate a
save unless the user explicitly chooses a clearly labelled conversion.

## Architectural principles

1. **One canonical model.** Rust owns accepted document state. Flutter owns only
   transient interaction and optimistic projections.
2. **Stable pages while editing.** Keyboard input cannot reload a page, replace
   a `PdfPage`, move the viewport, or invalidate unrelated textures.
3. **Commands are the mutation boundary.** Manual actions, AI tools, scripts,
   undo, redo, and recovery use the same typed commands.
4. **Stable object identities.** Agents and UI selections refer to Clarix object
   IDs, never transient PDFium handles, list indices, or viewer widgets.
5. **Revisions prevent stale writes.** Every command declares its base revision.
6. **Non-destructive by default.** Sidecar state is autosaved; source bytes
   change only during explicit Save or Save As.
7. **Immediate local feedback.** Flutter can optimistically display a valid
   input delta before the Rust acknowledgement, then reconcile by command ID.
8. **Incremental work.** Import, search, OCR, page scenes, and agent context are
   page- or object-scoped and prioritized by viewport proximity.
9. **Bounded resources.** Every cache, queue, worker pool, and background job has
   an owner, budget, cancellation path, and eviction rule.
10. **Observable behavior.** Performance, commands, model calls, save stages,
    memory pressure, and failures emit structured diagnostics without recording
    document content or secrets by default.

## System context

```text
┌──────────────────────────────── Flutter UI shell ────────────────────────────────┐
│ PDF viewport │ retained edit overlays │ inspector │ inline AI │ chat │ approvals │
└───────────────┬───────────────────────────┬───────────────────────────┬────────────┘
                │ typed FRB commands        │ revisioned event streams │
┌───────────────▼───────────────────────────▼───────────────────────────▼────────────┐
│                         Windows Rust runtime DLL                                  │
│                                                                                   │
│  ┌──────────────── Document Editing Core ────────────────┐                        │
│  │ model │ command bus │ history │ layout │ search │ I/O │◄──────────────┐        │
│  └──────────────┬────────────────────┬───────────────────┘               │ tools  │
│                 │                    │                                   │ only   │
│  ┌──────────────▼─────┐  ┌──────────▼──────────┐  ┌─────────────────────┴──────┐ │
│  │ PDF adapters       │  │ OCR / asset workers │  │ Agent Orchestration Core   │ │
│  │ import/render/save │  │ index / generation  │  │ plan / call / observe      │ │
│  └────────────────────┘  └─────────────────────┘  └────────────────────────────┘ │
└───────────────┬───────────────────┬──────────────────────────┬────────────────────┘
                │                   │                          │
        source/output PDFs   Clarix sidecar + assets    configured AI providers
```

Both Rust cores can initially ship in the existing `clarix_pdf_oxide.dll`, but
they must be separate crates/modules with one-way dependencies. The agent core
depends on public editing tools. It cannot import internal model repositories or
obtain a mutable `DocumentModel` reference.

## Component ownership

### Flutter UI shell

Flutter owns presentation and ephemeral interaction state:

- PDF page viewport, zoom, scroll, page virtualization, and stable anchors;
- pointer hit testing, hover, selection gestures, handles, and drag previews;
- `EditableText`/text-input integration, IME composition, clipboard, caret,
  accessibility, and keyboard shortcuts;
- retained page overlays for edited text, images, vectors, selections, and
  agent previews;
- command acknowledgement indicators and non-blocking progress;
- inspector panels, conversation surfaces, permission prompts, diffs, and save
  conflict dialogs;
- a small optimistic state per active gesture or text composition.

Flutter does not own accepted document objects, undo history, search results,
agent execution history, or sidecar persistence.

### Document Editing Core

Rust owns:

- one `EditorSession` actor per open document;
- canonical `DocumentModel` and object graph;
- stable IDs and source bindings;
- validation and capability decisions;
- text layout recipes and font resolution;
- typed command execution, transactions, inverse operations, undo, and redo;
- revisions, patches, snapshots, and conflict detection;
- sidecar schema, autosave, crash recovery, and migration;
- incremental import, search indexes, OCR object creation, and asset metadata;
- deterministic tool implementations;
- PDF materialization, validation, backup, and atomic replacement.

### Agent Orchestration Core

Rust owns:

- provider-independent conversation and run state;
- streaming model calls and normalized tool-call parsing;
- context assembly from selection, retrieval, and document-inspection tools;
- bounded plan/execute/observe loops;
- typed tool manifests and risk metadata;
- cancellation, retries for idempotent operations, checkpoints, and progress;
- approval requests and resumable execution after an approval;
- audit records linking prompts, model outputs, tools, commands, and revisions.

The agent core returns proposals and invokes tools. The editing core decides
whether a command is valid at the requested revision.

### PDF adapter layer

The model must not depend directly on pdfrx, PDFium handles, `lopdf` objects, or
one extraction library. It uses these interfaces:

```rust
trait PdfImporter {
    fn inspect_page(&self, source: &SourceRef, page: PageIndex) -> PageImport;
}

trait PdfPreviewRenderer {
    fn render_clean_patch(&self, request: CleanPatchRequest) -> RasterAsset;
}

trait PdfMaterializer {
    fn materialize(&self, model: &DocumentSnapshot, target: &Path) -> SaveReport;
}

trait PdfValidator {
    fn validate(&self, output: &Path, expectation: &SaveExpectation)
        -> ValidationReport;
}
```

Phase 0 qualifies the current `pdf_oxide`, `lopdf`, PDFium/pdfrx, and any
additional Windows-compatible library against a fixed corpus. The chosen
adapters may combine libraries: for example, one for rendering, one for
high-level extraction, and one for low-level content-stream writing. No library
becomes the domain model.

## Canonical document model

### Document graph

```text
DocumentModel
├─ DocumentMetadata
├─ PageNode[]
│  ├─ TextBlock
│  │  └─ TextRun[]
│  ├─ ImageNode
│  ├─ VectorNode
│  ├─ AnnotationNode
│  ├─ OcrLayer
│  └─ GroupNode
├─ AssetCatalog
├─ SourceBindingCatalog
├─ SearchIndexState
└─ CommandJournal
```

Every node has:

- `ObjectId`: a 128-bit Clarix identifier stable for the life of the project;
- `ObjectKind` and capability flags;
- page ID, z-order, local bounds, affine transform, clipping reference, and
  visibility;
- source binding, if imported from the PDF;
- creation revision and last-modified revision;
- semantic metadata and provenance;
- optional accessibility and reading-order relationships.

### Stable identity and source bindings

Imported IDs are deterministic within a source revision. They are derived from
the source fingerprint, page identity, indirect object references/content-stream
location where available, object kind, and normalized geometric/content
fingerprints. The complete source locator remains private to the PDF adapter.

After an edit, `ObjectId` remains unchanged even if export creates different
PDF object numbers. A `SourceBinding` records the current import/materialization
mapping and confidence. Agents see only `ObjectId`, capabilities, and semantic
data.

If the source file changes externally, Clarix compares the stored source
fingerprint and attempts an explicit rebase. Ambiguous mappings become
conflicts; Clarix never guesses and overwrites.

### Text model

A `TextBlock` contains:

- logical Unicode text;
- UTF-16 boundary map for Flutter and Windows text input;
- grapheme boundaries for caret and deletion behavior;
- script and writing direction;
- ordered `TextRun` styles;
- paragraph alignment, line spacing, character spacing, and horizontal scale;
- local bounds, baseline/layout constraints, transform, and overflow policy;
- font references that identify exact embedded or installed font bytes;
- source glyph/character mapping and materialization capability.

Bridge selections use `TextAnchor { object_id, utf16_offset, affinity }`.
Rust validates that an offset is a legal UTF-16 and grapheme boundary and maps
it internally without exposing Rust byte indices.

### Images, vectors, OCR, and groups

The model reserves first-class nodes from the beginning even though they are
implemented later:

- `ImageNode` references an immutable asset plus crop, mask, opacity, transform,
  color profile, and generation provenance.
- `VectorNode` contains normalized paths, paint, stroke, clipping, and transform.
- `OcrLayer` contains recognized spans, confidence, language, source image
  region, and review state. OCR output is never silently treated as original
  native text.
- `GroupNode` owns child IDs and a group transform without copying children.
- `AnnotationNode` represents comments, highlights, links, form appearances,
  and other supported interactive content.

## Command and revision model

### Command envelope

Every mutation uses a typed envelope:

```text
CommandEnvelope
  session_id
  command_id                 // idempotency key
  base_revision              // optimistic concurrency check
  transaction_id             // groups atomic multi-object work
  actor { user | agent | system }
  provenance                 // UI action, conversation/run/tool IDs
  permission_grant_id?
  payload                    // typed command enum
```

Initial command payloads are:

- `ReplaceTextRange`
- `SetTextStyle`
- `SetParagraphStyle`
- `MoveObject`
- `ResizeObject`
- `RotateObject`
- `Undo`
- `Redo`
- `CreateCheckpoint`

Later payloads add insert/replace image, vector mutations, OCR acceptance,
grouping, annotations, page operations, and asset generation.

### Single-writer document actor

Each open document has one Rust actor that serializes accepted mutations. Read
queries use immutable revision snapshots. Expensive import, OCR, rendering,
indexing, and validation work runs in bounded worker pools and returns results
to the actor for revision-checked publication.

This avoids shared mutable state across Flutter callbacks, agent tools, and
background jobs. Manual and agent commands cannot race; one either commits
first or the other receives a revision conflict.

### Results and patches

A successful command returns:

```text
CommandResult
  command_id
  previous_revision
  committed_revision
  object_patches[]
  invalidated_page_ids[]
  selection_rebase?
  inverse_command_ref
  warnings[]
```

Patches contain changed fields for affected objects, not a document snapshot.
Flutter discards patches older than its last committed revision. If an
optimistic input delta differs from the accepted result, Flutter reconciles the
active overlay by command ID without changing focus or scroll.

### Transactions and history

- A command is atomic.
- A replace-all or multi-object agent action is one transaction containing
  ordered commands and one approval decision.
- Transactions either commit fully or leave the model unchanged.
- Undo applies stored inverse operations to the canonical model; it does not
  replay keystrokes or model prompts.
- Typing commands are coalesced into human-sized undo groups by time,
  composition boundary, caret discontinuity, and command type.
- The append-only command journal is periodically compacted into snapshots so
  reopening does not replay an unbounded history.

## Rendering and interaction architecture

### Stable base page

The source PDF viewer provides stable page textures and coordinate transforms.
It must not be refreshed on a keystroke. A page widget's identity, dimensions,
scroll anchor, zoom, and focus remain unchanged while editing.

The viewer is behind a `PageSurface` abstraction. pdfrx can remain the first
implementation. Syncfusion or a future renderer can replace it without changing
the model, commands, agent tools, or overlays.

### Retained scene overlay

Each visible page has a retained Flutter `PageEditScene` keyed by page ID and
model revision. It contains only visible editor objects:

- changed text and its background-cleanup patch;
- caret, selection, composition underline, and block handles;
- edited images, vectors, annotations, and agent diff previews;
- lightweight hit-test geometry.

The scene rebuilds only when its page receives an object patch or when the
viewport transform changes. Typing rebuilds the active text object, not the PDF
viewer or all page overlays.

### Removing the source appearance

An edited source object cannot be displayed underneath its replacement. On
first edit, the preview renderer produces a clean raster patch for the object's
source bounds with that source object omitted. This occurs once per source
binding and required render scale, not per keystroke. Flutter composites:

1. stable source page texture;
2. clean background patch;
3. current model object;
4. selection and editor chrome.

Patches include bleed to cover antialiasing and clipping edges. Zooming can use
the previous patch briefly while a higher-resolution patch is generated. The
viewport never reloads. If a safe clean patch cannot be produced, the object is
not Phase 1 editable.

### Text input path

1. Pointer down hit-tests the visible page scene.
2. Rust/native page geometry resolves the nearest legal text anchor; a warm
   cached map resolves locally.
3. Flutter mounts one focused text editor over the block with the exact imported
   font asset and layout recipe.
4. A keystroke updates Flutter's local editing value and glyph composition in
   the same frame.
5. Flutter batches/coalesces a typed command to Rust without waiting to paint.
6. Rust validates and commits it, autosaves the sidecar transaction, and emits a
   patch.
7. Flutter acknowledges or reconciles the optimistic overlay.

Spacebar, Page Up/Down, arrows, Home/End, and text shortcuts are routed to the
active editor while it owns focus. The PDF viewer cannot handle navigation keys
until text composition ends.

Single click places a collapsed caret. Double click selects a word. Triple
click selects the visual line or paragraph according to the interaction policy.
Entering edit mode never selects the entire block automatically.

### Formatting fidelity

Flutter and Rust use the same font asset identity and explicit layout recipe.
The preview must use embedded font bytes when legally and technically
available. If the source font cannot encode new characters, the command proposes
an embeddable installed fallback and surfaces the substitution before commit.

Exact PDF and Flutter shaping may still differ for unsupported constructs. Such
content remains read-only until the shared layout/materialization pipeline can
round-trip it within the qualification tolerances.

## Page lifecycle, bounding boxes, and scalability

The current first-pages-only behavior is replaced by a document-wide page scene
service. Extraction is not tied to the lifetime of a page widget.

### Page states

```text
unseen -> indexed -> warm -> visible -> warm -> cold
```

- `unseen`: no page model has been imported.
- `indexed`: lightweight object bounds, text, IDs, and search data are stored in
  Rust/sidecar.
- `warm`: geometry and nearby clean patches are resident.
- `visible`: Flutter scene and hit-test data are mounted.
- `cold`: persistent metadata remains; raster and detailed geometry are evicted.

### Priority policy

Work queues are ordered:

1. active selection and current gesture;
2. visible pages;
3. pages within the preload window;
4. explicit search/agent targets;
5. background document indexing;
6. OCR and optional enrichment.

Scrolling requests the scene for every newly visible page. If import is not
complete, Flutter shows the stable PDF page immediately and adds bounds when the
revisioned page scene arrives. Leaving the viewport disposes Flutter widgets,
focus nodes, animations, and GPU layers but not persistent object metadata.

### Initial resource budgets

Budgets are configurable and benchmark-tuned; these are Windows-first defaults:

- visible page window: viewport plus two pages in each direction;
- detailed text geometry: 64 MiB per open document;
- clean-patch raster cache: 128 MiB per open document;
- OCR working images: 128 MiB globally, maximum two concurrent page images;
- decoded generated assets: 128 MiB globally;
- maximum pending interactive commands: one unsent coalesced command per active
  object plus the serialized actor queue;
- maximum background importer concurrency: two pages per open document, capped
  by a global worker budget.

Memory-pressure events evict cold raster patches, detailed geometry, OCR
bitmaps, and decoded assets in that order. Canonical model state, the latest
snapshot, and unflushed journal entries are never evicted.

## Sidecar project and recovery

### Location and format

The logical project is named after the source PDF but stored under
`%LOCALAPPDATA%\Clarix\Projects\<document-id>\` so editing works when the source
directory is read-only. Users may explicitly export or move a project later.

The project contains:

```text
project.sqlite
assets/
previews/
recovery/
```

SQLite in WAL mode stores metadata, source fingerprints, nodes, styles, source
bindings, commands, snapshots, selections/checkpoints, search indexes, OCR
results, conversations, agent runs, tool calls, permissions, and asset
manifests. Large immutable assets remain content-addressed files; SQLite stores
their hashes and metadata.

### Autosave semantics

- Every accepted command and its inverse are committed in the same SQLite
  transaction as the new document revision.
- The Flutter UI does not determine durability with a debounce timer.
- WAL checkpoints run during idle periods and clean shutdown.
- On restart, Rust validates the schema and source fingerprint, loads the newest
  snapshot, and replays the remaining journal.
- A corrupt newest snapshot falls back to the prior valid snapshot and journal.
- Schema migrations are forward-only, transactional, versioned, and backed up
  before migration.

### Checkpoints

The project tracks:

- opening source revision;
- latest autosaved sidecar revision;
- latest materialized PDF revision;
- undo cursor;
- named user checkpoints;
- active agent transaction checkpoints.

Closing a dirty document asks whether to Save into the PDF, keep the recoverable
project without materializing, or discard changes. Discard creates a tombstoned
recovery checkpoint for a short retention period rather than immediately
destroying data.

## Save and PDF materialization

### Ctrl+S / Save

Save is explicit and never triggered by an agent. The editing core:

1. Flushes the current text composition and command queue.
2. Captures an immutable model snapshot and source fingerprint.
3. Verifies the source file has not changed externally.
4. Materializes to a sibling temporary PDF on the same volume.
5. Reopens the temporary output with an independent validator.
6. Validates page count, edited text extraction, object geometry, fonts,
   unaffected content invariants, and output readability.
7. Flushes the temporary file and atomically replaces the opened PDF using the
   Windows replacement path. The previous bytes are retained as the rolling
   sibling `.<filename>.clarix-backup.pdf` until the replacement has reopened
   successfully and the sidecar has recorded the new materialized revision;
   the backup is then moved into the project's `recovery/` retention area.
8. Reopens/rebases the source bindings against the saved output.
9. Records the materialized revision in the sidecar and refreshes the stable
   viewer once, preserving the nearest page/zoom anchor.

If the source changed externally, Save stops before replacement and offers Save
As or a deliberate rebase. If validation or replacement fails, the original PDF
and current sidecar remain intact. If another process holds an incompatible file
lock, Clarix reports the locking conflict and offers retry or Save As; it does
not fall back to a non-atomic overwrite.

### Save As

Save As performs the same materialization and validation but writes a new path.
The user chooses whether the current project follows the new PDF or keeps the
original source association.

### Text materialization capability

Phase 1 saves only text blocks whose source bindings qualify for deterministic
rewrite or safe object replacement. The materializer removes/replaces the
source text representation and writes searchable/selectable replacement text.
It does not merely paint white rectangles or rasterize the page.

Output validation compares the source and result at both semantic and visual
levels. Unaffected regions must remain within defined raster-difference
tolerances, while edited regions must match the model's expected text and
geometry.

## Search, selection, and inline AI context

### Search index

Rust maintains a revisioned Unicode index over native and accepted OCR text.
The index stores object ID and UTF-16 ranges, not copied page coordinates as the
primary locator. Exact, case-folded, whole-word, regex, and normalized searches
produce stable `TextRangeRef` results.

A replace-all operation first creates an immutable match set at one revision.
It generates a diff, requires approval, then commits all still-valid matches in
one transaction. Changed matches produce a conflict report rather than partial
silent replacement.

### Read-mode selection token

Read-mode highlighting produces:

```text
SelectionContext
  document_id
  document_revision
  ranges[] { object_id, start_utf16, end_utf16, quoted_text }
  page_ids[]
  style_summary
  bounds/quads
  nearby_text_before/after
  optional rendered crop asset
```

The inline AI command passes the token, not an informal page number and quote.
Before a proposed edit commits, the editing core verifies the revision and
quoted text. A stale selection can be refreshed only through an explicit
rebase result shown to the user.

## Agent harness

### Run lifecycle

```text
user request
  -> context assembly
  -> model plan / response
  -> typed tool call
  -> permission decision
  -> deterministic execution
  -> observation
  -> continue, request approval, or finish
```

Every run has a run ID, conversation ID, starting document revision, status,
cancellation token, budgets, progress events, tool records, and final outcome.
The default loop is bounded by configurable tool-call, elapsed-time, and token
budgets. Exhausting a budget pauses with an explanation; it does not silently
continue.

### Tool contract

Each tool declares:

- stable name and version;
- JSON schema and typed Rust implementation;
- read or write scope;
- expected document revision behavior;
- risk level and approval policy;
- reversibility and idempotency;
- affected object/page estimation;
- progress and cancellation support;
- result schema suitable for model observation and UI rendering.

Initial tools:

- `inspect_selection`
- `inspect_text_object`
- `search_text`
- `propose_text_rewrite`
- `replace_text_range`
- `preview_replace_all`
- `commit_replace_all`
- `apply_text_style`
- `preview_transaction`
- `undo`
- `redo`
- `request_save`

`request_save` can focus the Save UI but cannot perform Save without explicit
user action.

Later tools add OCR, images, vectors, annotations, grouping, layout, generation,
and page operations.

### Safety and approval

- Read-only inspection is automatic.
- A reversible single-selection sidecar edit may execute automatically when the
  user's command is unambiguous.
- Bulk replacements, OCR rewrites, generated assets, structural/layout changes,
  and destructive conversions require a diff/preview approval.
- Saving into the opened PDF always requires explicit user action.
- Document text is untrusted data, not agent instruction. Retrieved PDF content
  cannot grant permissions or redefine tools.
- Provider API keys stay in Windows secure storage and never enter prompts,
  sidecars, logs, or tool observations.
- Remote-provider context disclosure is visible and constrained to the selected
  and retrieved material required for the request.

### Long-running work

OCR, indexing, generation, and multi-page operations emit structured progress
and checkpoint only deterministic state. Cancellation stops future work and
rolls back an uncommitted transaction. On restart, Clarix may offer to resume a
safe deterministic job, but it does not automatically resume a model loop or a
pending destructive action.

## Flutter/Rust bridge

The existing `flutter_rust_bridge` integration remains the transport. Public
FFI is a narrow service API, not a mirror of every internal Rust struct.

### Session API

The bridge exposes an opaque `EditorSession` handle with typed operations:

- open/close/recover project;
- request page scene and object details;
- submit/cancel command;
- subscribe to document events;
- search and selection context;
- begin/approve/cancel agent run;
- save/save-as and progress;
- report memory pressure and viewport priorities.

### Bridge rules

- Hot-path calls use generated typed DTOs, not JSON strings.
- Large files stay in Rust and are referenced by content-addressed handles or
  paths. Full PDFs and page snapshots do not cross the bridge per interaction.
- Events carry session ID, revision, event sequence, and affected IDs.
- A closed session rejects late callbacks. Flutter unsubscribes and disposes
  focus/animation resources before releasing the opaque handle.
- The bridge never blocks the Flutter UI isolate on parsing, OCR, indexing,
  model calls, PDF writing, or validation.

## Performance requirements

Performance gates are measured in profile/release builds on the Windows test
hardware matrix, not debug builds.

| Operation | Target |
|---|---:|
| Local keystroke-to-overlay paint, p95 | <= 16 ms |
| Warm caret placement, p95 | <= 32 ms |
| Rust command acknowledgement without disk pressure, p95 | <= 50 ms |
| Accepted command durable in sidecar, p95 | <= 100 ms |
| Visible indexed page scene request, p95 | <= 50 ms |
| Newly visible unindexed text page bounds, p95 | <= 250 ms |
| Scroll frame budget at 60 Hz | no sustained frame over 16.7 ms |
| Viewer/page reloads while typing | 0 |
| Focus or viewport changes caused by background commit | 0 |
| Lost accepted commands after forced process termination | 0 |

Large-document qualification includes 1,000-page text PDFs, 500-page mixed
documents, scanned documents, thousands of search matches, and at least 10,000
accepted commands. Memory must reach a stable plateau under repeated scrolling;
the exact process ceiling is established in Phase 0 per test hardware, with
separate accounting for an active local AI model.

## Reliability and error model

Typed failures include:

- source changed or source unavailable;
- sidecar migration/corruption/recovery failure;
- unsupported or ambiguous source binding;
- stale document/object/selection revision;
- invalid text boundary or layout overflow;
- missing, incompatible, or non-embeddable font;
- command validation or transaction failure;
- worker cancellation, timeout, or memory pressure;
- provider, tool schema, or agent-budget failure;
- PDF materialization, validation, flush, backup, or replacement failure.

No failure may leave Flutter believing an uncommitted change is canonical. No
save failure may discard the sidecar or original PDF. Diagnostic records include
IDs, stages, durations, sizes, revisions, and error codes; document text and
provider secrets are excluded unless the user explicitly exports a support
bundle.

## Testing strategy

### Rust core

- Unit tests for every command, validation rule, source binding, and tool.
- Property tests for command/inverse round trips and Unicode boundary mapping.
- Transaction tests proving all-or-nothing multi-object edits.
- Sidecar crash/fault-injection tests at every commit/checkpoint stage.
- Concurrency tests for manual/agent revision conflicts and cancellation.
- Fuzzing for imported PDF structures, command DTOs, and sidecar migrations.
- Materialization tests that reopen outputs and compare semantic/visual
  expectations.

### Flutter shell

- Widget tests for click-to-caret, word/line selection, IME, clipboard,
  shortcuts, focus ownership, and editor disposal.
- Golden tests for overlays at multiple zooms, DPI scales, rotations, fonts,
  directions, and page backgrounds.
- Scrolling tests proving every visible page can receive bounds and overlays.
- Tests proving typing does not reload pages, change page number, or move the
  viewport.
- Frame timing and memory integration tests in profile mode.

### Bridge and end-to-end

- Generated bridge contract/version tests.
- Sequence tests for optimistic command, acknowledgement, rejection, and
  reconciliation.
- Windows restart, sleep/resume, source removal, file lock, low disk, and
  antivirus-delay tests.
- Ctrl+S fault injection before and after every save stage.
- External-reader verification that saved text remains selectable, searchable,
  and extractable.

### Agent evaluation

- Exact-selection rewrite accuracy.
- Correct tool selection for search/replace versus generative rewrite.
- Revision-conflict recovery without silent retargeting.
- Approval enforcement for bulk/generated/structural edits.
- Prompt-injection resistance for instructions embedded in document content.
- Cancellation and budget adherence.
- Audit trace completeness from conversation turn to committed command.

## Phased delivery roadmap

Each phase is independently trackable. A phase begins only after its entry
dependencies pass and finishes only when every exit gate has evidence.

### Phase 0 — Foundations, qualification, and benchmark harness

**Purpose:** remove library and performance uncertainty before product UI work.

**Deliverables:**

- Split the Rust workspace into editing-core, PDF-adapter, agent-core, and FRB
  facade boundaries while keeping one DLL.
- Define DTO versions, object IDs, revisions, commands, patches, errors, and the
  `EditorSession` actor API.
- Build a representative licensed test corpus and golden-output policy.
- Qualify PDF import/render/materialization libraries against native text,
  embedded/subset fonts, rotations, multi-run text, vectors, images, forms, and
  malformed files.
- Build Windows frame-time, command latency, sidecar latency, save latency,
  raster-diff, and memory-plateau harnesses.
- Establish measured memory ceilings for the Windows hardware matrix.

**Exit gate:** adapter choices are recorded; the bridge can open/close a session
and stream events; benchmark baselines are reproducible; no product behavior
depends on transient native handles.

### Phase 1 — Manual native-text editing MVP

**Purpose:** deliver a fast, reliable manual editor before any agent mutation.

**Deliverables:**

- Canonical text/page model, stable IDs, source bindings, and capability flags.
- Incremental visible-page import and document-wide background indexing.
- Page scene lifecycle so bounding boxes appear on every visited page.
- Single-click caret, double-click word selection, drag selection, keyboard,
  clipboard, Windows IME, and accessibility.
- Retained text overlay plus clean source-background patches.
- Replace/delete/insert text, source formatting preservation, formatting panel,
  overflow handling, and font fallback approval.
- Rust command journal, undo/redo, SQLite sidecar autosave, crash recovery, and
  dirty/checkpoint UI.
- Atomic Ctrl+S, Save button, Save As, backup, independent validation, and
  external-reader qualification.

**Exit gate:** all Phase 1 performance targets pass; typing causes zero PDF page
reloads and zero viewport shifts; a forced process kill loses no accepted
command; supported edits survive Save/reopen as searchable selectable text.

### Phase 2 — Scalable text workflows and document operations

**Purpose:** make the manual text model useful across large documents.

**Deliverables:**

- Revisioned search index, exact/normalized/regex search, and deterministic
  replace-all preview/transaction.
- Multi-range and multi-object selection.
- Text block move, resize, rotation, paragraph reflow within block bounds, and
  alignment controls.
- Persistent page-scene cache policies, memory-pressure handling, and recovery
  under rapid scrolling.
- Comments/highlights integration with stable object/range IDs.
- Compatibility reporting that explains read-only objects.

**Exit gate:** 1,000-page corpus, thousands of matches, multi-object history,
and repeated scroll/edit cycles meet memory and latency gates without stale
bounds or lost selection.

### Phase 3 — Selection-aware conversational agent

**Purpose:** allow AI to inspect and edit exact user-selected content safely.

**Deliverables:**

- Rust agent orchestration core and provider abstraction.
- Inline AI command surface and chat continuation.
- Stable `SelectionContext`, nearby context builder, and disclosure preview.
- Initial read/search/rewrite/format/undo/redo tool set.
- In-place proposal diff, accept/reject, revision rebase, cancellation, progress,
  and audit trail.
- Permission model: automatic safe local edits, approval for bulk/risky changes,
  explicit-only Save.

**Exit gate:** agent evaluations prove exact targeting, correct tool choice,
approval enforcement, conflict handling, cancellation, and complete audit links.

### Phase 4 — OCR and advanced text intelligence

**Purpose:** extend the same model to scanned and image-contained text.

**Deliverables:**

- Incremental prioritized OCR pipeline with confidence/language metadata.
- Reviewable OCR layers aligned to source image regions.
- OCR correction tools and conversion of approved regions into editable text.
- Agent OCR tools, translation/rewrite workflows, and multi-page progress.
- OCR asset eviction, cancellation, checkpoint, and offline behavior.

**Exit gate:** OCR never blocks ordinary viewing/editing, confidence and source
provenance remain visible, and approved OCR edits save/reopen according to the
declared materialization mode.

### Phase 5 — Images, vectors, shapes, and generated assets

**Purpose:** expand beyond text without weakening the command or safety model.

**Deliverables:**

- Image/vector/group nodes and transform/edit commands.
- Insert, replace, crop, mask, arrange, group, and delete workflows.
- Asset catalog, deduplication, color metadata, thumbnails, and provenance.
- Generated-image proposal/approval flow and provider asset ingestion.
- Vector/path and simple shape tools with materialization validation.

**Exit gate:** all operations are undoable, sidecar-durable, previewable, and
validated after Save; generated content retains provenance and never bypasses
approval.

### Phase 6 — Hardening, extensibility, and portability preparation

**Purpose:** qualify production reliability and preserve future platform choice.

**Deliverables:**

- Long-duration soak, corruption, low-resource, security, accessibility, and
  installer/update tests.
- Sidecar schema compatibility and recovery tooling.
- Plugin/version boundaries for PDF adapters, agent providers, OCR, and tools.
- Telemetry/privacy controls and exportable support diagnostics.
- Platform-dependency inventory and portable filesystem/save abstractions.

**Exit gate:** release qualification passes on the supported Windows matrix and
non-Windows work can begin without redesigning the model, commands, or agent
tool boundary.

## Progress tracking

The implementation tracker should use this hierarchy:

```text
Phase
  Epic
    Capability slice
      Design/spec approved
      Tests written and observed failing
      Rust implementation
      FRB contract generated
      Flutter integration
      Performance/reliability evidence
      Documentation and migration
```

Every phase has a dashboard with:

- status: not started / discovery / implementation / qualification / complete;
- completed and remaining exit-gate evidence;
- benchmark trend versus budget;
- open correctness risks and owner;
- corpus coverage;
- next executable slice.

A phase is not reported complete from code coverage or unit tests alone. Its
user-visible behavior, performance budget, crash behavior, and saved output must
all satisfy the exit gate.

## Migration from the current Clarix codebase

The migration is incremental and feature-flagged.

### Reuse

- Existing Flutter workspace, viewer, right-side format panel, conversation UI,
  theme, and Windows shell.
- Existing `flutter_rust_bridge` packaging and Rust runtime loader.
- Rust `pdf_oxide`, `lopdf`, OCR, RAG, and PDF composition work behind new
  adapter interfaces where qualification passes.
- Existing command, permission, conversation, and tool concepts as behavioral
  input to the Rust contracts.
- Existing PDF fixtures and diagnostics, expanded into the qualification corpus.

### Replace

- Dart as the canonical PDF editing session and history authority.
- PDFium/pdfrx mutation and page reload on every input delta.
- Transient object paths as public identities.
- Visible-page-only discovery tied to widget lifetime.
- Agent tools that construct Dart mutation intents directly.

### Transition sequence

1. Add the Rust session/model beside the current reader with no editing UI.
2. Compare imported page scenes and text geometry against current discovery.
3. Enable the retained overlay editor behind a developer flag for supported
   text objects.
4. Route Phase 1 commands, history, and sidecar persistence to Rust.
5. Add validated Save and qualify output before enabling it by default.
6. Remove the native per-keystroke mutation path after the Phase 1 exit gate.
7. Move agent mutation tools to the Rust tool gateway in Phase 3.

No migration step should require a Tauri rewrite. If the UI shell changes in the
future, the Rust session API and sidecar remain reusable.

## Decision record

- Windows is the only first-release platform; portability is an interface goal.
- Flutter remains the UI shell.
- Rust owns both the deterministic editing core and the isolated agent
  orchestration core.
- The source PDF is immutable during ordinary editing.
- The sidecar autosaves every accepted command.
- Ctrl+S/Save atomically updates the opened PDF after validation and backup.
- Save As writes a new PDF.
- Phase 1 is manual native text only.
- Typing renders from a retained Flutter overlay and never reloads the PDF page.
- Edited source appearance is removed through cached clean background patches.
- Single click places a caret; entry does not select the entire block.
- Manual and agent actions share typed commands and revisions.
- Bulk, generated, OCR, and structural changes require preview approval.
- Saving always requires explicit user action.
- Syncfusion may be evaluated as a viewer/annotation adapter but is not the
  document-model or arbitrary-content editing authority.
- Tauri is not part of this architecture.

## Research basis

The design was checked against the current Clarix codebase and these primary
references on 2026-08-14:

- Flutter, **Performance best practices**:
  <https://docs.flutter.dev/perf/best-practices>. This supports localizing
  rebuilds and paint work, avoiding expensive UI-thread operations, and
  measuring in profile/release mode.
- Flutter, **Concurrency and isolates**:
  <https://docs.flutter.dev/perf/isolates>. Parsing, OCR, saving, validation,
  and other CPU-heavy work must not block the UI isolate.
- flutter_rust_bridge, **Concurrency**:
  <https://cjycode.com/flutter_rust_bridge/guides/concurrency>. The generated
  bridge supports asynchronous Rust work and streams without making Flutter the
  owner of native state.
- SQLite, **Write-Ahead Logging**: <https://www.sqlite.org/wal.html>. WAL is the
  basis for the sidecar's transactional command durability and idle checkpoint
  strategy.
- Microsoft, **ReplaceFileW**:
  <https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-replacefilew>.
  The Windows Save path uses same-volume temporary output, validation, backup,
  and atomic replacement semantics.
- Current repository dependencies and code: `flutter_rust_bridge 2.12.0`,
  `pdfrx 2.4.7`, `pdfrx_engine 0.4.6`, `pdf_oxide 0.3`, `lopdf 0.40`, the
  `clarix_pdf_oxide` Rust crate, the current Dart agent runtime/tool registry,
  and the existing PDF command/session implementation.

## Required follow-up specifications

This master architecture is intentionally decomposed. Implementation begins
only after separate specifications are approved in this order:

1. Phase 0 Rust workspace, canonical model, session actor, and benchmark corpus.
2. Sidecar schema, command journal, recovery, and save transaction.
3. PDF import/source-binding/materialization adapter qualification.
4. Phase 1 Flutter page scene, clean patches, text overlay, and input lifecycle.
5. Phase 2 search, replace-all, block layout, and large-document lifecycle.
6. Phase 3 agent orchestration, selection context, tools, approvals, and audit.
7. OCR and advanced text.
8. Images, vectors, shapes, and generated assets.

The immediate next specification is item 1. It should not implement user-facing
editing; it establishes the stable model and benchmark foundation on which the
remaining phases depend.
