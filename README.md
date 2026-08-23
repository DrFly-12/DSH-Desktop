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
- 秒开加载页：服务冷启动时先开加载页（loading.html），就绪后自动跳转，不用干等。
- 进程级清理：关闭 Chrome 窗口即自动停掉对应的 DSH 服务，不误杀其它 Node 进程。
- 防重复启动：PID 锁 + 端口检测，避免开多个实例。
- 日志轮转：启动日志自动截断（500 行 / 1MB），不会无限膨胀。
- 自动确认升级：隐藏桌面启动会自动确认 pnpm 的 DSH 安装提示。
- 启动保护：升级或启动阶段 30 秒无输出、或 120 秒未就绪会停止并显示错误页面。
- `dshweb` 快捷命令：复用已有服务或启动 DSH，并输出官方版本号。

## 系统要求

| 组件 | 要求 |
|------|------|
| 操作系统 | Windows 10 / 11（含 LTSB / LTSC），64 位 |
| Node.js | 22 LTS 推荐（脚本自动装，含 npm；pnpm 需已安装） |
| 浏览器 | Google Chrome（脚本自动装） |
| 网络 | 能访问 `registry.npmmirror.com`（脚本默认走国内镜像） |
| 权限 | 有管理员权限用 MSI 装 Node；无管理员自动用便携版，均无需手工干预 |

## 快速开始（安装）

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
  $version = (& pnpm.cmd dlx @deepseek-ai/dsh --version 2>$null | Select-Object -First 1)
  if ($version) { Write-Host "DeepSeek Harness v$version" }
  $url = 'http://127.0.0.1:3080'
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
    if ($response.StatusCode -eq 200) { Start-Process $url; return }
  } catch {}
  'y' | & pnpm.cmd dlx @deepseek-ai/dsh web
}
```

当前官方 Web 前端左上角的 `DeepSeek Harness` 是固定打包文本，项目配置无法直接追加 CLI 版本号；`dshweb` 会输出官方版本，桌面 loading 页也会显示启动时读取到的版本。

## 工作原理

```
桌面快捷方式 "DeepSeek Harness.lnk"
  → DeepSeek Harness.vbs（Windows 原生执行）
    → powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass
      → launcher.ps1
        → 预检 Node / pnpm / Chrome
        → 后台启动: pnpm dlx @deepseek-ai/dsh web
        → 立即打开 Chrome 到 loading.html（加载页）
        → 服务就绪后自动跳转 http://127.0.0.1:3080
        → Chrome 关闭时，仅清理本次桌面启动的 DSH 服务
```

## 目录结构

```
DSH-Desktop/
├── setup.ps1                 # 主安装脚本（7 阶段交互式）
├── README.md
├── .gitignore
└── project/                  # 要落到目标电脑的骨架
    ├── scripts/
    │   ├── launcher.ps1      # 启动器（pnpm dlx + Chrome 加载页 + 进程清理）
    │   ├── install.ps1       # 单独刷新 / 重建桌面快捷方式
    │   ├── DeepSeek Harness.vbs
    │   ├── loading.html
    │   └── dsh.ico
    └── profiles/web/
        └── cordis.patch.yml  # printUrl: true（其余 profile 文件由 dsh 首次运行自动生成）
```

> 注意：`profiles/node_modules`、`sessions/`、`storages/` 均为机器相关数据（node_modules 是指向
> pnpm 缓存的软链接），**不要**复制到新电脑，dsh 首次运行会自动重建。

## 卸载

1. 删除桌面快捷方式 `DeepSeek Harness.lnk`；
2. 删除项目目录（默认 `%USERPROFILE%\.dsh`）；
3. 若安装时设置过环境变量 `DSH_HOME`，在「系统属性 → 环境变量」里删除它；
4. （可选）卸载 Node.js / Chrome。

## 常见问题（FAQ）

- **node / npm 命令未生效**：刚装完 PATH 未刷新，关闭并重开终端即可。
- **执行策略拦截**：一律用 `powershell -ExecutionPolicy Bypass -File .\setup.ps1` 运行；若域控用 GPO 强制了 MachinePolicy 执行策略，需联系 IT 放行或对脚本签名。
- **AppLocker / SRP 拦截 wscript 或 ps1**：属公司安全策略，需 IT 放行。
- **下载超时 / 连不上镜像**：确认能访问 `registry.npmmirror.com`；公司有代理时先设置 `$env:HTTP_PROXY` / `$env:HTTPS_PROXY` 再运行。
- **端口 3080 被占用**：dsh 只监听 `127.0.0.1:3080`（本机回环），一般无需防火墙放行；若被占用可结束占用进程或改端口（需同步改 `launcher.ps1` 与 `loading.html`）。
- **要迁移个人配置**：把旧电脑 `%USERPROFILE%\.dsh\settings.yaml` 复制到新电脑同名位置即可；**API Key 建议在网页界面重新填写**，不要用明文文件跨机拷贝。

## 隐私说明

本仓库**只包含启动脚本与安装逻辑，不含任何个人数据**：

- 不含 API Key / 凭据（`.credentials.yaml` 已加入 `.gitignore`）；
- 不含会话历史（`sessions/`）、工作区存储（`storages/`）；
- 不含个人模型配置（`settings.yaml` 已加入 `.gitignore`）。

目标电脑上的 API Key 与模型配置，请在 DSH 网页界面里重新填写。

## 关于核心

DeepSeek Harness 由 DeepSeek 官方发布（`@deepseek-ai/dsh`），本仓库仅为其提供 Windows 桌面化封装与装机脚本，与官方仓库无隶属关系。官方仓库：<https://github.com/deepseek-ai/deepseek-harness>。
