# Phase 1 Manual Native-Text Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Windows-first, manual editing of qualified native PDF text with retained Flutter overlays, Rust-authoritative durable state, crash recovery, and validated atomic PDF saves.

**Architecture:** Extend `clarix_editing_core` with PDF-independent domain rules and ports, implement SQLite durability in a dedicated infrastructure crate, implement PDF import/preview/materialization and Windows replacement behind adapter interfaces, and keep `clarix_pdf_oxide` as the composition/FRB boundary. Flutter wraps the existing low-level editor bridge in a workspace application controller and renders retained per-page scenes over an unchanged pdfrx page surface; the current Dart/PDFium mutation path remains behind a legacy flag until the exit gate passes.

**Tech Stack:** Rust 2021, `rusqlite` with bundled SQLite, `crossbeam-channel`, `lopdf`, `pdf_oxide`, `windows-sys`, Flutter 3.44+/Dart 3.12+, Riverpod, pdfrx, flutter_rust_bridge 2.12, Criterion, Flutter widget/integration tests, PowerShell qualification scripts.

**Spec:** `docs/clarix-windows-editing-platform-architecture.md`

## Global Constraints

- Work directly on `main`; do not create a branch or linked worktree.
- Do not run `cargo build`; the user alone runs all `cargo build` commands. Other Cargo commands in this plan are permitted.
- Phase 0 is complete at commit `908072c`; preserve its crate boundaries, stable IDs, revision checks, typed FRB contract, corpus, and benchmark harness.
- Windows desktop is the only Phase 1 delivery platform; portability remains an interface goal.
- Flutter remains the UI shell; Rust owns accepted document state, history, persistence, recovery, and save orchestration.
- The source PDF is immutable during ordinary editing. Autosave writes only the Clarix project sidecar.
- Typing must render from a retained Flutter overlay and must never reload a PDF page, move the viewport, or lose focus.
- Every mutation goes through a typed, revision-checked Rust command. Flutter may hold only a bounded optimistic projection for the active input/gesture.
- Phase 1 supports only qualified native text. Unsafe, ambiguous, non-embeddable, or non-round-trippable objects remain explicitly read-only.
- Save is always explicit. Agents cannot invoke Save, and Phase 1 introduces no agent mutation behavior.
- No PDF library type, SQLite connection, FRB type, Windows handle, pdfrx object, or PDFium handle may enter the canonical domain model.
- Public bridge DTO schema remains version `1` until a breaking wire change is unavoidable; additive Phase 1 DTO fields must be optional or supplied by all producers in the same commit.
- Default resource budgets are: visible viewport plus two pages each way, 64 MiB detailed geometry per document, 128 MiB clean-patch cache per document, and two concurrent page imports per document subject to a global worker cap.
- Performance targets are those at `docs/clarix-windows-editing-platform-architecture.md:775`: local paint p95 <=16 ms, warm caret p95 <=32 ms, command acknowledgement p95 <=50 ms without disk pressure, durable acknowledgement p95 <=100 ms, visible indexed scene p95 <=50 ms, and newly visible unindexed text bounds p95 <=250 ms.
- Each task follows red-green-refactor: observe the named focused test fail, implement the smallest complete behavior, run focused tests, run the listed non-build checks, then commit.

## Phase 1 Entry Gate

The master architecture requires three follow-up designs before Phase 1 implementation: (1) sidecar schema/command journal/recovery/save transaction, (2) PDF import/source-binding/materialization qualification, and (3) Flutter page scene/clean patch/text input lifecycle. The existing `2026-08-14-live-native-pdf-text-editing-design.md`, `2026-08-14-native-pdf-object-editing-design.md`, and `2026-08-14-pdf-editing-interaction-font-repair-design.md` describe the superseded per-keystroke PDFium mutation approach and do not satisfy this gate. This document may be reviewed as the integrated implementation draft, but Task 1 must not begin until those three retained-overlay/Rust-authority designs are approved or the user explicitly accepts this plan as their replacement.

---

## File and Boundary Map

### Rust domain and application core

- Modify `rust/clarix_editing_core/src/model.rs`: canonical text layout, font identity, capability reasons, source-binding confidence, and page import state.
- Modify `rust/clarix_editing_core/src/text.rs`: UTF-16/grapheme anchors, paragraph/layout values, fallback decisions, and overflow policy.
- Modify `rust/clarix_editing_core/src/command.rs`: paragraph/style commands, typing-group metadata, complete results, warnings, and selection rebasing.
- Create `rust/clarix_editing_core/src/ports.rs`: PDF- and database-independent ports used by application services.
- Create `rust/clarix_editing_core/src/history.rs`: deterministic inverse generation and undo-group policy.
- Create `rust/clarix_editing_core/src/persistence.rs`: durable commit, snapshot, checkpoint, and recovery contracts.
- Create `rust/clarix_editing_core/src/page_service.rs`: bounded visible-page scheduling and revision-checked publication.
- Create `rust/clarix_editing_core/src/save.rs`: save state machine and failure-stage model over abstract materialize/validate/replace ports.
- Modify `rust/clarix_editing_core/src/session.rs` and `actor.rs`: prepare/persist/publish command flow and durable acknowledgements.

### Rust infrastructure

- Create `rust/clarix_editing_store/`: SQLite/WAL project repository, migrations, snapshots, replay, and recovery retention.
- Modify `rust/clarix_pdf_adapter/src/contract.rs`: implement core ports without leaking adapter internals.
- Modify `rust/clarix_pdf_adapter/src/pdf_oxide_importer.rs`: faithful text runs, geometry, font/source bindings, and explicit capability classification.
- Create `rust/clarix_pdf_adapter/src/clean_patch.rs`: source-object-omitting clean raster patches.
- Create `rust/clarix_pdf_adapter/src/materializer.rs`: deterministic searchable/selectable native-text replacement.
- Create `rust/clarix_pdf_adapter/src/validator.rs`: independent semantic and raster validation.
- Create `rust/clarix_pdf_adapter/src/windows_replace.rs`: flush, rolling backup, `ReplaceFileW`, reopen, and recovery transfer.
- Modify `rust/clarix_pdf_oxide/src/editing_api.rs`: composition root and narrow typed session/recovery/scene/command/save API.

### Flutter application and presentation

- Keep `lib/src/core/editing/editor_bridge*.dart` as the low-level transport boundary; extend it only with generated DTO conversion and lifecycle enforcement.
- Create `lib/src/features/workspace/editing/domain/`: immutable workspace editor state, page scenes, selection anchors, save/checkpoint state, and typed failures.
- Create `lib/src/features/workspace/editing/application/editor_session_controller.dart`: one controller per open document, optimistic reconciliation, viewport priorities, and close ordering.
- Create `lib/src/features/workspace/editing/infrastructure/editor_session_gateway.dart`: adapter from application interfaces to `EditorBridgeSession`.
- Create `lib/src/features/workspace/editing/presentation/page_surface.dart`: viewer abstraction and pdfrx implementation.
- Create `lib/src/features/workspace/editing/presentation/page_edit_scene.dart`: retained per-page layer with clean patches, glyph overlay, selection, caret, and handles.
- Create `lib/src/features/workspace/editing/presentation/native_text_editor.dart`: focused `EditableText`/IME/clipboard/keyboard integration.
- Modify `document_workspace.dart`, `pdf_text_format_panel.dart`, providers, notifier, and close/save dialogs to consume the new controller.
- Retire the current `PdfEditingController`/PDFium mutation path only after all Phase 1 evidence is recorded.

---

### Task 1: Complete the Canonical Phase 1 Text Model

**Files:**
- Modify: `rust/clarix_editing_core/src/text.rs`
- Modify: `rust/clarix_editing_core/src/model.rs`
- Modify: `rust/clarix_editing_core/src/error.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Test: `rust/clarix_editing_core/tests/model_contract.rs`
- Create: `rust/clarix_editing_core/tests/text_layout_contract.rs`

**Interfaces:**
- Consumes: existing `ObjectId`, `PageId`, `PdfBox`, `AffineTransform`, `Utf16Range`, and `DocumentRevision`.
- Produces: `TextAnchor`, `TextAffinity`, `FontRef`, `ParagraphStyle`, `TextLayoutRecipe`, `OverflowPolicy`, `CapabilityReason`, and complete `TextBlock` data used by import, overlay, persistence, and materialization.

- [ ] **Step 1: Write failing Unicode-anchor and serialization tests**

```rust
#[test]
fn text_anchor_rejects_surrogate_and_non_grapheme_boundaries() {
    let text = "A👩🏽‍💻e\u{301}";
    assert!(TextAnchor::validate(text, 1, TextAffinity::Downstream).is_ok());
    assert_eq!(
        TextAnchor::validate(text, 2, TextAffinity::Downstream).unwrap_err().code(),
        "invalid_text_boundary"
    );
    assert_eq!(
        TextAnchor::validate(text, 9, TextAffinity::Downstream).unwrap_err().code(),
        "invalid_grapheme_boundary"
    );
}

