# ============================================================================
# chrome-launcher.ps1 — Chrome path auto-detection and app-window launch
# Dot-sourced by launcher.ps1. Expects $logFile, $chromePaths to be defined.
# ============================================================================

function Find-Chrome {
    foreach ($path in $chromePaths) {
        if (Test-Path $path) { return $path }
    }
    Log "  Tried: $($chromePaths -join ', ')"
    return $null
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
    $chromeArgs = "--app=$AppUrl --no-first-run --user-data-dir=`"$userDataDir`""
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
