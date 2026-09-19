# ============================================================================
# post-install.ps1 — runs after the Inno Setup installer copies files.
#   1. Creates the workspace directory structure
#   2. Writes workdir.txt pointing at the workspace
#   3. Creates profiles/web/ package.json
#   4. Writes workspace package.json with @deepseek-ai/dsh ^0.1.5
#   5. (optional) Sets DSH_HOME user environment variable
# Args: <installDir>
# ============================================================================
param([Parameter(Mandatory = $true)][string]$InstallDir)

$ErrorActionPreference = "Continue"

# Workspace defaults to %USERPROFILE%\dsh-workspace
$workspace = Join-Path $env:USERPROFILE "dsh-workspace"
$profilesDir = Join-Path $workspace "profiles"
$webProfileDir = Join-Path $profilesDir "web"

Write-Host "=== DeepSeek Harness post-install configuration ==="
Write-Host "  Install dir : $InstallDir"
Write-Host "  Workspace   : $workspace"

# 1. Create workspace + profile dirs
New-Item -ItemType Directory -Path $workspace -Force | Out-Null
New-Item -ItemType Directory -Path $webProfileDir -Force | Out-Null
Write-Host "  Created workspace directories"

# 2. Write workdir.txt in the install dir
$workdirTxt = Join-Path $InstallDir "workdir.txt"
Set-Content -Path $workdirTxt -Value $workspace -Encoding ASCII -ErrorAction SilentlyContinue
Write-Host "  Wrote workdir.txt -> $workspace"

# 3. profiles/web/package.json (DSH profile)
$profilePkg = Join-Path $webProfileDir "package.json"
if (-not (Test-Path $profilePkg)) {
    $profileJson = @'
{
  "name": "dsh-web-profile",
  "version": "1.0.0",
  "private": true,
  "dependencies": {}
}
'@
    Set-Content -Path $profilePkg -Value $profileJson -Encoding UTF8
    Write-Host "  Created profiles/web/package.json"
}

# 4. Workspace package.json — declares @deepseek-ai/dsh via semver range
$wsPkg = Join-Path $workspace "package.json"
if (-not (Test-Path $wsPkg)) {
    $wsJson = @'
{
  "name": "dsh-workspace",
  "version": "1.1.0",
  "description": "DSH workspace — managed via pnpm lockfile (no launch-time version pinning)",
  "dependencies": {
    "@deepseek-ai/dsh": ">=0.1.5-rc.1 <0.1.5-rc.2"
  },
  "devDependencies": {},
  "scripts": {
    "dsh:version": "dsh --version",
    "dsh:web": "dsh web",
    "dsh:update": "pnpm update @deepseek-ai/dsh",
    "dsh:check": "pnpm outdated @deepseek-ai/dsh"
  },
  "packageManager": "pnpm@9.0.0",
  "engines": {
    "node": ">=18",
    "pnpm": ">=8"
  }
}
'@
    Set-Content -Path $wsPkg -Value $wsJson -Encoding UTF8
    Write-Host "  Created workspace package.json"
} else {
    Write-Host "  workspace package.json already exists — skipping"
}

# 5. Set DSH_HOME user env var (skip if installer already set it)
$currentDshHome = [Environment]::GetEnvironmentVariable("DSH_HOME", "User")
if (-not $currentDshHome) {
    [Environment]::SetEnvironmentVariable("DSH_HOME", $InstallDir, "User")
    Write-Host "  Set DSH_HOME user env var -> $InstallDir"
} else {
    Write-Host "  DSH_HOME already set to: $currentDshHome"
}

Write-Host "=== Post-install complete ==="
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open a NEW terminal (so DSH_HOME takes effect)"
Write-Host "  2. cd $workspace"
Write-Host "  3. pnpm install   (this downloads @deepseek-ai/dsh and creates pnpm-lock.yaml)"
Write-Host "  4. Launch DeepSeek Harness from the Start Menu"
