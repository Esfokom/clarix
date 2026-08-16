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
| Profile editing | 1,000 edits, IME, undo/redo, focus/page/zoom/scroll identity, frame timings | Pending profile execution |
| Large document | 2,001 scene requests, bounded residency, scene latency and RSS warm-tail/final sampling | Harness implemented; pending profile execution |
| Crash recovery | at least 100 seeded terminations including WAL checkpoint timing | Harness implemented with deterministic passive-checkpoint/truncate midpoint; pending executable and run |
| Save faults | every save stage; hashes for source/temp/backup/output/sidecar before and after | Passed; see `editing-phase1-save-faults.json` |
| External readers | actual supplied PDF through Rust and pdfrx/PDFium; named reader search/select evidence | Actual-file harness implemented; pending saved output and reader automation |
| Generated bindings | regeneration produces no diff | Pending gate run |
| User release DLL | user-owned release command exits zero and DLL hash is recorded | Pending user execution |

## Reproducible commands

```powershell
& tool/editing_phase1/run_phase1_checks.ps1
flutter drive --profile --driver test_driver/integration_test.dart --target integration_test/phase1_editing_test.dart
flutter drive --profile --driver test_driver/integration_test.dart --target integration_test/phase1_large_document_test.dart
& tool/editing_phase1/kill_recovery_probe.ps1 -ExecutablePath <profile-exe> -FixturePath <fixture> -SeedCount 100 -WalCheckpointInterval 10
& tool/editing_phase1/save_fault_probe.ps1
& tool/editing_phase1/external_reader_probe.ps1 -SavedPdf <saved-pdf> -ExpectedText <new-text> -OldText <old-text> -ReaderExecutable <reader> -ReaderName <name-and-version>
& tool/editing_phase1/record_phase1_evidence.ps1 -OutputPath docs/testing/editing-phase1-results.json
```

`run_phase1_checks.ps1` does not invoke `cargo build`. It prints this pending,
user-owned command:

```powershell
cargo build --release -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --target x86_64-pc-windows-msvc
```

## Final migration rule

Only after every required evidence item is `passed` may the three legacy
mutation/save infrastructure files and Dart-owned history be deleted. Rerun the
entire gate against that deletion commit before declaring Phase 1 complete.
