# Phase 2 Editing Exit Gate

Phase 2 is qualified in layers so normal development on a low-CPU Windows
machine remains practical. The fast layer is required for every implementation
handoff. Generated bindings, native-PDF fixtures, and the real 1,000-page soak
are explicit opt-in work on suitable hardware.

## Required fast layer

Run from the repository root:

```powershell
.\tool\editing_phase2\run_phase2_checks.ps1
```

This proves the Rust-authoritative invariants for transactions, revisioned
search and deterministic replace-all, selection validation, multi-object
history, text transforms/reflow, page-scene eviction, compatibility reporting,
annotation create/update/delete/recovery, and sidecar persistence. It also
checks the editing-only native facade without the expensive RAG feature set.

## Integration layer

Run after changing a public FRB DTO or a Dart integration surface:

```powershell
.\tool\editing_phase2\run_phase2_checks.ps1 -IncludeBindingGeneration -IncludeNativeFixture
```

The generated binding diff must be committed with its Rust DTO change. The
native fixture contract covers the page-scene/search and annotation-session
paths against a small PDF fixture.

## Qualification-hardware layer

The architecture's real large-document exit gate remains required before Phase
2 can be declared complete. Run it only on the qualification machine:

```powershell
.\tool\editing_phase2\run_phase2_checks.ps1 -IncludeBindingGeneration -IncludeNativeFixture -IncludeFullSoak
```

Record the corpus identity, machine, peak memory, tail memory slope, latency
percentiles, match count, repeated scroll/edit result, and any named gaps. The
1,000-page run is intentionally not substituted by the fast synthetic layer.
