# ============================================================================
# DeepSeek Harness — 公司电脑一键安装脚本
# ============================================================================
# 适用环境：Windows 10 LTSB/LTSC（内置 Windows PowerShell 5.1）+ 域控 + 国内网络
# 功能：
#   0. 环境探测（管理员 / 系统版本 / 桌面路径）
#   1. 确认项目安装路径 + 工作区路径
#   2. 检查 Node.js / npm / npx / Chrome / git，缺失则经确认后自动安装
#   3. 安装缺失组件（Node 走 npmmirror 镜像；管理员用 MSI，无管理员用便携版）
#   4. 复制项目骨架文件（不含任何个人数据 / API Key / 会话历史）
#   5. 创建桌面快捷方式
#   6. 配置 npm 镜像、冒烟验证、可选预热拉取官方 dsh
#   7. 打印首次运行与卸载说明
# ============================================================================
# 用法（在解压后的 dsh-installer 目录下）：
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Windows PowerShell 5.1 默认可能连不上 https，强制 TLS 1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ---- 常量 ----
$NPM_REGISTRY      = "https://registry.npmmirror.com"
$NODE_INDEX_URL    = "https://registry.npmmirror.com/-/binary/node/index.json"
$NODE_FALLBACK_VER = "22.14.0"
$CHROME_URL        = "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe"
$APP_PORT          = 3080
$LogFile           = Join-Path $PSScriptRoot "setup.log"

try { Start-Transcript -Path $LogFile -Force | Out-Null } catch {}

# ---- 输出辅助 ----
function Write-Step { param([string]$m) Write-Host ""; Write-Host ("==> " + $m) -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host ("    [OK] " + $m) -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host ("    [!] " + $m) -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host ("    [X] " + $m) -ForegroundColor Red }
function Write-Info { param([string]$m) Write-Host ("    " + $m) -ForegroundColor Gray }

function Confirm-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $true)
    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    $ans = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $DefaultYes }
    return ($ans.Trim().ToLower() -in @('y', 'yes', '是'))
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestNodeLts {
    # 优先取最新 v22 LTS（对 Win10 老 build 兼容性最好），失败则用内置版本
    try {
        $r = Invoke-WebRequest -Uri $NODE_INDEX_URL -UseBasicParsing -TimeoutSec 30
        $list = $r.Content | ConvertFrom-Json
        $v22 = $list | Where-Object { $_.version -match '^v22\.' -and $_.lts } | Select-Object -First 1
        if ($v22) { return $v22.version.TrimStart('v') }
        $any = $list | Where-Object { $_.lts } | Select-Object -First 1
        if ($any) { return $any.version.TrimStart('v') }
    } catch {
        Write-Warn "无法联网获取最新 Node 版本，使用内置版本 $NODE_FALLBACK_VER"
    }
    return $NODE_FALLBACK_VER
}

function Find-Chrome {
    $paths = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    return $null
}

function Refresh-PathEnv {
    $m = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $u = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$m;$u"
}

function Add-UserPath {
    param([string]$Dir)
    $cur = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $cur) { $cur = "" }
    if (($cur -split ';') -notcontains $Dir) {
        $new = if ($cur.Trim() -eq "") { $Dir } else { "$cur;$Dir" }
        [Environment]::SetEnvironmentVariable("Path", $new, "User")
        Write-Ok "已把 $Dir 加入用户 PATH"
    }
}

function Install-NodeMsi {
    param([string]$Version)
    $tmp = Join-Path $env:TEMP "node-v$Version-x64.msi"
    $url = "https://registry.npmmirror.com/-/binary/node/v$Version/node-v$Version-x64.msi"
    Write-Info "下载: $url"
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 600
    Write-Info "静默安装 Node.js v$Version（MSI，可能需要 1-2 分钟）..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Node MSI 安装失败，退出码 $($p.ExitCode)" }
    Refresh-PathEnv
    Write-Ok "Node.js v$Version 安装完成"
}

