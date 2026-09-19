# DSH-Desktop

DeepSeek Harness（官方 `@deepseek-ai/dsh`）的 **Windows 桌面化一键安装包**：把个人电脑上已经调好的 DSH Web 应用，完整、干净地迁移到另一台 Windows 电脑（公司电脑 / 新电脑），并生成一个「双击即用」的桌面图标。

> 核心内核是官方的 `pnpm dlx @deepseek-ai/dsh web` 命令。本仓库不修改、不打包任何官方代码，只负责**环境检查、组件安装、配置落地、桌面快捷方式**，以及一个让启动过程全程无黑框、带加载页的启动器。

---

## 这是什么

- **官方内核**：启动即 `pnpm dlx @deepseek-ai/dsh web`，拉起 DeepSeek Harness 的 Web 界面（`http://127.0.0.1:3080`）。
- **桌面应用体验**：桌面图标 → 隐藏窗口启动服务 → 自动打开一个无地址栏的 Chrome 应用窗口，看起来像原生 App。
- **一键装机**：`setup.ps1` 自动检查并安装 Node.js / Chrome，自动落配置、建快捷方式。
- **可迁移**：整个仓库就是一套「搬家工具」，把 DSH 从一台电脑搬到另一台电脑，**不带任何个人数据**。

## 特性

- 环境自检：自动探测管理员权限、系统版本、桌面路径、Node/pnpm/Chrome/git 是否就绪。
- 缺啥装啥：Node.js 走国内 npmmirror 镜像下载；管理员用官方 MSI，无管理员自动降级为便携版；Chrome 用官方 per-user 安装器（免管理员）。
- 隐藏启动：PowerShell 与 pnpm 均以隐藏窗口运行，全程无黑框。
- 秒开加载反馈：双击图标约 2 秒内即弹出加载窗口，状态栏实时显示「正在启动服务 (Ns)」等进度文案，不会误以为应用没点开。
- 首次打开即已登录：DSH `0.1.5-rc.x` 起 Web 界面走 cookie 认证（裸请求返回 `401`）。启动器等到它打印的一次性 `?token=` 地址后，关掉加载窗口、改用带 token 的地址打开 Chrome —— 只有浏览器**自发导航**才带得住那个 `SameSite=Strict` cookie，界面第一次就登录成功。
- 慢启动兜底：若长时间等不到 token（例如正在升级依赖），加载窗口继续显示已等待秒数，服务就绪后自动跳转；该路径下 cookie 同样会存下，按一次刷新即可进入。
- 数据与程序分离：程序文件在安装目录，个人数据（profiles / 会话 / 凭据）固定在 `%USERPROFILE%\.dsh`，重装、升级、卸载都不丢数据。
- 完全卸载工具：开始菜单内置「完全卸载」可执行程序，一键彻底清除程序文件、快捷方式、注册表项与运行期残留（默认保留个人数据，确认后才会删除）。
- 进程级清理：关闭 Chrome 窗口即自动停掉对应的 DSH 服务，不误杀其它 Node 进程。
- 防重复启动：PID 锁 + 端口检测（进程活着但 3080 端口未监听 → 判定僵尸启动器并回收），避免开多个实例。
- 版本受控升级：依赖只走 `package.json` 里的 semver 范围（绝不锁死 `@<精确版本>`），`dsh-version.ps1` 支持 status / list / pin / rollback，坏版本可一键回退 lastKnownGood。
- 日志轮转：启动日志自动截断（500 行 / 1MB），不会无限膨胀。
- 自动确认升级：隐藏桌面启动会自动确认 pnpm 的 DSH 安装提示。
- 启动保护：升级或启动阶段 30 秒无输出、或 120 秒未就绪会停止并显示错误页面。
- 僵尸锁自动回收：崩溃或强杀遗留的 `<文件>.lock` 会在冷启动前清掉 —— `dsh-atomic-write` 明确不自动回收孤儿锁（源码原话 "orphan recovery is an operator action"），等待上限只有 2 秒，不处理则每次启动都死在 `timed out waiting for the writer lock`。清理只针对 PID 已死的锁，活锁保留。
- 认证感知的就绪探测：Web 界面无 cookie 时返回 `401`，这被判定为"服务正常在跑"而非"没起来"（`Invoke-WebRequest` 遇非 2xx 直接抛异常，只看 200 会把健康服务误判为宕机）；只有传输失败才算不可用。
- `dshweb` 快捷命令：复用已有服务或启动 DSH，并输出官方版本号（同样按 401/403 判定服务存活，不会误判成"没起"而重复启动撞 `EADDRINUSE`）。

