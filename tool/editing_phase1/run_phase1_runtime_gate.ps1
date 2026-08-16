param(
    [Parameter(Mandatory = $true)][string]$UserBuildDllPath,
    [string]$ReaderName,
    [string]$ReaderEvidencePath,
    [string]$ReaderUnavailableReason,
    [int]$SeedCount = 100
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$resolvedDll = (Resolve-Path $UserBuildDllPath).Path
$SeedCount = [Math]::Max($SeedCount, 100)
$expectedDll = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "rust/target/x86_64-pc-windows-msvc/release/clarix_pdf_oxide.dll"))
if ($resolvedDll -ne $expectedDll) {
    throw "User build DLL must be the approved target: $expectedDll"
}

function Invoke-RuntimeStep {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "==> $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Phase 1 runtime gate failed: $Label" }
}

Push-Location $repoRoot
try {
    Invoke-RuntimeStep "Native editing profile" {
        flutter drive -d windows --profile `
            --driver test_driver/phase1_editing_test.dart `
            --target integration_test/phase1_editing_test.dart
    }
    Invoke-RuntimeStep "Large-document profile" {
        flutter drive -d windows --profile `
            --driver test_driver/phase1_large_document_test.dart `
            --target integration_test/phase1_large_document_test.dart
    }

    $profileExecutable = Join-Path $repoRoot "build/windows/x64/runner/Profile/clarix.exe"
    if (-not (Test-Path $profileExecutable)) {
        throw "Profile executable was not produced: $profileExecutable"
    }
    $fixture = Join-Path $repoRoot "test_fixtures/editing_corpus/generated/standard-latin.pdf"
    Invoke-RuntimeStep "Forced-kill recovery" {
        & (Join-Path $PSScriptRoot "kill_recovery_probe.ps1") `
            -ExecutablePath $profileExecutable `
            -FixturePath $fixture `
            -SeedCount $SeedCount `
            -WalCheckpointInterval 10
    }

    $editingProfile = Get-Content (Join-Path $repoRoot "build/editing_phase1/phase1-editing-profile.json") -Raw | ConvertFrom-Json
    $savedPdf = $editingProfile.phase1Editing.savedPdfPath
    $expectedText = $editingProfile.phase1Editing.expectedText
    $oldText = $editingProfile.phase1Editing.oldText
    if ($ReaderEvidencePath -or $ReaderUnavailableReason) {
        $readerArguments = @{
            SavedPdf = $savedPdf
            ExpectedText = $expectedText
            OldText = $oldText
            ReaderName = $ReaderName
        }
        if ($ReaderEvidencePath) { $readerArguments.ReaderEvidencePath = $ReaderEvidencePath }
        if ($ReaderUnavailableReason) { $readerArguments.ReaderUnavailableReason = $ReaderUnavailableReason }
        Invoke-RuntimeStep "External-reader qualification" {
            & (Join-Path $PSScriptRoot "external_reader_probe.ps1") @readerArguments
        }
    } else {
        Write-Warning "External-reader evidence remains pending; provide ReaderEvidencePath or a named unavailability reason."
    }

    $dllTimestamp = (Get-Item $resolvedDll).LastWriteTimeUtc.ToString("o")
    Invoke-RuntimeStep "Record runtime evidence" {
        & (Join-Path $PSScriptRoot "record_phase1_evidence.ps1") `
            -UserBuildExitCode "0" `
            -UserBuildDllPath $resolvedDll `
            -UserBuildTimestampUtc $dllTimestamp
    }
}
finally {
    Pop-Location
}
