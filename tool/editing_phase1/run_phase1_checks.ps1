$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

function Invoke-GateStep {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "==> $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Phase 1 gate failed: $Label" }
}

Push-Location $repoRoot
try {
    Invoke-GateStep "Rust format" { cargo fmt --all --manifest-path rust/Cargo.toml -- --check }
    Invoke-GateStep "Rust lint" { cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings }
    Invoke-GateStep "Rust tests" { cargo test --workspace --manifest-path rust/Cargo.toml }
    # Compile every registered benchmark without pulling benchmark-free facade/RAG artifacts into the release profile.
    Invoke-GateStep "Benchmark compilation" {
        cargo bench --manifest-path rust/Cargo.toml --no-run `
            -p clarix_editing_core `
            -p clarix_editing_store `
            -p clarix_pdf_adapter
    }
    Invoke-GateStep "Generate Flutter/Rust bindings" { flutter_rust_bridge_codegen generate }
    Invoke-GateStep "Generated bindings are clean" { git diff --exit-code -- rust/clarix_pdf_oxide/src/frb_generated.rs lib/src/core/ffi }
    Invoke-GateStep "Core editing tests" { flutter test test/core/editing test/workspace_editing }
    Invoke-GateStep "Legacy migration tests" { flutter test test/workspace_pdf }
    Invoke-GateStep "Editing analysis" { flutter analyze lib/src/core/editing lib/src/core/ffi lib/src/features/workspace/editing lib/src/features/workspace }

    Write-Host "==> Pending user-owned release evidence"
    Write-Host "cargo build --release -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --target x86_64-pc-windows-msvc"
    Write-Host "This script intentionally does not execute cargo build."
}
finally {
    Pop-Location
}
