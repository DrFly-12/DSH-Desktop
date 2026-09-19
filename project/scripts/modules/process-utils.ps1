# ============================================================================
# process-utils.ps1 — Process-tree kill, server-PID detection, Chrome launch
# Dot-sourced by launcher.ps1. Expects $logFile to be defined.
# ============================================================================

function Get-ChildProcessIds {
    param([Parameter(Mandatory = $true)][int]$ParentPid)
    $ids = @()
    try {
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentPid" -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            $ids += $child.ProcessId
            $ids += Get-ChildProcessIds $child.ProcessId
        }
    } catch {}
    return $ids
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$RootPid)
    $children = Get-ChildProcessIds $RootPid
    foreach ($cid in $children) {
        Stop-Process -Id $cid -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $RootPid -Force -ErrorAction SilentlyContinue
    Log "  Stopped process tree rooted at PID $RootPid"
}

function Test-TrackedProcess {
    param($Process)
    if (-not $Process) { return $false }
    try {
        $path = (Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)" -ErrorAction Stop).ExecutablePath
        return $path -and ($path -ieq (Get-Process -Id $Process.Id).Path)
    } catch {
        return $false
    }
}

function Get-ServerPid {
    try {
        $conn = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue |
                Select-Object -First 1
        if ($conn) { return $conn.OwningProcess }
    } catch {
        try {
            $line = netstat -ano 2>$null | Select-String ":3080.*LISTENING"
            if ($line -match '\s+(\d+)\s*$') { return [int]$Matches[1] }
        } catch {}
    }
    return $null
}

function Wait-ForProcessExit {
    param($Process, [string]$Label = "process")
    if (-not $Process) { return }
    Log "  Waiting for $Label to close..."
    $tries = 0
    while (-not $Process.HasExited) {
        Start-Sleep -Seconds 1
        $tries++
        if ($tries -gt 43200) {  # 12h safety cap
            Log "  WARNING: $Label still open after 12h, breaking wait loop"
            break
        }
    }
    Log "$Label closed (exit code: $($Process.ExitCode))"
}
