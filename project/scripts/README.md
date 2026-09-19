# DeepSeek Harness — Desktop App Launcher

## Overview
Completely hidden launcher that starts the DSH web server, waits for the one-time token it prints a few seconds later, and then opens a Chrome app window **already authenticated**, so the GUI loads on the first try. If startup runs long — a package upgrade, say — it falls back to a loading page with progress instead of leaving the user staring at a blank desktop.

## Architecture
Two launcher paths, one engine:

- **Installed app (EXE installer)** — Start-Menu/Desktop shortcut → `wscript.exe //B launch-dsh.vbs "{app}"` (GUI subsystem, zero console flash) → hidden PowerShell → `launcher.ps1`
- **Dev copy** — desktop shortcut points at `DeepSeek Harness.vbs` inside the project (created by `install.ps1`)

```
launcher.ps1
  → Pre-flight checks (Node.js, pnpm, Chrome) — fast, nothing blocking
  → If DSH already running:
      → Opens Chrome at the live session's tokenised URL (instant, authenticated)
  → If DSH not running (cold start):
      → Opens the loading.html window IMMEDIATELY (~2s after the double-click)
      → Start-Process cmd.exe -WindowStyle Hidden
        → (echo y)|pnpm dlx @deepseek-ai/dsh@"<semver range>" --profile web --patch desktop.patch.yml
        → (range read from workspace package.json; never an exact @<version> pin)
      → Waits up to 20s for the "?token=..." line DSH prints while booting
          → Token seen  → swaps the loading window for Chrome at the tokenised URL
                          (browser-initiated navigation keeps the Strict cookie flowing)
          → No token yet → keeps the loading window; the page polls token.js every 1.5s
                           and redirects itself once the token lands (one reload on 401)
      → Version check (`pnpm dlx ... --version`, up to 20s) runs only AFTER the server
        is ready — it must never sit between the double-click and the first window
  → On Chrome close → stops DSH server (process-specific cleanup)
```

## Key Features
- **Instant startup feedback** — the loading window appears ~2 seconds after the double-click (the old flow stayed blank for 6-20s); status text is localised and shows elapsed seconds from the first tick
- **Authenticated on the first try** — the loading window is swapped for Chrome at the tokenised URL the moment the token lands; that is the only navigation the auth cookie survives (see below)
- **Slow-boot fallback** — if the token is late, the loading page stays up with visible progress instead of a blank wait
- **Data-safe by design** — DSH data (profiles/sessions/credentials) always lives in `%USERPROFILE%\.dsh`, never inside the install dir; reinstall/upgrade/uninstall keeps user data
- **No console windows** — wscript + VBS + hidden PowerShell + hidden pnpm: nothing flashes
- **Chrome standalone window** — dedicated `--user-data-dir` so the spawned chrome.exe is the window-lifetime process (no handoff to an already-running Chrome)
- **Clean uninstall tool** — Start-Menu「完全卸载 DeepSeek Harness」(`CleanUninstall.exe`) stops processes, removes leftovers the standard uninstaller misses, and optionally clears user data
- **PID lock file** — Prevents duplicate instances (tracks the actual server PID via port detection)
- **Process-specific cleanup** — Kills only the DSH node process, never other Node.js apps
- **Auto cleanup** — Stops DSH when Chrome closes
- **Chrome location auto-detect** — Searches multiple standard install paths
- **Log rotation** — Keeps last 500 lines / 1 MB to prevent unbounded growth
- **Pre-flight checks** — Verifies Node.js, pnpm, and Chrome before launching
- **Automatic upgrade confirmation** — Sends the default `y` response when pnpm asks to install a newer DSH package
- **Startup safety timeout** — Stops and reports a launch that produces no output for 30 seconds or does not become ready within 120 seconds
- **Launch error page** — Shows unexpected DSH errors in the app window and records them in the launch log
- **Zombie lock recovery** — Clears an orphaned `<file>.lock` left behind by a crashed or force-killed run before a cold start. `dsh-atomic-write` deliberately never reclaims an orphaned lock ("orphan recovery is an operator action"), so without this the next launch dies on `timed out waiting for the writer lock`
- **Auth-aware readiness probe** — The Web GUI answers `401` to any request without its auth cookie. That is treated as "server is up and serving", not "server is absent"; only a transport failure counts as down

