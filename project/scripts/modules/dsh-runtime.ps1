# ============================================================================
# dsh-runtime.ps1 — DSH version config, launch command, health probe, token
# Dot-sourced by launcher.ps1. Expects $versionConfigPath, $processOutputPath,
# $processErrorPath, $url, $tokenJsPath, $upgradeTimeout, $workDir to be defined.
#
# DEPENDENCY MANAGEMENT (no @<exact-version> pinning):
#   DSH is declared in the workspace package.json with a SEMVER RANGE, e.g.
#   ">=0.1.5-rc.1 <0.1.5-rc.2". The launcher runs
#   `pnpm dlx @deepseek-ai/dsh@"<range>"` which resolves to the latest matching
#   version (cached after first run). An exact version like @0.1.5-rc.1 is
#   NEVER used — only ranges, so compatible updates are picked up automatically
#   while destructive releases (e.g. 0.1.6-alpha) are excluded by the range cap.
#   dsh-version.json tracks the resolved version + lastKnownGood for reporting.
# ============================================================================

function Get-DshVersionConfig {
    param([string]$ConfigPath = $versionConfigPath)
    $defaults = [PSCustomObject]@{
        installedVersion = ""
        lastKnownGood    = "0.1.5-rc.1"
        autoUpdate       = $false
        updateChannel    = "rc"
        history          = @()
    }
    if (-not (Test-Path $ConfigPath)) { return $defaults }
    try {
        $raw = Get-Content $ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop
        $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $cfg.lastKnownGood) { $cfg | Add-Member -NotePropertyName lastKnownGood -NotePropertyValue $defaults.lastKnownGood -Force }
        if ($null -eq $cfg.autoUpdate)  { $cfg | Add-Member -NotePropertyName autoUpdate -NotePropertyValue $false -Force }
        if (-not $cfg.history)          { $cfg | Add-Member -NotePropertyName history -NotePropertyValue @() -Force }
        if (-not $cfg.installedVersion) { $cfg | Add-Member -NotePropertyName installedVersion -NotePropertyValue "" -Force }
        return $cfg
    } catch {
        return $defaults
    }
}

# Reads the semver range from workspace package.json dependencies.
# Falls back to a safe default if package.json is missing or malformed.
function Get-DshVersionRange {
    param([string]$Workspace = $workDir)
    $pkgPath = Join-Path $Workspace "package.json"
    if (Test-Path $pkgPath) {
        try {
            $pkg = Get-Content $pkgPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            $range = $pkg.dependencies.'@deepseek-ai/dsh'
            if ($range) { return $range }
        } catch {}
    }
    return ">=0.1.5-rc.1 <0.1.5-rc.2"
}

# Resolves the actual DSH version by running `pnpm dlx @deepseek-ai/dsh@"<range>" --version`.
# Uses a semver RANGE — never an exact @<version> pin.
function Get-DshInstalledVersion {
    param([string]$Workspace = $workDir, [int]$TimeoutSec = 20)
    $range = Get-DshVersionRange -Workspace $Workspace
    $job = Start-Job -ScriptBlock {
        param($ws, $r)
        Push-Location $ws
        try { & pnpm.cmd dlx "@deepseek-ai/dsh@$r" --version 2>&1 | Select-Object -First 1 }
        finally { Pop-Location }
    } -ArgumentList $Workspace, $range
    $version = $null
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $version = (Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -First 1).ToString().Trim()
    } else {
        Log "  WARNING: dsh --version timed out after ${TimeoutSec}s"
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($version -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { return $version }
    return $null
}

function Get-DshFallbackVersion {
    $cfg = Get-DshVersionConfig
    $installed = Get-DshInstalledVersion
    if ($cfg.lastKnownGood -and $cfg.lastKnownGood -ne $installed) {
        return $cfg.lastKnownGood
    }
    return $null
}

# Health probe: the Web GUI answers 401 to unauthenticated requests, which
# still proves the server is up. Only a transport failure means "not running".
function Test-DshServing {
    param([string]$Url = $url, [int]$TimeoutSec = 3)
    try {
        $resp = Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500)
    } catch {
        $code = 0
        $r = $_.Exception.Response
        if ($r -and $r.StatusCode) {
            try { $code = [int]$r.StatusCode } catch { $code = 0 }
        }
        return ($code -eq 401 -or $code -eq 403)
    }
}

function Get-DshToken {
    $out = Get-RecentFileText $processOutputPath
    if ($out -match '\?token=([A-Za-z0-9_\-]+)') { return $Matches[1] }
    return $null
}

function Reset-TokenJs {
    Set-Content -Path $tokenJsPath -Value 'window.__DSH_TOKEN__ = "";' -Encoding ASCII -ErrorAction SilentlyContinue
}

function Publish-TokenJs {
    param([Parameter(Mandatory = $true)][string]$Token)
    Set-Content -Path $tokenJsPath -Value ('window.__DSH_TOKEN__ = "' + $Token + '";') -Encoding ASCII -ErrorAction SilentlyContinue
}

# Returns true when the DSH process output shows a pnpm install prompt that has
# been waiting longer than $upgradeTimeout.
function Test-UpgradePromptStuck {
    param([datetime]$PromptSeenAt)
    if (-not $PromptSeenAt) { return $false }
    return (((Get-Date) - $PromptSeenAt).TotalSeconds -ge $upgradeTimeout)
}
