# ============================================================================
# DSH Version Manager (dependency-management model)
# ============================================================================
# DSH is run via `pnpm dlx @deepseek-ai/dsh@"<semver range>"` where the range
# is declared in workspace package.json. This tool updates the range via
# `pnpm add` and records the resolved version. An exact @<version> is never
# used at launch time — only semver ranges.
# The launcher runs `pnpm dlx @deepseek-ai/dsh@"<range>"` (range from package.json)
# — never an exact @<version> pin. This tool updates the range via `pnpm add`.
#
# Usage:
#   dsh-version.ps1 status          Show installed + fallback versions
#   dsh-version.ps1 list            List available DSH versions (npm registry)
#   dsh-version.ps1 pin <version>   Install a version via pnpm add (replaces lockfile entry)
#   dsh-version.ps1 rollback        Reinstall lastKnownGood via pnpm add
#   dsh-version.ps1 set-fallback <version>  Set the fallback (lastKnownGood) version
# ============================================================================

$ErrorActionPreference = "Stop"

$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { "$env:USERPROFILE\.dsh" }
$versionConfigPath = "$dshHome\scripts\dsh-version.json"
$workDirCfg = "$dshHome\scripts\workdir.txt"
$workDir = $env:USERPROFILE
if (Test-Path $workDirCfg) {
    $txt = (Get-Content $workDirCfg -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($txt -and (Test-Path $txt)) { $workDir = $txt }
}

function Read-Config {
    if (-not (Test-Path $versionConfigPath)) {
        Write-Host "ERROR: version config not found at $versionConfigPath" -ForegroundColor Red
        exit 1
    }
    return (Get-Content $versionConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-Config($cfg) {
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $versionConfigPath -Encoding UTF8
}

# Resolves the DSH version via pnpm dlx with the semver range from package.json.
function Get-LocalVersion {
    $pkgPath = Join-Path $workDir "package.json"
    if (Test-Path $pkgPath) {
        try {
            $pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $range = $pkg.dependencies.'@deepseek-ai/dsh'
            if ($range) {
                Push-Location $workDir
                try {
                    $raw = & pnpm.cmd dlx "@deepseek-ai/dsh@$range" --version 2>$null
                    if ($raw -match '(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)') {
                        return $Matches[1]
                    }
                } finally { Pop-Location }
            }
        } catch {}
    }
    return $null
}

function Show-Status {
    $cfg = Read-Config
    $local = Get-LocalVersion
    if (-not $local) { $local = "not installed" }
    Write-Host ""
    Write-Host "=== DSH Version Status ===" -ForegroundColor Cyan
    Write-Host "  Installed (pnpm): $local" -ForegroundColor Green
    Write-Host "  Fallback (LKG)  : $($cfg.lastKnownGood)" -ForegroundColor Yellow
    Write-Host "  Auto-update     : $($cfg.autoUpdate)"
    Write-Host "  Update channel  : $($cfg.updateChannel)"
    Write-Host ""
    Write-Host "  History:" -ForegroundColor Gray
    foreach ($h in $cfg.history) {
        $marker = if ($h.status -eq "current") { "<<" } elseif ($h.status -eq "fallback") { "<=" } else { "  " }
        Write-Host "    $marker $($h.version)  [$($h.status)]  $($h.date)  $($h.note)"
    }
    Write-Host ""
}

function List-Versions {
    Write-Host "Fetching available versions from npm registry..." -ForegroundColor Gray
    $versions = pnpm.cmd view @deepseek-ai/dsh versions --json 2>$null | ConvertFrom-Json
    Write-Host ""
    Write-Host "=== Available DSH Versions (newest last) ===" -ForegroundColor Cyan
    foreach ($v in $versions) { Write-Host "  $v" }
    Write-Host ""
    Write-Host "Latest: $($versions[-1])" -ForegroundColor Green
}

function Pin-Version($version) {
    if (-not $version) {
        Write-Host "ERROR: version required. Usage: dsh-version.ps1 pin <version>" -ForegroundColor Red
        exit 1
    }
    Write-Host "Installing DSH version via pnpm add: $version" -ForegroundColor Cyan

    Write-Host "  Running: pnpm add @deepseek-ai/dsh@$version" -ForegroundColor Gray
    Push-Location $workDir
    try {
        & pnpm.cmd add "@deepseek-ai/dsh@$version" 2>&1 | Out-Null
    } catch {
        Write-Host "ERROR: pnpm add failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location

    $installed = Get-LocalVersion
    if ($installed -notmatch '^\d+\.\d+\.\d+') {
        Write-Host "ERROR: installation failed (got version: '$installed')" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Installed: v$installed" -ForegroundColor Green

    $cfg = Read-Config
    $oldInstalled = $cfg.installedVersion

    if ($oldInstalled -ne $version) {
        $cfg.lastKnownGood = $oldInstalled
        $historyEntry = [PSCustomObject]@{
            version = $version
            date    = (Get-Date -Format 'yyyy-MM-dd')
            status  = "current"
            note    = "Installed via pnpm add"
        }
        foreach ($h in $cfg.history) {
            if ($h.status -eq "current") { $h.status = "fallback" }
        }
        $cfg.history = @($historyEntry) + $cfg.history
    }

    $cfg.installedVersion = $version
    Write-Config $cfg

    Write-Host ""
    Write-Host "  Installed version : $version" -ForegroundColor Green
    Write-Host "  Fallback (LKG)    : $($cfg.lastKnownGood)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Lockfile updated. Next launch uses this version." -ForegroundColor Cyan
}

function Rollback {
    $cfg = Read-Config
    if (-not $cfg.lastKnownGood) {
        Write-Host "ERROR: no fallback version configured" -ForegroundColor Red
        exit 1
    }
    Write-Host "Rolling back to: $($cfg.lastKnownGood)" -ForegroundColor Cyan
    Pin-Version $cfg.lastKnownGood
}

function Set-Fallback($version) {
    if (-not $version) {
        Write-Host "ERROR: version required. Usage: dsh-version.ps1 set-fallback <version>" -ForegroundColor Red
        exit 1
    }
    $cfg = Read-Config
    $cfg.lastKnownGood = $version
    Write-Config $cfg
    Write-Host "Fallback version set to: $version" -ForegroundColor Green
}

# ---- Main ----
$action = $args[0]
switch ($action) {
    "status"    { Show-Status }
    "list"      { List-Versions }
    "pin"       { Pin-Version $args[1] }
    "rollback"  { Rollback }
    "set-fallback" { Set-Fallback $args[1] }
    default {
        Write-Host "DSH Version Manager" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "  dsh-version.ps1 status              Show current versions"
        Write-Host "  dsh-version.ps1 list                List available versions"
        Write-Host "  dsh-version.ps1 pin <version>       Install a version via pnpm add"
        Write-Host "  dsh-version.ps1 rollback            Reinstall lastKnownGood"
        Write-Host "  dsh-version.ps1 set-fallback <ver>  Set the fallback version"
        Write-Host ""
        Show-Status
    }
}