#[test]
fn phase1_text_block_round_trips_every_materialization_field() {
    let block = phase1_text_block_fixture();
    let json = serde_json::to_string(&block).unwrap();
    assert_eq!(serde_json::from_str::<TextBlock>(&json).unwrap(), block);
}
```

`phase1_text_block_fixture()` must contain an exact `FontRef` fingerprint, embedded-font asset ID, bidi direction, alignment, line height, character spacing, horizontal scale, baseline, transform, overflow policy, source glyph map, capability, and a nonempty capability reason for any non-editable fixture.

- [ ] **Step 2: Run the focused test and observe missing types**

```powershell
cargo test -p clarix_editing_core --test text_layout_contract --manifest-path rust/Cargo.toml
```

Expected: compile failure for unresolved Phase 1 text types.

- [ ] **Step 3: Implement immutable model values and invariants**

```rust
pub struct TextAnchor {
    pub object_id: ObjectId,
    pub utf16_offset: u32,
    pub affinity: TextAffinity,
}

pub struct FontRef {
    pub postscript_name: String,
    pub bytes_sha256: String,
    pub asset_id: Option<String>,
    pub source: FontSource,
    pub embeddable: bool,
}

pub struct TextLayoutRecipe {
    pub paragraph: ParagraphStyle,
    pub baseline: f64,
    pub line_height: f64,
    pub character_spacing: f64,
    pub horizontal_scale: f64,
    pub direction: WritingDirection,
    pub overflow: OverflowPolicy,
}
```

Use `unicode-segmentation` to validate grapheme boundaries after UTF-16-to-byte conversion. Reject empty font fingerprints, non-finite geometry/layout numbers, non-positive font size/line height/horizontal scale, out-of-range RGBA values, overlapping or incomplete text runs, and `Editable` imported text without a source binding, exact font identity, and materialization capability.

- [ ] **Step 4: Preserve reserved non-text nodes and backward model tests**

Keep image, vector, annotation, OCR, and group variants deserializable and read-only. Update Phase 0 fixtures through constructors rather than weakening new invariants.

- [ ] **Step 5: Verify domain tests and lint**

```powershell
cargo test -p clarix_editing_core --test model_contract --test text_layout_contract --manifest-path rust/Cargo.toml
cargo clippy -p clarix_editing_core --all-targets --manifest-path rust/Cargo.toml -- -D warnings
```

Expected: pass with no PDF, SQLite, Windows, Flutter, or FRB dependency added to the core crate.

- [ ] **Step 6: Commit**

```powershell
git add rust/clarix_editing_core
git commit -m "feat: complete canonical Phase 1 text model"
```

---

### Task 2: Make Commands Prepare Deterministic Inverses and Undo Groups

**Files:**
- Modify: `rust/clarix_editing_core/src/command.rs`
- Create: `rust/clarix_editing_core/src/history.rs`
- Modify: `rust/clarix_editing_core/src/session.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Test: `rust/clarix_editing_core/tests/command_session.rs`
- Create: `rust/clarix_editing_core/tests/history_contract.rs`

**Interfaces:**
- Consumes: canonical `TextBlock`, `TextAnchor`, and `TextLayoutRecipe` from Task 1.
- Produces: `PreparedCommand`, `InverseOperation`, `TypingGroup`, `SetParagraphStyle`, `CommandResult.previous_revision`, `selection_rebase`, warnings, and deterministic undo/redo transitions.

- [ ] **Step 1: Write failing prepare-without-mutation tests**

```rust
#[test]
fn prepare_does_not_publish_until_commit_and_carries_inverse() {
    let mut session = fixture_session("Before");
    let prepared = session.prepare(replace_envelope(0, 0..6, "After")).unwrap();
    assert_eq!(session.text(prepared.object_id()).unwrap(), "Before");
    assert_eq!(prepared.previous_revision, DocumentRevision::INITIAL);
    assert_eq!(prepared.committed_revision.value(), 1);
    assert_eq!(prepared.inverse, InverseOperation::ReplaceObject(prepared.before_objects[0].clone()));
    session.publish(prepared).unwrap();
    assert_eq!(session.text(fixture_object_id()).unwrap(), "After");
}
```

Add exact cases for emoji deletion, selection rebasing after insert/delete, paragraph alignment, overflow rejection, undo across checkpoints, redo invalidation, duplicate command IDs, and a typing group split by caret discontinuity.

- [ ] **Step 2: Run and observe the missing prepare API**

```powershell
cargo test -p clarix_editing_core --test history_contract --manifest-path rust/Cargo.toml
```

Expected: compile failure because `prepare`, `publish`, and `PreparedCommand` do not exist.

- [ ] **Step 3: Refactor mutation into prepare and publish phases**

```rust
pub struct PreparedCommand {
    pub envelope: CommandEnvelope,
    pub previous_revision: DocumentRevision,
    pub committed_revision: DocumentRevision,
    pub before_objects: Vec<DocumentObject>,
    pub after_objects: Vec<DocumentObject>,
    pub inverse: InverseOperation,
    pub object_patches: Vec<ObjectPatch>,
    pub selection_rebase: Option<SelectionRebase>,
    pub warnings: Vec<CommandWarning>,
    pub undo_group: UndoGroupId,
}
```

`prepare` performs all revision, boundary, capability, font, layout, and overflow validation against an immutable state. `publish` accepts only a prepared command whose previous revision still equals the session revision, swaps the prepared objects, advances revision once, updates history, and clears redo when appropriate.

- [ ] **Step 4: Implement deterministic typing coalescing**

Add `typing_group_id`, `composition_id`, and caret-before/caret-after metadata to the envelope. Merge adjacent `ReplaceTextRange` commands only when actor, object, command kind, composition boundary, group ID, and caret continuity all match; checkpoints, paste, style changes, selection jumps, and IME commit boundaries always split the group.

- [ ] **Step 5: Verify command, inverse, and property tests**

```powershell
cargo test -p clarix_editing_core --test command_session --test history_contract --manifest-path rust/Cargo.toml
cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml
```

Expected: every accepted command followed by undo restores the serialized object graph exactly; redo recreates the accepted graph at a new revision.

- [ ] **Step 6: Commit**

```powershell
git add rust/clarix_editing_core
git commit -m "feat: prepare durable invertible editing commands"
```

---

### Task 3: Define Persistence and Save Ports without Infrastructure Leakage

**Files:**
- Create: `rust/clarix_editing_core/src/ports.rs`
- Create: `rust/clarix_editing_core/src/persistence.rs`
- Create: `rust/clarix_editing_core/src/save.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Modify: `rust/clarix_editing_core/tests/architecture_fitness.rs`
- Create: `rust/clarix_editing_core/tests/port_contract.rs`

**Interfaces:**
- Consumes: `PreparedCommand`, canonical model snapshots, source fingerprint, and IDs.
- Produces: `ProjectRepository`, `PageImportSource`, `CleanPatchSource`, `PdfMaterializationPort`, `PdfValidationPort`, `AtomicReplacementPort`, `Clock`, `SaveCoordinator`, and typed stage failures.

- [ ] **Step 1: Write compile-time fake-port tests**

```rust
struct RecordingRepository { records: Mutex<Vec<DurableCommit>> }

impl ProjectRepository for RecordingRepository {
    fn recover(&self, _: RecoveryRequest) -> Result<RecoveredProject, PersistenceError> {
        Ok(recovered_project_fixture())
    }
    fn append(&self, commit: &DurableCommit) -> Result<(), PersistenceError> {
        self.records.lock().unwrap().push(commit.clone());
        Ok(())
    }
    fn write_snapshot(&self, _: &DurableSnapshot) -> Result<(), PersistenceError> { Ok(()) }
    fn checkpoint(&self, _: &ProjectCheckpoint) -> Result<(), PersistenceError> { Ok(()) }
    fn close(&self) -> Result<(), PersistenceError> { Ok(()) }
}

#[test]
fn core_save_coordinator_depends_only_on_ports() {
    let ports = recording_save_ports();
    let report = SaveCoordinator::new(ports).save(save_request()).unwrap();
    assert_eq!(report.stages, SaveStage::ALL);
}
```

- [ ] **Step 2: Run and observe unresolved ports**

```powershell
cargo test -p clarix_editing_core --test port_contract --manifest-path rust/Cargo.toml
```

Expected: compile failure for missing port traits.

- [ ] **Step 3: Define narrow domain-facing contracts**

```rust
pub trait ProjectRepository: Send + Sync {
    fn recover(&self, request: RecoveryRequest) -> Result<RecoveredProject, PersistenceError>;
    fn append(&self, commit: &DurableCommit) -> Result<(), PersistenceError>;
    fn write_snapshot(&self, snapshot: &DurableSnapshot) -> Result<(), PersistenceError>;
    fn checkpoint(&self, checkpoint: &ProjectCheckpoint) -> Result<(), PersistenceError>;
    fn close(&self) -> Result<(), PersistenceError>;
}

pub trait AtomicReplacementPort: Send + Sync {
    fn replace(&self, request: AtomicReplaceRequest) -> Result<AtomicReplaceReport, SaveError>;
}
```

Use owned byte buffers, hashes, paths, IDs, and canonical values only. Ports may use `std::path::Path`, but may not name rusqlite, lopdf, pdf_oxide, FRB, pdfrx, PDFium, or Win32 types.

- [ ] **Step 4: Specify the save state machine**

`SaveCoordinator` must execute `FlushCommands -> Snapshot -> VerifySource -> MaterializeTemp -> ValidateTemp -> FlushTemp -> ReplaceOrMove -> Rebase -> RecordMaterializedRevision`. Each stage returns a typed code and preserves the original PDF and sidecar on failure. `SaveAs` skips replacement, writes a new target atomically, and returns `KeepOriginalAssociation` or `FollowNewSource` as chosen in the request.

```rust
pub enum SaveStage {
    FlushCommands,
    Snapshot,
    VerifySource,
    MaterializeTemp,
    ValidateTemp,
    FlushTemp,
    ReplaceOrMove,
    Rebase,
    RecordMaterializedRevision,
}