## Data Directory
The launcher always forces `DSH_HOME=%USERPROFILE%\.dsh` for the DSH child process, and the
installer deletes any machine-specific `DSH_HOME` user env var it once set. Profiles, sessions
and credentials therefore live in the persistent user directory — never inside the install dir
(which is wiped on uninstall). The launcher resolves its own assets relative to its script
location, so the dev copy (`~\.dsh\scripts`) and the installed copy (`{app}\scripts`) coexist
without interfering.

## Web GUI authentication

The Web GUI sits behind a browser auth cookie (introduced with DSH `0.1.5-rc.x`; earlier builds served the page freely).

- A request without the cookie gets `401`, and `Invoke-WebRequest` raises on any non-2xx status. A naive `StatusCode -eq 200` check therefore reads a healthy server as down and burns the entire startup timeout before reporting failure.
- DSH prints a one-time URL at startup: `http://127.0.0.1:3080/?token=...`. Visiting it sets a 30-day cookie and redirects to the clean URL.
- **That cookie is signed with a persistent key and survives DSH restarts** — the token itself changes on every launch, but an already-authenticated browser keeps working with no token at all. This is why the normal path needs no token.
- The launcher records the tokenised URL in the launch log as `Auth URL (needed only if the browser shows 401): ...`.
- **The cookie is `SameSite=Strict`, and that fact decides the whole design.** Measured with the Chrome DevTools Protocol on fresh profiles:

  | Entry point | Cookie stored | Result |
  |---|---|---|
  | `http://127.0.0.1:3080/?token=…` opened by the browser | yes | GUI loads |
  | `file://…/loading.html` redirecting to the same URL | yes | `401` |

  The token exchange succeeds either way — the cookie really does land in the jar — but on the `file://` path Chrome treats the navigation chain as cross-site (the opaque `file` origin is the initiator) and **withholds** the Strict cookie on the very redirect that needs it. A splash page therefore cannot finish the handshake by itself, no matter how the token reaches it.
- Hence the launcher **waits for the token and opens Chrome at the tokenised URL**: a browser-initiated navigation is same-site, so the cookie is sent and the GUI loads on the first try. DSH prints the token about 4-6s into a warm boot, so the wait is short.
- `loading.html` and `token.js` are kept for the slow-boot fallback (a package upgrade can take minutes). The page still receives the token through a `<script>` tag — a `file://` page may not `fetch()` a sibling file, but it may *load* one — and the cookie still gets stored. If that page ends up showing `401`, **one reload is enough**: the cookie is already in the jar, and a reload is same-site.
- If no token shows up within 20 seconds of the server answering, the loading page falls back to the plain URL, which is correct for a browser that already holds the cookie.
- `token.js` is blanked by the launcher before every open, so a token from an earlier run can never point the browser at a session that has already exited.

## Splash screen (loading.html)

The loading window is the only feedback a cold start has, and it had two independent failure modes
that both present as "the splash screen does not appear". Both were fixed in **1.2.1** — do not
undo either one.

### 1. The `file://` URL must be percent-encoded

A child process receives its arguments as **one command line** and re-splits it on whitespace, so a
raw path breaks the moment it contains a space — and the default install target does exactly that:

```
--app=file:///C:/Users/<user>/AppData/Local/Programs/DeepSeek Harness/scripts/loading.html
```

Chrome received **two** arguments, opened the truncated `file:///.../Programs/DeepSeek`
(file not found) and the splash page never loaded. The evidence is still in the browser profile:
`chrome-profile\Default\Sessions\*` records that cut-off URL verbatim. The dev copy lives in
`%USERPROFILE%\.dsh`, which contains no space, and that is why the fault stayed invisible until the
packaged app was run.

- `ConvertTo-FileUrl` in `modules\chrome-launcher.ps1` percent-encodes the path
  (`ConvertTo-FileUrl "C:\a b\x.html"` → `file:///C:/a%20b/x.html`). It also handles non-ASCII
  user names (`%E4%B8%AD%E6%96%87`) and UNC paths, and `[System.Uri]` round-trips all of them.
- `Launch-Chrome` additionally quotes the `--app` value, so a caller that forgets to escape still
  passes a single argument.
- `launch-error.html` was assembled the same way and had the same defect; it now uses the helper too.

### 2. Never read/write `loading.html` without an explicit encoding

