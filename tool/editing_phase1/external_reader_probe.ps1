param(
    [Parameter(Mandatory = $true)][string]$SavedPdf,
    [string]$ReaderExecutable,
    [string]$ReaderName = "unavailable",
    [string]$OutputPath = "docs/testing/editing-phase1-external-reader.json"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$resolvedPdf = (Resolve-Path $SavedPdf).Path
$resolvedOutput = Join-Path $repoRoot $OutputPath

Push-Location $repoRoot
try {
    cargo test -p clarix_pdf_adapter --manifest-path rust/Cargo.toml --test validation --test materialization
    if ($LASTEXITCODE -ne 0) { throw "Independent Rust validation failed." }
    flutter test test/workspace_pdf/pdf_text_compatibility_test.dart
    if ($LASTEXITCODE -ne 0) { throw "pdfrx/PDFium extraction validation failed." }

    $reader = [ordered]@{ name = $ReaderName; status = "skipped"; reason = "named reader unavailable" }
    if ($ReaderExecutable) {
        $resolvedReader = (Resolve-Path $ReaderExecutable).Path
        $process = Start-Process -FilePath $resolvedReader -ArgumentList @($resolvedPdf) -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        if ($process.HasExited -and $process.ExitCode -ne 0) {
            throw "$ReaderName failed to open the saved PDF."
        }
        if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
        $reader = [ordered]@{ name = $ReaderName; status = "opened"; reason = $null }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput) | Out-Null
    [ordered]@{
        schemaVersion = 1
        capturedAtUtc = [DateTime]::UtcNow.ToString("o")
        savedPdfSha256 = (Get-FileHash $resolvedPdf -Algorithm SHA256).Hash.ToLowerInvariant()
        rustIndependentValidator = "passed"
        pdfrxPdfiumExtraction = "passed"
        externalReader = $reader
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $resolvedOutput
}
finally {
    Pop-Location
}
