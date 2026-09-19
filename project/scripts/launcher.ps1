# DeepSeek Harness - PowerShell Launcher (modular)
# Desktop shortcut → powershell -WindowStyle Hidden → this script
#   → starts `pnpm dlx @deepseek-ai/dsh@"<range>"` (semver range from package.json)
#   → opens Chrome app window already authenticated
#   → loading.html fallback for slow boots
#
# DEPENDENCY MANAGEMENT (no @<exact-version> pinning):
#   @deepseek-ai/dsh is declared in workspace package.json with a semver range
#   (e.g. ">=0.1.5-rc.1 <0.1.5-rc.2"). The launcher runs
#   `pnpm dlx @deepseek-ai/dsh@"<range>"` which resolves to the latest matching
#   version. An exact @<version> is NEVER used — only ranges. Version updates
#   are controlled by editing the range in package.json.

$ErrorActionPreference = "Continue"

# ---- Configurable paths ----
# Launcher 资产（scripts\modules 等）固定按本脚本自身位置解析：
# 安装版 $PSScriptRoot = {app}\scripts → $dshHome = {app}；开发版 → ~\.dsh。自洽且互不干扰。
$dshHome = Split-Path -Parent $PSScriptRoot
# DSH 进程的数据目录（profiles/storages/凭据/会话）固定为 ~/.dsh —— 用户级持久目录，
# 重装/升级/卸载均不清除；切勿指向 {app}（安装目录，卸载即删，会导致配置"丢失"）。
$env:DSH_HOME = "$env:USERPROFILE\.dsh"
$lockFile = "$dshHome\scripts\app.pid"
$logFile = "$dshHome\scripts\dsh-launch.log"
$loadingPath = "$dshHome\scripts\loading.html"
$desktopPatchPath = "$dshHome\scripts\desktop.patch.yml"
$errorPagePath = "$dshHome\scripts\launch-error.html"
$processOutputPath = "$dshHome\scripts\dsh-process-output.log"
$processErrorPath = "$dshHome\scripts\dsh-process-error.log"
$tokenJsPath = "$dshHome\scripts\token.js"
$versionConfigPath = "$dshHome\scripts\dsh-version.json"
$modulesDir = "$dshHome\scripts\modules"
$url = "http://127.0.0.1:3080"

# ---- Dot-source modular components ----
$moduleFiles = @("logger.ps1", "lock-manager.ps1", "process-utils.ps1", "dsh-runtime.ps1", "chrome-launcher.ps1")
foreach ($m in $moduleFiles) {
    $modPath = Join-Path $modulesDir $m
    if (Test-Path $modPath) {
        . $modPath
    } else {
        Write-Host "FATAL: required module not found: $modPath"
        exit 1
    }
}

