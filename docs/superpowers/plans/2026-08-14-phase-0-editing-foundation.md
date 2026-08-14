# Phase 0 Editing Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the Windows-first Rust workspace, canonical document model, single-writer editor session, typed Flutter bridge, PDF-adapter qualification corpus, and reproducible benchmark baseline required before user-facing editing begins.

**Architecture:** Four Rust crates ship through the existing `clarix_pdf_oxide.dll`: a dependency-free deterministic editing core, a PDF adapter layer, an agent boundary that can only use public editing tools, and the existing FRB facade. Phase 0 uses an in-memory model and read-only PDF inspection; sidecar persistence, PDF materialization, and Flutter editing overlays remain separate follow-up plans.

**Tech Stack:** Rust 2021, Cargo workspace, `flutter_rust_bridge 2.12.0`, `serde`, `uuid`, `thiserror`, `crossbeam-channel`, `pdf_oxide 0.3`, `lopdf 0.40`, Criterion, Flutter/Dart, Windows x64 MSVC.

**Spec:** `docs/clarix-windows-editing-platform-architecture.md`

## Global Constraints

- Windows desktop is the only Phase 0 runtime target; canonical types must not contain Windows handles or platform paths.
- Flutter remains the UI shell and `clarix_pdf_oxide.dll` remains the one packaged native library.
- Rust owns accepted model state, object identity, command ordering, and revisions.
- Phase 0 must not mutate a PDF, reload a viewer page, implement sidecar persistence, or add user-facing editing UI.
- Existing extraction, composition, annotation, OCR, and RAG Dart APIs must remain source-compatible.
- New hot-path FFI uses typed generated DTOs, never JSON strings.
- `ObjectId`, `DocumentId`, `PageId`, `SessionId`, and `CommandId` are opaque UUID values serialized as lowercase hyphenated strings.
- `DocumentRevision` starts at `0`; each accepted mutation increments it exactly once.
- Flutter-facing text offsets are UTF-16 code units; Rust byte offsets never cross the bridge.
- `clarix_editing_core` must not depend on FRB, PDF libraries, SQLite, agent code, or Flutter types.
- Tests follow red-green TDD and each task ends with a focused commit.
- Do not stage or modify the six pre-existing uncommitted workspace PDF files while executing this plan.

## Target File Structure

```text
rust/
├─ Cargo.toml
├─ Cargo.lock
├─ clarix_editing_core/
│  ├─ Cargo.toml
│  ├─ src/{lib,ids,geometry,text,model,command,error,session,actor,tools}.rs
│  └─ tests/{model_contract,command_session,actor_ordering}.rs
├─ clarix_pdf_adapter/
│  ├─ Cargo.toml
│  ├─ src/{lib,contract,qualification,pdf_oxide_importer}.rs
│  ├─ tests/{contract_tests,qualification_tests}.rs
│  └─ benches/page_inspection.rs
├─ clarix_agent_core/
│  ├─ Cargo.toml
│  ├─ src/lib.rs
│  └─ tests/tool_boundary.rs
└─ clarix_pdf_oxide/
   ├─ Cargo.toml
   ├─ src/{lib,api,editing_api}.rs
   └─ tests/{workspace_smoke,editing_bridge}.rs

lib/src/core/editing/{editor_bridge,editor_bridge_types}.dart
test/core/editing/editor_bridge_contract_test.dart
test_fixtures/editing_corpus/{README.md,manifest.json,generated/}
tool/editing_foundation/{record_baseline,run_phase0_checks}.ps1
tool/editing_foundation/{frame_trace_report,raster_diff}.dart
docs/testing/{editing-phase0-corpus.md,editing-phase0-baseline.json,editing-phase0-exit-gate.md}
```

Dependency direction:

```text
clarix_editing_core <- clarix_pdf_adapter
clarix_editing_core <- clarix_agent_core
clarix_editing_core + clarix_pdf_adapter + clarix_agent_core <- clarix_pdf_oxide
```

---

### Task 1: Create the Cargo Workspace Boundaries

**Files:**
- Create: `rust/Cargo.toml`
- Create: `rust/clarix_editing_core/Cargo.toml`
- Create: `rust/clarix_editing_core/src/lib.rs`
- Create: `rust/clarix_pdf_adapter/Cargo.toml`
- Create: `rust/clarix_pdf_adapter/src/lib.rs`
- Create: `rust/clarix_agent_core/Cargo.toml`
- Create: `rust/clarix_agent_core/src/lib.rs`
- Modify: `rust/clarix_pdf_oxide/Cargo.toml`
- Modify: `rust/clarix_pdf_oxide/src/lib.rs`
- Move: `rust/clarix_pdf_oxide/Cargo.lock` to workspace-generated `rust/Cargo.lock`
- Test: `rust/clarix_pdf_oxide/tests/workspace_smoke.rs`

**Interfaces:**
- Consumes: the existing native crate and all existing APIs.
- Produces: four named workspace crates used by every later task.

- [ ] **Step 1: Write the failing workspace smoke test**

```rust
#[test]
fn facade_links_all_phase_zero_crates() {
    assert_eq!(clarix_editing_core::EDITOR_CORE_SCHEMA_VERSION, 1);
    assert_eq!(clarix_pdf_adapter::PDF_ADAPTER_SCHEMA_VERSION, 1);
    assert_eq!(clarix_agent_core::AGENT_CORE_SCHEMA_VERSION, 1);
}
```

- [ ] **Step 2: Verify the test fails because the crates do not exist**

Run:

```powershell
cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml --test workspace_smoke
```

