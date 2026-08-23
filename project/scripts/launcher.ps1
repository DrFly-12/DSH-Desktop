# DeepSeek Harness - PowerShell Launcher
# Completely hidden console, opens Chrome immediately with a loading page
# while the DSH server starts in the background.
# Architecture: Desktop shortcut → powershell -WindowStyle Hidden → this script
#   → starts pnpm dlx (hidden background)
#   → opens Chrome to loading.html immediately
#   → loading.html auto-redirects to DSH when server is ready

$ErrorActionPreference = "Continue"

# ---- Configurable paths ----
# All paths are derived from %USERPROFILE% or the script's own location.
# Copy this entire .dsh folder to another PC → edit ONE file (workdir.txt) → run install.ps1 → done.

$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { "$env:USERPROFILE\.dsh" }
$lockFile = "$dshHome\scripts\app.pid"
$logFile = "$dshHome\scripts\dsh-launch.log"
$loadingPath = "$dshHome\scripts\loading.html"
$desktopPatchPath = "$dshHome\scripts\desktop.patch.yml"
$errorPagePath = "$dshHome\scripts\launch-error.html"
$processOutputPath = "$dshHome\scripts\dsh-process-output.log"
$processErrorPath = "$dshHome\scripts\dsh-process-error.log"
$url = "http://127.0.0.1:3080"

# Workspace directory where pnpm runs (your project root).
# Priority: workdir.txt > hardcoded default below.
# To change, either edit the line below or create "workdir.txt" next to this script
# containing just the path, e.g. "D:\WorkSpace\my-project"
$workDirCfg = "$dshHome\scripts\workdir.txt"
$workDir = $env:USERPROFILE                             # default — overridden by workdir.txt if present
if (Test-Path $workDirCfg) {
    $txt = (Get-Content $workDirCfg -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($txt -and (Test-Path $txt)) {
        $workDir = $txt
    }
}

# Chrome search paths (tried in order)
$chromePaths = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
)

$maxLogBytes = 1MB
$maxLogLines = 500
$startupTimeout = 120       # max seconds for server to become ready
$upgradeTimeout = 30        # max seconds after a package-install prompt appears

# ---- Helper functions ----

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') - $msg"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

function Rotate-Log {
    if (-not (Test-Path $logFile)) { return }
    try {
        $size = (Get-Item $logFile).Length
        if ($size -gt $maxLogBytes) {
            $lines = Get-Content $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($lines.Count -gt $maxLogLines) {
                $lines = $lines[-$maxLogLines..-1]
                Set-Content $logFile -Value $lines -Encoding UTF8
            }
            Log "Log rotated (was $size bytes)"
        }
    } catch {}
}

function Find-Chrome {
    foreach ($path in $chromePaths) {
        if (Test-Path $path) { return $path }
    }
    Log "  Tried: $($chromePaths -join ', ')"
    return $null
}

function Get-ChildProcessIds($parentPid) {
    $ids = @()
    try {
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentPid" -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            $ids += $child.ProcessId
            $ids += Get-ChildProcessIds $child.ProcessId
        }
    } catch {}
    return $ids
}

