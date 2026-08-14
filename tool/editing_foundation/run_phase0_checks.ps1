param(
    [switch]$IncludeBindingGeneration,
    [switch]$IncludeNativeBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

function Invoke-GateStep {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "==> $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Gate failed: $Label" }
}

Push-Location $repoRoot
try {
    Invoke-GateStep "Rust format" { cargo fmt --all --manifest-path rust/Cargo.toml -- --check }
    Invoke-GateStep "Rust lint" { cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings }
    Invoke-GateStep "Rust tests" { cargo test --workspace --manifest-path rust/Cargo.toml }
    if ($IncludeBindingGeneration) {
        Invoke-GateStep "Generate Flutter/Rust bindings" { flutter_rust_bridge_codegen generate }
        Invoke-GateStep "Generated bindings are clean" { git diff --exit-code -- rust/clarix_pdf_oxide/src/frb_generated.rs lib/src/core/ffi }
    } else {
        Write-Host "==> Binding regeneration skipped; pass -IncludeBindingGeneration to verify it."
    }
    Invoke-GateStep "Dart bridge contract" { flutter test test/core/editing/editor_bridge_contract_test.dart }
    Invoke-GateStep "Performance utility contracts" { flutter test test/core/editing/frame_trace_report_test.dart test/core/editing/raster_diff_test.dart }
    Invoke-GateStep "Editing analysis" { flutter analyze lib/src/core/editing lib/src/core/ffi test/core/editing }
    Invoke-GateStep "Benchmark compilation" { cargo bench -p clarix_editing_core -p clarix_pdf_adapter --manifest-path rust/Cargo.toml --no-run }
    if ($IncludeNativeBuild) {
        Invoke-GateStep "Windows release DLL" { cargo build --release -p clarix_pdf_oxide --manifest-path rust/Cargo.toml --target x86_64-pc-windows-msvc }
    } else {
        Write-Host "==> Native release build left to the user; pass -IncludeNativeBuild when ready."
    }
}
finally {
    Pop-Location
}