Expected: compilation fails with unresolved crate names.

- [ ] **Step 3: Create `rust/Cargo.toml`**

```toml
[workspace]
resolver = "2"
members = [
  "clarix_editing_core",
  "clarix_pdf_adapter",
  "clarix_agent_core",
  "clarix_pdf_oxide",
]

[workspace.package]
edition = "2021"
license = "LicenseRef-Clarix-Proprietary"

[workspace.dependencies]
crossbeam-channel = "0.5"
flutter_rust_bridge = "=2.12.0"
lopdf = "0.40"
pdf_oxide = "0.3"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
uuid = { version = "1", features = ["v4", "v5", "serde"] }
```

Each new crate uses `edition.workspace = true`, `publish = false`, and exports
the schema constant used by the test. Add all three path dependencies to the
facade without moving existing facade modules.

- [ ] **Step 4: Generate the workspace lockfile and test existing behavior**

```powershell
cargo generate-lockfile --manifest-path rust/Cargo.toml
cargo test --workspace --manifest-path rust/Cargo.toml
```

Expected: all existing and new tests pass; only `rust/Cargo.lock` remains.

- [ ] **Step 5: Inspect dependency direction**

```powershell
cargo tree --workspace --manifest-path rust/Cargo.toml
```

Expected: editing core has no FRB, PDF, adapter, agent, or facade dependency.

- [ ] **Step 6: Commit**

```powershell
git add rust/Cargo.toml rust/Cargo.lock rust/clarix_editing_core rust/clarix_pdf_adapter rust/clarix_agent_core rust/clarix_pdf_oxide/Cargo.toml rust/clarix_pdf_oxide/src/lib.rs rust/clarix_pdf_oxide/tests/workspace_smoke.rs
git commit -m "build: split native editing workspace"
```

---

### Task 2: Define Canonical IDs, Geometry, Text Ranges, and Object Graph

**Files:**
- Create: `rust/clarix_editing_core/src/ids.rs`
- Create: `rust/clarix_editing_core/src/geometry.rs`
- Create: `rust/clarix_editing_core/src/text.rs`
- Create: `rust/clarix_editing_core/src/model.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Test: `rust/clarix_editing_core/tests/model_contract.rs`

**Interfaces:**
- Produces: `DocumentId`, `PageId`, `ObjectId`, `SessionId`, `CommandId`,
  `DocumentRevision`, `PdfBox`, `AffineTransform`, `Utf16Range`, `TextStyle`,
  `TextRun`, `DocumentModel`, `PageNode`, `DocumentObject`, `TextBlock`,
  reserved non-text node types, `SourceBinding`, `EditCapability`, and
  `ObjectKind`.

- [ ] **Step 1: Write failing value and graph tests**

```rust
use clarix_editing_core::{
    AffineTransform, DocumentId, DocumentModel, DocumentObject,
    DocumentRevision, ObjectId, ObjectKind, PageId, PageNode, PdfBox,
    TextBlock, Utf16Range, validate_utf16_range,
};

#[test]
fn ids_revisions_and_utf16_ranges_are_stable() {
    let id = ObjectId::from_source_key("sha256:abc/page:3/object:7");
    assert_eq!(id.to_string().parse::<ObjectId>().unwrap(), id);
    assert_eq!(DocumentRevision::INITIAL.next().value(), 1);
    assert!(Utf16Range::new(5, 4).is_err());
    assert!(validate_utf16_range("A😀B", Utf16Range::new(1, 3).unwrap()).is_ok());
    assert!(validate_utf16_range("A😀B", Utf16Range::new(1, 2).unwrap()).is_err());
}

#[test]
fn document_graph_indexes_stable_objects() {
    let page_id = PageId::from_source_key("doc/page/1");
    let object_id = ObjectId::from_source_key("doc/page/1/text/1");
    let block = TextBlock::plain(
        object_id,
        page_id,
        "Hello",
        PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
    );
    let page = PageNode::new(
        page_id,
        1,
        612.0,
        792.0,
        vec![DocumentObject::Text(block)],
    );
    let model = DocumentModel::new(
        DocumentId::from_source_key("doc"),
        "source-sha256".into(),
        vec![page],
    ).unwrap();
    assert_eq!(model.object(object_id).unwrap().kind(), ObjectKind::Text);
    assert_eq!(AffineTransform::IDENTITY.determinant(), 1.0);
}
```

- [ ] **Step 2: Run and verify missing imports**

```powershell
cargo test -p clarix_editing_core --test model_contract --manifest-path rust/Cargo.toml
```

Expected: compilation fails on the undefined canonical types.

- [ ] **Step 3: Implement opaque values and validation**

Use private `Uuid` newtypes with `Display`, `FromStr`, `Serialize`, and
`Deserialize`. `from_source_key` uses UUID v5 with one fixed Clarix namespace.
`DocumentRevision` is a checked `u64` with `INITIAL`, `value`, and `next`.

`PdfBox::new` rejects non-finite or inverted bounds. `AffineTransform` stores
the six PDF matrix components and validates finiteness. `Utf16Range::new`
rejects reversed bounds. `validate_utf16_range` walks `char::len_utf16()`
boundaries and never treats UTF-16 offsets as Rust byte indices.

- [ ] **Step 4: Implement the object graph boundary**

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EditCapability { Editable, OverlayOnly, ReadOnly }

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ObjectKind { Text, Image, Vector, Annotation, OcrLayer, Group }

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum DocumentObject {
    Text(TextBlock),
    Image(ImageNode),
    Vector(VectorNode),
    Annotation(AnnotationNode),
    OcrLayer(OcrLayer),
    Group(GroupNode),
}
```

