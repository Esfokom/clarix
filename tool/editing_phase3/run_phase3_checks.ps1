param(
    [switch]$IncludeBindingGeneration,
    [switch]$IncludeNativeFixture,
    [switch]$IncludeLiveProviderQualification
)

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Push-Location $repo
try {
    cargo fmt --all --manifest-path rust/Cargo.toml -- --check
    cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml --test selection_context_contract --test agent_tool_gateway
    cargo test -p clarix_agent_core --manifest-path rust/Cargo.toml --test run_model_contract --test provider_contract --test tool_policy_contract --test proposal_contract --test run_engine_contract --test phase3_evaluations
    cargo test -p clarix_editing_store --manifest-path rust/Cargo.toml --test agent_repository_contract
    cargo check -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --lib --no-default-features
    dart analyze lib/src/core/agent lib/src/features/workspace/agent lib/src/features/workspace/application/ai_runtime_service.dart lib/src/features/workspace/infrastructure/native_conversation_migrator.dart
    flutter test test/core/agent test/workspace_agent/agent_run_controller_test.dart test/workspace_agent/selection_ai_surface_test.dart test/workspace_agent/agent_approval_ui_test.dart test/workspace_agent/native_conversation_migration_test.dart test/workspace_agent/phase3_integration_test.dart

    if ($IncludeBindingGeneration) {
        if (git status --porcelain) { throw 'Binding generation requires a clean worktree.' }
        flutter_rust_bridge_codegen generate
        git diff --exit-code -- rust/clarix_pdf_oxide/src/frb_generated.rs lib/src/core/ffi
    }
    if ($IncludeNativeFixture) {
        cargo test -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --no-default-features --test agent_bridge_contract
    }
    if ($IncludeLiveProviderQualification) {
        throw 'Live qualification is manual: configure a provider in Clarix, use an uncommitted credential, and record the result without the secret.'
    }
} finally {
    Pop-Location
}