# ---- Workspace directory where pnpm runs ----
$workDirCfg = "$dshHome\scripts\workdir.txt"
$workDir = $env:USERPROFILE
if (Test-Path $workDirCfg) {
    # Explicit UTF8: plain Get-Content falls back to the ANSI code page on
    # Windows PowerShell 5.1, which would mangle a non-ASCII profile path.
    $txt = (Get-Content $workDirCfg -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($txt -and (Test-Path $txt)) { $workDir = $txt }
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
$startupTimeout = 120
$upgradeTimeout = 30
$tokenWaitSeconds = 20

# ---- Helper functions (in modules) ----
# Log, Rotate-Log, Get-RecentFileText        → modules/logger.ps1
# Clear-StaleLock, Clear-StaleLocks, Test-LockHeldByLiveServer → modules/lock-manager.ps1
# Stop-ProcessTree, Test-TrackedProcess, Get-ServerPid, Wait-ForProcessExit → modules/process-utils.ps1
# Get-DshVersionConfig, Get-DshInstalledVersion, Get-DshFallbackVersion,
#   Test-DshServing, Get-DshToken, Reset-TokenJs, Publish-TokenJs → modules/dsh-runtime.ps1
# Find-Chrome, Launch-Chrome                  → modules/chrome-launcher.ps1

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
    # Escaped, not hand-built: the install path contains a space
    # ("...\Programs\DeepSeek Harness\..."), see ConvertTo-FileUrl.
    $errorUrl = ConvertTo-FileUrl $errorPagePath
    $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl $errorUrl
}

# ============================================================
# MAIN  (wrapped in try/catch so unexpected errors are logged)
# ============================================================

$cmdProc = $null
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
            # Test-LockHeldByLiveServer checks BOTH process liveness and port 3080.
            if (Test-LockHeldByLiveServer $oldPid) {
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
            } elseif ($oldProc -and (Test-TrackedProcess $oldProc)) {
                # Launcher alive but server not listening → stuck. Kill it.
                Log "Stale launcher (PID $oldPid) alive but server not running — killing and clearing lock"
                Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
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

    # NOTE: the DSH version check (`pnpm dlx ... --version`, Start-Job, up to 20s)
    # was deliberately MOVED OUT of pre-flight — it must never sit between the
    # double-click and the first visible window. It now runs after the server is
    # ready (PATH B) and only refreshes the version label in loading.html.

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
    if (Test-DshServing $url) {
        Log "DSH already serving on $url — skip backend launch"
        $dsAlreadyRunning = $true
    } else {
        Log "DSH not responding — will start"
    }

    # ================================================================
    # PATH A: DSH already running → open Chrome directly, instant load
    # ================================================================
    if ($dsAlreadyRunning) {
        $liveToken = Get-DshToken
        if ($liveToken) {
            Log "Step 4: Opening Chrome directly with session token..."
            $openUrl = "$url/?token=$liveToken"
        } else {
            Log "Step 4: Opening Chrome directly (DSH already up)..."
            $openUrl = $url
        }
        $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl $openUrl
        Wait-ForProcessExit $chromeProc "Chrome"
    }
    # ================================================================
    # PATH B: Cold start → pnpm dlx @deepseek-ai/dsh@"<range>" + Chrome with loading page
    # ================================================================
    else {
        Clear-StaleLocks

        # Launch strategy:
        #   Primary:  `pnpm dlx @deepseek-ai/dsh@"<range>"` (semver range, cached).
        #   Fallback: if the range resolution fails, install lastKnownGood via pnpm add.
        $fallbackVersion = Get-DshFallbackVersion
        $dshRange = Get-DshVersionRange -Workspace $workDir
        $attempts = @("range")
        if ($fallbackVersion) { $attempts += "fallback" }

        $serverReady = $false
        $chromeProc = $null
        $cmdProc = $null
        # Percent-encoded: the install path contains a space, and a raw space
        # splits the argument so Chrome opens a truncated URL (see ConvertTo-FileUrl).
        $loadingUrl = ConvertTo-FileUrl $loadingPath
        $userClosedWindow = $false

        foreach ($attempt in $attempts) {
            $ownsServer = $true
            Remove-Item $processOutputPath, $processErrorPath, $errorPagePath -Force -ErrorAction SilentlyContinue
            $isFallback = ($attempt -eq "fallback")
            if ($isFallback) {
                Log "Step 2 (retry): Range resolution failed — installing lastKnownGood $fallbackVersion via pnpm add"
                Push-Location $workDir
                try { & pnpm.cmd add "@deepseek-ai/dsh@$fallbackVersion" 2>&1 | Out-Null } catch {}
                Pop-Location
                $dshPkgArg = "@deepseek-ai/dsh@$fallbackVersion"
            } else {
                Log "Step 2: Starting pnpm dlx @deepseek-ai/dsh@""$dshRange"" --profile web --patch desktop.patch.yml"
                $dshPkgArg = "@deepseek-ai/dsh@$dshRange"
            }

            # --- Show the loading window FIRST ---
            # Startup feedback must appear within seconds of the double-click,
            # long before the server or the token is ready. loading.html polls
            # token.js / the server and follows the boot progress on its own.
            # (The version check that used to delay this window was moved after
            # server-ready — see the NOTE in the pre-flight section.)
            if (-not $chromeProc -or $chromeProc.HasExited) {
                Reset-TokenJs
                if (Test-Path $loadingPath) {
                    Log "Step 1.5: Opening loading window immediately (startup feedback)"
                    $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl $loadingUrl
                } else {
                    Log "  WARNING: loading.html not found — no early feedback window"
                }
            }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            if (-not (Test-Path $desktopPatchPath)) {
                Log "ERROR: Desktop patch not found at $desktopPatchPath"
                Remove-Item $lockFile -ErrorAction SilentlyContinue
                exit 1
            }
            # `pnpm dlx @deepseek-ai/dsh@"<range>"` resolves the latest matching
            # version (cached after first run) — never an exact @<version> pin.
            # NOTE: $dshPkgArg MUST be wrapped in double quotes — the semver
            # range contains '<' and '>' (e.g. ">=0.1.5-rc.1 <0.1.5-rc.2"),
            # which cmd.exe would otherwise parse as redirection operators
            # ("系统找不到指定的文件" / exit 1).
            $psi.Arguments = '/d /s /c "(echo y)|pnpm.cmd dlx "' + $dshPkgArg + '" --profile web --patch "' + $desktopPatchPath + '" 1>"' + $processOutputPath + '" 2>"' + $processErrorPath + '""'
            $psi.WorkingDirectory = $workDir
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardInput = $false
            $psi.RedirectStandardOutput = $false
            $psi.RedirectStandardError = $false
            $cmdProc = [System.Diagnostics.Process]::Start($psi)
            Log "  cmd.exe PID = $($cmdProc.Id) ($attempt)"

            # --- Wait for the session token, then swap in the authenticated window ---
            Reset-TokenJs
            Log "Step 3: Waiting up to ${tokenWaitSeconds}s for the session token..."
            $sessionToken = $null
            for ($t = 1; $t -le $tokenWaitSeconds; $t++) {
                Start-Sleep -Seconds 1
                if ($chromeProc -and $chromeProc.HasExited) { $userClosedWindow = $true; break }
                if ($cmdProc.HasExited) { break }
                $sessionToken = Get-DshToken
                if ($sessionToken) { break }
            }

            if ($userClosedWindow) {
                Log "  Loading window closed during startup — user aborted; stopping launch"
                break
            }

            if ($sessionToken) {
                Publish-TokenJs $sessionToken
                Log "  Token ready after ${t}s — swapping loading window for the authenticated app window"
                # Close the early loading window and open the app window at the
                # tokenised URL: a browser-initiated navigation keeps the Strict
                # auth cookie flowing (a file:// redirect would 401 once).
                if ($chromeProc -and -not $chromeProc.HasExited) {
                    Stop-Process -Id $chromeProc.Id -Force -ErrorAction SilentlyContinue
                }
                $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl "$url/?token=$sessionToken"
            } else {
                # Slow boot: the loading window (already open) stays up; when the
                # token appears during the poll below, the page redirects itself.
                if ($chromeProc -and -not $chromeProc.HasExited) {
                    Log "  No token after ${tokenWaitSeconds}s (slow boot) — loading window stays up"
                } elseif (Test-Path $loadingPath) {
                    Log "  No token after ${tokenWaitSeconds}s (slow boot) — opening loading page"
                    $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl $loadingUrl
                } else {
                    Log "  WARNING: loading.html not found, opening blank page"
                    $chromeProc = Launch-Chrome -ChromePath $chrome -AppUrl "about:blank"
                }
            }

            # --- Poll for server in background while Chrome is open ---
            Log "Step 4: Waiting for server (background, up to ${startupTimeout}s)..."
            $upgradePromptAt = $null
            $tokenPublished = [bool]$sessionToken
            $lastOutputAt = Get-Date
            $maxAttempts = [math]::Ceiling($startupTimeout / 2)
            for ($i = 1; $i -le $maxAttempts; $i++) {
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
                    Log "  ERROR from DSH ($attempt): startup stopped"
                    break
                }
                $processOutput = Get-RecentFileText $processOutputPath
                if ($processOutput -match 'Need to install the following packages|Ok to proceed') {
                    if (-not $upgradePromptAt) { $upgradePromptAt = Get-Date }
                    if (Test-UpgradePromptStuck $upgradePromptAt) {
                        Log "  ERROR: upgrade prompt timed out ($attempt)"
                        break
                    }
                }
                if ($cmdProc.HasExited -and -not $serverReady) {
                    Log "  ERROR: DSH exited unexpectedly ($attempt, exit code: $($cmdProc.ExitCode))"
                    break
                }
                if (((Get-Date) - $lastOutputAt).TotalSeconds -ge $upgradeTimeout -and -not $serverReady) {
                    Log "  ERROR: no output for $upgradeTimeout seconds ($attempt)"
                    break
                }
                $tok = Get-DshToken
                if ($tok -and -not $tokenPublished) {
                    $tokenPublished = $true
                    Publish-TokenJs $tok
                    Log "  Session token handed to loading page (reload once if the page shows 401)"
                }
                if (Test-DshServing $url -TimeoutSec 2) { $serverReady = $true; break }
                if ($i % 5 -eq 0) { Log "  ...waiting ($($i*2)s / ${startupTimeout}s)" }
            }

            if ($serverReady) {
                Log "Server ready ($attempt, took $($i*2)s)"
                $serverPid = Get-ServerPid
                if ($serverPid) {
                    $serverPid | Set-Content $lockFile -ErrorAction SilentlyContinue
                    Log "  Tracking server PID $serverPid (port 3080 listener)"
                }
                $tokenised = $null
                $out = Get-RecentFileText $processOutputPath
                if ($out -match '(https?://127\.0\.0\.1:\d+/\?token=[A-Za-z0-9_\-]+)') {
                    $tokenised = $Matches[1]
                }
                if ($tokenised) {
                    Log "  Auth URL (needed only if the browser shows 401): $tokenised"
                } else {
                    Log "  Auth URL not found in output; see dsh-process-output.log"
                }
                if ($isFallback) {
                    Log "  NOTE: running on fallback version $fallbackVersion. Run dsh-version.ps1 to set it as lastKnownGood."
                }
                # Version check lives here now (moved out of pre-flight so the
                # loading window can appear within seconds). It runs `pnpm dlx
                # ... --version` and rewrites the version label in loading.html —
                # the open page is not re-read, so this refreshes the NEXT launch.
                $dshVersion = Get-DshInstalledVersion -Workspace $workDir -TimeoutSec 20
                if ($dshVersion -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
                    Log "  dsh  : v$dshVersion (range: $dshRange)"
                    # UTF-8 read/write is MANDATORY here. loading.html is UTF-8
                    # *without* a BOM and carries Chinese status text; plain
                    # `Get-Content` on Windows PowerShell 5.1 falls back to the
                    # ANSI code page (GBK here), which turned every Chinese
                    # string into mojibake and — because '?' replaces bytes GBK
                    # cannot map — ate the closing quote of a JS string literal,
                    # breaking the whole <script> block. The page then rendered
                    # but never polled or redirected. Never re-introduce a
                    # bare Get-Content/Set-Content pair on this file.
                    if (Test-Path $loadingPath) {
                        try {
                            $loadingHtml = [System.IO.File]::ReadAllText($loadingPath, [System.Text.Encoding]::UTF8)
                            if ($loadingHtml) {
                                $loadingHtml = $loadingHtml -replace 'v(?:__DSH_VERSION__|\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)', "v$dshVersion"
                                # UTF8Encoding($false) => no BOM, byte-identical style to the source file
                                [System.IO.File]::WriteAllText($loadingPath, $loadingHtml, (New-Object System.Text.UTF8Encoding($false)))
                            }
                        } catch {
                            Log "  WARNING: could not refresh version label in loading.html: $_"
                        }
                    }
                } else {
                    Log "  WARNING: Could not determine DSH version (got: '$dshVersion')"
                }
                break
            }

            # --- This attempt failed: clean up before trying the next ---
            if ($cmdProc -and -not $cmdProc.HasExited) {
                Stop-ProcessTree $cmdProc.Id
            }
            $leftover = Get-ServerPid
            if ($leftover) {
                Stop-ProcessTree $leftover
            }
            Start-Sleep -Seconds 2
            if ($chromeProc -and -not $chromeProc.HasExited) {
                Stop-Process -Id $chromeProc.Id -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not $serverReady -and -not $userClosedWindow) {
            Show-LaunchError "DSH failed to start (range '$dshRange' and fallback $fallbackVersion). Run dsh-version.ps1 to check versions."
            Log "  All launch attempts failed"
        } elseif ($userClosedWindow) {
            Log "  Launch aborted by user (loading window closed) — cleaning up silently"
        }

        Wait-ForProcessExit $chromeProc "Chrome"
    }

    # ---- Cleanup ----
    Log "Cleanup: stopping DSH server..."
    Start-Sleep -Seconds 2

    if ($ownsServer) {
        $trackedPid = Get-Content $lockFile -ErrorAction SilentlyContinue
        if ($trackedPid -match '^\d+$' -and [int]$trackedPid -ne $pid) {
            $trackedProc = Get-Process -Id $trackedPid -ErrorAction SilentlyContinue
            if ($trackedProc) {
                Log "  stopping process PID=$trackedPid ($($trackedProc.ProcessName))"
                Stop-ProcessTree $trackedPid
            }
        }

        if ($cmdProc -and -not $cmdProc.HasExited) {
            Stop-ProcessTree $cmdProc.Id
        }

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
