param(
    [switch]$IncludeBindingGeneration,
    [switch]$IncludeNativeFixture,
    [switch]$IncludeFullSoak
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

function Invoke-GateStep {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "==> $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Phase 2 gate failed: $Label" }
}

Push-Location $repoRoot
try {
    Invoke-GateStep "Rust format" { cargo fmt --all --manifest-path rust/Cargo.toml -- --check }
    Invoke-GateStep "Phase 2 core contracts" {
        cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml --test actor_ordering --test command_session --test compatibility_report --test history_contract --test model_contract --test page_service --test replace_all_contract --test search_contract --test selection_contract
    }
    Invoke-GateStep "Phase 2 durable store contracts" {
        cargo test -p clarix_editing_store --manifest-path rust/Cargo.toml --test repository_contract
    }
    Invoke-GateStep "Editing-only native facade compile" {
        cargo check -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --lib --no-default-features
    }

    if ($IncludeBindingGeneration) {
        Invoke-GateStep "Generate Flutter/Rust bindings" { flutter_rust_bridge_codegen generate }
        Invoke-GateStep "Generated bindings are clean" { git diff --exit-code -- rust/clarix_pdf_oxide/src/frb_generated.rs lib/src/core/ffi }
        Invoke-GateStep "Flutter editing contracts" { flutter test test/core/editing test/workspace_editing }
    }
    else {
        Write-Host "==> FRB generation and Flutter integration checks skipped; pass -IncludeBindingGeneration on a machine with enough CPU."
    }

    if ($IncludeNativeFixture) {
        Invoke-GateStep "Native phase 2 fixture contracts" {
            cargo test -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --no-default-features --test editing_bridge
        }
    }
    else {
        Write-Host "==> Native fixture contracts skipped; pass -IncludeNativeFixture when the PDF harness is affordable."
    }

    if ($IncludeFullSoak) {
        Invoke-GateStep "Large-document soak" {
            cargo test -p clarix_editing_core --manifest-path rust/Cargo.toml -- --ignored phase2_large_document
        }
    }
    else {
        Write-Host "==> 1,000-page soak skipped by default; pass -IncludeFullSoak on qualification hardware."
    }
}
finally {
    Pop-Location
}
