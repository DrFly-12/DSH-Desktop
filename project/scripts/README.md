# DeepSeek Harness — Desktop App Launcher

## Overview
Completely hidden launcher that starts the DSH web server, waits for the one-time token it prints a few seconds later, and then opens a Chrome app window **already authenticated**, so the GUI loads on the first try. If startup runs long — a package upgrade, say — it falls back to a loading page with progress instead of leaving the user staring at a blank desktop.

## Architecture
```
Desktop shortcut "DeepSeek Harness.lnk" → points directly to DeepSeek Harness.vbs inside the project
  → Windows executes .vbs natively (no System32 path in shortcut properties)
    → powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass
      → launcher.ps1
        → Pre-flight checks (Node.js, pnpm, Chrome)
        → If DSH already running:
            → Opens Chrome at the live session's tokenised URL (instant, authenticated)
        → If DSH not running (cold start):
            → Start-Process cmd.exe -WindowStyle Hidden
              → (echo y)|pnpm dlx @deepseek-ai/dsh --profile web --patch desktop.patch.yml (hidden console)
            → Waits up to 20s for the "?token=..." line DSH prints while booting
                → Token seen  → opens Chrome at that tokenised URL (already authenticated)
                → No token yet → opens Chrome at loading.html (splash screen, polls every 1.5s)
            → Server ready → GUI loads
        → On Chrome close → stops DSH server (process-specific cleanup)
```

## Key Features
- **Authenticated on the first try** — Chrome is opened at the tokenised URL, which is the only navigation the auth cookie survives (see below)
- **Slow-boot fallback** — if the token is late, the loading page takes over with visible progress instead of a blank wait
- **No console windows** — PowerShell and pnpm both start with hidden windows
- **Chrome standalone window** — No browser chrome, looks like native app
- **Loading page with status** — Shows startup progress, error message if server fails
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

## Usage
Double-click "DeepSeek Harness" desktop icon.
The app window appears once DSH prints its token — about 4-6s on a warm start — already signed in.
On a slow start (a package upgrade, for instance) a loading screen shows progress and the window follows.
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
    $version = (& pnpm.cmd dlx @deepseek-ai/dsh --version 2>$null | Select-Object -First 1)
    if ($version) { Write-Host "DeepSeek Harness v$version" }
    'y' | & pnpm.cmd dlx @deepseek-ai/dsh web
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

## Install / Refresh Shortcut
```powershell
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh\scripts\install.ps1"
```

## Files
| File | Purpose |
|------|---------|
| `launcher.ps1` | Main launcher — orchestrates pnpm dlx, Chrome, cleanup |
| `desktop.patch.yml` | Desktop-only profile override that disables DSH's default-browser handoff |
| `loading.html` | Splash page shown while server starts; auto-redirects when ready |
| `token.js` | Session-token handoff from the launcher to the loading page; blanked on every launch |
| `install.ps1` | Creates/refreshes the desktop shortcut |
| `dsh.ico` | App icon for the desktop shortcut |
| `app.pid` | Runtime lock file (prevents duplicate launches) |
| `dsh-launch.log` | Diagnostic log (auto-rotated) |
| `dsh-process-output.log` | Captured DSH startup output |
| `dsh-process-error.log` | Captured DSH startup errors |
| `launch-error.html` | Error page shown when desktop startup fails |

## Uninstall
1. Delete the desktop shortcut `DeepSeek Harness.lnk`
2. Delete `%USERPROFILE%\.dsh\scripts\` folder
3. (Optional) Restore `%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml` if customised