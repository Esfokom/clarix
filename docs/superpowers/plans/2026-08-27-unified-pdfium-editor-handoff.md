# Unified PDFium editor migration handoff

Last updated: 2026-08-27

This note accompanies [the migration plan](2026-08-27-unified-pdfium-editor-migration.md)
and [the design](../specs/2026-08-27-unified-pdfium-editor-design.md). It is a
safe restart point for work in this or another thread.

## Current result

The repository has a working live-PDFium foundation. A Dart-owned
`LivePdfiumSession` mutates one in-memory PDFium document, regenerates the
affected page before its native page handle closes, rerenders dirty tiles from
that same document, and can encode the resulting PDF bytes. Flutter paints
those live tiles in edit scenes instead of duplicating edited glyphs with
Flutter text overlays.

Rust remains the semantic authority. For supported text replacements it now
prepares a `PhysicalEditPlan` containing both forward and inverse operations.
The bridge has a two-phase protocol:

1. Rust validates and prepares a command without publishing a revision.
2. Dart applies the physical PDFium plan to the live document.
3. Dart publishes the prepared token only after successful application.

This ordering is mandatory. Never publish a semantic revision before PDFium
has applied and regenerated its matching physical operation.

The gateway now owns a `LivePdfiumSession` and `LivePdfiumLocatorRegistry`
for each open editor tab. It can route a whole-text replacement through
prepare -> apply -> publish when a canonical import manifest supplies a
registered semantic object binding. Unbound objects remain on the legacy
semantic/materializer path. The live session also rejects a physical plan
prepared for a different revision.

## Completed commits

The most relevant commits, newest first:

- `7cf9a7f` / `797b759` — canonical live-import manifest builder and
  single-object projection coverage. Manifest identities use only the source
  fingerprint and recursive PDFium object path, with Rust-compatible UUIDv5
  IDs; text, geometry, and object order are not inputs.
- `c6c41e6` — live session exposes PDFium-owned text inspection for the
  forthcoming Dart-owned page importer.
- `cc5da01` — validates import-manifest/source-fingerprint consistency and
  cleans up both owners when opening fails.
- `997c17b` — routes explicitly bound text edits through live PDFium while
  retaining the legacy route for unbound objects.
- `74c7dbb` — live physical-plan revision guard.
- `55596b6` / `e619d4e` — semantic binding retention plus per-tab live
  session and registry lifecycle.

- `3148c15` — regression coverage for revision-checked live locator bindings.
- `0d7a69f` — `LivePdfiumLocatorRegistry` rejects stale physical bindings.
- `6abb79b` — `LivePdfiumEditorPort` composes prepare, live apply, and publish.
- `cca9b23` — FRB/Dart contract for prepared live commands and physical plans.
- `3f65c8a` — editing-core actor supports prepare/publish.
- `0e512be` / `03383da` — semantic text replacement emits forward/inverse
  physical plans.
- `2196c2a`, `e71f669`, `e2f22ce` — stale-plan rejection, rollback safety,
  and clean-patch suppression for live pages.
- `13827e2`, `0df3191` — live-tile presentation and visible-page retention.
- `ddfe923`, `96f1c50`, `29f6738`, `037d3ea`, `0c5a2d0`, `65f7cfa` — live
  session, same-page batching, regeneration, rendering, and tile-cache base.

## Key implementation locations

| Concern | Location |
| --- | --- |
| Live PDFium owner/mutation/save | `lib/src/features/pdf_editor/infrastructure/live_pdfium_session.dart` |
| Physical PDFium plan types | `lib/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart` |
| Live tile renderer | `lib/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart` |
| Semantic two-phase actor | `rust/clarix_editing_core/src/actor.rs` and `session.rs` |
| FRB native prepare/publish | `rust/clarix_pdf_oxide/src/editing_api.rs` |
| Dart bridge conversion | `lib/src/core/editing/editor_bridge.dart`, `frb_native_editor_port.dart` |
| Live composition and registry | `lib/src/core/editing/live_pdfium_editor_port.dart` |
| Current production gateway | `lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart` |