function Install-NodePortable {
    param([string]$Version)
    $parent   = Join-Path $env:LOCALAPPDATA "Programs"
    $dir      = Join-Path $parent "nodejs"
    $zip      = Join-Path $env:TEMP "node-v$Version-win-x64.zip"
    $url      = "https://registry.npmmirror.com/-/binary/node/v$Version/node-v$Version-win-x64.zip"
    Write-Info "下载: $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 600
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Write-Info "解压到 $dir ..."
    Expand-Archive -Path $zip -DestinationPath $parent -Force
    $unpacked = Join-Path $parent "node-v$Version-win-x64"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    if (Test-Path $unpacked) { Rename-Item $unpacked $dir }
    Add-UserPath $dir
    $env:Path = "$dir;$env:Path"
    Write-Ok "Node.js v$Version 便携版安装到 $dir"
}

function Install-Chrome {
    $tmp = Join-Path $env:TEMP "ChromeStandaloneSetup64.exe"
    Write-Info "下载 Chrome 独立安装器..."
    Invoke-WebRequest -Uri $CHROME_URL -OutFile $tmp -UseBasicParsing -TimeoutSec 600
    Write-Info "静默安装 Chrome（当前用户，无需管理员）..."
    Start-Process $tmp -ArgumentList "/silent", "/install" -Wait
    Write-Ok "Chrome 安装完成"
}

function Install-Git {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "使用 winget 安装 Git..."
        Start-Process winget.exe -ArgumentList "install", "--id", "Git.Git", "--silent", "--accept-package-agreements", "--accept-source-agreements" -Wait
        Write-Ok "Git 安装完成"
    } else {
        Write-Warn "未找到 winget。Git 为可选组件，请稍后手动安装：https://git-scm.com/download/win"
    }
}