impl SaveStage {
    pub const ALL: [Self; 9] = [
        Self::FlushCommands, Self::Snapshot, Self::VerifySource,
        Self::MaterializeTemp, Self::ValidateTemp, Self::FlushTemp,
        Self::ReplaceOrMove, Self::Rebase, Self::RecordMaterializedRevision,
    ];
}
```

- [ ] **Step 5: Strengthen architecture fitness checks**

Assert `clarix_editing_core` has no dependencies named `rusqlite`, `libsqlite3-sys`, `windows`, `windows-sys`, `pdf_oxide`, `lopdf`, `flutter_rust_bridge`, `clarix_pdf_adapter`, `clarix_editing_store`, or `clarix_pdf_oxide`. Later infrastructure crates may depend inward on the core; the agent crate remains unable to import them.

- [ ] **Step 6: Verify**

```powershell
cargo test -p clarix_editing_core --test port_contract --test architecture_fitness --manifest-path rust/Cargo.toml
cargo clippy -p clarix_editing_core --all-targets --manifest-path rust/Cargo.toml -- -D warnings
```

- [ ] **Step 7: Commit**

```powershell
git add rust/clarix_editing_core
git commit -m "feat: define editing persistence and save ports"
```

---

### Task 4: Implement the SQLite Sidecar Infrastructure

**Files:**
- Modify: `rust/Cargo.toml`
- Modify: `rust/clarix_editing_core/tests/architecture_fitness.rs`
- Create: `rust/clarix_editing_store/Cargo.toml`
- Create: `rust/clarix_editing_store/src/lib.rs`
- Create: `rust/clarix_editing_store/src/location.rs`
- Create: `rust/clarix_editing_store/src/schema.rs`
- Create: `rust/clarix_editing_store/src/repository.rs`
- Create: `rust/clarix_editing_store/src/recovery.rs`
- Create: `rust/clarix_editing_store/tests/repository_contract.rs`
- Create: `rust/clarix_editing_store/tests/fault_injection.rs`

**Interfaces:**
- Consumes: `ProjectRepository` and durable values from Task 3.
- Produces: `SqliteProjectRepository::open(ProjectLocation)`, schema version `1`, WAL durability, snapshots, journal replay, forward migrations, and tombstoned recovery checkpoints.

- [ ] **Step 1: Write failing repository and location tests**

```rust
#[test]
fn project_location_is_local_app_data_document_id() {
    let root = PathBuf::from(r"C:\Users\tester\AppData\Local");
    let location = ProjectLocation::under(&root, document_id());
    assert_eq!(location.database, root.join("Clarix/Projects").join(document_id().to_string()).join("project.sqlite"));
}

#[test]
fn append_is_atomic_with_revision_and_inverse() {
    let repo = temporary_repository();
    repo.append(&durable_commit(1)).unwrap();
    assert_eq!(repo.recover(recovery_request()).unwrap().revision.value(), 1);
    assert_eq!(repo.raw_count("commands"), 1);
    assert_eq!(repo.raw_count("inverse_operations"), 1);
}
```

- [ ] **Step 2: Register the crate and observe the missing implementation**

```powershell
cargo test -p clarix_editing_store --manifest-path rust/Cargo.toml
```

Expected: compile failure until the new crate and repository exist.

- [ ] **Step 3: Create the exact schema and transactional repository**

Use `rusqlite = { version = "0.32", features = ["bundled"] }`. Schema version `1` contains `project`, `source_revisions`, `pages`, `page_index_state`, `objects`, `text_runs`, `styles`, `source_bindings`, `text_index`, `commands`, `inverse_operations`, `snapshots`, `selections`, `checkpoints`, `materializations`, `assets`, `previews`, and `migration_log`. Create sibling `assets/`, `previews/`, and `recovery/` directories. Store canonical serialized payloads with SHA-256 checksums; enable `journal_mode=WAL`, `foreign_keys=ON`, `synchronous=FULL`, and a finite busy timeout. One accepted command transaction writes command, inverse, changed objects/runs/styles/bindings, revision, dirty state, and undo cursor before commit returns.

- [ ] **Step 4: Implement recovery and migration safety**

On open, verify schema and source fingerprint, choose the newest checksum-valid snapshot, replay later commands, and fall back to the previous valid snapshot if necessary. Before any forward migration, copy `project.sqlite`, `-wal`, and `-shm` into `recovery/migration-v<from>-<timestamp>/`; a failed migration restores the prior files. Unknown newer schemas return `sidecar_schema_too_new` without modification.

- [ ] **Step 5: Add fault injection at transaction boundaries**

Inject failures before begin, after command insert, after inverse insert, after object update, before commit, after commit, during snapshot rename, and during WAL checkpoint. Reopening must expose either the full old revision or full new revision, never a mixture. A forced process termination simulation must recover every command whose append call returned success.

- [ ] **Step 6: Verify repository behavior**

```powershell
cargo test -p clarix_editing_store --test repository_contract --test fault_injection --manifest-path rust/Cargo.toml
cargo clippy -p clarix_editing_store --all-targets --manifest-path rust/Cargo.toml -- -D warnings
```

- [ ] **Step 7: Commit**

```powershell
git add rust/Cargo.toml rust/clarix_editing_core/tests/architecture_fitness.rs rust/clarix_editing_store
git commit -m "feat: add crash-safe SQLite editing sidecar"
```

---

### Task 5: Make the Session Actor Acknowledge Only Durable Commands

**Files:**
- Modify: `rust/clarix_editing_core/src/actor.rs`
- Modify: `rust/clarix_editing_core/src/session.rs`
- Modify: `rust/clarix_editing_core/src/persistence.rs`
- Modify: `rust/clarix_editing_core/tests/actor_ordering.rs`
- Create: `rust/clarix_editing_core/tests/durable_actor.rs`

**Interfaces:**
- Consumes: `PreparedCommand` and `ProjectRepository`.
- Produces: `EditorSessionActor::spawn_durable`, recovery-first startup, `CommandCommitted { durable: true }`, dirty/checkpoint events, and close-time WAL checkpointing.

- [ ] **Step 1: Write failing durability-order tests**

```rust
#[test]
fn repository_failure_does_not_mutate_or_emit_commit() {
    let store = Arc::new(FailingRepository::at(AppendStage::BeforeCommit));
    let actor = durable_actor(store);
    let events = actor.subscribe().unwrap();
    let error = actor.submit(replace_envelope(0, 0..6, "After")).unwrap_err();
    assert_eq!(error.code(), "sidecar_commit_failed");
    assert_eq!(actor.snapshot().unwrap().revision.value(), 0);
    assert_no_committed_event(events);
}
```

Add a success test that records repository append, in-memory publish, and event emission in that exact order; add restart replay and clean-close checkpoint cases.

- [ ] **Step 2: Run and observe missing durable actor construction**

```powershell
cargo test -p clarix_editing_core --test durable_actor --manifest-path rust/Cargo.toml
```

- [ ] **Step 3: Implement prepare -> append -> publish -> emit**

The actor owns the sole mutable session. It prepares without mutation, calls `ProjectRepository::append`, publishes only after the durable transaction succeeds, then sends the result. Repository I/O occurs on the actor thread so command order cannot invert; bounded request/subscriber channels remain unchanged. On startup, recover before emitting `Ready`.

- [ ] **Step 4: Emit checkpoint and materialization state**

Add typed events for `DirtyStateChanged`, `CheckpointCreated`, `RecoveryWarning`, `SaveProgress`, and `Materialized`. Events include session ID, sequence, canonical revision, and only affected IDs/codes. No event includes document text.

- [ ] **Step 5: Verify actor concurrency and durability**

```powershell
cargo test -p clarix_editing_core --test actor_ordering --test durable_actor --manifest-path rust/Cargo.toml
cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml
```

- [ ] **Step 6: Commit**

```powershell
git add rust/clarix_editing_core
git commit -m "feat: make editor acknowledgements sidecar durable"
```

---

### Task 6: Import Qualified Text Fidelity and Publish Every Visited Page

**Files:**
- Modify: `rust/clarix_pdf_adapter/src/contract.rs`
- Modify: `rust/clarix_pdf_adapter/src/pdf_oxide_importer.rs`
- Modify: `rust/clarix_pdf_adapter/src/lib.rs`
- Create: `rust/clarix_editing_core/src/page_service.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Create: `rust/clarix_pdf_adapter/tests/text_fidelity.rs`
- Create: `rust/clarix_editing_core/tests/page_service.rs`
- Modify: `test_fixtures/editing_corpus/manifest.json`

**Interfaces:**
- Consumes: full text model and `PageImportSource` port.
- Produces: `PageSceneRequest`, `ViewportPriority`, `PageImportState`, bounded `PageSceneService`, exact imported runs/layout/source bindings, and explicit capability reasons.

- [ ] **Step 1: Write fidelity and all-pages tests**

```rust
#[test]
fn importer_never_marks_incomplete_font_mapping_editable() {
    let page = importer().inspect_page(&subset_font_fixture(), 1).unwrap();
    let text = only_text(&page.page);
    assert_eq!(text.capability(), EditCapability::ReadOnly);
    assert_eq!(text.capability_reason().unwrap().code, "font_encoding_incomplete");
}

#[test]
fn visiting_page_137_publishes_its_scene_even_when_background_index_is_behind() {
    let service = fixture_page_service(500, 2);
    let scene = service.request(PageSceneRequest::visible(137, revision(0))).unwrap();
    assert_eq!(scene.page.page_number, 137);
    assert!(service.max_observed_concurrency() <= 2);
}
```

