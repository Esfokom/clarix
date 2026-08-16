param(
    [string]$OutputPath = "docs/testing/editing-phase1-results.json"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$benchmarkTarget = Join-Path $repoRoot "build/editing_phase1/cargo-benchmark-target"
$criterionRoot = Join-Path $benchmarkTarget "criterion"
$resolvedOutput = Join-Path $repoRoot $OutputPath
$previousCargoTarget = $env:CARGO_TARGET_DIR
$previousCargoIncremental = $env:CARGO_INCREMENTAL
$previousBenchDebug = $env:CARGO_PROFILE_BENCH_DEBUG

$env:CARGO_TARGET_DIR = $benchmarkTarget
$env:CARGO_INCREMENTAL = "0"
$env:CARGO_PROFILE_BENCH_DEBUG = "0"

function Invoke-BenchmarkStep {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "==> $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Phase 1 benchmark failed: $Label" }
}

Push-Location $repoRoot
try {
    Invoke-BenchmarkStep "Page scene latency" {
        cargo bench -p clarix_editing_core --bench page_scene_latency --manifest-path rust/Cargo.toml
    }
    Invoke-BenchmarkStep "Sidecar latency" {
        cargo bench -p clarix_editing_store --bench sidecar_latency --manifest-path rust/Cargo.toml
    }
    Invoke-BenchmarkStep "Clean-patch latency" {
        cargo bench -p clarix_pdf_adapter --bench clean_patch --manifest-path rust/Cargo.toml
    }
    Invoke-BenchmarkStep "Save latency" {
        cargo bench -p clarix_pdf_adapter --bench save_latency --manifest-path rust/Cargo.toml
    }

    Write-Host "==> Recording Criterion evidence"
    & (Join-Path $PSScriptRoot "record_phase1_evidence.ps1") `
        -CriterionRoot $criterionRoot `
        -OutputPath $OutputPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to record Phase 1 Criterion evidence." }

    $report = Get-Content $resolvedOutput -Raw | ConvertFrom-Json
    if ($report.performance.criterion.status -ne "passed") {
        throw "Criterion evidence is not complete and passing: $($report.performance.criterion.status)"
    }
}
finally {
    try {
        if (Test-Path $benchmarkTarget) {
            Write-Host "==> Cleaning isolated Cargo benchmark target"
            cargo clean --manifest-path rust/Cargo.toml --target-dir $benchmarkTarget
            if ($LASTEXITCODE -ne 0) { throw "Failed to clean isolated Cargo benchmark target." }
        }
    }
    finally {
        if ($null -eq $previousCargoTarget) { Remove-Item Env:CARGO_TARGET_DIR -ErrorAction SilentlyContinue } else { $env:CARGO_TARGET_DIR = $previousCargoTarget }
        if ($null -eq $previousCargoIncremental) { Remove-Item Env:CARGO_INCREMENTAL -ErrorAction SilentlyContinue } else { $env:CARGO_INCREMENTAL = $previousCargoIncremental }
        if ($null -eq $previousBenchDebug) { Remove-Item Env:CARGO_PROFILE_BENCH_DEBUG -ErrorAction SilentlyContinue } else { $env:CARGO_PROFILE_BENCH_DEBUG = $previousBenchDebug }
        Pop-Location
    }
}
