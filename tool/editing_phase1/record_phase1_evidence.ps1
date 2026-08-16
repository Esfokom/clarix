param(
    [string]$OutputPath = "docs/testing/editing-phase1-results.json",
    [string]$UserBuildExitCode,
    [string]$UserBuildDllPath,
    [string]$UserBuildTimestampUtc
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$resolvedOutput = Join-Path $repoRoot $OutputPath
$computer = Get-CimInstance Win32_ComputerSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$buildEvidence = [ordered]@{ status = "pending_user_execution"; exitCode = $null; dllPath = $null; dllSha256 = $null; timestampUtc = $null }
$saveFaultEvidencePath = Join-Path $repoRoot "docs/testing/editing-phase1-save-faults.json"
$externalReaderEvidencePath = Join-Path $repoRoot "docs/testing/editing-phase1-external-reader.json"
$killRecoveryEvidencePath = Join-Path $repoRoot "docs/testing/editing-phase1-kill-recovery.json"
$saveFaultEvidence = if (Test-Path $saveFaultEvidencePath) { Get-Content $saveFaultEvidencePath -Raw | ConvertFrom-Json } else { $null }
$externalReaderEvidence = if (Test-Path $externalReaderEvidencePath) { Get-Content $externalReaderEvidencePath -Raw | ConvertFrom-Json } else { $null }
$killRecoveryEvidence = if (Test-Path $killRecoveryEvidencePath) { Get-Content $killRecoveryEvidencePath -Raw | ConvertFrom-Json } else { $null }

if ($UserBuildExitCode) {
    $buildEvidence.status = if ([int]$UserBuildExitCode -eq 0) { "passed" } else { "failed" }
    $buildEvidence.exitCode = [int]$UserBuildExitCode
    $buildEvidence.timestampUtc = $UserBuildTimestampUtc
    if ($UserBuildDllPath -and (Test-Path $UserBuildDllPath)) {
        $resolvedDll = (Resolve-Path $UserBuildDllPath).Path
        $buildEvidence.dllPath = $resolvedDll
        $buildEvidence.dllSha256 = (Get-FileHash $resolvedDll -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$report = [ordered]@{
    schemaVersion = 1
    capturedAtUtc = [DateTime]::UtcNow.ToString("o")
    gitCommit = (git -C $repoRoot rev-parse HEAD).Trim()
    os = [System.Environment]::OSVersion.VersionString
    cpu = $processor.Name.Trim()
    logicalProcessors = [int]$computer.NumberOfLogicalProcessors
    memoryBytes = [uint64]$computer.TotalPhysicalMemory
    rustc = ((rustc --version) -join "`n").Trim()
    corpusManifestSha256 = (Get-FileHash (Join-Path $repoRoot "test_fixtures/editing_corpus/manifest.json") -Algorithm SHA256).Hash.ToLowerInvariant()
    nonBuildGate = [ordered]@{ status = "pending_execution" }
    profileEditing = [ordered]@{ status = "pending_profile_execution" }
    profileLargeDocument = [ordered]@{ status = "pending_profile_execution" }
    forcedKillRecovery = if ($killRecoveryEvidence) {
        [ordered]@{
            status = if ($killRecoveryEvidence.passed) { "passed" } else { "failed" }
            evidencePath = "docs/testing/editing-phase1-kill-recovery.json"
            seeds = [int]$killRecoveryEvidence.seeds
            walCheckpointTerminations = [int]$killRecoveryEvidence.walCheckpointTerminations
        }
    } else {
        [ordered]@{ status = "pending_executable"; requiredSeeds = 100; requiresWalCheckpointTermination = $true }
    }
    saveFaultMatrix = if ($saveFaultEvidence) {
        [ordered]@{
            status = $saveFaultEvidence.status
            evidencePath = "docs/testing/editing-phase1-save-faults.json"
            stages = $saveFaultEvidence.stages.Count
        }
    } else {
        [ordered]@{ status = "pending_execution" }
    }
    externalReaders = if ($externalReaderEvidence) {
        [ordered]@{
            rust = $externalReaderEvidence.rustSearchExtractGeometry
            pdfrxPdfium = $externalReaderEvidence.pdfrxPdfiumSearchExtractGeometry
            oldTextAbsent = $externalReaderEvidence.oldTextAbsent
            namedReader = $externalReaderEvidence.externalReader
            evidencePath = "docs/testing/editing-phase1-external-reader.json"
        }
    } else {
        [ordered]@{ rust = "pending"; pdfrxPdfium = "pending"; namedReader = "pending_or_named_skip" }
    }
    performance = [ordered]@{
        sidecarLatency = "pending_criterion"
        saveLatency = "pending_criterion"
        frameLatency = "pending_profile"
        memoryPlateau = "pending_profile"
        reloadCount = "pending_profile"
        viewportShiftCount = "pending_profile"
    }
    generatedBindingsDiff = "pending"
    userOwnedReleaseBuild = $buildEvidence
    legacyDeletion = "blocked_until_all_required_evidence_passes"
}

New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput) | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $resolvedOutput
