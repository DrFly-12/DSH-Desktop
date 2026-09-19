# ============================================================================
# lock-manager.ps1 — App lock file + dsh-atomic-write stale-lock recovery
# Dot-sourced by launcher.ps1. Expects $dshHome, $lockFile, $logFile, $url
# to be defined in the caller's scope.
# ============================================================================

# dsh-atomic-write creates "<file>.lock" with the owner PID as content and
# never reclaims an orphaned lock by design. A crashed/force-killed run
# therefore leaves the next launch stuck on "timed out waiting for the writer
# lock". Clear it only when the recorded owner PID is no longer running.
function Clear-StaleLock {
    param([Parameter(Mandatory = $true)][string]$LockPath)
    if (-not (Test-Path $LockPath)) { return }
    $owner = (Get-Content $LockPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($owner) { $owner = $owner.Trim() }
    $ownerAlive = $false
    if ($owner -match '^\d+$') {
        $ownerProc = Get-Process -Id ([int]$owner) -ErrorAction SilentlyContinue
        if ($ownerProc) { $ownerAlive = $true }
    }
    if ($ownerAlive) {
        Log "  Lock still held by live PID $owner - $LockPath"
    } else {
        Remove-Item $LockPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $LockPath) {
            Log "  WARNING: could not clear stale lock $LockPath"
        } else {
            Log "  Cleared stale lock $LockPath (owner PID '$owner' is gone)"
        }
    }
}

function Clear-StaleLocks {
    Get-ChildItem -Path $dshHome -Filter '*.lock' -File -ErrorAction SilentlyContinue |
        ForEach-Object { Clear-StaleLock $_.FullName }
    $profileRoot = Join-Path $dshHome 'profiles'
    if (-not (Test-Path $profileRoot)) { return }
    Get-ChildItem -Path $profileRoot -Filter '*.lock' -File -ErrorAction SilentlyContinue |
        ForEach-Object { Clear-StaleLock $_.FullName }
    Get-ChildItem -Path (Join-Path $profileRoot '*') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $profileDir = $_.FullName
            Get-ChildItem -Path $profileDir -Filter '*.lock' -File -ErrorAction SilentlyContinue |
                ForEach-Object { Clear-StaleLock $_.FullName }
        }
}

# Returns $true only when the recorded launcher PID is alive AND the DSH
# server is actually listening on port 3080. A launcher stuck in pre-flight
# (e.g. slow pnpm resolution) leaves a live powershell but no server — without
# the port check every subsequent launch would refuse to start.
function Test-LockHeldByLiveServer {
    param([Parameter(Mandatory = $true)][string]$PidString)
    if ($PidString -notmatch '^\d+$') { return $false }
    $proc = Get-Process -Id ([int]$PidString) -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }
    if (-not (Test-TrackedProcess $proc)) { return $false }
    try {
        $conn = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue |
                Select-Object -First 1
        return ($null -ne $conn)
    } catch { return $false }
}