- [ ] **Step 2: Run focused tests and observe missing fidelity/state fields**

```powershell
cargo test -p clarix_pdf_adapter --test text_fidelity --manifest-path rust/Cargo.toml
cargo test -p clarix_editing_core --test page_service --manifest-path rust/Cargo.toml
```

- [ ] **Step 3: Map imported native text without optimistic capability claims**

Populate logical Unicode, UTF-16/grapheme maps, per-run exact font reference, size, color, spacing, horizontal scale, baseline, line height, direction, bounds, transform, source glyph map, and private source locator. `Editable` requires deterministic source locator, exact or approved embeddable font, encodable existing glyphs, safe clean-patch support, and deterministic materialization; otherwise assign `OverlayOnly` or `ReadOnly` with a stable reason code.

- [ ] **Step 4: Implement page lifecycle and priority scheduling**

Represent `Unseen -> Indexed -> Warm -> Visible -> Warm -> Cold`. Deduplicate requests by document/page/source revision, cap imports at two per document, prioritize active selection then visible pages then the +/-2 preload window then background indexing, and reject stale publication after source/revision changes. After interactive queues drain, continue importing/indexing every document page regardless of widget lifetime. Persist indexed bounds/text/IDs and normalized text-index rows through the project repository; expose no replace-all/search UI in Phase 1. Evict detailed geometry only after a page becomes cold.

- [ ] **Step 5: Extend corpus assertions**

For standard Latin, rotations, multiple runs, embedded/subset fonts, mixed content, forms, scanned pages, and malformed PDFs, record expected object counts, stable IDs, capability state/reason, font fingerprint, transform, and materialization eligibility. Run every deterministic case twice and compare serialized scenes byte-for-byte after removing measured durations.

- [ ] **Step 6: Verify**

```powershell
cargo test -p clarix_pdf_adapter --test qualification_tests --test text_fidelity --manifest-path rust/Cargo.toml
cargo test -p clarix_editing_core --test page_service --manifest-path rust/Cargo.toml
```

- [ ] **Step 7: Commit**

```powershell
git add rust/clarix_editing_core rust/clarix_pdf_adapter test_fixtures/editing_corpus/manifest.json
git commit -m "feat: import qualified text across all pages"
```

---

### Task 7: Render and Cache Clean Source-Background Patches

**Files:**
- Create: `rust/clarix_pdf_adapter/src/clean_patch.rs`
- Modify: `rust/clarix_pdf_adapter/src/lib.rs`
- Modify: `rust/clarix_pdf_adapter/Cargo.toml`
- Create: `rust/clarix_pdf_adapter/tests/clean_patch.rs`
- Create: `rust/clarix_pdf_adapter/benches/clean_patch.rs`

**Interfaces:**
- Consumes: qualified source binding, page ID, source bounds, transform, requested scale/DPI, and `CleanPatchSource` port.
- Produces: `CleanPatchKey { source_fingerprint, source_key, dpi_bucket }`, premultiplied RGBA raster, bleed metadata, LRU cache capped at 128 MiB/document, and explicit unsafe-patch failures.

- [ ] **Step 1: Write failing omission, bleed, and cache tests**

```rust
#[test]
fn clean_patch_omits_only_the_bound_source_text() {
    let result = renderer().render_clean_patch(request_for("standard-latin", 144)).unwrap();
    assert!(result.bleed_points >= 1.0);
    assert_eq!(extract_text_from_patch_source(&result), "");
    assert_raster_matches("standard-latin-clean-144dpi.png", &result.rgba_bytes, 0.002);
}

#[test]
fn second_request_hits_cache_and_budget_evicts_coldest_scale() {
    let cache = test_cache(1024);
    cache.get_or_render(request_a()).unwrap();
    cache.get_or_render(request_a()).unwrap();
    assert_eq!(cache.render_count(), 1);
    cache.get_or_render(request_b_larger_than_budget()).unwrap();
    assert!(!cache.contains(key_a()));
}
```

- [ ] **Step 2: Run and observe missing renderer**

```powershell
cargo test -p clarix_pdf_adapter --test clean_patch --manifest-path rust/Cargo.toml
```

- [ ] **Step 3: Implement object-omitting rendering**

Clone the page/content representation in memory, remove only the qualified source operation identified by the private locator, render the bounded region with at least one device-pixel antialias bleed on every side, and return premultiplied RGBA plus PDF bounds. Do not white-fill, rasterize the replacement text, or modify the source file. Reject ambiguous shared text operators, clipping that cannot be reproduced, transparency groups that change unrelated content, and missing locator confidence.

- [ ] **Step 4: Implement scale buckets, cancellation, and LRU accounting**

Bucket by effective DPI so zoom can reuse the nearest lower-resolution patch while a sharper version is queued. Count decoded byte size, cap at 128 MiB/document, evict coldest non-visible entries first, and cancel queued renders after session close/source revision change.

- [ ] **Step 5: Verify raster and benchmark contracts**

```powershell
cargo test -p clarix_pdf_adapter --test clean_patch --manifest-path rust/Cargo.toml
cargo bench -p clarix_pdf_adapter --bench clean_patch --manifest-path rust/Cargo.toml --no-run
```

- [ ] **Step 6: Commit**

```powershell
git add rust/clarix_pdf_adapter test_fixtures/editing_corpus
git commit -m "feat: render cached clean text background patches"
```

---

### Task 8: Materialize and Independently Validate Native Text

**Files:**
- Create: `rust/clarix_pdf_adapter/src/materializer.rs`
- Create: `rust/clarix_pdf_adapter/src/validator.rs`
- Modify: `rust/clarix_pdf_adapter/src/lib.rs`
- Modify: `rust/clarix_pdf_adapter/Cargo.toml`
- Create: `rust/clarix_pdf_adapter/tests/materialization.rs`
- Create: `rust/clarix_pdf_adapter/tests/validation.rs`
- Create: `test_fixtures/editing_corpus/expected/phase1/README.md`

**Interfaces:**
- Consumes: immutable canonical snapshot, qualified source bindings, exact/approved fonts, and save expectations.
- Produces: searchable/selectable replacement text, `MaterializationReport`, `ValidationReport`, semantic/geometry/font checks, and unaffected-region raster evidence.

- [ ] **Step 1: Write failing round-trip tests**

```rust
#[test]
fn replacement_survives_reopen_as_searchable_selectable_text() {
    let output = temp_output();
    materializer().materialize(&edited_snapshot("After"), &output).unwrap();
    let reopened = independent_importer().inspect_page(&SourceRef::from_path(&output).unwrap(), 1).unwrap();
    assert_eq!(only_text(&reopened.page).text, "After");
    assert_eq!(only_text(&reopened.page).bounds(), expected_bounds());
}

#[test]
fn validator_rejects_changed_unaffected_pixels() {
    let report = validator().validate(&tampered_output(), &expectation()).unwrap();
    assert!(!report.valid);
    assert!(report.failures.iter().any(|failure| failure.code == "unaffected_region_changed"));
}
```

- [ ] **Step 2: Run and observe unsupported adapter operations**

```powershell
cargo test -p clarix_pdf_adapter --test materialization --test validation --manifest-path rust/Cargo.toml
```

- [ ] **Step 3: Implement deterministic text replacement**

Rewrite or safely replace only qualified source text operators, preserve page resources and unrelated object bytes where feasible, embed/reuse the exact permitted font, encode every replacement glyph, reproduce runs/layout/transform/clipping, and keep text extractable. Reject missing glyphs, forbidden embedding, ambiguous source mapping, layout overflow, unsupported writing modes, or lossy substitution before writing an output.

- [ ] **Step 4: Implement an independent validator**

Reopen with a path independent of the writer and verify: PDF readability, page count, expected edited text/ranges, bounds/transform tolerance, embedded font identity, no old duplicate text, and selectable/searchable extraction. Raster source/output at fixed DPI, mask edited bounds plus bleed, require unaffected regions within the corpus tolerance, and require edited regions within their golden tolerance. A warning never turns a failed invariant into success.

- [ ] **Step 5: Qualify exact Phase 1 cases**

Cover insert, delete, replacement, multiline, multiple runs, rotation, color/style, approved installed fallback, unsupported glyph rejection, subset-font rejection/approval, overflow rejection, and unchanged mixed page content. Store hashes and tolerances, not proprietary font bytes.

- [ ] **Step 6: Verify**

```powershell
cargo test -p clarix_pdf_adapter --test materialization --test validation --manifest-path rust/Cargo.toml
cargo clippy -p clarix_pdf_adapter --all-targets --manifest-path rust/Cargo.toml -- -D warnings
```

- [ ] **Step 7: Commit**

```powershell
git add rust/clarix_pdf_adapter test_fixtures/editing_corpus
git commit -m "feat: materialize and validate native text edits"
```

---

### Task 9: Implement Windows-Safe Save, Save As, Backup, and Rebase

**Files:**
- Create: `rust/clarix_pdf_adapter/src/windows_replace.rs`
- Modify: `rust/clarix_pdf_adapter/src/lib.rs`
- Modify: `rust/clarix_pdf_adapter/Cargo.toml`
- Modify: `rust/clarix_editing_core/src/save.rs`
- Create: `rust/clarix_pdf_adapter/tests/windows_replace.rs`
- Create: `rust/clarix_editing_core/tests/save_coordinator.rs`