All variants expose ID, page ID, kind, bounds, transform, capability, created
revision, and modified revision. Reserved non-text nodes contain typed minimal
metadata and are not editable in Phase 0.

`SourceBinding` stores adapter ID, source revision, opaque source key, and
confidence. `DocumentModel::new` builds private indexes and rejects duplicate
IDs/page numbers, invalid dimensions, missing group children, and cross-page
groups.

- [ ] **Step 5: Add duplicate-ID and JSON round-trip tests**

Assert duplicate object IDs fail construction. Serialize and deserialize a
one-page model and assert UUID strings, revision zero, and no native paths or
handles appear in JSON.

- [ ] **Step 6: Verify**

```powershell
cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml
cargo clippy -p clarix_editing_core --manifest-path rust/Cargo.toml -- -D warnings
```

Expected: pass with no warnings.

- [ ] **Step 7: Commit**

```powershell
git add rust/clarix_editing_core
git commit -m "feat: define canonical editing model"
```

---

### Task 3: Implement Commands, Revisions, Undo, and the Single-Writer Actor

**Files:**
- Create: `rust/clarix_editing_core/src/error.rs`
- Create: `rust/clarix_editing_core/src/command.rs`
- Create: `rust/clarix_editing_core/src/session.rs`
- Create: `rust/clarix_editing_core/src/actor.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Test: `rust/clarix_editing_core/tests/command_session.rs`
- Test: `rust/clarix_editing_core/tests/actor_ordering.rs`

**Interfaces:**
- Produces: `ActorKind`, `CommandEnvelope`, `EditorCommand`, `CommandResult`,
  `ObjectPatch`, `EditingError`, `EditorSessionState`, `EditorSessionActor`, and
  `EditorEvent`.

- [ ] **Step 1: Write failing session tests**

```rust
#[test]
fn replacement_commits_once_and_stale_commands_do_not_mutate() {
    let (model, object_id) = sample_model("Hello world");
    let mut session = EditorSessionState::new(SessionId::new(), model);
    let command = CommandEnvelope::user(
        CommandId::new(),
        DocumentRevision::INITIAL,
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(6, 11).unwrap(),
            replacement: "Rust".into(),
        },
    );
    let result = session.submit(command).unwrap();
    assert_eq!(result.committed_revision.value(), 1);
    assert_eq!(result.object_patches.len(), 1);
    assert_eq!(session.text(object_id).unwrap(), "Hello Rust");

    let stale = CommandEnvelope::user(
        CommandId::new(),
        DocumentRevision::INITIAL,
        EditorCommand::CreateCheckpoint { label: "stale".into() },
    );
    assert_eq!(session.submit(stale).unwrap_err().code(), "revision_conflict");
    assert_eq!(session.revision().value(), 1);
}
```

Add another test replacing the emoji in `A😀B`, then undoing and redoing. Assert
texts and revisions `0 -> 1 -> 2 -> 3`.

- [ ] **Step 2: Run and verify missing command/session types**

```powershell
cargo test -p clarix_editing_core --test command_session --manifest-path rust/Cargo.toml
```

Expected: unresolved imports.

- [ ] **Step 3: Implement typed commands and stable failures**

```rust
pub enum EditorCommand {
    ReplaceTextRange { object_id: ObjectId, range: Utf16Range, replacement: String },
    SetTextStyle { object_id: ObjectId, range: Utf16Range, style: TextStyle },
    MoveObject { object_id: ObjectId, transform: AffineTransform },
    ResizeObject { object_id: ObjectId, bounds: PdfBox },
    RotateObject { object_id: ObjectId, radians: f64, center_x: f64, center_y: f64 },
    CreateCheckpoint { label: String },
    Undo,
    Redo,
}
```

`CommandEnvelope` includes command ID, base revision, optional transaction ID,
actor, provenance IDs, and payload. `EditingError` uses `thiserror` and exposes
stable codes including `revision_conflict`, `duplicate_command`,
`invalid_text_boundary`, `wrong_object_kind`, `read_only`, and `session_closed`.

`ObjectPatch` contains only changed fields, object/page IDs, and new modified
revision. It must not contain a page or document snapshot.

- [ ] **Step 4: Implement atomic deterministic submission**

Validate revision, command ID, object kind/capability, and UTF-16 boundaries
before changing state. Store the inverse command, clear redo after new edits,
and advance the revision once only after success. Failed commands change no
model, history, ID set, or revision.

- [ ] **Step 5: Write failing actor tests**

```rust
#[test]
fn actor_emits_commits_in_revision_order_and_closes_cleanly() {
    let (model, object_id) = sample_model("A");
    let actor = EditorSessionActor::spawn(model);
    let events = actor.subscribe().unwrap();
    assert!(matches!(events.recv().unwrap(), EditorEvent::Ready { revision } if revision.value() == 0));
    assert_eq!(actor.submit(replace(object_id, 0, "AB")).unwrap().committed_revision.value(), 1);
    assert_eq!(actor.submit(replace(object_id, 1, "ABC")).unwrap().committed_revision.value(), 2);
    actor.close().unwrap();
    assert_eq!(actor.snapshot().unwrap_err().code(), "session_closed");
}
```

- [ ] **Step 6: Implement the bounded actor**

Use `crossbeam_channel` and a private request enum. The worker owns
`EditorSessionState`; no caller obtains a mutable model reference. Request and
subscriber channels are bounded. Slow subscribers cannot block commits or grow
memory; they receive `EditorEvent::Lagged { latest_revision }` after capacity
returns. Close is idempotent and joins the worker.

- [ ] **Step 7: Stress ordering and backpressure**

Add eight caller threads and assert unique increasing revisions. Add a capacity
two subscriber, submit ten commands, and assert the actor completes. Run:

```powershell
1..20 | ForEach-Object { cargo test -p clarix_editing_core --test actor_ordering --manifest-path rust/Cargo.toml --quiet; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
```

Expected: twenty passing runs without a hang.

- [ ] **Step 8: Commit**

```powershell
git add rust/clarix_editing_core
git commit -m "feat: add revisioned editor session actor"
```

---

### Task 4: Enforce the Agent Tool Boundary

**Files:**
- Create: `rust/clarix_editing_core/src/tools.rs`
- Modify: `rust/clarix_editing_core/src/lib.rs`
- Modify: `rust/clarix_agent_core/Cargo.toml`
- Modify: `rust/clarix_agent_core/src/lib.rs`
- Test: `rust/clarix_agent_core/tests/tool_boundary.rs`

**Interfaces:**
- Produces: `EditingToolGateway`, `ToolRequest`, `ToolObservation`, `ToolRisk`,
  and `AgentRunBoundary<G>`.

- [ ] **Step 1: Write a failing boundary test**

```rust
#[test]
fn agent_can_only_observe_or_submit_typed_tools() {
    let gateway = RecordingGateway::new(DocumentRevision::INITIAL);
    let boundary = AgentRunBoundary::new(gateway);
    let observation = boundary.invoke(ToolRequest::InspectDocument {
        revision: DocumentRevision::INITIAL,
    }).unwrap();
    assert_eq!(observation.revision(), DocumentRevision::INITIAL);
}
```

The test-local `RecordingGateway` implements the public trait and records typed
requests. It never constructs a `DocumentModel`.

- [ ] **Step 2: Run and verify missing gateway types**

```powershell
cargo test -p clarix_agent_core --test tool_boundary --manifest-path rust/Cargo.toml
```

Expected: unresolved imports.

- [ ] **Step 3: Implement the restricted gateway**

```rust
pub trait EditingToolGateway: Send + Sync + 'static {
    fn invoke(&self, request: ToolRequest) -> Result<ToolObservation, EditingError>;
}

