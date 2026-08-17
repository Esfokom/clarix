# Editing Phase 3 exit gate

Run `tool/editing_phase3/run_phase3_checks.ps1` from the repository root. It is the required, deterministic, slow-machine-friendly gate. It checks formatting, selection/tool/run/proposal contracts, SQLite audit and conversation migration, the no-default-features native bridge compile, Dart protocol analysis, and focused Flutter integration tests.

Optional layers are deliberately separate:

- `-IncludeBindingGeneration` regenerates FRB bindings from a clean worktree and requires a clean generated diff.
- `-IncludeNativeFixture` runs the tiny PDF plus loopback SSE bridge contract.
- `-IncludeLiveProviderQualification` is a manual qualification reminder. Never place credentials in the repository, command history, logs, screenshots, or test fixtures.

Record the exact command and result. Do not report an optional layer as passed unless it actually ran. A live-provider failure does not weaken the deterministic gate; investigate it as provider-specific transport/configuration evidence.