**Interfaces:**
- Consumes: materializer/validator, repository materialization checkpoint, source fingerprint, and save request.
- Produces: sibling temp output, flushed validated replacement, rolling `.<filename>.clarix-backup.pdf`, `ReplaceFileW` adapter, Save As association choice, and rebased source bindings.

- [ ] **Step 1: Write save-stage fault tests**

```rust
#[test]
fn every_pre_replace_failure_preserves_source_and_sidecar() {
    for stage in [SaveStage::VerifySource, SaveStage::MaterializeTemp, SaveStage::ValidateTemp, SaveStage::FlushTemp] {
        let harness = save_harness_failing_at(stage);
        assert!(harness.save().is_err());
        assert_eq!(harness.source_bytes(), ORIGINAL_PDF);
        assert_eq!(harness.sidecar_revision(), revision(3));
    }
}

#[test]
fn source_fingerprint_conflict_stops_before_materialization() {
    let harness = save_harness_with_external_source_change();
    assert_eq!(harness.save().unwrap_err().code(), "source_changed");
    assert_eq!(harness.materialize_calls(), 0);
}
```

- [ ] **Step 2: Run and observe missing Windows replacement adapter**

```powershell
cargo test -p clarix_editing_core --test save_coordinator --manifest-path rust/Cargo.toml
cargo test -p clarix_pdf_adapter --test windows_replace --manifest-path rust/Cargo.toml
```

- [ ] **Step 3: Implement the exact Save transaction**

Flush active composition/command queue, snapshot at a fixed revision, re-hash source, materialize to a unique sibling temp on the same volume, validate independently, flush file buffers, call `ReplaceFileW` with the rolling backup path, reopen the installed output, re-import/rebase source bindings, record materialized revision, then move the backup into project `recovery/`. If reopen or sidecar recording fails after replacement, preserve both installed output and backup and report a recoverable partial-finalization state.

- [ ] **Step 4: Implement Save As**

Materialize and validate into the destination directory, atomically rename the new file without touching the original, then apply the explicit association choice. `FollowNewSource` records the new fingerprint and rebases; `KeepOriginalAssociation` records an export event while the project remains attached to the original.

- [ ] **Step 5: Map Windows failures**

Map sharing violation to `source_locked`, access denial to `permission_denied`, disk full to `disk_full`, non-same-volume replacement to `non_atomic_target`, antivirus delay timeout to `replace_timeout`, and reopen failure to `installed_output_unreadable`. Do not fall back to delete/rename overwrite.

- [ ] **Step 6: Verify fault matrix**

```powershell
cargo test -p clarix_editing_core --test save_coordinator --manifest-path rust/Cargo.toml
cargo test -p clarix_pdf_adapter --test windows_replace --manifest-path rust/Cargo.toml
```

- [ ] **Step 7: Commit**

```powershell
git add rust/clarix_editing_core rust/clarix_pdf_adapter
git commit -m "feat: add validated atomic Windows PDF save"
```

---

### Task 10: Expand the Typed Native Editor Session API

**Files:**
- Modify: `rust/clarix_pdf_oxide/Cargo.toml`
- Modify: `rust/clarix_pdf_oxide/src/editing_api.rs`
- Modify: `rust/clarix_pdf_oxide/tests/editing_bridge.rs`
- Regenerate: `rust/clarix_pdf_oxide/src/frb_generated.rs`
- Regenerate: `lib/src/core/ffi/editing_api.dart`
- Regenerate: `lib/src/core/ffi/frb_generated*.dart`
- Modify: `lib/src/core/editing/editor_bridge_types.dart`
- Modify: `lib/src/core/editing/editor_bridge.dart`
- Modify: `test/core/editing/editor_bridge_contract_test.dart`

**Interfaces:**
- Consumes: durable actor, store, page service, clean patches, save coordinator.
- Produces: typed `open/recover`, viewport priority, page scene, object details, submit/cancel, events, checkpoint, save/save-as, memory-pressure, and close methods.

- [ ] **Step 1: Write failing Rust bridge lifecycle tests**

```rust
#[test]
fn accepted_command_is_durable_before_native_result_returns() {
    let session = open_test_session();
    let result = session.submit(replace_request(0, "After")).unwrap();
    drop(session);
    let recovered = NativeEditorSession::open(recover_request()).unwrap();
    assert_eq!(recovered.object_details(object_request()).unwrap().text, "After");
    assert_eq!(recovered.metadata().unwrap().revision, result.committed_revision);
}
```

Add exact tests for visible page 137, clean-patch handle lifetime, viewport priority cancellation, save progress ordering, source conflict, Save As association, dirty close choices, schema mismatch, and late callbacks after close.

- [ ] **Step 2: Run and observe missing Phase 1 DTOs**

```powershell
cargo test -p clarix_pdf_oxide --test editing_bridge --manifest-path rust/Cargo.toml
```

- [ ] **Step 3: Compose infrastructure without exposing it**

`NativeEditorSession::open` resolves the project path, opens/recover the SQLite repository, constructs qualified PDF adapters and page service, recovers the actor, and emits `Ready` only afterward. Keep all infrastructure fields private. Return typed `NativeEditorFailure { code, stage, message, retryable }` instead of colon-delimited strings for new calls; convert old error strings at the handwritten Dart boundary until all callers migrate.

- [ ] **Step 4: Extend hot-path DTOs**

Page scenes include page revision, object capability/reason, layout recipe, hit-test glyph boxes, exact font asset handle/fingerprint, clean-patch asset handle/bounds/DPI, and only visible objects. Asset calls resolve content-addressed font/patch handles without copying the PDF or complete page raster over the bridge. Command results include previous/committed revision, patches, selection rebase, durability, and warnings. Save calls stream progress and never block the UI isolate.

- [ ] **Step 5: Regenerate and update the handwritten Dart adapter**

```powershell
flutter_rust_bridge_codegen generate
dart format lib/src/core/ffi lib/src/core/editing
```

Validate every UUID, nonnegative checked integer, enum, schema version, event sequence, page revision, UTF-16 range, and RGBA length. Dispose patch handles and event subscriptions before native close.

- [ ] **Step 6: Verify bridge compatibility**

```powershell
cargo test -p clarix_pdf_oxide --test editing_bridge --manifest-path rust/Cargo.toml
flutter test test/core/editing/editor_bridge_contract_test.dart
flutter analyze lib/src/core/editing lib/src/core/ffi test/core/editing
```

- [ ] **Step 7: Commit**

```powershell
git add rust/clarix_pdf_oxide lib/src/core/ffi lib/src/core/editing test/core/editing
git commit -m "feat: expose durable Phase 1 editor session API"
```

---

### Task 11: Add the Flutter Workspace Editing Application Layer

**Files:**
- Create: `lib/src/features/workspace/editing/domain/editor_document_state.dart`
- Create: `lib/src/features/workspace/editing/domain/editor_selection.dart`
- Create: `lib/src/features/workspace/editing/domain/editor_save_state.dart`
- Create: `lib/src/features/workspace/editing/application/editor_session_controller.dart`
- Create: `lib/src/features/workspace/editing/application/editor_session_registry.dart`
- Create: `lib/src/features/workspace/editing/infrastructure/editor_session_gateway.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Create: `test/workspace_editing/editor_session_controller_test.dart`
- Create: `test/workspace_editing/editor_session_registry_test.dart`

**Interfaces:**
- Consumes: low-level `EditorBridgeSession` only through `EditorSessionGateway`.
- Produces: one application controller per open tab/document, immutable accepted scenes, one bounded optimistic edit, revision reconciliation, dirty/checkpoint/save state, and ordered disposal.

- [ ] **Step 1: Write failing optimistic reconciliation tests**

```dart
test('optimistic text paints immediately and accepted patch reconciles by command id', () async {
  final gateway = FakeEditorSessionGateway(scene: scene(text: 'Before', revision: 0));
  final controller = EditorSessionController(gateway: gateway, commandIds: fixedIds());
  await controller.open('fixture.pdf');
  controller.applyLocalDelta(objectId: objectId, range: const TextRange(start: 0, end: 6), replacement: 'After');
  expect(controller.state.visibleText(objectId), 'After');
  expect(gateway.pendingSubmitCount, 1);
  gateway.completeSubmit(result(commandId: firstId, revision: 1, text: 'After'));
  await pumpEventQueue();
  expect(controller.state.revision, 1);
  expect(controller.state.optimisticEdit, isNull);
});
```

Add rejection rollback without focus/viewport change, stale patch discard, lagged-event scene refresh, close order, and maximum one unsent coalesced command per active object.

- [ ] **Step 2: Run and observe missing application layer**

```powershell
flutter test test/workspace_editing/editor_session_controller_test.dart test/workspace_editing/editor_session_registry_test.dart
```

- [ ] **Step 3: Implement clean domain/application separation**

Domain files import neither Flutter widgets, pdfrx, FRB, nor generated types. `EditorSessionController` depends on an abstract gateway, maps events into immutable state, owns command IDs/base revisions, and serializes submits. `EditorSessionRegistry` owns a controller per tab and closes it before tab state disappears.

- [ ] **Step 4: Implement optimistic command reconciliation**

Paint local `TextEditingValue` in the initiating frame, retain command ID and base revision, coalesce while one submit is unsent, and reconcile only the matching result. On typed rejection, restore the last accepted object, preserve focus/caret/scroll, surface the error, and request a fresh object/scene when the revision is stale.

- [ ] **Step 5: Verify application tests and analysis**

```powershell
flutter test test/workspace_editing/editor_session_controller_test.dart test/workspace_editing/editor_session_registry_test.dart
flutter analyze lib/src/features/workspace/editing test/workspace_editing
```

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/editing lib/src/features/workspace/application/workspace_providers.dart test/workspace_editing
git commit -m "feat: add Rust-backed workspace editing controller"
```