`loading.html` is UTF-8 **without a BOM** and carries Chinese status text. A bare `Get-Content`
on Windows PowerShell 5.1 falls back to the **ANSI code page** (GBK here), so the version-label
refresh read `正在启动服务...` as `姝ｅ湪鍚姩鏈嶅姟...` and wrote the mojibake back out as UTF-8.
Worse, GBK cannot map every byte pair and substitutes `?` — which swallowed the closing quote of a
JS string literal inside `showError(...)`, breaking the whole `<script>` block. The page then
rendered but never polled `token.js` or redirected.

The refresh now uses `[System.IO.File]::ReadAllText` / `WriteAllText` with an explicit UTF-8
encoding and writes back without a BOM. Measured regression check on a copy of the real file:
source 5759 bytes / 122 double-quotes → old path 5865 bytes / 120 quotes (two quotes lost),
new path 5749 bytes / 122 quotes (only the intended `v0.1.5-rc.X` shrink). `scripts\workdir.txt` is
read with `-Encoding UTF8` for the same reason.

## Usage
Double-click "DeepSeek Harness" desktop icon.
A loading window appears within ~2 seconds — no more blank-desktop guessing about whether the
double-click registered. On a warm start (~4-6s) it is swapped for the authenticated app window;
on a slow start (a package upgrade, for instance) it stays up and shows progress until the GUI
is ready.
Close the window → DSH auto-terminates.

### PowerShell shortcut

To start DSH from any project directory with `dshweb`, add this function to your PowerShell profile:

```powershell
# Create the profile file first if it does not exist
New-Item -Path $PROFILE -Type File -Force
Add-Content -Path $PROFILE -Value @'
function dshweb {
    $url = 'http://127.0.0.1:3080'
    # A bare request answering 401/403 still proves the server is up: the new
    # DSH Web GUI is cookie-authenticated, and Invoke-WebRequest throws on any
    # non-2xx status. Testing for 200 alone therefore misreads a live server as
    # down, starts a second instance and fails with EADDRINUSE.
    $alive = $false
    try {
        $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        $alive = $true
    } catch {
        try { if ([int]$_.Exception.Response.StatusCode -in 401, 403) { $alive = $true } } catch {}
    }
    if ($alive) {
        Start-Process $url
        return
    }
    $range = (Get-Content package.json -Raw | ConvertFrom-Json).dependencies.'@deepseek-ai/dsh'
    $version = (& pnpm.cmd dlx "@deepseek-ai/dsh@$range" --version 2>$null | Select-Object -First 1)
    if ($version) { Write-Host "DeepSeek Harness v$version" }
    'y' | & pnpm.cmd dlx "@deepseek-ai/dsh@$range" web
}
'@
```

Restart PowerShell, then run `dshweb`. If the `.dsh` folder is stored somewhere other than `%USERPROFILE%\.dsh`, set `DSH_HOME` to that folder before running the desktop launcher. The `dshweb` function runs from the current directory and does not depend on `DSH_HOME`.

For an already-open PowerShell session, run `. $PROFILE` once instead of restarting the terminal.

The first run, or a later package upgrade, may display an installation confirmation. The desktop launcher answers `y` automatically; the interactive `dshweb` command can be confirmed in the terminal.

The desktop launcher passes `desktop.patch.yml`, which sets `openBrowser: false` because it opens its own Chrome app window after starting the server. The `dshweb` shortcut reuses an already-running service on port 3080, or starts one when needed, and opens the default browser.

The current official Web frontend does not expose the CLI version as a configurable top-left label. `dshweb` prints the official version obtained from `pnpm dlx @deepseek-ai/dsh --version`, and the desktop launcher fills the current version into the loading page at startup. The packaged Web UI still keeps its built-in `DeepSeek Harness` label; changing that label would require rebuilding or modifying the official frontend package and would be overwritten on upgrade.

## Configuration
Edit variables at the top of `launcher.ps1`:
- `$workDir` — your project working directory (default: `D:\WorkSpace\dsh`)
- `$startupTimeout` — max seconds to wait for server (default: `120`)
- `$tokenWaitSeconds` — max seconds to wait for the startup token before falling back to the loading page (default: `20`)
- `$maxLogBytes` / `$maxLogLines` — log rotation thresholds

## Dependency Management (stability)

