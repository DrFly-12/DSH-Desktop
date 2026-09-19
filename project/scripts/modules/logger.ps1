# ============================================================================
# logger.ps1 — Logging and log-rotation utilities
# Dot-sourced by launcher.ps1. Expects $logFile, $maxLogBytes, $maxLogLines
# to be defined in the caller's scope.
# ============================================================================

function Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = "$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') - $Message"
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

function Get-RecentFileText {
    param([Parameter(Mandatory = $true)][string]$Path, [int]$TailLines = 12)
    if (-not (Test-Path $Path)) { return "" }
    try {
        return ((Get-Content $Path -Tail $TailLines -Encoding UTF8 -ErrorAction SilentlyContinue) -join "`n")
    } catch {
        return ""
    }
}