pub enum ToolRequest {
    InspectDocument { revision: DocumentRevision },
    InspectObject { revision: DocumentRevision, object_id: ObjectId },
    SubmitCommand(CommandEnvelope),
}
```

Observations expose revision, typed summaries, or a command result. They do not
expose `EditorSessionState`, `DocumentModel`, native handles, or callbacks.
`AgentRunBoundary` delegates only through `invoke`. Do not add an LLM provider,
conversation loop, or permission model in Phase 0.

- [ ] **Step 4: Verify dependency direction and tests**

```powershell
cargo tree -p clarix_agent_core --manifest-path rust/Cargo.toml
cargo test -p clarix_agent_core -p clarix_editing_core --manifest-path rust/Cargo.toml
```

Expected: agent depends on editing core; editing core does not depend on agent.

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_editing_core rust/clarix_agent_core
git commit -m "feat: isolate agent editing tool boundary"
```

---

### Task 5: Define PDF Adapter Contracts and the Qualification Corpus

**Files:**
- Create: `rust/clarix_pdf_adapter/src/contract.rs`
- Create: `rust/clarix_pdf_adapter/src/qualification.rs`
- Modify: `rust/clarix_pdf_adapter/src/lib.rs`
- Test: `rust/clarix_pdf_adapter/tests/contract_tests.rs`
- Create: `test_fixtures/editing_corpus/README.md`
- Create: `test_fixtures/editing_corpus/manifest.json`
- Create: `test_fixtures/editing_corpus/generated/.gitkeep`
- Modify: `.gitignore`
- Create: `docs/testing/editing-phase0-corpus.md`

**Interfaces:**
- Produces: `PdfImporter`, `PdfPreviewRenderer`, `PdfMaterializer`,
  `PdfValidator`, `SourceRef`, `PageImport`, `CleanPatchRequest`, `RasterAsset`,
  `SaveReport`, `SaveExpectation`, `ValidationReport`, `CapabilityStatus`, and
  `QualificationCaseResult`.

- [ ] **Step 1: Write failing fake-adapter tests**

```rust
#[test]
fn capabilities_report_each_operation_independently() {
    let report = CapabilityReport::new("fake/1")
        .with_import(CapabilityStatus::Supported)
        .with_clean_patch(CapabilityStatus::Unsupported("not implemented".into()))
        .with_materialization(CapabilityStatus::Unsupported("not implemented".into()))
        .with_validation(CapabilityStatus::Supported);
    assert!(report.import.is_supported());
    assert!(!report.materialization.is_supported());
}

#[test]
fn importer_returns_stable_objects_without_native_handles() {
    let importer = FakeImporter::one_text_page("Hello");
    let source = SourceRef::new("hash", "fixture.pdf");
    assert_eq!(
        importer.inspect_page(&source, 1).unwrap().page,
        importer.inspect_page(&source, 1).unwrap().page,
    );
}
```

- [ ] **Step 2: Run and verify missing contracts**

```powershell
cargo test -p clarix_pdf_adapter --test contract_tests --manifest-path rust/Cargo.toml
```

Expected: unresolved imports.

- [ ] **Step 3: Implement object-safe traits**

