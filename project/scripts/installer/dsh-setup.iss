; ============================================================================
; DeepSeek Harness — Inno Setup 安装脚本（自定义中文界面 + 分步进度条）
; Build: & "<ISCC path>\ISCC.exe" dsh-setup.iss
; Output: Output\DeepSeekHarness-Setup-1.2.0.exe
; ============================================================================

#define MyAppName "DeepSeek Harness"
#define MyAppVersion "1.2.0"
#define MyAppPublisher "DeepSeek Harness"
#define MyAppExeName "launcher.ps1"
#define MyAppURL "https://github.com/deepseek-ai/dsh"

[Setup]
; 固定 AppId：升级/卸载时据此识别已有安装。
; Inno 会基于 AppId 自动生成卸载注册表项，切勿再手写 [Registry] 卸载键（会重复）。
AppId={{B9D2E7F1-3A4C-4E8B-9D6F-1A2B3C4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\DeepSeek Harness
DefaultGroupName=DeepSeek Harness
AllowNoIcons=yes
LicenseFile=LICENSE.txt
OutputDir=Output
OutputBaseFilename=DeepSeekHarness-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ShowLanguageDialog=no

; 自定义品牌视觉
SetupIconFile=..\dsh.ico
WizardImageFile=wizard-large.bmp
WizardSmallImageFile=wizard-small.bmp
UninstallDisplayName={#MyAppName}

; 内嵌版本信息（EXE 属性 → 详细信息）
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
VersionInfoDescription={#MyAppName} 安装程序
VersionInfoCompany={#MyAppPublisher}
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Messages]
; 品牌化欢迎页 / 完成页文案（其余按钮与标题使用简体中文语言包翻译）
SetupAppTitle=DeepSeek Harness 安装
SetupWindowTitle=DeepSeek Harness 安装
WelcomeLabel1=欢迎使用 DeepSeek Harness 安装向导
WelcomeLabel2=此向导将引导您完成 DeepSeek Harness [version] 的安装。%n%nDeepSeek Harness 将以独立应用窗口方式启动 DSH Web 服务，并自动完成登录与进程管理。%n%n建议在继续之前关闭其他正在运行的应用程序。%n%n单击「下一步」继续。
ReadyLabel1=安装程序已准备好开始安装 DeepSeek Harness
ReadyLabel2a=单击「安装」开始安装。如需复查或修改设置，请单击「上一步」。
FinishedHeadingLabel=DeepSeek Harness 安装完成
FinishedLabel=DeepSeek Harness 已成功安装到您的计算机。
WizardSelectProgramGroup=选择开始菜单文件夹
SelectStartMenuFolderDesc=选择安装程序创建程序快捷方式的位置。

[Tasks]
Name: "desktopicon"; Description: "在桌面上创建图标(&D)"; GroupDescription: "附加图标："

[Files]
; 安装布局：launcher 资产安装到 {app}\scripts\（launcher 按自身位置解析资产目录）。
; DSH 数据目录（profiles/storages/凭据）固定为用户级 ~/.dsh，不随安装/卸载清除。
; workdir.txt 不打包——其中是机器相关路径，由安装时的配置步骤生成。
Source: "launch-dsh.vbs"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\launcher.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\install.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\dsh-version.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\dsh-version.json"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\desktop.patch.yml"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\loading.html"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\token.js"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\dsh.ico"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\modules\*.ps1"; DestDir: "{app}\scripts\modules"; Flags: ignoreversion recursesubdirs
Source: "LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "CleanUninstall.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; 经 wscript（GUI 子系统）无窗口启动，避免 PowerShell 控制台闪现
Name: "{group}\{#MyAppName}"; Filename: "wscript.exe"; \
    Parameters: "//B ""{app}\scripts\launch-dsh.vbs"" ""{app}"""; \
    IconFilename: "{app}\scripts\dsh.ico"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
; 完全卸载工具：额外清除运行期残留文件，并可选删除用户数据
Name: "{group}\完全卸载 {#MyAppName}"; Filename: "{app}\CleanUninstall.exe"; \
    IconFilename: "{app}\scripts\dsh.ico"; Comment: "彻底移除程序文件、快捷方式与注册表项（可选删除用户数据）"
Name: "{autodesktop}\{#MyAppName}"; Filename: "wscript.exe"; \
    Parameters: "//B ""{app}\scripts\launch-dsh.vbs"" ""{app}"""; \
    IconFilename: "{app}\scripts\dsh.ico"; Tasks: desktopicon

[Run]
; 完成页复选框：安装后立即启动（默认勾选；启动器 2 秒内即显示加载窗口。
; nowait 不阻塞安装程序退出；skipifsilent 使静默安装跳过此步）
Filename: "wscript.exe"; \
    Parameters: "//B ""{app}\scripts\launch-dsh.vbs"" ""{app}"""; \
    Description: "立即启动 DeepSeek Harness"; \
    Flags: postinstall nowait skipifsilent runhidden

[UninstallRun]
; 卸载时清除指向安装目录的 DSH_HOME 用户环境变量
Filename: "powershell.exe"; \
    Parameters: "-ExecutionPolicy Bypass -NoProfile -Command ""[Environment]::SetEnvironmentVariable('DSH_HOME', $null, 'User')"""; \
    Flags: runhidden; RunOnceId: "RemoveDshHomeEnvVar"

[Code]
// ---- Win32 API ----
// HWND_BROADCAST 为 Inno 内置常量，此处仅声明消息标志与 API
const
  WM_SETTINGCHANGE = $1A;
  SMTO_ABORTIFHUNG = $0002;

procedure SendMessageTimeoutW(hWnd: HWND; Msg: Cardinal; wParam: Cardinal;
  lParam: String; fuFlags: Cardinal; uTimeout: Cardinal; var lpdwResult: Cardinal);
  external 'SendMessageTimeoutW@user32.dll stdcall';
procedure SleepEx(dwMilliseconds: Cardinal);
  external 'Sleep@kernel32.dll stdcall';

// ---- 工具过程：以 UTF-8（带 BOM）覆盖/追加写整段文本 ----
procedure SaveStringToUTF8(const FileName, Text: String; const Append: Boolean);
var
  Lines: TArrayOfString;
begin
  SetArrayLength(Lines, 1);
  Lines[0] := Text;
  SaveStringsToUTF8File(FileName, Lines, Append);
end;

// ---- 页面控件 ----
var
  EnvPage: TWizardPage;
  LblIntro: TNewStaticText;
  LblNode: TNewStaticText;
  LblPnpm: TNewStaticText;
  LblChrome: TNewStaticText;
  LblHint: TNewStaticText;
  BtnRecheck: TNewButton;

// ---- 环境检测 ----
function CheckCmdOk(const Cmd: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'), '/c ' + Cmd + ' >nul 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

function FindChromePath(): String;
begin
  Result := '';
  if FileExists(ExpandConstant('{pf}\Google\Chrome\Application\chrome.exe')) then
    Result := ExpandConstant('{pf}\Google\Chrome\Application\chrome.exe')
  else if FileExists(ExpandConstant('{pf32}\Google\Chrome\Application\chrome.exe')) then
    Result := ExpandConstant('{pf32}\Google\Chrome\Application\chrome.exe')
  else if FileExists(ExpandConstant('{localappdata}\Google\Chrome\Application\chrome.exe')) then
    Result := ExpandConstant('{localappdata}\Google\Chrome\Application\chrome.exe');
end;

procedure SetEnvRow(Lbl: TNewStaticText; const Prefix, Detail: String; Status: Integer);
// Status: 0=正常(绿) 1=缺失(红) 2=检测中(灰)
begin
  Lbl.Caption := Prefix + Detail;
  if Status = 0 then
    Lbl.Font.Color := clGreen
  else if Status = 1 then
    Lbl.Font.Color := clRed
  else
    Lbl.Font.Color := clGrayText;
end;

procedure RunEnvCheck();
var
  ChromePath: String;
begin
  SetEnvRow(LblNode,   'Node.js (>=18) ............ ', '检测中...', 2);
  SetEnvRow(LblPnpm,   'pnpm (>=8) ................ ', '检测中...', 2);
  SetEnvRow(LblChrome, 'Google Chrome ............. ', '检测中...', 2);
  BtnRecheck.Enabled := False;

  if CheckCmdOk('node --version') then
    SetEnvRow(LblNode, 'Node.js (>=18) ............ ', '√ 已安装', 0)
  else
    SetEnvRow(LblNode, 'Node.js (>=18) ............ ', '× 未检测到（必需）', 1);

  if CheckCmdOk('pnpm --version') then
    SetEnvRow(LblPnpm, 'pnpm (>=8) ................ ', '√ 已安装', 0)
  else
    SetEnvRow(LblPnpm, 'pnpm (>=8) ................ ', '× 未检测到（必需，可用 corepack enable 启用）', 1);

  ChromePath := FindChromePath;
  if ChromePath <> '' then
    SetEnvRow(LblChrome, 'Google Chrome ............. ', '√ 已安装', 0)
  else
    SetEnvRow(LblChrome, 'Google Chrome ............. ', '× 未检测到（界面需要 Chrome）', 1);

  BtnRecheck.Enabled := True;
end;

procedure RecheckClick(Sender: TObject);
begin
  RunEnvCheck;
end;

// ---- 页面初始化 ----
procedure InitializeWizard();
var
  Y: Integer;
begin
  // 自定义「环境检测」页：位于许可证页之后、安装目录页之前
  EnvPage := CreateCustomPage(wpLicense,
    '环境检测', '安装前请确认以下必需组件');

  LblIntro := TNewStaticText.Create(EnvPage);
  LblIntro.Parent := EnvPage.Surface;
  LblIntro.AutoSize := False;
  LblIntro.WordWrap := True;
  LblIntro.Width := EnvPage.SurfaceWidth;
  LblIntro.Height := ScaleY(36);
  LblIntro.Caption := 'DeepSeek Harness 依赖 Node.js、pnpm 与 Google Chrome。安装程序已自动检测当前环境：';

  Y := ScaleY(50);
  LblNode := TNewStaticText.Create(EnvPage);
  LblNode.Parent := EnvPage.Surface;
  LblNode.AutoSize := False;
  LblNode.Width := EnvPage.SurfaceWidth;
  LblNode.Height := ScaleY(18);
  LblNode.Top := Y;
  LblNode.Font.Name := 'Consolas';
  LblNode.Font.Size := 9;

  Y := Y + ScaleY(26);
  LblPnpm := TNewStaticText.Create(EnvPage);
  LblPnpm.Parent := EnvPage.Surface;
  LblPnpm.AutoSize := False;
  LblPnpm.Width := EnvPage.SurfaceWidth;
  LblPnpm.Height := ScaleY(18);
  LblPnpm.Top := Y;
  LblPnpm.Font.Name := 'Consolas';
  LblPnpm.Font.Size := 9;

  Y := Y + ScaleY(26);
  LblChrome := TNewStaticText.Create(EnvPage);
  LblChrome.Parent := EnvPage.Surface;
  LblChrome.AutoSize := False;
  LblChrome.Width := EnvPage.SurfaceWidth;
  LblChrome.Height := ScaleY(18);
  LblChrome.Top := Y;
  LblChrome.Font.Name := 'Consolas';
  LblChrome.Font.Size := 9;

  Y := Y + ScaleY(34);
  BtnRecheck := TNewButton.Create(EnvPage);
  BtnRecheck.Parent := EnvPage.Surface;
  BtnRecheck.Top := Y;
  BtnRecheck.Width := ScaleX(110);
  BtnRecheck.Height := ScaleY(26);
  BtnRecheck.Caption := '重新检测';
  BtnRecheck.OnClick := @RecheckClick;

  Y := Y + ScaleY(38);
  LblHint := TNewStaticText.Create(EnvPage);
  LblHint.Parent := EnvPage.Surface;
  LblHint.AutoSize := False;
  LblHint.WordWrap := True;
  LblHint.Width := EnvPage.SurfaceWidth;
  LblHint.Height := ScaleY(48);
  LblHint.Top := Y;
  LblHint.Font.Color := clGrayText;
  LblHint.Caption := '提示：Node.js 可从 https://nodejs.org 下载（>=18）；pnpm 可在安装 Node 后运行 '
    + '「corepack enable」启用。缺少必需组件仍可继续安装，但请在首次启动前补齐。';
end;

// ---- 启动前的 Node 预检（在向导最早期给出提示）----
function IsNodeInstalled(): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'), '/c node --version >nul 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := Result and (ResultCode = 0);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if not IsNodeInstalled() then
  begin
    if MsgBox('未在当前系统检测到 Node.js。' + #13#10 +
              'DeepSeek Harness 需要 Node.js >= 18。' + #13#10 + #13#10 +
              '请从 https://nodejs.org 下载安装后重新运行本安装程序。' + #13#10 + #13#10 +
              '是否仍要继续？（您可以稍后再安装 Node.js）',
              mbConfirmation, MB_YESNO) = IDNO then
      Result := False;
  end;
end;

// ---- 页面切换：进入环境检测页时自动执行一次检测 ----
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = EnvPage.ID then
    RunEnvCheck;
end;

// ---- 安装后配置：自定义分步进度页 ----
procedure ConfigureWorkspace();
var
  Page: TOutputProgressWizardPage;
  Workspace, WebDir, AppDir, PkgPath: String;
  EnvVal: String;
  Res: Cardinal;
  ProfileJson, WorkspaceJson: String;
begin
  AppDir := ExpandConstant('{app}');
  Workspace := AddBackslash(GetEnv('USERPROFILE')) + 'dsh-workspace';
  WebDir := AddBackslash(Workspace) + 'profiles\web';

  ProfileJson :=
    '{' + #13#10 +
    '  "name": "dsh-profile-web",' + #13#10 +
    '  "private": true,' + #13#10 +
    '  "dependencies": {},' + #13#10 +
    '  "dsh": {' + #13#10 +
    '    "profile": {' + #13#10 +
    '      "bundles": [' + #13#10 +
    '        "@deepseek-ai/dsh-base",' + #13#10 +
    '        "@deepseek-ai/dsh-web-app"' + #13#10 +
    '      ]' + #13#10 +
    '    }' + #13#10 +
    '  }' + #13#10 +
    '}';

  WorkspaceJson :=
    '{' + #13#10 +
    '  "name": "dsh-workspace",' + #13#10 +
    '  "version": "1.1.0",' + #13#10 +
    '  "description": "DSH workspace - managed via semver range",' + #13#10 +
    '  "dependencies": {' + #13#10 +
    '    "@deepseek-ai/dsh": ">=0.1.5-rc.1 <0.1.5-rc.2"' + #13#10 +
    '  },' + #13#10 +
    '  "devDependencies": {},' + #13#10 +
    '  "scripts": {' + #13#10 +
    '    "dsh:version": "dsh --version",' + #13#10 +
    '    "dsh:web": "dsh web",' + #13#10 +
    '    "dsh:update": "pnpm update @deepseek-ai/dsh",' + #13#10 +
    '    "dsh:check": "pnpm outdated @deepseek-ai/dsh"' + #13#10 +
    '  },' + #13#10 +
    '  "packageManager": "pnpm@9.0.0",' + #13#10 +
    '  "engines": {' + #13#10 +
    '    "node": ">=18",' + #13#10 +
    '    "pnpm": ">=8"' + #13#10 +
    '  }' + #13#10 +
    '}';

  Page := CreateOutputProgressPage('正在配置 DeepSeek Harness',
    '正在初始化工作区，请稍候...');
  Page.SetProgress(0, 100);
  Page.Show;
  try
    // 1/6 创建工作区目录
    Page.Msg2Label.Caption := '正在创建工作区目录：' + Workspace;
    ForceDirectories(WebDir);
    Page.SetProgress(17, 100);
    SleepEx(250);

    // 2/6 写入 workdir.txt（launcher 据此定位工作区；须在 {app}\scripts\ 下）
    Page.Msg2Label.Caption := '正在写入 workdir.txt 工作区指针...';
    SaveStringToUTF8(AddBackslash(AppDir) + 'scripts\workdir.txt', Workspace, False);
    Page.SetProgress(34, 100);
    SleepEx(250);

    // 3/6 profiles/web/package.json
    Page.Msg2Label.Caption := '正在创建 DSH Web 配置（profiles/web/package.json）...';
    PkgPath := AddBackslash(WebDir) + 'package.json';
    if not FileExists(PkgPath) then
      SaveStringToUTF8(PkgPath, ProfileJson, False);
    Page.SetProgress(50, 100);
    SleepEx(250);

    // 4/6 工作区 package.json（semver 范围，非锁定版本）
    Page.Msg2Label.Caption := '正在写入工作区 package.json（DSH semver 依赖范围）...';
    PkgPath := AddBackslash(Workspace) + 'package.json';
    if not FileExists(PkgPath) then
      SaveStringToUTF8(PkgPath, WorkspaceJson, False);
    Page.SetProgress(68, 100);
    SleepEx(250);

    // 5/6 清理旧版 DSH_HOME 用户环境变量（数据固定 ~/.dsh，重装/升级不丢失）
    Page.Msg2Label.Caption := '正在清理旧版 DSH_HOME 环境变量...';
    if RegQueryStringValue(HKCU, 'Environment', 'DSH_HOME', EnvVal) then
    begin
      RegDeleteValue(HKCU, 'Environment', 'DSH_HOME');
      // 广播环境变量变更，使新进程立即可见
      SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, 'Environment',
        SMTO_ABORTIFHUNG, 5000, Res);
    end;
    Page.SetProgress(86, 100);
    SleepEx(250);

    // 6/6 完成
    Page.Msg2Label.Caption := '配置完成。';
    Page.SetProgress(100, 100);
    SleepEx(400);
  finally
    Page.Hide;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    ConfigureWorkspace;
end;
