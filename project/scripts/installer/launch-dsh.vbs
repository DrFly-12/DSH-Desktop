' DeepSeek Harness 无窗口启动器
' 作用：由 wscript.exe（GUI 子系统）承载启动，彻底避免 PowerShell 控制台窗口闪现。
' 用法：wscript.exe //B launch-dsh.vbs "<应用安装目录>"
' 内部：以隐藏窗口（intWindowStyle=0）启动 launcher.ps1 后立即返回（bWaitOnReturn=False）。
Option Explicit
Dim sh, appDir, ps, cmd
If WScript.Arguments.Count < 1 Then WScript.Quit 1
appDir = WScript.Arguments(0)
Set sh = CreateObject("WScript.Shell")
ps = sh.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
cmd = """" & ps & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & appDir & "\scripts\launcher.ps1"""
sh.Run cmd, 0, False
