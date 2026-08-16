param(
    [string]$OutputPath = "docs/testing/editing-phase1-results.json",
    [string]$CriterionRoot = "",
    [switch]$NonBuildGatePassed,
    [string]$UserBuildExitCode,
    [string]$UserBuildDllPath,
    [string]$UserBuildTimestampUtc
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$resolvedOutput = Join-Path $repoRoot $OutputPath
$existingReport = if (Test-Path $resolvedOutput) { Get-Content $resolvedOutput -Raw | ConvertFrom-Json } else { $null }
if (-not $CriterionRoot) {
    $CriterionRoot = Join-Path $repoRoot "rust/target/criterion"
}

function Get-CriterionP95Micros {
    param([string[]]$Segments)

    $segmentedPath = $CriterionRoot
    foreach ($segment in $Segments) {
        $segmentedPath = Join-Path $segmentedPath $segment
    }
    $candidatePaths = @(
        (Join-Path $segmentedPath "new/sample.json"),
        (Join-Path (Join-Path $CriterionRoot ($Segments -join "_")) "new/sample.json")
    )
    $samplePath = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $samplePath) {
        return $null
    }
    $sample = Get-Content $samplePath -Raw | ConvertFrom-Json
    $durations = for ($index = 0; $index -lt $sample.times.Count; $index++) {
        [double]$sample.times[$index] / [double]$sample.iters[$index] / 1000.0
    }
    if ($durations.Count -eq 0) {
        return $null
    }
    $ordered = @($durations | Sort-Object)
    $p95Index = [Math]::Max(0, [Math]::Ceiling($ordered.Count * 0.95) - 1)
    return [Math]::Round([double]$ordered[$p95Index], 3)
}