## 系统要求

| 组件 | 要求 |
|------|------|
| 操作系统 | Windows 10 / 11（含 LTSB / LTSC），64 位 |
| Node.js | 22 LTS 推荐（脚本自动装，含 npm；pnpm 需已安装） |
| 浏览器 | Google Chrome（脚本自动装） |
| 网络 | 能访问 `registry.npmmirror.com`（脚本默认走国内镜像） |
| 权限 | 有管理员权限用 MSI 装 Node；无管理员自动用便携版，均无需手工干预 |

## 快速开始（安装）

### 一条命令安装并启动（推荐）

在 PowerShell 中执行下面这一条命令。它会从 GitHub 下载最新安装器并启动；安装完成并按回车退出后，会自动打开桌面版 DSH：

```powershell
irm https://github.com/DrFly-12/DSH-Desktop/raw/main/dsh.ps1 | iex
```

它等价于官方 CLI 的短命令风格：远程引导脚本只负责下载临时安装包，正式的 `setup.ps1` 仍会询问安装路径和工作区路径。安装完成后无需再手动执行 `pnpm dlx`，直接关闭安装窗口即可看到 DSH 启动窗口。

> 安全提示：执行前可先在浏览器打开 [dsh.ps1](https://github.com/DrFly-12/DSH-Desktop/raw/main/dsh.ps1) 检查脚本内容；公司安全策略禁止 `irm | iex` 时，请使用下方的 ZIP 下载方式。

### 图形化安装包（EXE，推荐）

仓库根目录直接提供编译好的 [`DeepSeekHarness-Setup-1.2.0.exe`](https://github.com/DrFly-12/DSH-Desktop/raw/main/DeepSeekHarness-Setup-1.2.0.exe)（2 MB，免编译，双击即用）：简体中文界面、许可证 + 环境检测（Node / pnpm / Chrome 实时状态）+ 分步进度条，完成后可勾选「立即启动」。安装目录默认 `%LOCALAPPDATA%\Programs\DeepSeek Harness`，个人数据仍固定在 `%USERPROFILE%\.dsh`；开始菜单附「完全卸载」工具。

也可从 `project/installer/dsh-setup.iss`（Inno Setup 源码）自行编译。

### 1. 获取本仓库

任选其一：

```bash
git clone https://github.com/DrFly-12/DSH-Desktop.git
```

或在 GitHub 网页点 **Code → Download ZIP** 后解压。

### 2. 运行安装脚本

进入解压出来的 `DSH-Desktop` 目录，右键 `setup.ps1` → **使用 PowerShell 运行**；
若右键没有该菜单，打开 PowerShell / CMD 执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

### 3. 按提示完成

脚本会一步步询问并自动执行：

1. 确认 **项目安装路径**（默认 `C:\Users\<你>\.dsh`，与个人电脑保持一致）；
2. 输入 **工作区路径**（pnpm 的运行目录，必填，例如 `D:\WorkSpace\my-project`）；
3. 缺失的 Node.js / Chrome 会先列出，确认后自动下载安装；
4. 复制骨架文件、创建桌面快捷方式；
5. 自动配置 npm 国内镜像，并可选「预热」拉取官方 dsh。

## 首次运行

安装完成后，**第一次**可在一个看得见的终端里执行（用于拉取官方 dsh 并初始化 profile）：

```powershell
pnpm dlx @deepseek-ai/dsh web
```

看到 `http://127.0.0.1:3080` 即成功。之后直接双击桌面「DeepSeek Harness」图标即可（启动器已带 `-y`，会自动拉包）。

> 说明：桌面 launcher 会自动确认 pnpm 的安装提示；手动运行时请按终端提示确认。

## 日常使用

- **启动**：双击桌面图标「DeepSeek Harness」。
- **关闭**：直接关闭 Chrome 应用窗口，DSH 服务会自动停止。
- **改工作区**：编辑 `%USERPROFILE%\.dsh\scripts\workdir.txt`，写一行新路径即可。
- **看日志**：`%USERPROFILE%\.dsh\scripts\dsh-launch.log`。

也可以在 PowerShell profile 中添加 `dshweb`，从任意项目目录启动或复用 DSH：

```powershell
function dshweb {
  $url = 'http://127.0.0.1:3080'
  # 裸请求回 401/403 同样说明服务活着：新版 Web 界面走 cookie 认证，
  # 而 Invoke-WebRequest 遇到任何非 2xx 都会抛异常。只判断 200 会把
  # 正在运行的服务误判为"没起来"，于是重复启动并撞上 EADDRINUSE。
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
```

当前官方 Web 前端左上角的 `DeepSeek Harness` 是固定打包文本，项目配置无法直接追加 CLI 版本号；`dshweb` 会输出官方版本，桌面 loading 页也会显示启动时读取到的版本。

## 工作原理

```
桌面快捷方式 "DeepSeek Harness.lnk"
  → DeepSeek Harness.vbs（Windows 原生执行；EXE 安装版为 wscript + launch-dsh.vbs）
    → powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass
      → launcher.ps1
        → 预检 Node / pnpm / Chrome，并清理 PID 已死的僵尸锁与僵尸启动器
        → 立即打开 loading.html 加载窗口（约 2 秒，反馈先行，显示已等待秒数）
        → 若 DSH 已在运行：直接用当前会话的 token 地址打开 Chrome（瞬时，已登录）
        → 若未运行：后台启动 pnpm dlx @deepseek-ai/dsh@"<semver 范围>" --profile web --patch desktop.patch.yml
             → 等它打印 "?token=..."（最多 20 秒）
                 等到 token → 关掉加载窗口，用带 token 的地址打开 Chrome（打开即已登录）
                 没等到     → 加载窗口继续显示进度，服务就绪后跳转（必要时刷新一次）
        → 版本检查挪到服务就绪之后执行（非阻塞），只刷新下次启动的版本号显示
        → Chrome 关闭时，仅清理本次桌面启动的 DSH 服务
```

## 目录结构

```
DSH-Desktop/
├── setup.ps1                 # 主安装脚本（7 阶段交互式）
├── dsh.ps1                   # 远程一条命令引导脚本
├── DeepSeekHarness-Setup-1.2.0.exe  # 图形化安装包（免编译，双击即用）
├── README.md
├── .gitignore
└── project/                  # 要落到目标电脑的骨架
    ├── scripts/
    │   ├── launcher.ps1      # 启动器（秒开加载窗口 + 换窗登录 + 进程清理）
    │   ├── modules/          # 启动器拆分的 5 个单一职责模块（logger / lock-manager / process-utils / dsh-runtime / chrome-launcher）
    │   ├── dsh-version.ps1   # 版本管理（status / list / pin / rollback / set-fallback）
    │   ├── dsh-version.json  # 版本跟踪（installedVersion / lastKnownGood）
    │   ├── install.ps1       # 单独刷新 / 重建桌面快捷方式
    │   ├── DeepSeek Harness.vbs
    │   ├── loading.html
    │   └── dsh.ico
    ├── installer/            # 图形安装向导（dsh-setup.iss + 完全卸载工具 CleanUninstall.cs 源码）
    └── profiles/web/
        └── cordis.patch.yml  # printUrl: true（其余 profile 文件由 dsh 首次运行自动生成）
```

> 注意：`profiles/node_modules`、`sessions/`、`storages/` 均为机器相关数据（node_modules 是指向
> pnpm 缓存的软链接），**不要**复制到新电脑，dsh 首次运行会自动重建。

## 卸载

### EXE 安装版

- **开始菜单 → DeepSeek Harness → 完全卸载**：运行 CleanUninstall 工具，交互确认后彻底清除程序文件、快捷方式、注册表项与运行期残留；默认**保留**个人数据，明确确认后才删除；
- 或 **Windows 设置 → 应用** 里标准卸载（同时清除 `DSH_HOME` 用户环境变量）。

### 脚本版

1. 删除桌面快捷方式 `DeepSeek Harness.lnk`；
2. 删除项目目录（默认 `%USERPROFILE%\.dsh`）；
3. 若安装时设置过环境变量 `DSH_HOME`，在「系统属性 → 环境变量」里删除它；
4. （可选）卸载 Node.js / Chrome。

> 个人数据（profiles / 会话 / 凭据）位于 `%USERPROFILE%\.dsh`，卸载默认保留；需要彻底清除时使用「完全卸载」工具并确认删除。

## 常见问题（FAQ）

- **node / npm 命令未生效**：刚装完 PATH 未刷新，关闭并重开终端即可。
- **执行策略拦截**：一律用 `powershell -ExecutionPolicy Bypass -File .\setup.ps1` 运行；若域控用 GPO 强制了 MachinePolicy 执行策略，需联系 IT 放行或对脚本签名。
- **AppLocker / SRP 拦截 wscript 或 ps1**：属公司安全策略，需 IT 放行。
- **下载超时 / 连不上镜像**：确认能访问 `registry.npmmirror.com`；公司有代理时先设置 `$env:HTTP_PROXY` / `$env:HTTPS_PROXY` 再运行。
- **端口 3080 被占用**：dsh 只监听 `127.0.0.1:3080`（本机回环），一般无需防火墙放行；若被占用可结束占用进程或改端口（需同步改 `launcher.ps1` 与 `loading.html`）。
- **报 `EADDRINUSE: address already in use 127.0.0.1:3080`**：已经有一个实例在跑（可能是上次异常退出留下的）。先结束占用 3080 的进程再启动。桌面启动器与 `dshweb` 都已按 401 判定服务存活，不会再重复拉起。
- **窗口显示 `dsh web authentication required`**：本次请求没带上认证 cookie。从 `%USERPROFILE%\.dsh\scripts\dsh-launch.log` 取 `Auth URL (needed only if the browser shows 401):` 那一行，粘进地址栏访问一次即可；此后 30 天内免登录。
- **报 `timed out waiting for the writer lock`**：`%USERPROFILE%\.dsh\.credentials.yaml.lock` 是进程被强杀后遗留的孤儿写锁。启动器会在冷启动前自动清理；手动处理时先确认锁里记录的 PID 已不存在，再删除该 `.lock` 文件（**不要动 `.credentials.yaml` 本体**）。
- **要迁移个人配置**：把旧电脑 `%USERPROFILE%\.dsh\settings.yaml` 复制到新电脑同名位置即可；**API Key 建议在网页界面重新填写**，不要用明文文件跨机拷贝。

## 隐私说明

本仓库**只包含启动脚本与安装逻辑，不含任何个人数据**：

- 不含 API Key / 凭据（`.credentials.yaml` 已加入 `.gitignore`）；
- 不含会话历史（`sessions/`）、工作区存储（`storages/`）；
- 不含个人模型配置（`settings.yaml` 已加入 `.gitignore`）。

目标电脑上的 API Key 与模型配置，请在 DSH 网页界面里重新填写。

## 关于核心

DeepSeek Harness 由 DeepSeek 官方发布（`@deepseek-ai/dsh`），本仓库仅为其提供 Windows 桌面化封装与装机脚本，与官方仓库无隶属关系。官方仓库：<https://github.com/deepseek-ai/deepseek-harness>。
