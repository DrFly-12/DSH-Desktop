# ============================================================================
# chrome-launcher.ps1 — Chrome path auto-detection, file-URL escaping, launch
# Dot-sourced by launcher.ps1. Expects $logFile, $chromePaths to be defined.
# ============================================================================

function Find-Chrome {
    foreach ($path in $chromePaths) {
        if (Test-Path $path) { return $path }
    }
    Log "  Tried: $($chromePaths -join ', ')"
    return $null
}

# Converts a local Windows path into a properly percent-encoded file:/// URL.
#
# WHY THIS EXISTS: a child process receives its arguments as ONE command line
# and re-splits it on whitespace. A raw path therefore breaks the moment it
# contains a space — and the default install target does exactly that:
#
#   C:\Users\<user>\AppData\Local\Programs\DeepSeek Harness\scripts\loading.html
#
# Passing "file:///C:/.../Programs/DeepSeek Harness/scripts/loading.html"
# made Chrome receive two arguments, so it opened
# "file:///C:/.../Programs/DeepSeek" (file not found) and the splash screen
# never appeared. The dev copy under %USERPROFILE%\.dsh has no space, which is
# why the fault stayed invisible until the packaged app was run.
#
# Percent-encoding also covers non-ASCII user names in %LOCALAPPDATA%, which a
# raw file URL would otherwise mangle.
function ConvertTo-FileUrl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    # UNC (\\server\share) keeps the host in the authority position: the leading
    # "\\" below becomes "//", so the prefix must be "file:" and not "file://".
    $prefix = 'file:///'
    if ($full.StartsWith('\\')) { $prefix = 'file:' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($prefix)
    foreach ($ch in $full.ToCharArray()) {
        $s = [string]$ch
        if ($ch -eq '\') { [void]$sb.Append('/') }                    # path separator
        elseif ($s -match '^[A-Za-z0-9\-_.~/]$') { [void]$sb.Append($s) }
        elseif ($ch -eq ':') { [void]$sb.Append(':') }                # drive colon
        else { [void]$sb.Append([System.Uri]::EscapeDataString($s)) } # space -> %20, UTF-8
    }
    return $sb.ToString()
}

function Launch-Chrome {
    param(
        [Parameter(Mandatory = $true)][string]$ChromePath,
        [Parameter(Mandatory = $true)][string]$AppUrl
    )
    # 独立 user-data-dir：确保本 chrome.exe 就是应用窗口本体进程。
    # 若共用用户默认配置，Chrome 已在运行时 --app 窗口会"移交"给现有实例后立即退出，
    # launcher 会误判为"窗口已关闭"而杀掉 DSH 服务，窗口只剩报错页。
    # --no-first-run 抑制独立配置首次启动的欢迎页。
    $userDataDir = Join-Path $dshHome 'chrome-profile'
    # The --app value is quoted so that a URL containing whitespace still arrives
    # as ONE argument instead of being split in two (see ConvertTo-FileUrl above;
    # file paths should still be escaped there rather than relying on this).
    $chromeArgs = "--app=`"$AppUrl`" --no-first-run --user-data-dir=`"$userDataDir`""
    Log "  Launching: $ChromePath $chromeArgs"
    try {
        $proc = Start-Process $ChromePath -ArgumentList $chromeArgs -PassThru -ErrorAction Stop
        Log "  Chrome PID = $($proc.Id)"
        return $proc
    } catch {
        Log "ERROR: Failed to launch Chrome: $_"
        return $null
    }
}
