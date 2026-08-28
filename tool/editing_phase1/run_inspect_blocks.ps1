param(
    [Parameter(Mandatory = $true)][string]$PdfPath
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$resolvedPdf = (Resolve-Path $PdfPath).Path

function Invoke-InspectionStep {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "==> $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Block inspection failed: $Label" }
}

Push-Location $repoRoot
try {
    Invoke-InspectionStep "Block inspection: $resolvedPdf" {
        flutter drive -d windows --profile `
            --driver test_driver/integration_test.dart `
            --target tool/editing_phase1/inspect_blocks.dart `
            "--dart-define=PDF=$resolvedPdf"
    }
}
finally {
    Pop-Location
}
