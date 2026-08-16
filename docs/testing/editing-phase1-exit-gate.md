# Phase 1 Native Text Editing Exit Gate

Status: **implementation verification in progress; runtime evidence pending**.

Phase 1 is not accepted, and the legacy Dart/PDFium mutation path must not be
deleted, until every required row below passes on the evidence commit. The
canonical results file is
[`editing-phase1-results.json`](editing-phase1-results.json).

## Required identity

- Git commit and dirty-worktree status.
- Windows, CPU, logical processors, installed memory, Rust/Flutter versions.
- Editing corpus manifest SHA-256 and any private fixture hashes without fixture content.
- Native DLL path, SHA-256, timestamp, and exit code supplied by the user.
- Named external reader and version, or a named unavailability reason.

## Performance thresholds

| Metric | Required result |
|---|---:|
| Local keystroke to overlay paint, p95 | <= 16 ms |
| Warm caret placement, p95 | <= 32 ms |
| In-memory Rust acknowledgement, p95 | <= 50 ms |
| Durable SQLite acknowledgement, p95 | <= 100 ms |
| Visible indexed page scene, p95 | <= 50 ms |
| Newly visible unindexed text bounds, p95 | <= 250 ms |
| Sustained scroll frame | no sustained frame over 16.7 ms |
| PDF/page reloads while typing | 0 |
| Viewport shifts while typing | 0 |
| Focus changes from background commits | 0 |
| Accepted commands lost after forced kill | 0 of at least 100 seeded kills |

Criterion results are distributions, not unit-test wall-clock assertions.
The evidence recorder reads per-iteration samples from
`rust/target/criterion` and records p95 values for actor/SQLite durability,
snapshot/recovery, indexed/unindexed scenes, cold/warm patches, materialization,
validation, and atomic replacement. The profile runs remain authoritative for
end-to-end Flutter caret, paint, frame, and native scene thresholds.
Memory acceptance is based on a recorded plateau for the evidence hardware;
the report must include warm-tail, peak, final RSS, and resident scene/patch
counts. Clean patches remain capped at 128 MiB per document and page import at
two workers per document.

## Functional evidence matrix

| Area | Required evidence | Current state |
|---|---|---|
| Durable editing | 10,000 accepted replace/undo operations, reopen at revision 10,000, exact text and journal rows | Harness implemented |
| Page service | 1,000 pages visited exactly once, maximum two workers, empty in-flight queue | Harness implemented |
| Patch cache | cold/warm behavior, decoded bytes within budget, coldest non-visible eviction | Harness implemented |
| Save loop | repeated materialize/independent-validate cycles and no temp/backup leak | Harness implemented |
| Approved font fallback | explicit one-time approval, durable project asset recovery, embedded searchable output, and local font-state restoration | Passed on `07ca201`; focused Rust/Flutter verification |
| Profile editing | 1,000 edits, IME, undo/redo, focus/page/zoom/scroll identity, frame timings | Pending profile execution |
| Large document | 2,001 scene requests, separate indexed/unindexed p95s, bounded residency, and RSS warm-tail/final sampling | Harness implemented; pending profile execution |
| Crash recovery | at least 100 seeded terminations including WAL checkpoint timing | Harness implemented with deterministic passive-checkpoint/truncate midpoint; pending executable and run |
| Save faults | every save stage; hashes for source/temp/backup/output/sidecar before and after | Passed; see `editing-phase1-save-faults.json` |
| External readers | actual supplied PDF through Rust and pdfrx/PDFium; named reader search/select evidence | Actual-file harness implemented; pending saved output and reader automation |
| Generated bindings | regeneration produces no diff | Full gate passed on the recorded evidence commit; fallback DTOs regenerated on `07ca201` and passed focused compile/Clippy/analyze |
| User release DLL | user-owned release command exits zero and DLL hash is recorded | Pending user execution |

## Reproducible commands

```powershell
& tool/editing_phase1/run_phase1_checks.ps1
cargo bench -p clarix_editing_core --bench page_scene_latency --manifest-path rust/Cargo.toml
cargo bench -p clarix_editing_store --bench sidecar_latency --manifest-path rust/Cargo.toml
cargo bench -p clarix_pdf_adapter --bench clean_patch --bench save_latency --manifest-path rust/Cargo.toml
flutter drive --profile --driver test_driver/phase1_editing_test.dart --target integration_test/phase1_editing_test.dart
flutter drive --profile --driver test_driver/phase1_large_document_test.dart --target integration_test/phase1_large_document_test.dart
& tool/editing_phase1/kill_recovery_probe.ps1 -ExecutablePath <profile-exe> -FixturePath <fixture> -SeedCount 100 -WalCheckpointInterval 10
& tool/editing_phase1/save_fault_probe.ps1
& tool/editing_phase1/external_reader_probe.ps1 -SavedPdf <saved-pdf> -ExpectedText <new-text> -OldText <old-text> -ReaderName <name-and-version> -ReaderEvidencePath <reader-evidence.json>
& tool/editing_phase1/record_phase1_evidence.ps1 -NonBuildGatePassed -OutputPath docs/testing/editing-phase1-results.json
```

The two profile targets use `BridgeEditorSessionGateway`, the packaged Rust
DLL, isolated project roots, and real PDF files. Their drivers retain separate
metric files under `build/editing_phase1/`; the evidence recorder validates
the required latency, frame, reload, focus, scene-residency, and request-count
thresholds before marking either profile result passed.

Named-reader evidence uses schema version 1 and must bind the reader name and
version to the saved-PDF and expected-text SHA-256 values, with `search`,
`selectionCopy`, and `visualPosition` all recorded as `passed`. A generic
process launch is recorded as insufficient evidence. A skip is accepted only
with a named reader and a concrete unavailability reason.

```json
{
  "schemaVersion": 1,
  "readerName": "Microsoft Edge",
  "readerVersion": "151.0.4129.86",
  "savedPdfSha256": "<lowercase-sha256>",
  "expectedTextSha256": "<lowercase-utf8-text-sha256>",
  "oldTextSha256": "<lowercase-utf8-text-sha256>",
  "search": "passed",
  "selectionCopy": "passed",
  "visualPosition": "passed",
  "oldTextAbsent": "passed"
}
```

`run_phase1_checks.ps1` does not invoke `cargo build`. It prints this pending,
user-owned command:

```powershell
cargo build --release -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --target x86_64-pc-windows-msvc
```

The canonical JSON keeps the full non-build sweep attributed to its original
evidence commit. The later `07ca201` fallback delta is recorded separately with
its focused verification scope; no release build or runtime/profile result is
inferred from those focused checks.

## Final migration rule

Only after every required evidence item is `passed` may the three legacy
mutation/save infrastructure files and Dart-owned history be deleted. Rerun the
entire gate against that deletion commit before declaring Phase 1 complete.