---

### Task 12: Introduce a Stable Page Surface and Visible-Page Scene Lifecycle

**Files:**
- Create: `lib/src/features/workspace/editing/presentation/page_surface.dart`
- Create: `lib/src/features/workspace/editing/presentation/pdfrx_page_surface.dart`
- Create: `lib/src/features/workspace/editing/presentation/page_scene_host.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Create: `test/workspace_editing/page_surface_test.dart`
- Create: `test/workspace_editing/page_scene_lifecycle_test.dart`

**Interfaces:**
- Consumes: pdfrx controller/viewer and `EditorSessionController`.
- Produces: `PageSurface` coordinate transforms, visible page IDs/priorities, stable viewer identity, +/-2 preload requests, and disposal of cold Flutter resources only.

- [ ] **Step 1: Write failing stability and all-pages widget tests**

```dart
testWidgets('typing never invalidates or replaces the page surface', (tester) async {
  final surface = RecordingPageSurface();
  await tester.pumpWidget(editorHarness(surface: surface));
  await enterText(tester, find.byKey(const Key('clarix-native-editor')), 'x');
  await tester.pump();
  expect(surface.reloadCount, 0);
  expect(surface.identityChanges, 0);
  expect(surface.viewport, initialViewport);
});

testWidgets('scrolling to page 137 requests and mounts page 137 scene', (tester) async {
  final gateway = FakeEditorGateway(pageCount: 500);
  await tester.pumpWidget(editorHarness(gateway: gateway));
  gateway.surface.showPage(137);
  await tester.pumpAndSettle();
  expect(gateway.requestedPages, contains(137));
  expect(find.byKey(const ValueKey('page-edit-scene-137')), findsOneWidget);
});
```

- [ ] **Step 2: Run and observe missing page abstraction**

```powershell
flutter test test/workspace_editing/page_surface_test.dart test/workspace_editing/page_scene_lifecycle_test.dart
```

- [ ] **Step 3: Wrap pdfrx without editing through it**

Expose page/document coordinate transforms, visible page set, zoom, scroll anchor, page size, and lifecycle notifications. Do not expose PDF mutation methods to the new editor. Remove new-path calls to `invalidate`, `forceRepaintAllPageImages`, PDFium text suppression, or document re-encode.

- [ ] **Step 4: Drive Rust page priorities from viewport changes**

Request every visible page, preload two pages in each direction, cancel obsolete warm requests, report cold pages, and keep the stable PDF page visible while bounds load. Disposing an offscreen scene releases focus nodes, animation controllers, patch image handles, and GPU layers but not accepted model metadata.

- [ ] **Step 5: Verify no-reload behavior**

```powershell
flutter test test/workspace_editing/page_surface_test.dart test/workspace_editing/page_scene_lifecycle_test.dart
flutter analyze lib/src/features/workspace/editing/presentation lib/src/features/workspace/presentation/widgets/document_workspace.dart
```

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/editing/presentation lib/src/features/workspace/presentation/widgets/document_workspace.dart test/workspace_editing
git commit -m "feat: add stable retained page scene lifecycle"
```

---

### Task 13: Composite Clean Patches and Retained Text Overlays

**Files:**
- Create: `lib/src/features/workspace/editing/presentation/page_edit_scene.dart`
- Create: `lib/src/features/workspace/editing/presentation/editor_text_painter.dart`
- Create: `lib/src/features/workspace/editing/presentation/clean_patch_layer.dart`
- Create: `lib/src/features/workspace/editing/presentation/editor_hit_test.dart`
- Create: `test/workspace_editing/page_edit_scene_test.dart`
- Create: `test/workspace_editing/page_edit_scene_golden_test.dart`

**Interfaces:**
- Consumes: accepted/optimistic page scenes, imported font assets, clean patch handles, page transform.
- Produces: retained composition order `base -> clean patch -> text -> editor chrome`, object-scoped repaint boundaries, hit-test anchors, and golden evidence.

- [ ] **Step 1: Write failing layer-order and repaint tests**

```dart
testWidgets('edited source is covered before replacement glyphs paint', (tester) async {
  final recorder = LayerRecorder();
  await tester.pumpWidget(sceneHarness(recorder: recorder, edited: true));
  expect(recorder.layers, <String>['clean-patch', 'text-object', 'selection-chrome']);
});

testWidgets('typing repaints only the active object boundary', (tester) async {
  final counters = RepaintCounters();
  await tester.pumpWidget(sceneHarness(counters: counters, objectCount: 3));
  await typeIntoObject(tester, objectId: 'object-2', text: 'x');
  expect(counters.forObject('object-1'), 0);
  expect(counters.forObject('object-2'), greaterThan(0));
  expect(counters.forObject('object-3'), 0);
  expect(counters.basePage, 0);
});
```

- [ ] **Step 2: Run and observe missing retained scene widgets**

```powershell
flutter test test/workspace_editing/page_edit_scene_test.dart
```

- [ ] **Step 3: Implement retained object layers**

Key scenes by page ID and accepted revision; key object repaint boundaries by object ID. Decode patch assets outside paint, map PDF coordinates through `PageSurface`, clip to patch bleed, render text with exact registered font identity/layout recipe, then paint selection/caret/handles. Unedited objects do not get overlays. Higher-DPI patches replace lower-DPI patches without changing page identity or geometry.

- [ ] **Step 4: Implement warm hit testing**

Use Rust-provided glyph boxes and legal anchors, apply object transform, choose nearest legal UTF-16/grapheme anchor, and return object ID/offset/affinity. Ignore read-only objects for edit entry while still allowing read-mode selection.

- [ ] **Step 5: Record goldens**

Cover 100%, 150%, and 200% DPI; 75%, 100%, and 200% zoom; rotated text; dark/light page surroundings; Latin and RTL; selection/caret/composition; and patch scale replacement. Compare edited regions and ensure base page pixels outside scene bounds are identical.

- [ ] **Step 6: Verify**

```powershell
flutter test test/workspace_editing/page_edit_scene_test.dart
flutter test test/workspace_editing/page_edit_scene_golden_test.dart --update-goldens
flutter test test/workspace_editing/page_edit_scene_golden_test.dart
```

- [ ] **Step 7: Commit**

```powershell
git add lib/src/features/workspace/editing/presentation test/workspace_editing
git commit -m "feat: render retained native text edit overlays"
```

---

### Task 14: Implement Click, Selection, Keyboard, Clipboard, IME, and Accessibility

**Files:**
- Create: `lib/src/features/workspace/editing/presentation/native_text_editor.dart`
- Create: `lib/src/features/workspace/editing/presentation/editor_shortcuts.dart`
- Create: `lib/src/features/workspace/editing/presentation/editor_semantics.dart`
- Modify: `lib/src/features/workspace/editing/presentation/page_edit_scene.dart`
- Create: `test/workspace_editing/native_text_editor_test.dart`
- Create: `test/workspace_editing/native_text_ime_test.dart`
- Create: `test/workspace_editing/native_text_accessibility_test.dart`

**Interfaces:**
- Consumes: hit-test anchors, controller optimistic delta API, canonical UTF-16 ranges, text styles/layout.
- Produces: single focused editor per active block, Windows IME composition, click/word/drag selection, clipboard, keyboard ownership, and semantics.

- [ ] **Step 1: Write failing interaction tests**

```dart
testWidgets('single click places caret without selecting the block', (tester) async {
  await tester.pumpWidget(textEditorHarness(text: 'one two'));
  await tester.tapAt(anchorPosition(4));
  await tester.pump();
  expect(activeSelection(), const TextSelection.collapsed(offset: 4));
});

testWidgets('double click selects a word and drag extends legal UTF-16 range', (tester) async {
  await tester.pumpWidget(textEditorHarness(text: 'one two 👩🏽‍💻'));
  await tester.tapAt(anchorPosition(5), buttons: kPrimaryButton);
  await tester.tapAt(anchorPosition(5), buttons: kPrimaryButton);
  expect(activeSelection(), const TextSelection(baseOffset: 4, extentOffset: 7));
  await dragSelectionTo(tester, legalEndAnchor());
  expect(activeSelection().extentOffset, legalEndOffset());
});
```

Add exact tests for triple-click visual line, arrows, Home/End, Ctrl+A/C/X/V/Z/Y, Backspace/Delete by grapheme, Space/PageUp/PageDown ownership, Escape, focus preservation after acknowledgement, and no whole-block selection on entry.

- [ ] **Step 2: Write Windows IME composition tests**

Use `tester.testTextInput.updateEditingValue` to send composing values, assert the underline paints locally before submit, assert intermediate composing updates coalesce without Rust commits, and assert composition commit sends one command with a composition boundary. Cancelled composition restores accepted text and sends no command.

- [ ] **Step 3: Run and observe missing input widget**

```powershell
flutter test test/workspace_editing/native_text_editor_test.dart test/workspace_editing/native_text_ime_test.dart
```

- [ ] **Step 4: Implement one `EditableText`-backed active editor**

