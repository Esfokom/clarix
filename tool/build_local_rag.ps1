[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$crate = Join-Path $PSScriptRoot '..\rust\clarix_pdf_oxide\Cargo.toml'
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw 'Cargo is required to build the optional local RAG runtime.'
}

Write-Host 'Building the Clarix local RAG runtime (FastEmbed + ONNX Runtime)...'
& cargo build --release --manifest-path $crate
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host 'Done. Run Flutter again to copy clarix_pdf_oxide.dll beside clarix.exe.'