DSH releases frequent rc builds with breaking changes. The launcher **never** uses an exact version pin like `@deepseek-ai/dsh@0.1.5-rc.1` at runtime. Instead, it reads a **semver range** from the workspace `package.json` and runs `pnpm dlx @deepseek-ai/dsh@"<range>"`, which resolves to the latest matching version (cached after first run).

The workspace `package.json` declares:

```json
{
  "dependencies": {
    "@deepseek-ai/dsh": ">=0.1.5-rc.1 <0.1.5-rc.2"
  },
  "packageManager": "pnpm@9.0.0",
  "engines": { "node": ">=18", "pnpm": ">=8" }
}
```

- **`>=0.1.5-rc.1 <0.1.5-rc.2`** — a semver range (not an exact `@<version>` pin). Currently caps below rc.2 because `0.1.5-rc.2` has a broken `@deepseek-ai/dsh-type-meta` dependency that 404s on the npm registry. Widen to `<0.1.6` once a fixed rc is released.
- **`pnpm dlx` with range** — the launcher runs `pnpm dlx @deepseek-ai/dsh@">=0.1.5-rc.1 <0.1.5-rc.2"`, resolving to the latest version in range. The package is cached after first download.
- **`dsh-version.json`** tracks the resolved version + `lastKnownGood` fallback for reporting; it does not pin.
- **Updates** are controlled by editing the range in `package.json` (e.g. widening to `<0.1.6`).

Manage versions with `dsh-version.ps1`:

```powershell
dsh-version.ps1 status              # show resolved (pnpm dlx) + fallback versions
dsh-version.ps1 list                # list all available DSH versions
dsh-version.ps1 pin 0.1.5-rc.3      # update package.json range + pnpm add (updates lockfile)
dsh-version.ps1 rollback            # reinstall lastKnownGood via pnpm add
dsh-version.ps1 set-fallback 0.1.5-rc.1  # set the fallback version
```

`pin` runs `pnpm add @deepseek-ai/dsh@<version>` and promotes the previous version to `lastKnownGood`, giving you a one-click rollback via `rollback`.

## Install / Refresh Shortcut
```powershell
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh\scripts\install.ps1"
```

## EXE Installer (Inno Setup)

A graphical, fully localised Chinese installer is provided in `installer/dsh-setup.iss`
(current version **1.2.1**).

### Build the installer EXE

1. Install Inno Setup 6:
   ```powershell
   winget install --id JRSoftware.InnoSetup --exact
   ```