## What is not yet wired

The production `BridgeEditorSessionGateway` can select
`LivePdfiumEditorPort`, but only after a validated canonical manifest registers
the command target. Its default manifest is intentionally empty. The Rust
legacy importer still creates semantic objects from span-derived source keys,
whereas the live PDFium inspector creates path-based source keys. Those are
not the same identity domain; do not correlate them by coordinates, text, or
object order.

The next implementation slice is therefore:

1. Add a Dart -> Rust live-page import DTO/API. It must carry a page's
   path-based source keys, Rust-compatible UUIDv5 object IDs, text/layout
   metadata, and recursive PDFium locators from one `LivePdfiumSession` scan.
2. Change the semantic session to hydrate live-backed `PageNode`s from that
   DTO instead of calling the span-based `PdfOxideImporter` for those pages.
3. Have `BridgeEditorSessionGateway.requestPage()` inspect the visible page,
   submit its live import, register the resulting manifest, then request the
   semantic scene. Index visible and adjacent pages only.
4. Verify a supported replacement takes prepare -> apply -> publish and emits
   live-tile invalidations; retain legacy routing only for explicitly
   unsupported or unimported objects.
5. Connect successful invalidations to `PageSceneLifecycle`.

## Remaining plan work

After production routing, continue the plan in this order:

1. Migrate Save/Save As to encode the live PDFium owner through the existing
   atomic recovery flow.
2. Apply physical inverse/forward plans for undo/redo before semantic
   publication.
3. Extend the physical plan vocabulary beyond whole text replacement:
   formatting, transforms, partial runs, reflow, font fallback, Form XObjects,
   images, and vectors.
4. Complete capability classification/fallback and run the plan's integration,
   save/reopen, performance, and recovery gates.

## Verified evidence

Focused checks run successfully during this migration include:

```text
cargo test --manifest-path rust/Cargo.toml -p clarix_editing_core
cargo test --manifest-path rust/Cargo.toml -p clarix_pdf_oxide live_command_prepares_a_physical_plan_before_it_is_published -- --exact
flutter test --no-pub test/pdf_editor/domain_infrastructure/live_pdfium_session_test.dart
flutter test --no-pub test/pdf_editor/domain_infrastructure/editor_session_gateway_live_pdfium_test.dart
flutter test --no-pub test/core/editing/editor_bridge_contract_test.dart
flutter test --no-pub test/core/editing/live_pdfium_locator_registry_test.dart
dart analyze lib/src/core/editing/live_pdfium_editor_port.dart lib/src/features/pdf_editor/infrastructure/editor_session_gateway.dart
```

Do not claim the full migration complete from these focused tests. The Dart ->
Rust live-page import, end-to-end production live routing,
`PageSceneLifecycle` invalidations, Save/undo/redo integration, and broad PDF
compatibility remain unverified.

## Safety and continuation instructions

- Work inline on `main`; do not create a worktree unless the user changes that
  instruction.
- The user permits `cargo test` but does not want `cargo build`.
- Use `apply_patch` for edits. Preserve unrelated worktree changes. At the
  time of writing, these were pre-existing user changes and must not be reset:
  `lib/src/core/ffi/agent_api.dart`, `pdf_text_engine.dart`,
  `pdfium_text_engine_stub.dart`, and `pdfium_text_engine_worker_helpers.dart`.
- Never open a second mutable PDFium document for the same interactive editor
  session. PDFium handles remain on the pdfrx worker.
- Call `FPDFPage_GenerateContent()` while the loaded `FPDF_PAGE` is still
  alive; generating after reopening a page loses the mutation.
- Preserve the prepare -> apply -> publish order, validate `expectedText`, and
  keep same-page physical plans atomic. On apply failure, do not publish.
- Regenerate FRB bindings after changing public Rust FFI DTOs with
  `flutter_rust_bridge_codegen generate --no-build-runner --no-dart-fix --no-web`.