```rust
pub trait PdfImporter: Send + Sync {
    fn adapter_id(&self) -> &'static str;
    fn inspect_document(&self, source: &SourceRef) -> Result<DocumentImport, PdfAdapterError>;
    fn inspect_page(&self, source: &SourceRef, page_number: u32) -> Result<PageImport, PdfAdapterError>;
}

pub trait PdfPreviewRenderer: Send + Sync {
    fn render_clean_patch(&self, request: CleanPatchRequest) -> Result<RasterAsset, PdfAdapterError>;
}

pub trait PdfMaterializer: Send + Sync {
    fn materialize(&self, snapshot: &DocumentSnapshot, target: &Path) -> Result<SaveReport, PdfAdapterError>;
}

pub trait PdfValidator: Send + Sync {
    fn validate(&self, output: &Path, expectation: &SaveExpectation) -> Result<ValidationReport, PdfAdapterError>;
}
```

Unsupported Phase 0 operations report explicit capability status and never
return fake successful data. Qualification results contain case ID, source
SHA-256, adapter ID, duration, object counts, capabilities, warnings, and stable
error code, but no extracted document text.

- [ ] **Step 4: Create the licensed corpus manifest**

```json
{
  "schemaVersion": 1,
  "cases": [
    {"id":"standard-latin","path":"generated/standard-latin.pdf","license":"generated-by-clarix-tests","expectedPages":1,"requiredKinds":["text"]},
    {"id":"rotated-text","path":"generated/rotated-text.pdf","license":"generated-by-clarix-tests","expectedPages":1,"requiredKinds":["text"]},
    {"id":"multi-run-text","path":"generated/multi-run-text.pdf","license":"generated-by-clarix-tests","expectedPages":1,"requiredKinds":["text"]},
    {"id":"mixed-page","path":"generated/mixed-page.pdf","license":"generated-by-clarix-tests","expectedPages":1,"requiredKinds":["text","image","vector"]},
    {"id":"form-xobject","path":"generated/form-xobject.pdf","license":"generated-by-clarix-tests","expectedPages":1,"requiredKinds":["form"]},
    {"id":"scanned-page","path":"generated/scanned-page.pdf","license":"generated-by-clarix-tests","expectedPages":1,"requiredKinds":["image"]},
    {"id":"embedded-truetype","path":"local/embedded-truetype.pdf","license":"user-supplied-private-corpus","expectedPages":1,"requiredKinds":["text"],"requiredForExit":true},
    {"id":"subset-font","path":"local/subset-font.pdf","license":"user-supplied-private-corpus","expectedPages":1,"requiredKinds":["text"],"requiredForExit":true},
    {"id":"malformed-input","path":"generated/malformed.pdf","license":"generated-by-clarix-tests","expectedError":"invalid_pdf"}
  ]
}
```

The README forbids customer PDFs, unlicensed copyrighted files, secrets, or
document text in committed reports. An ignored `local/` directory holds private
licensed cases. The Phase 0 exit gate requires the two private font cases to be
present on the qualification machine; reports commit only their hashes,
capability results, and timings, never their bytes or extracted text.
Add `/test_fixtures/editing_corpus/local/` to `.gitignore`.

- [ ] **Step 5: Verify**

```powershell
cargo test -p clarix_pdf_adapter --manifest-path rust/Cargo.toml
cargo clippy -p clarix_pdf_adapter --manifest-path rust/Cargo.toml -- -D warnings
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add .gitignore rust/clarix_pdf_adapter test_fixtures/editing_corpus docs/testing/editing-phase0-corpus.md
git commit -m "feat: define PDF adapter qualification contract"
```

---

### Task 6: Implement Deterministic Read-Only PDF Oxide Inspection

**Files:**
- Create: `rust/clarix_pdf_adapter/src/pdf_oxide_importer.rs`
- Modify: `rust/clarix_pdf_adapter/src/lib.rs`
- Modify: `rust/clarix_pdf_adapter/Cargo.toml`
- Create: `rust/clarix_pdf_adapter/tests/qualification_tests.rs`
- Create: `rust/clarix_pdf_adapter/examples/generate_corpus.rs`
- Modify: `test_fixtures/editing_corpus/manifest.json`

**Interfaces:**
- Consumes: canonical graph, adapter contract, `pdf_oxide`, and `lopdf`.
- Produces: `PdfOxideImporter` and repository-owned generated PDF fixtures.

- [ ] **Step 1: Write the failing deterministic-import test**

```rust
#[test]
fn pdf_oxide_import_is_deterministic_and_read_only() {
    let fixture = generated_standard_latin_pdf();
    let source = SourceRef::from_path(&fixture).unwrap();
    let importer = PdfOxideImporter::default();
    let first = importer.inspect_page(&source, 1).unwrap();
    let second = importer.inspect_page(&source, 1).unwrap();
    assert_eq!(first.page, second.page);
    assert_eq!(first.report.import, CapabilityStatus::Supported);
    assert!(matches!(first.report.materialization, CapabilityStatus::Unsupported(_)));
}
```

Add malformed-input and out-of-range page tests with stable error codes.

- [ ] **Step 2: Run and verify the importer is absent**

```powershell
cargo test -p clarix_pdf_adapter --test qualification_tests --manifest-path rust/Cargo.toml
```

Expected: unresolved `PdfOxideImporter`.

- [ ] **Step 3: Implement read-only inspection**

Verify source SHA-256, inspect document/page metadata, extract available text
and bounds, and map results into canonical text objects. Derive deterministic
source keys from source fingerprint, page number, normalized geometry, and text
fingerprints. Never expose `pdf_oxide` types publicly and never claim font,
vector, image, clean-patch, materialization, or validation fidelity that was not
inspected.