2. Generate the wizard brand images and compile the clean-uninstall tool (one-time):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\gen-images.ps1
   csc /nologo /target:winexe /out:CleanUninstall.exe /r:System.dll /r:System.Core.dll `
       /r:System.Management.dll /r:System.Windows.Forms.dll `
       /win32icon:..\dsh.ico /codepage:65001 CleanUninstall.cs
   ```
   (`csc` ships with .NET Framework 4 at `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\`)
3. Compile (ISCC location differs for per-user vs machine-wide installs):
   ```powershell
   $iscc = @(
     "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
     "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
   ) | Where-Object { Test-Path $_ } | Select-Object -First 1
   & $iscc "c:\Users\gavan\.dsh\scripts\installer\dsh-setup.iss"
   ```
4. The output EXE is written to `installer\Output\DeepSeekHarness-Setup-<version>.exe`.

### What the installer does

- **Fully localised Chinese wizard** — welcome / license / directory / environment-detection
  (Node.js, pnpm, Chrome with re-check button) / step-by-step progress / completion pages.
- Installs all scripts + `modules\` to the chosen directory; the clean-uninstall tool goes to
  `{app}` root.
- Creates **Start Menu** shortcuts (app / uninstall / **完全卸载**) and a **desktop** shortcut
  (**checked by default**).
- Completion page has **no launch option** (changed in 1.2.1). The `[Run]` entry used to carry
  `Flags: postinstall`, which Inno Setup renders as a "立即启动" checkbox on the finished page.
  It is gone: the wizard now closes as soon as the files are written, and the app is started from
  the desktop / Start-Menu shortcut. `[Run]` is intentionally left empty — re-adding a postinstall
  entry would bring the checkbox back.
- Runs its own `[Code] ConfigureWorkspace()` step (progress page) to create the workspace,
  `profiles\web`, and a `package.json` with the DSH semver range, and writes
  `scripts\workdir.txt`; **deletes** any machine-specific `DSH_HOME` user env var (data lives in
  `~\.dsh`, see *Data Directory*). Note `installer\post-install.ps1` is a standalone manual helper
  — it is **not** packaged into the EXE and the wizard does not call it.
- Registers uninstall info in **Windows Settings > Apps**; uninstalling also clears `DSH_HOME`.
- Warns if **Node.js** is not detected (prerequisite).

### Clean uninstall tool (CleanUninstall.exe)

Start-Menu shortcut「完全卸载 DeepSeek Harness」or `{app}\CleanUninstall.exe` directly:

1. Stops all DSH-related processes (WMI command-line match + port 3080 listener probe).
2. Runs the official `unins000.exe` uninstaller (silent), then kills it if it hangs (>120s).
3. Removes runtime leftovers the standard uninstaller does not track (logs, `chrome-profile`),
   plus the desktop / Start-Menu shortcuts and the uninstall registry key as a safety net.
4. Deletes the `DSH_HOME` user env var (with `WM_SETTINGCHANGE` broadcast).
5. **User data** (`~\.dsh`, the configured workspace) is kept by default; a three-way confirm
   dialog offers full removal — skipped automatically if the folder contains a `.git`
   directory (development repository guard).

Silent/automation flags: `/silent` (no dialogs, keep user data), `/silent /full` (also remove
user data), `/dir <path>` (target override), `/test` (file operations only — no process kills,
no registry/env/shortcut changes; used for CI-style testing).

### Prerequisites (not bundled)

- **Node.js** >= 18 — https://nodejs.org
- **pnpm** >= 8 — `corepack enable && corepack prepare pnpm@latest --activate`

## Files
| File | Purpose |
|------|---------|
| `launcher.ps1` | Main launcher — orchestrates `pnpm dlx @deepseek-ai/dsh@"<range>"`, early loading window, Chrome, cleanup |
| `modules/` | Modular components: logger, lock-manager, process-utils, dsh-runtime, chrome-launcher |
| `desktop.patch.yml` | Desktop-only profile override that disables DSH's default-browser handoff |
| `loading.html` | Splash page shown while server starts; auto-redirects when ready (localised status + elapsed seconds) |
| `token.js` | Session-token handoff from the launcher to the loading page; blanked on every launch |
| `install.ps1` | Creates/refreshes the dev desktop shortcut (points at `DeepSeek Harness.vbs`) |
| `dsh-version.json` | Tracks installed DSH version + lastKnownGood fallback (no launch-time pinning) |
| `dsh-version.ps1` | Version manager: status / list / pin (via pnpm add) / rollback / set-fallback |
| `installer/dsh-setup.iss` | Inno Setup script for the graphical EXE installer (localised Chinese wizard) |
| `installer/launch-dsh.vbs` | wscript shim for the installed app — GUI subsystem, no console flash |
| `installer/post-install.ps1` | Post-install configuration (workspace, profiles, env var) |
| `installer/CleanUninstall.cs` | Source of the clean-uninstall tool (build with `csc`, see installer section) |
| `installer/CleanUninstall.exe` | Compiled clean-uninstall tool packaged into the installer |
| `installer/ChineseSimplified.isl` | Localised Inno Setup language file |
| `installer/gen-images.ps1` | Regenerates the wizard brand images (wizard-large/small.bmp) |
| `installer/LICENSE.txt` | License shown in the installer wizard |
| `dsh.ico` | App icon for the desktop shortcut |
| `app.pid` | Runtime lock file (prevents duplicate launches) |
| `dsh-launch.log` | Diagnostic log (auto-rotated) |
| `dsh-process-output.log` | Captured DSH startup output |
| `dsh-process-error.log` | Captured DSH startup errors |
| `launch-error.html` | Error page shown when desktop startup fails |

## Uninstall
1. **Standard**: Windows Settings → Apps → DeepSeek Harness → Uninstall (removes installed
   files, shortcuts, the uninstall registry key and the `DSH_HOME` user env var).
2. **Deep clean**: Start-Menu →「完全卸载 DeepSeek Harness」(`CleanUninstall.exe`) — also stops
   running processes and removes runtime leftovers (logs, `chrome-profile`) the standard
   uninstaller does not track. Offers optional user-data removal.
3. User data in `%USERPROFILE%\.dsh` (profiles, sessions, credentials) is kept unless the
   full-removal option was chosen explicitly.

---
