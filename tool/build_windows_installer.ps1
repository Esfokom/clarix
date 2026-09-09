[CmdletBinding()]
param(
  [string]$BuildName,
  [int]$BuildNumber,
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$installerScript = Join-Path $projectRoot 'installer\clarix.iss'
$launcherIconConfig = Join-Path $projectRoot 'flutter_launcher_icons.yaml'
$windowsIconPath = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
$innoCompiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'

if (-not (Test-Path -LiteralPath $innoCompiler)) {
  throw "Inno Setup 6 was not found at '$innoCompiler'. Install Inno Setup 6 and run this script again."
}
if (-not (Test-Path -LiteralPath $launcherIconConfig)) {
  throw "The launcher icon configuration is missing at '$launcherIconConfig'."
}

Push-Location $projectRoot
try {
  & dart run flutter_launcher_icons -f $launcherIconConfig
  if ($LASTEXITCODE -ne 0) {
    throw "Launcher icon generation failed with exit code $LASTEXITCODE."
  }
}
finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $windowsIconPath)) {
  throw "The generated Windows launcher icon is missing at '$windowsIconPath'."
}

$versionLine = Select-String -LiteralPath $pubspecPath -Pattern '^version:\s*([^+\s]+)(?:\+(\d+))?\s*$' |
  Select-Object -First 1
if ($null -eq $versionLine) {
  throw 'Could not read the application version from pubspec.yaml.'
}

$parsedName = $versionLine.Matches[0].Groups[1].Value
$parsedNumber = $versionLine.Matches[0].Groups[2].Value
if ([string]::IsNullOrWhiteSpace($BuildName)) {
  $BuildName = $parsedName
}
if ($PSBoundParameters.ContainsKey('BuildNumber') -eq $false -and -not [string]::IsNullOrWhiteSpace($parsedNumber)) {
  $BuildNumber = [int]$parsedNumber
}

$rustDllCandidates = @(
  (Join-Path $projectRoot 'rust\target\x86_64-pc-windows-msvc\release\clarix_pdf_oxide.dll'),
  (Join-Path $projectRoot 'rust\target\release\clarix_pdf_oxide.dll')
)
if (-not ($rustDllCandidates | Where-Object { Test-Path -LiteralPath $_ })) {
  throw 'The native RAG DLL is missing. Run .\tool\build_local_rag.ps1 before packaging.'
}

Push-Location $projectRoot
try {
  if (-not $SkipFlutterBuild) {
    $buildArguments = @('build', 'windows', '--release', "--build-name=$BuildName")
    if ($PSBoundParameters.ContainsKey('BuildNumber')) {
      $buildArguments += "--build-number=$BuildNumber"
    }
    & flutter @buildArguments
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build windows failed with exit code $LASTEXITCODE."
    }
  }

  if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'clarix.exe'))) {
    throw "The Windows release bundle was not found at '$releaseDir'."
  }
  if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'clarix_pdf_oxide.dll'))) {
    throw 'The release bundle is missing clarix_pdf_oxide.dll, so semantic local RAG would be unavailable.'
  }

  $env:CLARIX_APP_VERSION = $BuildName
  $env:CLARIX_RELEASE_DIR = $releaseDir
  & $innoCompiler $installerScript
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE."
  }
}
finally {
  Pop-Location
}

$installerPath = Join-Path $projectRoot "dist\Clarix-Setup-$BuildName.exe"
if (-not (Test-Path -LiteralPath $installerPath)) {
  throw "Inno Setup completed without producing '$installerPath'."
}

Get-Item -LiteralPath $installerPath | Select-Object FullName, Length, LastWriteTime