# ============================================================================
# 主流程
# ============================================================================
try {
    $host.UI.RawUI.WindowTitle = "DeepSeek Harness 安装程序"
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  DeepSeek Harness — 公司电脑一键安装" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    # ---- 阶段 0：环境探测 ----
    Write-Step "阶段 0/7：环境探测"
    $isAdmin = Test-Admin
    if ($isAdmin) { Write-Ok "当前为管理员权限（可用 MSI 安装 Node）" }
    else          { Write-Warn "当前无管理员权限（Node 将用便携版，Chrome 为 per-user 安装）" }

    $os = [Environment]::OSVersion.Version
    Write-Info ("操作系统: Windows {0}.{1} (build {2})" -f $os.Major, $os.Minor, $os.Build)
    $desktop = [Environment]::GetFolderPath("Desktop")
    Write-Info ("桌面路径: $desktop")
    if ($desktop -match '^\\\\') { Write-Warn "桌面疑似重定向到网络共享，请留意快捷方式创建结果" }

    # ---- 阶段 1：确认路径 ----
    Write-Step "阶段 1/7：确认安装路径"
    $defaultHome = Join-Path $env:USERPROFILE ".dsh"
    Write-Info "项目安装路径：存放启动器脚本与 DSH 配置的目录（默认与个人电脑一致）。"
    $inputHome = Read-Host "项目安装路径 (回车使用默认 $defaultHome)"
    if ([string]::IsNullOrWhiteSpace($inputHome)) {
        $projectPath = $defaultHome
    } else {
        $projectPath = $inputHome.Trim().TrimEnd('\', '/')
        if ($projectPath -match '^~([\\/]|$)') { $projectPath = $projectPath -replace '^~', $env:USERPROFILE }
        $projectPath = [System.IO.Path]::GetFullPath($projectPath)
    }
    Write-Ok "项目安装路径: $projectPath"

    $ws = ""
    while ([string]::IsNullOrWhiteSpace($ws)) {
        $ws = Read-Host "工作区路径 (必填，npx 在此目录运行，例如 D:\WorkSpace\my-project)"
        if ([string]::IsNullOrWhiteSpace($ws)) { Write-Warn "工作区路径不能为空，请重新输入" }
    }
    $ws = [System.IO.Path]::GetFullPath($ws.Trim())
    if (-not (Test-Path $ws)) {
        if (Confirm-YesNo "工作区目录 $ws 不存在，是否创建？" $true) {
            New-Item -ItemType Directory -Force -Path $ws | Out-Null
            Write-Ok "已创建 $ws"
        } else {
            Write-Err "未创建工作区，安装中止"
            Stop-Transcript | Out-Null
            exit 1
        }
    }
    Write-Ok "工作区路径: $ws"

    # 写 workdir.txt（launcher.ps1 会读取它决定 npx 运行目录）
    $scriptsDir = Join-Path $projectPath "scripts"
    New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
    Set-Content -Path (Join-Path $scriptsDir "workdir.txt") -Value $ws -Encoding UTF8
    Write-Ok "已写入 workdir.txt: $ws"

    # 设置 DSH_HOME（进程 + 用户级），让 launcher.ps1 与官方 dsh CLI 使用同一个 home
    $env:DSH_HOME = $projectPath
    if ($projectPath -ne $defaultHome) {
        [Environment]::SetEnvironmentVariable("DSH_HOME", $projectPath, "User")
        Write-Ok "已设置用户环境变量 DSH_HOME = $projectPath"
    } else {
        Write-Info "项目路径为默认位置，无需额外设置 DSH_HOME"
    }

    # ---- 阶段 2：检查依赖组件 ----
    Write-Step "阶段 2/7：检查依赖组件"
    $needInstall = @()

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    $npmCmd  = Get-Command npm  -ErrorAction SilentlyContinue
    $npxCmd  = Get-Command npx  -ErrorAction SilentlyContinue
    if ($nodeCmd -and $npmCmd -and $npxCmd) {
        Write-Ok ("Node.js 已安装: " + (& node -v))
    } else {
        Write-Warn "未检测到完整的 Node.js / npm / npx 环境"
        $needInstall += "node"
    }

    $chromePath = Find-Chrome
    if ($chromePath) { Write-Ok "Chrome 已安装: $chromePath" }
    else { Write-Warn "未检测到 Google Chrome"; $needInstall += "chrome" }

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) { Write-Ok "Git 已安装 (可选组件)" }
    else { Write-Info "Git 未安装（可选，不影响 DSH 运行；仅用于同步 GitHub 仓库）" }

    # ---- 阶段 3：安装缺失组件 ----
    if ($needInstall.Count -gt 0) {
        Write-Step "阶段 3/7：安装缺失组件"
        if (-not (Confirm-YesNo ("检测到缺失组件: " + ($needInstall -join ', ') + "。是否现在自动安装？") $true)) {
            Write-Err "用户取消组件安装，安装中止"
            Stop-Transcript | Out-Null
            exit 1
        }

        if ($needInstall -contains "node") {
            $ver = Get-LatestNodeLts
            Write-Info ("将安装 Node.js LTS v$ver")
            $method = if ($isAdmin) { "msi" } else { "portable" }
            if ($isAdmin) {
                if (Confirm-YesNo "使用官方 MSI 安装 Node（管理员，推荐）？选 N 则改用便携版（免管理员）。" $true) {
                    $method = "msi"
                } else {
                    $method = "portable"
                }
            } else {
                Write-Info "无管理员权限，改用便携版 Node"
            }
            if ($method -eq "msi") { Install-NodeMsi $ver } else { Install-NodePortable $ver }
        }

        if ($needInstall -contains "chrome") {
            if (Confirm-YesNo "是否安装 Google Chrome（当前用户，静默安装）？" $true) { Install-Chrome }
        }
    }

    if (-not $gitCmd) {
        if (Confirm-YesNo "是否顺便安装 Git（可选，用于拉取/同步 GitHub 仓库）？" $false) { Install-Git }
    }

    # ---- 阶段 4：复制项目骨架文件 ----
    Write-Step "阶段 4/7：复制项目骨架文件"
    $srcScripts = Join-Path $PSScriptRoot "project\scripts"
    $srcProfile = Join-Path $PSScriptRoot "project\profiles\web"
    if (-not (Test-Path (Join-Path $srcScripts "launcher.ps1"))) {
        throw "找不到源文件 $srcScripts\launcher.ps1 —— 请从完整安装包目录运行本脚本"
    }

    Copy-Item -Path (Join-Path $srcScripts "*") -Destination $scriptsDir -Force -Recurse

    $profileDir = Join-Path $projectPath "profiles\web"
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    Copy-Item -Path (Join-Path $srcProfile "cordis.patch.yml") -Destination $profileDir -Force

    Write-Ok "骨架文件已复制到 $projectPath"
    Write-Info "按你的选择，settings.yaml / API Key / 会话历史 均未迁移（到公司后重新配置）"

    # ---- 阶段 5：创建桌面快捷方式 ----
    Write-Step "阶段 5/7：创建桌面快捷方式"
    $vbsPath  = Join-Path $scriptsDir "DeepSeek Harness.vbs"
    $icoPath  = Join-Path $scriptsDir "dsh.ico"
    $shortcutPath = Join-Path $desktop "DeepSeek Harness.lnk"
    if (-not (Test-Path $vbsPath)) { throw "缺少 $vbsPath" }

    $wsh = New-Object -ComObject WScript.Shell
    $sc  = $wsh.CreateShortcut($shortcutPath)
    $sc.TargetPath = $vbsPath
    $sc.Arguments = ""
    $sc.WorkingDirectory = $ws
    $sc.Description = "DeepSeek Harness — AI 编程助手 (DSH Web + Chrome 应用窗口)"
    if (Test-Path $icoPath) { $sc.IconLocation = "$icoPath, 0" }
    $sc.Save()
    Write-Ok "桌面快捷方式已创建: $shortcutPath"

    # ---- 阶段 6：配置镜像 + 验证 + 预热 ----
    Write-Step "阶段 6/7：配置 npm 镜像并验证"
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        & npm config set registry $NPM_REGISTRY | Out-Null
        Write-Ok "npm 已切换镜像: $NPM_REGISTRY"
    }

    try { Write-Info ("  node : " + (& node -v)) } catch { Write-Warn "node 未生效，请重开终端后再试" }
    try { Write-Info ("  npm  : " + (& npm  -v)) } catch { Write-Warn "npm 未生效，请重开终端后再试" }
    try { Write-Info ("  npx  : " + (& npx  -v)) } catch { Write-Warn "npx 未生效，请重开终端后再试" }
    if (Find-Chrome) { Write-Ok "Chrome 检测正常" }

    if (Confirm-YesNo "是否现在自动预热（npx 拉取官方 @deepseek-ai/dsh，约 1-3 分钟）？" $true) {
        Write-Info "执行: npx -y @deepseek-ai/dsh --version"
        Push-Location $ws
        try {
            & npx -y @deepseek-ai/dsh --version
            Write-Ok "官方 dsh 已拉取成功"
        } catch {
            Write-Warn "预热未完成，可稍后手动运行（见下方说明）"
        } finally {
            Pop-Location
        }
    }

    # ---- 阶段 7：完成 ----
    Write-Step "阶段 7/7：安装完成"
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Green
    Write-Host "  安装完成！" -ForegroundColor Green
    Write-Host "==============================================================" -ForegroundColor Green
    Write-Host "  项目路径     : $projectPath"
    Write-Host "  工作区       : $ws"
    Write-Host "  桌面快捷方式 : DeepSeek Harness"
    Write-Host ""
    Write-Host "  首次使用：" -ForegroundColor Cyan
    Write-Host "    1) 打开 PowerShell / CMD，运行：" -ForegroundColor Yellow
    Write-Host "         npx -y @deepseek-ai/dsh web" -ForegroundColor White
    Write-Host "       （首次会拉取官方 dsh 并初始化 profile，看到 http://127.0.0.1:$APP_PORT 即成功）" -ForegroundColor Gray
    Write-Host "    2) 之后直接双击桌面图标即可（launcher 已带 -y，会自动拉包）" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  提示：" -ForegroundColor Cyan
    Write-Host "    - 若本终端 node/npm 命令未生效，请关闭并重开终端（PATH 刷新）" -ForegroundColor Gray
    Write-Host "    - 端口 $APP_PORT 为本地回环端口，如被拦截请放行 127.0.0.1:$APP_PORT" -ForegroundColor Gray
    Write-Host "    - API Key 与模型配置请在网页界面重新填写（本次未迁移个人数据）" -ForegroundColor Gray
    Write-Host "    - 卸载：删除桌面快捷方式 + 删除 $projectPath；若设置了 DSH_HOME 环境变量也一并删除" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  安装日志: $LogFile" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "安装结束，按回车键退出"
}
catch {
    Write-Err ("安装出错: " + $_.Exception.Message)
    if ($_.ScriptStackTrace) { Write-Err $_.ScriptStackTrace }
    Write-Host ""
    Read-Host "按回车键退出"
}
finally {
    Stop-Transcript | Out-Null
}
