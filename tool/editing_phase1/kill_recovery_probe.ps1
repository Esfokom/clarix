param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$FixturePath,
    [int]$SeedCount = 100,
    [int]$WalCheckpointInterval = 10,
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
$checkpointMarkerVariable = "CLARIX_PHASE1_WAL_CHECKPOINT_MARKER"
$checkpointPauseVariable = "CLARIX_PHASE1_WAL_CHECKPOINT_PAUSE_MS"
$priorCheckpointMarker = [Environment]::GetEnvironmentVariable($checkpointMarkerVariable, "Process")
$priorCheckpointPause = [Environment]::GetEnvironmentVariable($checkpointPauseVariable, "Process")

if ($SeedCount -lt 1) { throw "SeedCount must be at least 1." }
if ($WalCheckpointInterval -lt 1) { throw "WalCheckpointInterval must be at least 1." }
if ($WalCheckpointInterval -gt $SeedCount) { throw "WalCheckpointInterval must not exceed SeedCount." }

try {
    for ($seed = 0; $seed -lt $SeedCount; $seed++) {
        $marker = Join-Path $probeRoot "accepted-$seed.json"
        $recovered = Join-Path $probeRoot "recovered-$seed.json"
        $checkpointMarker = Join-Path $probeRoot "checkpoint-$seed.marker"
        $seedProjectRoot = Join-Path $probeRoot "project-$seed"
        $killWindow = if ((($seed + 1) % $WalCheckpointInterval) -eq 0) { "wal-checkpoint" } else { "accepted-command" }
        $arguments = @(
            "--phase1-recovery-probe",
            "--fixture", $resolvedFixture,
            "--project-root", $seedProjectRoot,
            "--seed", $seed,
            "--accepted-marker", $marker,
            "--kill-window", $killWindow
        )
        if ($killWindow -eq "wal-checkpoint") {
            [Environment]::SetEnvironmentVariable($checkpointMarkerVariable, $checkpointMarker, "Process")
            [Environment]::SetEnvironmentVariable($checkpointPauseVariable, "30000", "Process")
        } else {
            [Environment]::SetEnvironmentVariable($checkpointMarkerVariable, $null, "Process")
            [Environment]::SetEnvironmentVariable($checkpointPauseVariable, $null, "Process")
        }
        try {
            $process = Start-Process -FilePath $resolvedExecutable -ArgumentList $arguments -PassThru -WindowStyle Hidden
        } finally {
            [Environment]::SetEnvironmentVariable($checkpointMarkerVariable, $null, "Process")
            [Environment]::SetEnvironmentVariable($checkpointPauseVariable, $null, "Process")
        }
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $killMarker = if ($killWindow -eq "wal-checkpoint") { $checkpointMarker } else { $marker }
        while (!(Test-Path $killMarker) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (!(Test-Path $killMarker)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "Seed $seed did not reach its $killWindow marker."
        }
        Stop-Process -Id $process.Id -Force
        Wait-Process -Id $process.Id -ErrorAction SilentlyContinue

        if (!(Test-Path $marker)) {
            throw "Seed $seed did not publish its last accepted state."
        }

        $verifyArguments = @(
            "--phase1-recovery-verify",
            "--fixture", $resolvedFixture,
            "--project-root", $seedProjectRoot,
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
            killWindow = $killWindow
            checkpointMidpointObserved = Test-Path $checkpointMarker
            acceptedRevision = [uint64]$acceptedState.revision
            recoveredRevision = [uint64]$recoveredState.revision
            matched = $matched
        })
        if (!$matched) { throw "Seed $seed recovered state does not match the last accepted marker." }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput) | Out-Null
    $checkpointRuns = @($runs | Where-Object { $_.killWindow -eq "wal-checkpoint" })
    $failedRuns = @($runs | Where-Object { !$_.matched })
    $missedCheckpointMidpoints = @($checkpointRuns | Where-Object { !$_.checkpointMidpointObserved })
    [ordered]@{
        schemaVersion = 2
        capturedAtUtc = [DateTime]::UtcNow.ToString("o")
        fixtureSha256 = (Get-FileHash $resolvedFixture -Algorithm SHA256).Hash.ToLowerInvariant()
        seeds = $SeedCount
        walCheckpointInterval = $WalCheckpointInterval
        walCheckpointTerminations = $checkpointRuns.Count
        passed = $failedRuns.Count -eq 0 -and $checkpointRuns.Count -gt 0 -and $missedCheckpointMidpoints.Count -eq 0
        runs = $runs
    } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $resolvedOutput
}
finally {
    [Environment]::SetEnvironmentVariable($checkpointMarkerVariable, $priorCheckpointMarker, "Process")
    [Environment]::SetEnvironmentVariable($checkpointPauseVariable, $priorCheckpointPause, "Process")
    if (Test-Path $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force }
}
