param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$FixturePath,
    [int]$SeedCount = 100,
    [int]$TimeoutSeconds = 30,
    [string]$OutputPath = "docs/testing/editing-phase1-kill-recovery.json"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$resolvedExecutable = (Resolve-Path $ExecutablePath).Path
$resolvedFixture = (Resolve-Path $FixturePath).Path
$resolvedOutput = Join-Path $repoRoot $OutputPath
$probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clarix-kill-probe-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $probeRoot | Out-Null
$runs = [System.Collections.Generic.List[object]]::new()

try {
    for ($seed = 0; $seed -lt $SeedCount; $seed++) {
        $marker = Join-Path $probeRoot "accepted-$seed.json"
        $recovered = Join-Path $probeRoot "recovered-$seed.json"
        $arguments = @(
            "--phase1-recovery-probe",
            "--fixture", $resolvedFixture,
            "--seed", $seed,
            "--accepted-marker", $marker
        )
        $process = Start-Process -FilePath $resolvedExecutable -ArgumentList $arguments -PassThru -WindowStyle Hidden
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (!(Test-Path $marker) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (!(Test-Path $marker)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "Seed $seed did not publish an accepted-command marker."
        }
        Stop-Process -Id $process.Id -Force
        Wait-Process -Id $process.Id -ErrorAction SilentlyContinue

        $verifyArguments = @(
            "--phase1-recovery-verify",
            "--fixture", $resolvedFixture,
            "--seed", $seed,
            "--recovered-marker", $recovered
        )
        $verify = Start-Process -FilePath $resolvedExecutable -ArgumentList $verifyArguments -PassThru -Wait -WindowStyle Hidden
        if ($verify.ExitCode -ne 0 -or !(Test-Path $recovered)) {
            throw "Seed $seed recovery verification failed."
        }
        $acceptedState = Get-Content $marker -Raw | ConvertFrom-Json
        $recoveredState = Get-Content $recovered -Raw | ConvertFrom-Json
        $matched = $acceptedState.revision -eq $recoveredState.revision -and $acceptedState.textSha256 -eq $recoveredState.textSha256
        $runs.Add([ordered]@{
            seed = $seed
            acceptedRevision = [uint64]$acceptedState.revision
            recoveredRevision = [uint64]$recoveredState.revision
            matched = $matched
        })
        if (!$matched) { throw "Seed $seed recovered state does not match the last accepted marker." }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput) | Out-Null
    [ordered]@{
        schemaVersion = 1
        capturedAtUtc = [DateTime]::UtcNow.ToString("o")
        fixtureSha256 = (Get-FileHash $resolvedFixture -Algorithm SHA256).Hash.ToLowerInvariant()
        seeds = $SeedCount
        passed = ($runs | Where-Object { !$_.matched }).Count -eq 0
        runs = $runs
    } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $resolvedOutput
}
finally {
    if (Test-Path $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force }
}