$capturedCriterion = [ordered]@{
    inMemoryActorP95Micros = Get-CriterionP95Micros @("sidecar_ack", "in_memory_warm_actor")
    sqliteDurableP95Micros = Get-CriterionP95Micros @("sidecar_ack", "sqlite_durable")
    recoveryP95Micros = Get-CriterionP95Micros @("sidecar_recovery", "current_snapshot")
    snapshotP95Micros = Get-CriterionP95Micros @("sidecar_snapshot", "sqlite")
    indexedPageSceneP95Micros = Get-CriterionP95Micros @("page_scene", "indexed_visible")
    unindexedPageSceneP95Micros = Get-CriterionP95Micros @("page_scene", "unindexed_visible")
    cleanPatchColdP95Micros = Get-CriterionP95Micros @("clean_patch", "cold", "standard_latin", "144dpi")
    cleanPatchWarmP95Micros = Get-CriterionP95Micros @("clean_patch", "warm", "standard_latin", "144dpi")
    materializationP95Micros = Get-CriterionP95Micros @("save", "materialization")
    validationP95Micros = Get-CriterionP95Micros @("save", "independent_validation")
    atomicReplacementP95Micros = Get-CriterionP95Micros @("save", "atomic_move_setup")
}
$capturedCriterionCount = @($capturedCriterion.Values | Where-Object { $null -ne $_ }).Count
$criterionReport = if ($capturedCriterionCount -gt 0) {
    $criterionComplete = $capturedCriterionCount -eq $capturedCriterion.Count
    $criterionPassed = $criterionComplete `
        -and [double]$capturedCriterion.inMemoryActorP95Micros -le 50000 `
        -and [double]$capturedCriterion.sqliteDurableP95Micros -le 100000 `
        -and [double]$capturedCriterion.indexedPageSceneP95Micros -le 50000 `
        -and [double]$capturedCriterion.unindexedPageSceneP95Micros -le 250000
    [ordered]@{
        status = if (-not $criterionComplete) { "incomplete" } elseif ($criterionPassed) { "passed" } else { "failed_threshold" }
        metrics = $capturedCriterion
    }
} elseif ($existingReport -and $existingReport.performance -and $existingReport.performance.criterion) {
    $existingReport.performance.criterion
} else {
    $null
}
$computer = Get-CimInstance Win32_ComputerSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$buildEvidence = if ($existingReport -and $existingReport.userOwnedReleaseBuild) {
    $existingReport.userOwnedReleaseBuild
} else {
    [ordered]@{ status = "pending_user_execution"; exitCode = $null; dllPath = $null; dllSha256 = $null; timestampUtc = $null }
}
$saveFaultEvidencePath = Join-Path $repoRoot "docs/testing/editing-phase1-save-faults.json"
$externalReaderEvidencePath = Join-Path $repoRoot "docs/testing/editing-phase1-external-reader.json"
$killRecoveryEvidencePath = Join-Path $repoRoot "docs/testing/editing-phase1-kill-recovery.json"
$profileEditingEvidencePath = Join-Path $repoRoot "build/editing_phase1/phase1-editing-profile.json"
$profileLargeDocumentEvidencePath = Join-Path $repoRoot "build/editing_phase1/phase1-large-document-profile.json"
$saveFaultEvidence = if (Test-Path $saveFaultEvidencePath) { Get-Content $saveFaultEvidencePath -Raw | ConvertFrom-Json } else { $null }
$externalReaderEvidence = if (Test-Path $externalReaderEvidencePath) { Get-Content $externalReaderEvidencePath -Raw | ConvertFrom-Json } else { $null }
$killRecoveryEvidence = if (Test-Path $killRecoveryEvidencePath) { Get-Content $killRecoveryEvidencePath -Raw | ConvertFrom-Json } else { $null }
$profileEditingEvidence = if (Test-Path $profileEditingEvidencePath) { Get-Content $profileEditingEvidencePath -Raw | ConvertFrom-Json } else { $null }
$profileLargeDocumentEvidence = if (Test-Path $profileLargeDocumentEvidencePath) { Get-Content $profileLargeDocumentEvidencePath -Raw | ConvertFrom-Json } else { $null }
$profileEditingPassed = $profileEditingEvidence -and $profileEditingEvidence.phase1Editing `
    -and [int]$profileEditingEvidence.phase1Editing.commands -eq 1003 `
    -and [int64]$profileEditingEvidence.phase1Editing.p95LocalPaintMicros -le 16000 `
    -and [int64]$profileEditingEvidence.phase1Editing.p95CommandRoundTripMicros -le 100000 `
    -and [int64]$profileEditingEvidence.phase1Editing.p95WarmCaretLookupMicros -le 32000 `
    -and ([int64]$profileEditingEvidence.phase1Editing.p95FrameBuildMicros + [int64]$profileEditingEvidence.phase1Editing.p95FrameRasterMicros) -le 16700 `
    -and [int]$profileEditingEvidence.phase1Editing.frames -gt 0 `
    -and [int]$profileEditingEvidence.phase1Editing.pageReloadCount -eq 0 `
    -and [int]$profileEditingEvidence.phase1Editing.viewportShiftCount -eq 0 `
    -and [int]$profileEditingEvidence.phase1Editing.focusChangeCount -eq 0
$profileLargeDocumentPassed = $profileLargeDocumentEvidence -and $profileLargeDocumentEvidence.phase1LargeDocument `
    -and [int]$profileLargeDocumentEvidence.phase1LargeDocument.pageCount -eq 1000 `
    -and [int]$profileLargeDocumentEvidence.phase1LargeDocument.sceneRequests -eq 2001 `
    -and [int64]$profileLargeDocumentEvidence.phase1LargeDocument.p95IndexedSceneRequestMicros -le 50000 `
    -and [int64]$profileLargeDocumentEvidence.phase1LargeDocument.p95UnindexedSceneRequestMicros -le 250000 `
    -and ([int64]$profileLargeDocumentEvidence.phase1LargeDocument.p95FrameBuildMicros + [int64]$profileLargeDocumentEvidence.phase1LargeDocument.p95FrameRasterMicros) -le 16700 `
    -and [int]$profileLargeDocumentEvidence.phase1LargeDocument.frames -gt 0 `
    -and [int]$profileLargeDocumentEvidence.phase1LargeDocument.residentSceneCount -le 8

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
    nonBuildGate = if ($NonBuildGatePassed) {
        [ordered]@{
            status = "passed"
            scope = @("rust_format", "rust_clippy", "rust_tests", "benchmark_compilation", "generated_bindings", "flutter_editing_tests", "flutter_compatibility_tests", "flutter_analysis")
        }
    } elseif ($existingReport -and $existingReport.nonBuildGate) {
        $existingReport.nonBuildGate
    } else {
        [ordered]@{ status = "pending_execution" }
    }
    postGateDelta = if ($existingReport -and $existingReport.postGateDelta) { $existingReport.postGateDelta } else { $null }
    profileEditing = if ($profileEditingEvidence -and $profileEditingEvidence.phase1Editing) {
        [ordered]@{
            status = if ($profileEditingPassed) { "passed" } else { "failed_threshold" }
            evidencePath = "build/editing_phase1/phase1-editing-profile.json"
            metrics = $profileEditingEvidence.phase1Editing
        }
    } else {
        [ordered]@{ status = "pending_profile_execution" }
    }
    profileLargeDocument = if ($profileLargeDocumentEvidence -and $profileLargeDocumentEvidence.phase1LargeDocument) {
        [ordered]@{
            status = if ($profileLargeDocumentPassed) { "passed" } else { "failed_threshold" }
            evidencePath = "build/editing_phase1/phase1-large-document-profile.json"
            metrics = $profileLargeDocumentEvidence.phase1LargeDocument
        }
    } else {
        [ordered]@{ status = "pending_profile_execution" }
    }
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
            status = if ($externalReaderEvidence.rustSearchExtractGeometry -eq "passed" `
                -and $externalReaderEvidence.pdfrxPdfiumSearchExtractGeometry -eq "passed" `
                -and (@("passed", "skipped_unavailable") -contains $externalReaderEvidence.externalReader.status)) { "passed" } else { "failed_or_incomplete" }
            rust = $externalReaderEvidence.rustSearchExtractGeometry
            pdfrxPdfium = $externalReaderEvidence.pdfrxPdfiumSearchExtractGeometry
            oldTextAbsent = $externalReaderEvidence.oldTextAbsent
            namedReader = $externalReaderEvidence.externalReader
            evidencePath = "docs/testing/editing-phase1-external-reader.json"
        }
    } else {
        [ordered]@{ status = "pending"; rust = "pending"; pdfrxPdfium = "pending"; namedReader = "pending_or_named_skip" }
    }
    performance = [ordered]@{
        criterion = if ($criterionReport) { $criterionReport } else { [ordered]@{ status = "pending_execution" } }
        localPaintP95Micros = if ($profileEditingEvidence -and $profileEditingEvidence.phase1Editing) { [int64]$profileEditingEvidence.phase1Editing.p95LocalPaintMicros } else { "pending_profile" }
        durableCommandP95Micros = if ($profileEditingEvidence -and $profileEditingEvidence.phase1Editing) { [int64]$profileEditingEvidence.phase1Editing.p95CommandRoundTripMicros } else { "pending_profile" }
        warmCaretP95Micros = if ($profileEditingEvidence -and $profileEditingEvidence.phase1Editing) { [int64]$profileEditingEvidence.phase1Editing.p95WarmCaretLookupMicros } else { "pending_profile" }
        frameLatency = if ($profileEditingEvidence -and $profileEditingEvidence.phase1Editing) {
            [ordered]@{
                p95BuildMicros = [int64]$profileEditingEvidence.phase1Editing.p95FrameBuildMicros
                p95RasterMicros = [int64]$profileEditingEvidence.phase1Editing.p95FrameRasterMicros
            }
        } else { "pending_profile" }
        memoryPlateau = if ($profileLargeDocumentEvidence -and $profileLargeDocumentEvidence.phase1LargeDocument) {
            [ordered]@{
                warmTailBytes = [uint64]$profileLargeDocumentEvidence.phase1LargeDocument.memoryWarmTailBytes
                finalBytes = [uint64]$profileLargeDocumentEvidence.phase1LargeDocument.memoryFinalBytes
                tailGrowthBytes = [int64]$profileLargeDocumentEvidence.phase1LargeDocument.memoryTailGrowthBytes
            }
        } else { "pending_profile" }
        reloadCount = if ($profileEditingEvidence -and $profileEditingEvidence.phase1Editing) { [int]$profileEditingEvidence.phase1Editing.pageReloadCount } else { "pending_profile" }
        viewportShiftCount = if ($profileEditingEvidence -and $profileEditingEvidence.phase1Editing) { [int]$profileEditingEvidence.phase1Editing.viewportShiftCount } else { "pending_profile" }
    }
    generatedBindingsDiff = if ($NonBuildGatePassed) {
        "passed"
    } elseif ($existingReport -and $existingReport.generatedBindingsDiff) {
        $existingReport.generatedBindingsDiff
    } else {
        "pending"
    }
    userOwnedReleaseBuild = $buildEvidence
    legacyDeletion = "blocked_until_all_required_evidence_passes"
}

New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput) | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $resolvedOutput
