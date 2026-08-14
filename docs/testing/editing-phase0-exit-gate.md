# Phase 0 Editing Foundation Exit Gate

Status: **accepted with named gaps** for Windows foundation work.

This gate qualifies the canonical edit model, single-writer session actor,
typed agent boundary, read-only PDF import adapter, typed Flutter bridge, and
performance harness. It does not qualify user-facing editing or PDF saving.

## Evidence identity

- Evidence source commit: `117239c96e7f7354f71bf81572c05f2e34c58094`
- Baseline: [`editing-phase0-baseline.json`](editing-phase0-baseline.json)
- Corpus manifest SHA-256:
  `5fb0acecc59659bcddfae118701ea8f90ebcd36fcd24b37388ce36b3e089d622`
- Machine: Windows, Intel Core i7-8650U, 8 logical processors, 17,015,324,672 bytes RAM
- Toolchain: Rust 1.96.0

The baseline's source commit is the last implementation commit before this
evidence-only change. The final gate commit is identified by repository history
because a commit cannot contain its own hash.

## Gate results

| Area | Evidence | Result |
|---|---|---|
| Command stability | 1,000 replace/undo pairs; text restored and revision 2,000 | Pass |
| Corpus inspection | Every generated valid page imported below 10,000 objects | Pass |
| Architecture | Cargo metadata fitness test enforces dependency direction and one `cdylib` facade | Pass |
| Dart diagnostics | Frame-trace and raster-diff focused tests | Pass |
| Benchmark harness | Both Criterion executables compile in bench profile | Pass |
| Memory | 100 full-corpus iterations; 11,866,112-byte peak; 27.73 bytes/iteration tail slope | Pass |
| Default Phase 0 script | Workspace format, lint, tests, Dart checks, and benchmark compilation | Pass |
| FRB regeneration | Existing typed bindings were verified during bridge implementation | Not rerun in final script |
| Windows DLL | Explicitly left for the user to run | Pending manual build |

The initial repeatable-probe ceiling is 16 MiB working set with a tail slope no
greater than 4 KiB per iteration over the last 50 samples. This ceiling is based
on the recorded 11.32 MiB peak and 27.73 bytes/iteration slope and applies only to
the Phase 0 generated-corpus importer probe. Phase 1 must replace it with a
representative long-document and viewport-residency budget.

Criterion timing on the baseline machine (95% confidence interval):

| Metric | Time |
|---|---:|
| Direct command submit | 3.74–4.57 µs |
| Actor command round trip | 255.72–305.63 µs |
| 10,000 stable-ID derivations | 4.62–5.11 ms |
| Generated page inspection | 332.31–673.35 µs/page |

Raw Criterion samples and HTML reports remain in `rust/target/criterion/` and
are intentionally not committed.

## Adapter qualification matrix

| Case | Import | What is qualified | Named gap |
|---|---|---|---|
| `standard-latin` | Pass | Deterministic text/object import | Font fidelity and writing |
| `rotated-text` | Pass | Stable page/object import | Rotation-aware editing/materialization |
| `multi-run-text` | Pass | Repeatable text extraction | Run-level style reconstruction |
| `mixed-page` | Pass | Page inspection | Image/vector object fidelity |
| `form-xobject` | Pass | Document/page inspection | Editable form expansion |
| `scanned-page` | Pass | Page inspection | OCR execution and OCR edits |
| `malformed-input` | Pass | Stable `invalid_pdf` rejection | Recovery is deferred |
| `embedded-truetype` (private) | Pass locally | Page imports with objects | Embedded font reuse/writing |
| `subset-font` (private) | Pass locally | Page imports with objects | Subset extension/re-embedding |

Private fixture hashes used locally, without committing their bytes or content:

- `embedded-truetype`: `8ad8fcd20bc92481a1fbca701e0a4d5fa2d51fbc9ac92ab287d57418f2dd8a85`
- `subset-font`: `20a0fa73c0921cf092e13bf6e35b752d4cffbf2743aa2dfcfb05866a4affcee4`

## Boundary evidence

- Canonical documents, objects, revisions, commands, and bridge DTOs contain
  stable values and UUIDs, never native PDF pointers or handles.
- `EditorSessionActor` is the only writer; revision and command-ID checks make
  commands ordered and idempotent, with bounded subscribers and explicit close.
- Typed open, hydrate, submit, event, snapshot, and close operations cross FRB;
  protocol/schema validation rejects mismatches and late events.
- Agent operations reach editing only through the typed `EditingToolGateway`.
- Unsupported clean-patch rendering, PDF materialization, and validation return
  explicit unsupported capability results and cannot report success.

## Deliberately absent

No Phase 0 change adds a Flutter caret/editor overlay, sidecar durability,
autonomous conversation loop, OCR pipeline, clean-page patching, Ctrl+S, Save
As, or PDF materialization. Those remain gated by their later architecture
phases. The adapter is accepted for read-only deterministic import with the
named gaps above; it is not accepted as the final PDF editing engine.

## Manual completion command

The user retained the final build step:

```powershell
cargo build --release -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --target x86_64-pc-windows-msvc
```

After it succeeds, verify
`rust/target/x86_64-pc-windows-msvc/release/clarix_pdf_oxide.dll` exists. No
agent-run `cargo build` was performed for this gate.
