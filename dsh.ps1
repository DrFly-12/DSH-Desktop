# DSH-Desktop short remote installer
$ErrorActionPreference = 'Stop'
$repo = 'https://github.com/DrFly-12/DSH-Desktop/archive/refs/heads/main.zip'
$work = Join-Path $env:TEMP "DSH-$([guid]::NewGuid().ToString('N'))"
$zip = "$work.zip"

try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Invoke-WebRequest -Uri $repo -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $work -Force
    $root = Get-ChildItem -Path $work -Directory | Select-Object -First 1
    & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $root.FullName 'setup.ps1')
    $shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk'
    if (Test-Path $shortcut) { Start-Process $shortcut }
}
finally {
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