- [ ] **Step 4: Generate repository-owned fixtures**

Use `lopdf` in `generate_corpus.rs` to produce standard Latin, rotated text,
multiple text runs, mixed text/image/vector, form XObject, and scanned-image
files; write invalid bytes for malformed input. The example accepts an optional
`--private-font-path` and, when supplied, creates full-embedded and subset-font
cases under the ignored `local/` directory without copying the font into Git.
Run:

```powershell
cargo run -p clarix_pdf_adapter --example generate_corpus --manifest-path rust/Cargo.toml -- test_fixtures/editing_corpus/generated
cargo run -p clarix_pdf_adapter --example generate_corpus --manifest-path rust/Cargo.toml -- test_fixtures/editing_corpus/generated --private-font-path C:\Windows\Fonts\arial.ttf --private-output test_fixtures/editing_corpus/local
```

Record each repository-generated SHA-256 in the manifest. Record private hashes
only in the local qualification result consumed by the exit gate.

- [ ] **Step 5: Run qualification twice**

```powershell
cargo test -p clarix_pdf_adapter --test qualification_tests --manifest-path rust/Cargo.toml
cargo test -p clarix_pdf_adapter --test qualification_tests --manifest-path rust/Cargo.toml
```

Expected: identical stable IDs, object counts, capabilities, and error codes.

- [ ] **Step 6: Commit**

```powershell
git add rust/clarix_pdf_adapter test_fixtures/editing_corpus
git commit -m "test: qualify read-only PDF import"
```

---

### Task 7: Expose the Typed Editor Session through FRB

**Files:**
- Create: `rust/clarix_pdf_oxide/src/editing_api.rs`
- Modify: `rust/clarix_pdf_oxide/src/lib.rs`
- Modify: `rust/clarix_pdf_oxide/Cargo.toml`
- Test: `rust/clarix_pdf_oxide/tests/editing_bridge.rs`
- Regenerate: `rust/clarix_pdf_oxide/src/frb_generated.rs`
- Regenerate: `lib/src/core/ffi/api.dart`
- Regenerate: `lib/src/core/ffi/frb_generated.dart`
- Regenerate: `lib/src/core/ffi/frb_generated.io.dart`
- Regenerate: `lib/src/core/ffi/frb_generated.web.dart`
- Regenerate: `lib/src/core/ffi/lib.dart`

**Interfaces:**
- Produces: opaque `NativeEditorSession`, typed request/result/event DTOs, and
  `open`, `metadata`, `page_scene`, `submit`, `events`, and `close` methods.

- [ ] **Step 1: Write a failing facade test**

```rust
#[test]
fn native_editor_session_opens_at_revision_zero_and_closes() {
    let fixture = generated_standard_latin_pdf();
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture.to_string_lossy().into_owned(),
    }).unwrap();
    let metadata = session.metadata().unwrap();
    assert_eq!(metadata.schema_version, 1);
    assert_eq!(metadata.revision, 0);
    assert_eq!(metadata.page_count, 1);
    session.close().unwrap();
}
```

- [ ] **Step 2: Run and verify missing session DTOs**

```powershell
cargo test -p clarix_pdf_oxide --test editing_bridge --manifest-path rust/Cargo.toml
```

Expected: unresolved native editor types.

- [ ] **Step 3: Implement the typed facade**

```rust
pub struct NativeOpenEditorRequest { pub source_path: String }

pub struct NativeEditorMetadata {
    pub schema_version: u32,
    pub session_id: String,
    pub document_id: String,
    pub source_fingerprint: String,
    pub revision: u64,
    pub page_count: u32,
}

pub struct NativePageSceneRequest {
    pub page_number: u32,
    pub expected_revision: u64,
}

pub struct NativeSubmitCommandRequest {
    pub schema_version: u32,
    pub command_id: String,
    pub base_revision: u64,
    pub payload: NativeEditorCommand,
}
```

Use a typed `NativeEditorCommand` enum and `StreamSink<NativeEditorEvent>`, not
JSON. Conversion functions validate UUIDs, schema version, and checked numeric
conversions. The opaque session owns the actor and importer. Opening inspects
metadata; pages import on request. Submission remains in memory and has no UI.

- [ ] **Step 4: Add stale-revision and close tests**

Submit a replacement, assert revision one and one patch, reject base revision
zero, close, and assert every later method returns `session_closed`.

- [ ] **Step 5: Regenerate bindings and verify compatibility**

```powershell
flutter_rust_bridge_codegen generate
cargo test -p clarix_pdf_oxide --test editing_bridge --manifest-path rust/Cargo.toml
dart format --output=none --set-exit-if-changed lib/src/core/ffi
flutter analyze lib/src/core/ffi lib/src/core/clarix_rust_runtime.dart
```

Expected: typed editor APIs appear and all existing generated APIs remain.

- [ ] **Step 6: Commit**

```powershell
git add rust/clarix_pdf_oxide lib/src/core/ffi
git commit -m "feat: expose native editor session bridge"
```

---

### Task 8: Add the Handwritten Dart Lifecycle Adapter

**Files:**
- Create: `lib/src/core/editing/editor_bridge_types.dart`
- Create: `lib/src/core/editing/editor_bridge.dart`
- Create: `test/core/editing/editor_bridge_contract_test.dart`
- Modify: `lib/src/core/clarix_rust_runtime.dart`

**Interfaces:**
- Produces: `EditorBridge`, `EditorBridgeSession`, `EditorSessionMetadata`,
  `EditorPageScene`, `EditorCommandRequest`, and `EditorEvent`.

