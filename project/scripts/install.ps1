# ============================================================================
# DeepSeek Harness - Desktop App Installer
# ============================================================================
# Creates/updates the desktop shortcut that launches DSH silently:
#   Desktop "DeepSeek Harness" shortcut
#     → wscript.exe "DeepSeek Harness.vbs"
#       → powershell.exe -WindowStyle Hidden
#         → launcher.ps1 → pnpm dlx @deepseek-ai/dsh --profile web --patch desktop.patch.yml → Chrome --app=...
# ============================================================================
# Usage:
#   powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh\scripts\install.ps1"
# ============================================================================

$ErrorActionPreference = "Stop"

# ---- Configurable paths ----
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { "$env:USERPROFILE\.dsh" }
$scriptsDir = "$dshHome\scripts"
$launcherPath = "$scriptsDir\launcher.ps1"
$vbsPath = "$scriptsDir\DeepSeek Harness.vbs"
$icoPath = "$scriptsDir\dsh.ico"
$desktopDir = [Environment]::GetFolderPath("Desktop")
$shortcutPath = "$desktopDir\DeepSeek Harness.lnk"

# Workspace directory — read from workdir.txt if present, else default
$workDirCfg = "$scriptsDir\workdir.txt"
$workDir = $env:USERPROFILE                             # fallback default
if (Test-Path $workDirCfg) {
    $txt = (Get-Content $workDirCfg -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($txt) { $workDir = $txt }
}

Write-Host "=== DeepSeek Harness Desktop App Installer ===" -ForegroundColor Cyan
Write-Host ""

# ---- Step 1: Verify prerequisites ----
Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Test-Path $scriptsDir)) {
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    Write-Host "  Created scripts directory" -ForegroundColor Yellow
}

# Verify launcher.ps1 exists
if (-not (Test-Path $launcherPath)) {
    Write-Host "  ERROR: launcher.ps1 not found at $launcherPath" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] launcher.ps1 found" -ForegroundColor Green

# Verify VBS wrapper exists
if (-not (Test-Path $vbsPath)) {
    Write-Host "  ERROR: VBS wrapper not found at $vbsPath" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] DeepSeek Harness.vbs found" -ForegroundColor Green

# Verify profile config
$patchPath = "$dshHome\profiles\web\cordis.patch.yml"
if (Test-Path $patchPath) {
    $content = Get-Content $patchPath -Raw
    if ($content -match "printUrl:\s*true") {
        Write-Host "  [OK] cordis.patch.yml configured (printUrl: true)" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] cordis.patch.yml: printUrl should be 'true'" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [WARN] Profile config not found at $patchPath" -ForegroundColor Yellow
}

# ---- Step 2: Icon status ----
Write-Host ""
Write-Host "[2/5] Checking icon..." -ForegroundColor Yellow

if (Test-Path $icoPath) {
    Write-Host "  [OK] dsh.ico ready" -ForegroundColor Green
} else {
    Write-Host "  [WARN] dsh.ico not found — shortcut will use default icon" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  === Manual Icon Setup ===" -ForegroundColor Cyan
    Write-Host "  1. Start DSH: pnpm dlx @deepseek-ai/dsh web" -ForegroundColor Cyan
    Write-Host "  2. Open http://127.0.0.1:3080/favicon.svg in browser" -ForegroundColor Cyan
    Write-Host "  3. Save the SVG content as favicon.svg" -ForegroundColor Cyan
    Write-Host "  4. Visit https://convertio.co/svg-ico/ to convert SVG to ICO" -ForegroundColor Cyan
    Write-Host "  5. Place dsh.ico at: $icoPath" -ForegroundColor Cyan
    Write-Host "  6. Re-run this script to apply the icon to the shortcut" -ForegroundColor Cyan
    Write-Host ""
}

# ---- Step 3: Check for existing shortcut ----
Write-Host "[3/5] Checking existing shortcut..." -ForegroundColor Yellow
if (Test-Path $shortcutPath) {
    Write-Host "  Existing shortcut found — will replace" -ForegroundColor Yellow
} else {
    Write-Host "  No existing shortcut — creating new" -ForegroundColor Gray
}

# ---- Step 4: Create Desktop Shortcut ----
Write-Host "[4/5] Creating desktop shortcut..." -ForegroundColor Yellow

$WScriptShell = New-Object -ComObject WScript.Shell
$shortcut = $WScriptShell.CreateShortcut($shortcutPath)

# Target: the VBS file itself — Windows executes .vbs natively (no System32 path needed)
# The shortcut points entirely within the .dsh project folder. Clean and portable.
$shortcut.TargetPath = $vbsPath
$shortcut.Arguments = ""
$shortcut.WorkingDirectory = $workDir
$shortcut.Description = "DeepSeek Harness — AI coding agent (DSH Web + Chrome app window)"

if (Test-Path $icoPath) {
    $shortcut.IconLocation = "$icoPath, 0"
}

$shortcut.Save()

if (Test-Path $shortcutPath) {
    Write-Host "  [OK] Shortcut created: $shortcutPath" -ForegroundColor Green
} else {
    Write-Host "  ERROR: Failed to create shortcut" -ForegroundColor Red
    exit 1
}

# ---- Step 5: Summary ----
Write-Host ""
Write-Host "[5/5] Installation Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "  Installation Complete!" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "  Shortcut   : DeepSeek Harness.lnk" -ForegroundColor Cyan
Write-Host "  Target     : DeepSeek Harness.vbs (in project folder)" -ForegroundColor Cyan
Write-Host "  Start in   : $workDir" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  VBS →      : powershell.exe -WindowStyle Hidden" -ForegroundColor DarkGray
Write-Host "  PS1 →      : launcher.ps1 → pnpm dlx + Chrome" -ForegroundColor DarkGray
Write-Host "  Log        : $dshHome\scripts\dsh-launch.log" -ForegroundColor DarkGray
Write-Host "  Work Dir   : $workDir  (edit workdir.txt to change)" -ForegroundColor DarkGray
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Usage  : Double-click desktop icon to start" -ForegroundColor Gray
Write-Host "  Close  : Close the Chrome app window → DSH auto-stops" -ForegroundColor Gray
Write-Host ""
Write-Host "  Portable: Copy entire .dsh folder to another PC," -ForegroundColor Gray
Write-Host "           edit workdir.txt → run this script → ready." -ForegroundColor Gray