param(
    [Parameter(Mandatory = $true)][string]$SavedPdf,
    [Parameter(Mandatory = $true)][string]$ExpectedText,
    [string]$OldText,
    [string]$ReaderExecutable,
    [string]$ReaderName,
    [string]$ReaderEvidencePath,
    [string]$ReaderUnavailableReason,
    [string]$OutputPath = "docs/testing/editing-phase1-external-reader.json"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$resolvedPdf = (Resolve-Path $SavedPdf).Path
$resolvedOutput = Join-Path $repoRoot $OutputPath
$savedPdfHash = (Get-FileHash $resolvedPdf -Algorithm SHA256).Hash.ToLowerInvariant()
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$expectedHash = [Convert]::ToHexString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($ExpectedText))).ToLowerInvariant()
$oldHash = if ($OldText) { [Convert]::ToHexString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($OldText))).ToLowerInvariant() } else { $null }

Push-Location $repoRoot
try {
    $env:CLARIX_PHASE1_SAVED_PDF = $resolvedPdf
    $env:CLARIX_PHASE1_EXPECTED_TEXT = $ExpectedText
    $env:CLARIX_PHASE1_OLD_TEXT = $OldText

    cargo test -p clarix_pdf_adapter --manifest-path rust/Cargo.toml --test validation phase1_saved_pdf_is_searchable_extractable_and_old_text_is_absent -- --ignored --exact
    if ($LASTEXITCODE -ne 0) { throw "Independent Rust validation failed." }
    flutter test test/workspace_pdf/pdf_text_compatibility_test.dart --plain-name "Phase 1 supplied saved PDF is searchable selectable and excludes old text"
    if ($LASTEXITCODE -ne 0) { throw "pdfrx/PDFium extraction validation failed." }

    $reader = $null
    if ($ReaderEvidencePath) {
        if (-not $ReaderName) { throw "ReaderName is required with ReaderEvidencePath." }
        $resolvedReaderEvidence = (Resolve-Path $ReaderEvidencePath).Path
        $readerEvidence = Get-Content $resolvedReaderEvidence -Raw | ConvertFrom-Json
        if ([int]$readerEvidence.schemaVersion -ne 1) { throw "Unsupported reader evidence schema." }
        if ($readerEvidence.readerName -ne $ReaderName) { throw "Reader evidence name does not match ReaderName." }
        if (-not $readerEvidence.readerVersion) { throw "Reader evidence must include readerVersion." }
        if ($readerEvidence.savedPdfSha256 -ne $savedPdfHash) { throw "Reader evidence PDF hash does not match the supplied PDF." }
        if ($readerEvidence.expectedTextSha256 -ne $expectedHash) { throw "Reader evidence text hash does not match ExpectedText." }
        foreach ($field in @("search", "selectionCopy", "visualPosition")) {
            if ($readerEvidence.$field -ne "passed") { throw "Reader evidence field '$field' did not pass." }
        }
        if ($OldText) {
            if ($readerEvidence.oldTextSha256 -ne $oldHash) { throw "Reader evidence old-text hash does not match OldText." }
            if ($readerEvidence.oldTextAbsent -ne "passed") { throw "Reader evidence did not prove old text absent." }
        }
        $reader = [ordered]@{
            name = $ReaderName
            version = $readerEvidence.readerVersion
            status = "passed"
            verification = "search_selection_copy_visual_position_old_text_absence"
            evidencePath = $resolvedReaderEvidence
        }
    } elseif ($ReaderExecutable) {
        if (-not $ReaderName) { throw "ReaderName is required with ReaderExecutable." }
        $resolvedReader = (Resolve-Path $ReaderExecutable).Path
        $process = Start-Process -FilePath $resolvedReader -ArgumentList @($resolvedPdf) -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        if ($process.HasExited -and $process.ExitCode -ne 0) {
            throw "$ReaderName failed to open the saved PDF."
        }
        if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
        $reader = [ordered]@{
            name = $ReaderName
            status = "insufficient_evidence"
            verification = "open_only"
            reason = "generic process launch cannot prove search, selection-copy, or visual position; supply ReaderEvidencePath"
        }
    } elseif ($ReaderUnavailableReason) {
        if (-not $ReaderName) { throw "ReaderName is required with ReaderUnavailableReason." }
        $reader = [ordered]@{ name = $ReaderName; status = "skipped_unavailable"; reason = $ReaderUnavailableReason }
    } else {
        throw "Supply ReaderEvidencePath, ReaderExecutable, or a named ReaderUnavailableReason."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput) | Out-Null
    [ordered]@{
        schemaVersion = 1
        capturedAtUtc = [DateTime]::UtcNow.ToString("o")
        savedPdfSha256 = $savedPdfHash
        expectedTextSha256 = $expectedHash
        oldTextSha256 = $oldHash
        rustIndependentValidator = "passed"
        rustSearchExtractGeometry = "passed"
        pdfrxPdfiumSearchExtractGeometry = "passed"
        oldTextAbsent = if ($OldText) { "passed" } else { "not_requested" }
        externalReader = $reader
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $resolvedOutput
}
finally {
    Remove-Item Env:CLARIX_PHASE1_SAVED_PDF -ErrorAction SilentlyContinue
    Remove-Item Env:CLARIX_PHASE1_EXPECTED_TEXT -ErrorAction SilentlyContinue
    Remove-Item Env:CLARIX_PHASE1_OLD_TEXT -ErrorAction SilentlyContinue
    Pop-Location
}