- [ ] **Step 1: Write a failing lifecycle test**

```dart
test('editor bridge rejects requests and events after close', () async {
  final native = FakeNativeEditorPort();
  final session = EditorBridgeSession.forTest(native);
  final events = <EditorEvent>[];
  final subscription = session.events.listen(events.add);
  native.emit(const EditorEvent.ready(sequence: 1, revision: 0));
  await session.close();
  native.emit(const EditorEvent.commandCommitted(
    sequence: 2,
    revision: 1,
    commandId: 'late',
  ));
  await expectLater(session.metadata(), throwsA(isA<EditorSessionClosed>()));
  expect(events, <EditorEvent>[const EditorEvent.ready(sequence: 1, revision: 0)]);
  await subscription.cancel();
});
```

The production generated types stay behind `NativeEditorPort`; tests use a
private fake and do not load the DLL.

- [ ] **Step 2: Run and verify missing Dart boundary**

```powershell
flutter test test/core/editing/editor_bridge_contract_test.dart
```

Expected: missing imports.

- [ ] **Step 3: Implement immutable values and lifecycle**

Convert generated `BigInt`, UUID strings, and enums at one boundary. Own one
broadcast event controller, reject duplicate or decreasing sequence numbers,
cancel native subscription before close, make close idempotent, and reject late
operations locally. Reject schema versions other than one with
`EditorProtocolViolation`.

Do not add Riverpod, workspace widgets, PDF viewer code, or editing UI.

- [ ] **Step 4: Test malformed protocol and ordering**

Add tests for schema version two, event sequence `2` followed by `1`, duplicate
sequence `2`, and a second close call. Expected: typed local failures, no leaked
stream, and exactly one native close.

- [ ] **Step 5: Verify**

```powershell
flutter test test/core/editing/editor_bridge_contract_test.dart
flutter analyze lib/src/core/editing test/core/editing lib/src/core/clarix_rust_runtime.dart
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/core/editing lib/src/core/clarix_rust_runtime.dart test/core/editing
git commit -m "feat: add Flutter editor bridge boundary"
```

---

### Task 9: Establish Reproducible Benchmarks and the Phase 0 Gate

**Files:**
- Create: `rust/clarix_editing_core/benches/command_latency.rs`
- Create: `rust/clarix_pdf_adapter/benches/page_inspection.rs`
- Modify: `rust/clarix_editing_core/Cargo.toml`
- Modify: `rust/clarix_pdf_adapter/Cargo.toml`
- Create: `rust/clarix_editing_core/tests/architecture_fitness.rs`
- Create: `rust/clarix_editing_core/examples/memory_probe.rs`
- Create: `tool/editing_foundation/record_baseline.ps1`
- Create: `tool/editing_foundation/run_phase0_checks.ps1`
- Create: `tool/editing_foundation/frame_trace_report.dart`
- Create: `tool/editing_foundation/raster_diff.dart`
- Create: `test/core/editing/frame_trace_report_test.dart`
- Create: `test/core/editing/raster_diff_test.dart`
- Create: `docs/testing/editing-phase0-baseline.json`
- Create: `docs/testing/editing-phase0-exit-gate.md`
- Modify: `rust/clarix_pdf_oxide/README.md`

**Interfaces:**
- Produces: Criterion groups `command_latency`, `actor_round_trip`,
  `stable_id_derivation`, and `page_inspection`; `memory_probe` JSON; Flutter
  timeline and raster comparison reports; baseline schema version one; one
  full-gate PowerShell command.

- [ ] **Step 1: Add functional benchmark smoke tests**

Write ignored tests that execute 1,000 replace/undo pairs and inspect every
generated corpus page. Assert final text/revision and bounded object counts.
Run:

```powershell
cargo test -p clarix_editing_core -p clarix_pdf_adapter --manifest-path rust/Cargo.toml -- --ignored
```

Expected: pass before timing is introduced.

- [ ] **Step 2: Implement Criterion benchmarks**

Add `criterion = { version = "0.5", features = ["html_reports"] }` as a dev
dependency. Measure warm direct submit, actor round trip, 10,000 stable-ID
derivations, and inspection of each valid generated fixture. Use `black_box` and
reset mutable state outside timed closures. Do not hard-code product latency
assertions because machines differ.

- [ ] **Step 3: Write architecture fitness tests**

Use `cargo metadata --format-version 1` and assert:

- editing core has no FRB, PDF, adapter, agent, or facade dependency;
- agent core depends on editing core but not adapter/facade;
- only the facade has crate type `cdylib`.

- [ ] **Step 4: Write failing frame-trace and raster-diff tests**

`frame_trace_report_test.dart` supplies a literal timeline containing build and
raster durations of 8,000, 12,000, and 20,000 microseconds. Assert p95, maximum,
and over-budget frame count. `raster_diff_test.dart` creates two 2x2 RGBA PNGs
with one changed pixel and asserts changed-pixel count `1`, ratio `0.25`, and
maximum channel delta from the literal pixels.

Run:

```powershell
flutter test test/core/editing/frame_trace_report_test.dart test/core/editing/raster_diff_test.dart
```

Expected: fail because both report tools are absent.

- [ ] **Step 5: Implement performance utility contracts**

`frame_trace_report.dart --input <timeline.json> --output <report.json>` parses
Flutter timeline frame events and writes count, p50, p95, p99, max, and frames
over 16,667 microseconds. `raster_diff.dart --expected <png> --actual <png>
--output <report.json>` writes dimensions, changed pixels, changed ratio, mean
absolute channel delta, and maximum channel delta. Both reject mismatched schema
or image dimensions with nonzero exit status.