Mount only for the active object; initialize selection from the clicked anchor; retain its focus node/controller across accepted patches; update local value synchronously; translate deltas to canonical UTF-16 ranges; and submit/coalesce asynchronously. While composing, route navigation/text shortcuts to the editor and prevent pdfrx key handling.

- [ ] **Step 5: Implement semantics**

Expose editable text, current selection, read-only reason, set-selection, set-text, copy/cut/paste, and focus actions through a stable semantics node. Announce validation/font/overflow errors without moving focus.

- [ ] **Step 6: Verify interactions**

```powershell
flutter test test/workspace_editing/native_text_editor_test.dart test/workspace_editing/native_text_ime_test.dart test/workspace_editing/native_text_accessibility_test.dart
flutter analyze lib/src/features/workspace/editing/presentation test/workspace_editing
```

- [ ] **Step 7: Commit**

```powershell
git add lib/src/features/workspace/editing/presentation test/workspace_editing
git commit -m "feat: add native text input and Windows IME flow"
```

---

### Task 15: Wire Formatting, Overflow, Font Fallback Approval, and History UI

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart`
- Create: `lib/src/features/workspace/editing/presentation/object_transform_handles.dart`
- Create: `lib/src/features/workspace/editing/presentation/font_fallback_dialog.dart`
- Create: `lib/src/features/workspace/editing/presentation/overflow_indicator.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Create: `test/workspace_editing/format_panel_test.dart`
- Create: `test/workspace_editing/font_fallback_dialog_test.dart`
- Create: `test/workspace_editing/history_shortcuts_test.dart`
- Create: `test/workspace_editing/object_transform_handles_test.dart`

**Interfaces:**
- Consumes: selected object/range style, typed commands, font fallback proposal, overflow result, undo/redo availability.
- Produces: source-preserving format controls, explicit fallback approval, actionable overflow UI, typed move/resize/rotate gestures, and Rust-backed undo/redo/checkpoints.

- [ ] **Step 1: Write failing format and fallback tests**

```dart
testWidgets('format panel reflects source run and submits typed style command', (tester) async {
  final gateway = FakeEditorGateway(scene: styledScene(font: 'Arial', size: 12));
  await tester.pumpWidget(formatHarness(gateway));
  expect(find.text('Arial'), findsOneWidget);
  await tester.enterText(find.byKey(const Key('font-size-field')), '14');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  expect(gateway.lastCommand.kind, EditorCommandKind.setTextStyle);
  expect(gateway.lastCommand.style!.fontSize, 14);
});

testWidgets('unencodable glyph requires explicit fallback approval', (tester) async {
  final gateway = FakeEditorGateway(rejectWith: fallbackProposal('Arial Unicode MS'));
  await tester.pumpWidget(formatHarness(gateway));
  await typeTextRequiringFallback(tester);
  expect(find.byType(FontFallbackDialog), findsOneWidget);
  expect(gateway.committedFallbacks, isEmpty);
});
```

- [ ] **Step 2: Run and observe old-controller coupling**

```powershell
flutter test test/workspace_editing/format_panel_test.dart test/workspace_editing/font_fallback_dialog_test.dart
```

- [ ] **Step 3: Adapt the existing panel to canonical commands**

Read mixed/exact style from the Rust-backed selection, submit `SetTextStyle` or `SetParagraphStyle`, disable controls absent from Phase 1, and show read-only reasons. Preserve font, size, color, spacing, alignment, transform, and line height unless the user changes that field.

- [ ] **Step 4: Require fallback approval and handle overflow**

Display proposed font name/source/embedding status and affected characters. Approve by resubmitting against the current revision with the proposal token; reject without mutation. For `Reject` overflow policy, keep optimistic text visibly marked until rejection then reconcile; offer only `IncreaseBounds` or cancel where the model explicitly permits resizing. Never silently shrink, reflow unrelated blocks, or substitute.

- [ ] **Step 5: Route history and checkpoint UI to Rust**

Ctrl+Z/Ctrl+Y and toolbar actions submit typed undo/redo commands; dirty indicators derive from sidecar/materialized revisions; named checkpoints use `CreateCheckpoint`. Disable actions while the previous history command is outstanding.

- [ ] **Step 6: Route transform handles through typed commands**

Use local drag previews without changing canonical state. On pointer-up, convert the page-space result into exactly one `MoveObject`, `ResizeObject`, or `RotateObject` command at the accepted base revision. Escape cancels the preview; a rejected command restores accepted bounds/transform without moving the page surface. Add tests asserting one command per gesture, correct PDF-coordinate conversion at 75%/200% zoom, and no pdfrx mutation/reload.

- [ ] **Step 7: Verify**

```powershell
flutter test test/workspace_editing/format_panel_test.dart test/workspace_editing/font_fallback_dialog_test.dart test/workspace_editing/history_shortcuts_test.dart test/workspace_editing/object_transform_handles_test.dart
flutter analyze lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart lib/src/features/workspace/editing test/workspace_editing
```

- [ ] **Step 8: Commit**

```powershell
git add lib/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/editing test/workspace_editing
git commit -m "feat: wire canonical formatting and history UI"
```

---

### Task 16: Wire Dirty Close, Recovery, Save, and Save As UI

**Files:**
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Create: `lib/src/features/workspace/editing/presentation/dirty_close_dialog.dart`
- Create: `lib/src/features/workspace/editing/presentation/save_progress_dialog.dart`
- Create: `lib/src/features/workspace/editing/presentation/save_conflict_dialog.dart`
- Create: `lib/src/features/workspace/editing/presentation/recovery_banner.dart`
- Create: `test/workspace_editing/dirty_close_test.dart`
- Create: `test/workspace_editing/save_ui_test.dart`
- Create: `test/workspace_editing/recovery_ui_test.dart`

**Interfaces:**
- Consumes: durable dirty/checkpoint state, save progress/results, recoverable project metadata.
- Produces: explicit Ctrl+S/Save/Save As, conflict choices, recover-on-open, and close choices `Save PDF`, `Keep Recoverable Project`, `Discard to Recovery`.

- [ ] **Step 1: Write failing UI flow tests**

```dart
testWidgets('closing a dirty tab offers all three non-destructive choices', (tester) async {
  await tester.pumpWidget(workspaceHarness(dirty: true));
  await closeActiveTab(tester);
  expect(find.text('Save PDF'), findsOneWidget);
  expect(find.text('Keep Recoverable Project'), findsOneWidget);
  expect(find.text('Discard to Recovery'), findsOneWidget);
});

testWidgets('Ctrl+S flushes composition before native save', (tester) async {
  final gateway = RecordingEditorGateway();
  await tester.pumpWidget(workspaceHarness(gateway: gateway, composing: true));
  await sendControlS(tester);
  expect(gateway.calls, <String>['commit-composition', 'flush-commands', 'save']);
});
```

Add source-changed -> Save As/rebase dialog, locked-file -> retry/Save As, failed validation -> original preserved, successful save -> one viewer refresh with nearest page/zoom anchor, Save As association choice, and recovered-project banner tests.

- [ ] **Step 2: Run and observe missing dialogs/new controller flow**

```powershell
flutter test test/workspace_editing/dirty_close_test.dart test/workspace_editing/save_ui_test.dart test/workspace_editing/recovery_ui_test.dart
```

- [ ] **Step 3: Implement explicit save actions**

Ctrl+S and Save call the controller only after committing active IME composition and flushing the command queue. Show streamed stages and permit cancel only before atomic replacement begins. After success, refresh the base viewer exactly once and restore the nearest page/zoom anchor; accepted overlay state is rebased rather than discarded.

- [ ] **Step 4: Implement recovery-safe close choices**

`Keep Recoverable Project` closes cleanly after WAL checkpoint without materializing. `Discard to Recovery` creates a tombstoned recovery checkpoint and closes; it does not delete project data. `Save PDF` closes only after successful save. Cancel leaves the session open.

- [ ] **Step 5: Verify**

