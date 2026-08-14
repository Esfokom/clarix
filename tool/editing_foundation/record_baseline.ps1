param(
    [string]$OutputPath = "docs/testing/editing-phase0-baseline.json",
    [int]$MemoryIterations = 100
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$commands = [System.Collections.Generic.List[object]]::new()

function Invoke-RecordedCommand {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "==> $Label"
    & $Command
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    $commands.Add([ordered]@{ command = $Label; exitCode = $code })
    if ($code -ne 0) { throw "Command failed ($code): $Label" }
}

Push-Location $repoRoot
try {
    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("clarix-phase0-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $memoryPath = Join-Path $temporaryDirectory "memory.json"

    Invoke-RecordedCommand "cargo test -p clarix_editing_core -p clarix_pdf_adapter --manifest-path rust/Cargo.toml -- --ignored" {
        cargo test -p clarix_editing_core -p clarix_pdf_adapter --manifest-path rust/Cargo.toml -- --ignored
    }
    Invoke-RecordedCommand "cargo run -p clarix_pdf_adapter --example memory_probe --manifest-path rust/Cargo.toml -- --iterations $MemoryIterations --output <temp>/memory.json" {
        cargo run -p clarix_pdf_adapter --example memory_probe --manifest-path rust/Cargo.toml -- --iterations $MemoryIterations --output $memoryPath
    }
    Invoke-RecordedCommand "cargo bench -p clarix_editing_core -p clarix_pdf_adapter --manifest-path rust/Cargo.toml --no-run" {
        cargo bench -p clarix_editing_core -p clarix_pdf_adapter --manifest-path rust/Cargo.toml --no-run
    }

    $computer = Get-CimInstance Win32_ComputerSystem
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $manifestHash = (Get-FileHash test_fixtures/editing_corpus/manifest.json -Algorithm SHA256).Hash.ToLowerInvariant()
    $memoryProbe = Get-Content $memoryPath -Raw | ConvertFrom-Json
    $report = [ordered]@{
        schemaVersion = 1
        capturedAtUtc = [DateTime]::UtcNow.ToString("o")
        gitCommit = (git rev-parse HEAD).Trim()
        os = "Windows"
        cpu = $processor.Name.Trim()
        logicalProcessors = [int]$computer.NumberOfLogicalProcessors
        memoryBytes = [uint64]$computer.TotalPhysicalMemory
        rustc = ((rustc --version) -join "`n").Trim()
        cargoProfile = "bench"
        corpusManifestSha256 = $manifestHash
        memoryProbe = [ordered]@{
            warmupBytes = [uint64]$memoryProbe.warmupBytes
            peakBytes = [uint64]$memoryProbe.peakBytes
            finalBytes = [uint64]$memoryProbe.finalBytes
            tailSlopeBytesPerIteration = [double]$memoryProbe.tailSlopeBytesPerIteration
        }
        metricCatalog = [ordered]@{
            flutterFrameTime = "harness_ready_no_phase1_overlay"
            commandLatency = "measured"
            pageInspectionLatency = "measured"
            memoryPlateau = "measured"
            rasterDifference = "harness_ready_no_materializer"
            sidecarLatency = "owned_by_sidecar_plan"
            saveLatency = "owned_by_save_plan"
        }
        commands = $commands
    }
    $resolvedOutput = Join-Path $repoRoot $OutputPath
    New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput) | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $resolvedOutput
}
finally {
    Pop-Location
    if ($temporaryDirectory -and (Test-Path $temporaryDirectory)) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