`memory_probe.rs --iterations 100 --output <path>` repeatedly imports the full
generated corpus, releases each page result, samples the Windows process working
set through `sysinfo`, and writes warm-up bytes, peak bytes, final bytes, and the
linear slope over the last 50 iterations. The baseline records the values; the
Phase 0 report establishes the initial ceiling rather than hard-coding an
unmeasured number.

- [ ] **Step 6: Implement baseline recording**

`record_baseline.ps1 -OutputPath <path>` records this exact schema:

```json
{
  "schemaVersion": 1,
  "capturedAtUtc": "ISO-8601",
  "gitCommit": "40-hex commit",
  "os": "Windows",
  "cpu": "processor name",
  "logicalProcessors": 0,
  "memoryBytes": 0,
  "rustc": "rustc version",
  "cargoProfile": "bench",
  "corpusManifestSha256": "hex",
  "memoryProbe": {"warmupBytes":0,"peakBytes":0,"finalBytes":0,"tailSlopeBytesPerIteration":0},
  "metricCatalog": {
    "flutterFrameTime": "harness_ready_no_phase1_overlay",
    "commandLatency": "measured",
    "pageInspectionLatency": "measured",
    "memoryPlateau": "measured",
    "rasterDifference": "harness_ready_no_materializer",
    "sidecarLatency": "owned_by_sidecar_plan",
    "saveLatency": "owned_by_save_plan"
  },
  "commands": []
}
```

It runs ignored smoke tests, the memory probe, and `cargo bench --workspace
--no-run`, recording commands and exit codes. Raw Criterion output remains under
`target/`. Harness-ready metrics are explicit states, not invented measurements;
the later overlay, sidecar, and save plans must change them to `measured`.

- [ ] **Step 7: Implement the full quality gate**

`run_phase0_checks.ps1` stops on first failure and runs:

```powershell
cargo fmt --all --manifest-path rust/Cargo.toml --check
cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings
cargo test --workspace --manifest-path rust/Cargo.toml
flutter_rust_bridge_codegen generate
git diff --exit-code -- rust/clarix_pdf_oxide/src/frb_generated.rs lib/src/core/ffi
flutter test test/core/editing/editor_bridge_contract_test.dart
flutter test test/core/editing/frame_trace_report_test.dart test/core/editing/raster_diff_test.dart
flutter analyze lib/src/core/editing lib/src/core/ffi test/core/editing
cargo bench --workspace --manifest-path rust/Cargo.toml --no-run
cargo build --release -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --target x86_64-pc-windows-msvc
```

- [ ] **Step 8: Record and run the gate**

```powershell
& tool/editing_foundation/record_baseline.ps1 -OutputPath docs/testing/editing-phase0-baseline.json
& tool/editing_foundation/run_phase0_checks.ps1
```

Expected: exit zero, no generated-binding diff, and release DLL at
`rust/target/x86_64-pc-windows-msvc/release/clarix_pdf_oxide.dll`.

- [ ] **Step 9: Record exit evidence**

`editing-phase0-exit-gate.md` records commit, command summaries, corpus hash,
baseline path, measured memory ceiling, adapter capability table for every
generated and private-font case, read-only limitations, and evidence that
open/close/events work, IDs contain no handles, and no user-facing editor,
sidecar, or Save behavior was added. It also records the Phase 0 adapter
recommendation—accepted, accepted with named gaps, or rejected—and the exact
evidence behind that decision.

- [ ] **Step 10: Commit**

```powershell
git add rust/clarix_editing_core rust/clarix_pdf_adapter tool/editing_foundation test/core/editing docs/testing/editing-phase0-baseline.json docs/testing/editing-phase0-exit-gate.md rust/clarix_pdf_oxide/README.md
git commit -m "test: enforce Phase 0 editing foundation gate"
```

## Phase 0 Completion Checklist

- [ ] Four approved crates build through one DLL facade.
- [ ] Existing native APIs and tests still pass.
- [ ] Canonical values and graph contain no native handles.
- [ ] Commands are deterministic, revision-checked, idempotency-checked, and invertible.
- [ ] One bounded Rust actor is the only session writer.
- [ ] Slow subscribers cannot block commits or grow memory without limit.
- [ ] Agent core reaches editing only through `EditingToolGateway`.
- [ ] Unsupported PDF adapter operations cannot report success.
- [ ] Corpus licensing rules and generated fixtures are committed.
- [ ] Read-only PDF inspection produces deterministic stable IDs.
- [ ] Typed FRB session/event APIs are generated and tested.
- [ ] Dart bridge rejects protocol mismatches and late events.
- [ ] Benchmarks and Windows metadata are reproducible.
- [ ] Full Phase 0 gate and release DLL build pass.
- [ ] Exit-gate evidence exists before sidecar or Phase 1 work begins.

## Explicitly Deferred

- SQLite sidecar, command durability, crash replay, and migrations.
- PDF materialization, validation, backup, `ReplaceFileW`, Ctrl+S, and Save As.
- Clean background patches and Flutter retained page scenes.
- Flutter caret, IME, format panels, and user-facing editing.
- Search/replace-all, OCR execution, and OCR editing.
- LLM providers, conversations, autonomous loops, and permissions UI.
- Image, vector, shape, group, annotation, and generated-asset editing.

These require the subsequent specifications listed in the master architecture.
Phase 0 is complete only when this foundation is small, stable, measured, and
independent of the current per-keystroke PDF mutation path.