function Stop-ProcessTree($rootPid) {
    $children = Get-ChildProcessIds $rootPid
    foreach ($cid in $children) {
        Stop-Process -Id $cid -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $rootPid -Force -ErrorAction SilentlyContinue
    Log "  Stopped process tree rooted at PID $rootPid"
}

function Test-TrackedProcess($process) {
    if (-not $process) { return $false }
    try {
        $path = (Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)" -ErrorAction Stop).ExecutablePath
        return $path -and ($path -ieq (Get-Process -Id $process.Id).Path)
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

function Launch-Chrome($ChromePath, $AppUrl) {
    Log "  Launching: $ChromePath --app=$AppUrl"
    try {
        $proc = Start-Process $ChromePath -ArgumentList "--app=$AppUrl" -PassThru -ErrorAction Stop
        Log "  Chrome PID = $($proc.Id)"
        return $proc
    } catch {
        Log "ERROR: Failed to launch Chrome: $_"
        return $null
    }
}

function Wait-ForProcessExit($proc, $label) {
    if (-not $proc) { return }
    Log "  Waiting for $label to close..."
    $tries = 0
    while (-not $proc.HasExited) {
        Start-Sleep -Seconds 1
        $tries++
        # Safety: don't wait forever — 12 hours max
        if ($tries -gt 43200) {
            Log "  WARNING: $label still open after 12h, breaking wait loop"
            break
        }
    }
    Log "$label closed (exit code: $($proc.ExitCode))"
}

function Get-RecentFileText($path) {
    if (-not (Test-Path $path)) { return "" }
    try {
        return ((Get-Content $path -Tail 12 -Encoding UTF8 -ErrorAction SilentlyContinue) -join "`n")
    } catch {
        return ""
    }
}

function Show-LaunchError($message) {
    $details = Get-RecentFileText $processErrorPath
    if (-not $details) { $details = Get-RecentFileText $processOutputPath }
    if ($details) { $message = "$message`n`n$details" }
    Log "ERROR: $message"

    try {
        Set-Content -Path $errorPagePath -Value $message -Encoding UTF8
    } catch {
        Log "ERROR: Failed to write launch error page: $_"
    }

    if ($chromeProc -and -not $chromeProc.HasExited) {
        Stop-Process -Id $chromeProc.Id -Force -ErrorAction SilentlyContinue
    }
    $errorUrl = "file:///" + ($errorPagePath -replace '\\', '/')
    $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl $errorUrl
}

# ============================================================
# MAIN  (wrapped in try/catch so unexpected errors are logged)
# ============================================================

$cmdProc = $null   # the cmd.exe that spawned pnpm
$chromeProc = $null
$ownsServer = $false

try {
    Rotate-Log
    Log "=== DSH Launcher (PID $pid) ==="

    # ---- Anti-duplicate check ----
    if (Test-Path $lockFile) {
        $oldPid = Get-Content $lockFile -ErrorAction SilentlyContinue
        if ($oldPid -match '^\d+$') {
            $oldProc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($oldProc -and (Test-TrackedProcess $oldProc)) {
                Log "Already running (PID $oldPid; $($oldProc.ProcessName)) — exiting"
                Add-Type -Name "DSH_WindowHelper2" -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);
'@ -ErrorAction SilentlyContinue

                $chromeProcs = Get-Process chrome -ErrorAction SilentlyContinue
                foreach ($cp in $chromeProcs) {
                    if ($cp.MainWindowHandle -ne 0) {
                        try {
                            if ($cp.MainWindowTitle -match "DeepSeek|Harness|DSH") {
                                [DSH_WindowHelper2]::SetForegroundWindow($cp.MainWindowHandle) | Out-Null
                                Log "  Brought Chrome window to front"
                                break
                            }
                        } catch {}
                    }
                }
                exit 0
            }
        }
        Log "Stale lock file (PID $oldPid is no longer the tracked launcher) — clearing"
    }
    $pid | Set-Content $lockFile -ErrorAction SilentlyContinue

    # ---- Pre-flight checks ----
    Log "Step 0: Pre-flight checks"

    $nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $nodePath) {
        Log "ERROR: Node.js not found. Install Node.js from https://nodejs.org/"
        Remove-Item $lockFile -ErrorAction SilentlyContinue
        exit 1
    }
    Log "  node : $nodePath"

    $pnpmPath = (Get-Command pnpm -ErrorAction SilentlyContinue).Source
    if (-not $pnpmPath) {
        Log "ERROR: pnpm not found. Install pnpm with Corepack or npm."
        Remove-Item $lockFile -ErrorAction SilentlyContinue
        exit 1
    }
    Log "  pnpm : $pnpmPath"

    $dshVersion = (& pnpm.cmd dlx @deepseek-ai/dsh --version 2>&1 | Select-Object -First 1).ToString().Trim()
    if ($dshVersion -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
        Log "  dsh  : v$dshVersion"
        if (Test-Path $loadingPath) {
            $loadingHtml = Get-Content $loadingPath -Raw -ErrorAction SilentlyContinue
            if ($loadingHtml) {
                $loadingHtml = $loadingHtml -replace 'v(?:__DSH_VERSION__|\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)', "v$dshVersion"
                Set-Content -Path $loadingPath -Value $loadingHtml -Encoding UTF8
            }
        }
    } else {
        Log "  WARNING: Could not determine DSH version"
    }

    $chrome = Find-Chrome
    if (-not $chrome) {
        Log "ERROR: Google Chrome not found"
        Remove-Item $lockFile -ErrorAction SilentlyContinue
        exit 1
    }
    Log "  Chrome: $chrome"

    # ---- Step 1: Check if DSH is already running ----
    $dsAlreadyRunning = $false
    Log "Step 1: Checking if DSH already running..."
    try {
        $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) {
            Log "DSH already serving on $url — skip backend launch"
            $dsAlreadyRunning = $true
        }
    } catch {
        Log "DSH not responding — will start"
    }

    # ================================================================
    # PATH A: DSH already running → open Chrome directly, instant load
    # ================================================================
    if ($dsAlreadyRunning) {
        Log "Step 4: Opening Chrome directly (DSH already up)..."
        $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl $url
        Wait-ForProcessExit $chromeProc "Chrome"
    }
    # ================================================================
    # PATH B: Cold start → pnpm in background + Chrome with loading page
    # ================================================================
    else {
        # --- Start pnpm in background ---
        $ownsServer = $true
        Remove-Item $processOutputPath, $processErrorPath, $errorPagePath -Force -ErrorAction SilentlyContinue
        Log "Step 2: Starting pnpm dlx @deepseek-ai/dsh --profile web --patch desktop.patch.yml (hidden)"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        # Keep the child attached to this launcher so stdout/stderr can be logged
        # and a stalled upgrade can be shown in the app instead of hanging hidden.
        if (-not (Test-Path $desktopPatchPath)) {
            Log "ERROR: Desktop patch not found at $desktopPatchPath"
            Remove-Item $lockFile -ErrorAction SilentlyContinue
            exit 1
        }
        $psi.Arguments = '/d /s /c "(echo y)|pnpm.cmd dlx @deepseek-ai/dsh --profile web --patch "' + $desktopPatchPath + '" 1>"' + $processOutputPath + '" 2>"' + $processErrorPath + '""'
        $psi.WorkingDirectory = $workDir
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $false
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false
        $cmdProc = [System.Diagnostics.Process]::Start($psi)
        Log "  cmd.exe PID = $($cmdProc.Id)"

        # --- Open Chrome IMMEDIATELY with loading page ---
        Log "Step 3: Opening Chrome with loading page..."
        $loadingUrl = "file:///" + ($loadingPath -replace '\\', '/')
        if (Test-Path $loadingPath) {
            $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl $loadingUrl
        } else {
            Log "  WARNING: loading.html not found, opening blank page"
            $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl "about:blank"
        }

        # --- Poll for server in background while Chrome is open ---
        Log "Step 4: Waiting for server (background, up to ${startupTimeout}s)..."
        $serverReady = $false
        $launchFailed = $false
        $upgradePromptAt = $null
        $lastOutputAt = Get-Date
        $maxAttempts = [math]::Ceiling($startupTimeout / 2)
        for ($i = 1; $i -le $maxAttempts; $i++) {
            # If Chrome was closed early, stop polling
            if ($chromeProc -and $chromeProc.HasExited) {
                Log "  Chrome closed early (after $($i*2)s) — stopping server poll"
                break
            }
            Start-Sleep -Seconds 2
            if ((Test-Path $processOutputPath) -or (Test-Path $processErrorPath)) {
                $lastOutputAt = Get-ChildItem $processOutputPath, $processErrorPath -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
                    Select-Object -ExpandProperty LastWriteTime
            }
            $processError = Get-RecentFileText $processErrorPath
            if ($processError) {
                Show-LaunchError "DSH reported an error and startup stopped."
                $launchFailed = $true
                break
            }
            $processOutput = Get-RecentFileText $processOutputPath
            if ($processOutput -match 'Need to install the following packages|Ok to proceed') {
                if (-not $upgradePromptAt) { $upgradePromptAt = Get-Date }
                if (((Get-Date) - $upgradePromptAt).TotalSeconds -ge $upgradeTimeout) {
                    Show-LaunchError "Package upgrade confirmation did not finish within $upgradeTimeout seconds."
                    $launchFailed = $true
                    break
                }
            }
            if ($cmdProc.HasExited -and -not $serverReady) {
                Show-LaunchError "DSH exited unexpectedly (exit code: $($cmdProc.ExitCode))."
                $launchFailed = $true
                break
            }
            if (((Get-Date) - $lastOutputAt).TotalSeconds -ge $upgradeTimeout -and -not $serverReady) {
                Show-LaunchError "DSH produced no output for $upgradeTimeout seconds; startup may be stuck."
                $launchFailed = $true
                break
            }
            try {
                $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2
                if ($r.StatusCode -eq 200) { $serverReady = $true; break }
            } catch {}
            if ($i % 5 -eq 0) { Log "  ...waiting ($($i*2)s / ${startupTimeout}s)" }
        }

        if ($serverReady) {
            Log "Server ready (took $($i*2)s)"
            # Update lock file with the actual server PID (port listener)
            $serverPid = Get-ServerPid
            if ($serverPid) {
                $serverPid | Set-Content $lockFile -ErrorAction SilentlyContinue
                Log "  Tracking server PID $serverPid (port 3080 listener)"
            }
        } elseif (-not $launchFailed) {
            Show-LaunchError "DSH did not start within $startupTimeout seconds."
            Log "  Server did not become ready (Chrome loading page will show error)"
        }

        # --- Wait for Chrome to close (loading page handles its own timeout/retry) ---
        Wait-ForProcessExit $chromeProc "Chrome"
    }

    # ---- Cleanup ----
    Log "Cleanup: stopping DSH server..."
    Start-Sleep -Seconds 2

    if ($ownsServer) {
        # Try tracked server PID from lock file
        $trackedPid = Get-Content $lockFile -ErrorAction SilentlyContinue
        if ($trackedPid -match '^\d+$' -and [int]$trackedPid -ne $pid) {
            $trackedProc = Get-Process -Id $trackedPid -ErrorAction SilentlyContinue
            if ($trackedProc) {
                Log "  stopping process PID=$trackedPid ($($trackedProc.ProcessName))"
                Stop-ProcessTree $trackedPid
            }
        }

        # Fallback: stop the cmd.exe we launched (and its descendants)
        if ($cmdProc -and -not $cmdProc.HasExited) {
            Stop-ProcessTree $cmdProc.Id
        }

        # Final safety: check if anything is still listening on port 3080
        $leftover = Get-ServerPid
        if ($leftover) {
            Log "  found leftover listener PID=$leftover — stopping"
            Stop-ProcessTree $leftover
        }
    } else {
        Log "  DSH was already running before launch — leaving its server untouched"
    }

    Remove-Item $lockFile -ErrorAction SilentlyContinue
    Log "=== Clean exit ==="

} catch {
    Log "FATAL: Unexpected error: $_"
    if ($cmdProc -and -not $cmdProc.HasExited) {
        Stop-ProcessTree $cmdProc.Id -ErrorAction SilentlyContinue
    }
    Remove-Item $lockFile -ErrorAction SilentlyContinue
    exit 1
}