```powershell
flutter test test/workspace_editing/dirty_close_test.dart test/workspace_editing/save_ui_test.dart test/workspace_editing/recovery_ui_test.dart
flutter analyze lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/editing
```

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/editing test/workspace_editing
git commit -m "feat: add recoverable save and close workflows"
```

---

### Task 17: Feature-Flag Migration and Remove the Per-Keystroke PDF Mutation Path

**Files:**
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Modify: `lib/src/features/workspace/application/pdf_editing_controller.dart`
- Delete after exit evidence passes: `lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart`
- Delete after exit evidence passes: `lib/src/features/workspace/infrastructure/pdf_preview_document_controller.dart`
- Delete after exit evidence passes: `lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart`
- Update or delete legacy-only tests under `test/workspace_pdf/`
- Create: `test/workspace_editing/editor_migration_test.dart`

**Interfaces:**
- Consumes: complete Rust-backed Phase 1 path.
- Produces: `clarixRustEditingV1` developer flag, side-by-side comparison mode, then one authoritative editor with no Dart history or PDFium mutation fallback.

- [ ] **Step 1: Write failing authority-boundary tests**

```dart
test('Rust editor flag never constructs legacy mutation services', () async {
  final dependencies = RecordingEditingDependencies();
  await createWorkspace(editingFlag: EditingFlag.clarixRustEditingV1, dependencies: dependencies);
  expect(dependencies.pdfiumMutationCoordinatorCreations, 0);
  expect(dependencies.dartEditingSessionCreations, 0);
});
```

Add a static repository scan test that fails if the new editing subtree imports `pdf_edit_session.dart`, `pdf_native_edit_coordinator.dart`, `pdf_preview_document_controller.dart`, or `pdf_edit_save_service.dart`.

- [ ] **Step 2: Run and observe legacy construction**

```powershell
flutter test test/workspace_editing/editor_migration_test.dart
```

- [ ] **Step 3: Add comparison and rollout states**

Support `legacy`, `compareScenes`, and `clarixRustEditingV1`. `compareScenes` opens the Rust session read-only, compares IDs/bounds/text/capabilities against legacy discovery, emits content-free diagnostics, and leaves gestures on legacy. `clarixRustEditingV1` routes all edit/history/save behavior to the new controller and never mutates the pdfrx document.

- [ ] **Step 4: Remove the legacy authority only after Task 18 evidence passes**

Delete the three infrastructure files and their provider wiring, remove Dart-owned command/history/save state, and retain only reusable presentation math/tests that do not depend on transient object paths or PDFium mutation. Update AI code to remain read-only with respect to Phase 1; agent mutation stays deferred to Phase 3.

- [ ] **Step 5: Verify migration boundary**

```powershell
flutter test test/workspace_editing/editor_migration_test.dart
flutter test test/workspace_pdf
flutter analyze lib/src/features/workspace test/workspace_editing test/workspace_pdf
```

- [ ] **Step 6: Commit the flag before gate, and legacy deletion after gate**

```powershell
git add lib/src/features/workspace test/workspace_editing test/workspace_pdf
git commit -m "feat: gate Rust authoritative PDF editing"
```

After Task 18 passes and before Phase 1 is declared complete:

```powershell
git add -A lib/src/features/workspace test/workspace_pdf
git commit -m "refactor: remove per-keystroke PDF mutation path"
```

---

### Task 18: Build the Phase 1 Performance, Crash, Save, and External-Reader Gate

**Files:**
- Create: `rust/clarix_editing_store/benches/sidecar_latency.rs`
- Create: `rust/clarix_pdf_adapter/benches/save_latency.rs`
- Create: `integration_test/phase1_editing_test.dart`
- Create: `integration_test/phase1_large_document_test.dart`
- Create: `tool/editing_phase1/run_phase1_checks.ps1`
- Create: `tool/editing_phase1/kill_recovery_probe.ps1`
- Create: `tool/editing_phase1/external_reader_probe.ps1`
- Create: `tool/editing_phase1/record_phase1_evidence.ps1`
- Create: `docs/testing/editing-phase1-exit-gate.md`
- Create: `docs/testing/editing-phase1-results.json`
- Modify: `docs/testing/editing-phase0-baseline.json`
- Modify: `rust/clarix_pdf_oxide/README.md`

**Interfaces:**
- Consumes: all Phase 1 behavior and Phase 0 benchmark baseline.
- Produces: reproducible gate evidence for latency, no-reload/no-shift, memory plateau, crash recovery, atomic save, external readers, corpus capability, and user-owned DLL build result.

- [ ] **Step 1: Add functional benchmark smoke tests before timing**

Test 10,000 accepted replace/undo operations with repository reopen, 1,000-page visit order with a two-worker cap, clean-patch cache eviction, and repeated materialize/validate cycles. Assert final revision/text, zero lost accepted commits, bounded queue/cache sizes, and no temp/backup leak.

- [ ] **Step 2: Implement Criterion measurements**

Measure warm actor acknowledgement with in-memory repository, SQLite durable acknowledgement, snapshot/recovery, indexed/unindexed page request, warm caret lookup, clean patch cold/warm, materialization, validation, and atomic replacement setup. Record distributions; do not encode hardware-independent wall-clock assertions in Rust unit tests.

- [ ] **Step 3: Implement profile-mode Flutter evidence**

`phase1_editing_test.dart` records keystroke-to-overlay frame, caret placement, focus, page widget identity, reload counter, page number, zoom, and scroll anchor across 1,000 typed characters, IME composition, undo/redo, and background acknowledgements. `phase1_large_document_test.dart` scrolls the large corpus repeatedly and records scene latency, frame timing, resident scene count, patch bytes, and process memory plateau.

- [ ] **Step 4: Implement forced-kill and save fault probes**

`kill_recovery_probe.ps1` launches the profile app with a fixture, waits for each accepted-command marker, terminates the process without graceful shutdown at seeded command counts, reopens, and compares recovered revision/text to the last accepted marker. Run at least 100 seeded terminations including during WAL checkpoint. The save probe injects every stage failure from Task 9 and hashes original, temp, backup, installed output, and sidecar before/after.

- [ ] **Step 5: Implement external-reader qualification**

Open every supported saved output through the independent Rust validator, pdfrx/PDFium extraction, and at least one Windows external reader automation available on the test machine. Verify replacement text is searchable, selectable, extractable, correctly positioned, and old text is absent. Record reader/version and skip reason only when a named reader is unavailable; Rust and pdfrx checks are mandatory.

- [ ] **Step 6: Create a gate that never runs `cargo build`**

`run_phase1_checks.ps1` runs exactly:

```powershell
cargo fmt --all --manifest-path rust/Cargo.toml -- --check
cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings
cargo test --workspace --manifest-path rust/Cargo.toml
cargo bench --workspace --manifest-path rust/Cargo.toml --no-run
flutter_rust_bridge_codegen generate
git diff --exit-code -- rust/clarix_pdf_oxide/src/frb_generated.rs lib/src/core/ffi
flutter test test/core/editing test/workspace_editing
flutter test test/workspace_pdf
flutter analyze lib/src/core/editing lib/src/core/ffi lib/src/features/workspace/editing lib/src/features/workspace
```

The script must not invoke `cargo build` directly or indirectly. It prints the exact user-owned release build command as a pending evidence item but does not execute it.

- [ ] **Step 7: Run non-build checks and evidence probes**

```powershell
& tool/editing_phase1/run_phase1_checks.ps1
& tool/editing_phase1/kill_recovery_probe.ps1
& tool/editing_phase1/external_reader_probe.ps1
& tool/editing_phase1/record_phase1_evidence.ps1 -OutputPath docs/testing/editing-phase1-results.json
```

Expected: all commands exit zero; performance JSON meets every architecture target; reload and viewport-shift counters are zero; recovered revision always equals the last accepted revision; supported outputs pass mandatory readers.

- [ ] **Step 8: Hand the release build to the user**

Record this as `pending_user_execution` until the user runs it:

```powershell
cargo build --release -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --target x86_64-pc-windows-msvc
```

The implementing agent must not run that command. The user supplies exit code, DLL path/hash, and timestamp for `editing-phase1-results.json`.

- [ ] **Step 9: Record the exit gate and finalize migration**

`editing-phase1-exit-gate.md` records commit, hardware/OS/tool versions, corpus hash, adapter capability/reason matrix, every performance percentile, crash seeds, save fault stages, external-reader results, memory plateau, zero reload/shift proof, generated-binding diff, user-owned build evidence, and remaining read-only constructs. After every item passes, execute Task 17's legacy deletion commit and rerun Steps 6-8 against that commit.

- [ ] **Step 10: Commit evidence**

```powershell
git add rust/clarix_editing_store rust/clarix_pdf_adapter integration_test tool/editing_phase1 docs/testing rust/clarix_pdf_oxide/README.md
git commit -m "test: enforce Phase 1 native text editing gate"
```

---

## Phase 1 Completion Checklist

- [ ] Every visited page can publish stable text bounds/IDs independent of widget lifetime.
- [ ] Only explicitly qualified native text is editable; every rejection has a stable actionable reason.
- [ ] Single click places a caret; double click selects a word; drag, keyboard, clipboard, IME, and accessibility pass.
- [ ] Local input paints within the initiating frame and reconciles by command ID/revision.
- [ ] Typing causes zero pdfrx/PDF page reloads, zero viewport shifts, and zero focus changes from background commits.
- [ ] Clean patches omit only the original source appearance and obey the 128 MiB cache budget.
- [ ] Rust commands, inverses, undo groups, checkpoints, and canonical state are the only accepted editing authority.
- [ ] Every returned-success command is durable in SQLite and survives forced termination.
- [ ] Recovery validates schema/source/snapshots and falls back safely when the newest snapshot is corrupt.
- [ ] Formatting preserves unchanged source attributes; font substitution always requires explicit approval.
- [ ] Overflow and unsupported glyphs fail safely without silent reflow, shrink, rasterization, or substitution.
- [ ] Save and Save As materialize only supported source bindings as native searchable/selectable text.
- [ ] Validation, lock, disk, antivirus, and replacement failures preserve the source PDF and sidecar.
- [ ] Successful Save uses backup plus atomic Windows replacement and refreshes the viewer exactly once.
- [ ] All Phase 1 latency, frame, memory, crash, corpus, and external-reader targets have recorded evidence.
- [ ] The user-owned release `cargo build` succeeds and its evidence is recorded; no agent ran `cargo build`.
- [ ] The legacy Dart/PDFium per-keystroke mutation, history, and save authority is removed only after the gate passes.

## Explicitly Deferred

- Search/replace-all, document-wide reflow, block layout across unrelated objects, and bulk transactions (Phase 2).
- Conversation state, model providers, selection-aware AI, agent plans/tools/approvals, and autonomous execution (Phase 3).
- OCR execution and acceptance, OCR text editing, semantic enrichment, and OCR image budgets (Phase 4).
- Image insertion/replacement, vectors, shapes, groups, annotations, and generated assets (Phase 5).
- Cross-platform atomic replacement implementations and non-Windows delivery (Phase 6).
