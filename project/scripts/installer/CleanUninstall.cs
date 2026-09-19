// ============================================================================
// DeepSeek Harness — Clean Uninstall Tool (完全卸载工具)
//
// 用途：在系统自带的卸载（unins000.exe）之外提供一个"一键彻底清除"的可执行程序。
// 范围：结束 DSH 相关进程 → 运行官方卸载器 → 清除残留文件 → 删除快捷方式
//       → 清除注册表卸载项与 DSH_HOME 环境变量。
// 数据红线：用户数据 ~/.dsh（会话/配置/凭据）默认保留；仅在用户明确选择
//           "完全卸载"（或命令行 /full）时才删除，且检测到开发仓库(.git)时跳过。
//
// 用法：
//   CleanUninstall.exe                 交互模式（确认对话框）
//   CleanUninstall.exe /silent         静默模式，保留用户数据
//   CleanUninstall.exe /silent /full   静默模式，连同用户数据一起删除
//   CleanUninstall.exe /dir <路径>     指定目标安装目录（默认取本程序所在目录）
//   CleanUninstall.exe /test           测试模式：不杀进程、不动注册表/环境变量/快捷方式
// 日志：%TEMP%\dsh-clean-uninstall.log
//
// 编译（.NET Framework 4 自带 csc，无需额外 SDK）：
//   csc /target:winexe /out:CleanUninstall.exe /r:System.dll /r:System.Core.dll
//       /r:System.Management.dll /r:System.Windows.Forms.dll
//       /win32icon:..\dsh.ico /codepage:65001 CleanUninstall.cs
// ============================================================================

using System;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace DeepSeekHarness
{
    internal static class CleanUninstall
    {
        // 与 dsh-setup.iss 的 AppId 保持一致
        private const string AppId = "{B9D2E7F1-3A4C-4E8B-9D6F-1A2B3C4D5E6F}_is1";
        private const string AppName = "DeepSeek Harness";
        private static string _logPath;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
            uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

        private static readonly IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);
        private const uint WM_SETTINGCHANGE = 0x001A;
        private const uint SMTO_ABORTIFHUNG = 0x0002;

        private static void Log(string msg)
        {
            try
            {
                File.AppendAllText(_logPath,
                    DateTime.Now.ToString("yyyy/MM/dd HH:mm:ss") + " - " + msg + "\r\n",
                    Encoding.UTF8);
            }
            catch { }
        }

        private static bool HasArg(string[] args, string name)
        {
            foreach (string a in args)
            {
                if (string.Equals(a, name, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        private static string ArgValue(string[] args, string name)
        {
            for (int i = 0; i < args.Length - 1; i++)
            {
                if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                    return args[i + 1];
            }
            return null;
        }

        private static void KillTree(int pid)
        {
            try
            {
                var psi = new ProcessStartInfo("taskkill.exe",
                    "/PID " + pid + " /T /F")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using (var p = Process.Start(psi)) { p.WaitForExit(8000); }
                Log("  killed process tree PID=" + pid);
            }
            catch (Exception ex) { Log("  kill PID=" + pid + " failed: " + ex.Message); }
        }

        private static void KillDshProcesses(string targetDir)
        {
            int selfPid = Process.GetCurrentProcess().Id;
            Log("Step: killing DSH-related processes");

            // 1) WMI 按命令行匹配（launcher/pnpm/node/chrome-profile 等）
            try
            {
                var searcher = new ManagementObjectSearcher(
                    "SELECT ProcessId, CommandLine FROM Win32_Process");
                foreach (ManagementObject o in searcher.Get())
                {
                    object idObj = o["ProcessId"];
                    object clObj = o["CommandLine"];
                    if (idObj == null) continue;
                    int pid = Convert.ToInt32(idObj);
                    if (pid == selfPid) continue;
                    string cl = clObj as string;
                    if (string.IsNullOrEmpty(cl)) continue;

                    bool hit =
                        cl.IndexOf(targetDir, StringComparison.OrdinalIgnoreCase) >= 0 ||
                        cl.IndexOf("@deepseek-ai", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        cl.IndexOf("dsh-workspace", StringComparison.OrdinalIgnoreCase) >= 0;
                    if (hit && cl.IndexOf("CleanUninstall", StringComparison.OrdinalIgnoreCase) < 0)
                    {
                        Log("  match: PID=" + pid + " " + Clipped(cl, 120));
                        KillTree(pid);
                    }
                }
            }
            catch (Exception ex) { Log("  WMI scan failed: " + ex.Message); }

            // 2) 端口 3080 监听进程兜底（node 服务可能不带可匹配的命令行特征）
            try
            {
                var psi = new ProcessStartInfo("netstat.exe", "-ano -p tcp")
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true
                };
                using (var p = Process.Start(psi))
                {
                    string output = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(5000);
                    foreach (string line in output.Split('\n'))
                    {
                        if (line.IndexOf(":3080", StringComparison.Ordinal) < 0) continue;
                        if (line.IndexOf("LISTENING", StringComparison.Ordinal) < 0) continue;
                        string[] parts = line.Trim().Split();
                        int pid;
                        if (parts.Length > 0 && int.TryParse(parts[parts.Length - 1], out pid)
                            && pid != selfPid && pid != 0)
                        {
                            Log("  port 3080 listener PID=" + pid);
                            KillTree(pid);
                        }
                    }
                }
            }
            catch (Exception ex) { Log("  netstat scan failed: " + ex.Message); }
        }

        private static string Clipped(string s, int max)
        {
            if (s.Length <= max) return s;
            return s.Substring(0, max) + "...";
        }

        private static bool DeleteDir(string path)
        {
            if (!Directory.Exists(path)) return true;
            for (int i = 0; i < 6; i++)
            {
                try
                {
                    Directory.Delete(path, true);
                    if (!Directory.Exists(path)) return true;
                }
                catch { }
                Thread.Sleep(700);
            }
            // 兜底：cmd rmdir /s /q（不跟随 junction，安全性优于递归删除）
            try
            {
                var psi = new ProcessStartInfo("cmd.exe",
                    "/d /c rmdir /s /q \"" + path + "\"")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using (var p = Process.Start(psi)) { p.WaitForExit(15000); }
            }
            catch { }
            return !Directory.Exists(path);
        }

        private static void BroadcastEnvironmentChange()
        {
            UIntPtr result;
            SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, UIntPtr.Zero,
                "Environment", SMTO_ABORTIFHUNG, 3000, out result);
        }

        private static int Main(string[] args)
        {
            _logPath = Path.Combine(Path.GetTempPath(), "dsh-clean-uninstall.log");
            try { File.Delete(_logPath); } catch { }
            Log("=== " + AppName + " Clean Uninstall started ===");

            bool silent = HasArg(args, "/silent");
            bool full = HasArg(args, "/full");
            bool test = HasArg(args, "/test");
            string dirOverride = ArgValue(args, "/dir");

            // 目标目录：默认本程序所在目录（安装后位于 {app} 根）
            string selfPath = Process.GetCurrentProcess().MainModule.FileName;
            string targetDir = string.IsNullOrEmpty(dirOverride)
                ? Path.GetDirectoryName(selfPath)
                : Path.GetFullPath(dirOverride);

            bool keepUserData = true;

            if (!silent)
            {
                string msg =
                    "将彻底卸载 " + AppName + "：\n\n" +
                    "• 结束相关进程\n" +
                    "• 移除安装目录、开始菜单与桌面快捷方式\n" +
                    "• 清除注册表卸载项与 DSH_HOME 环境变量\n\n" +
                    "—— 是(Y)：完全卸载，同时删除用户数据\n" +
                    "     （~\\.dsh 的会话/配置/凭据与工作区，不可恢复！）\n" +
                    "—— 否(N)：标准卸载，保留用户数据（重装可恢复）\n" +
                    "—— 取消：退出\n\n" +
                    "是否继续？";
                DialogResult r = MessageBox.Show(msg, "完全卸载 " + AppName,
                    MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning,
                    MessageBoxDefaultButton.Button2);
                if (r == DialogResult.Cancel)
                {
                    Log("user cancelled");
                    return 0;
                }
                keepUserData = (r != DialogResult.Yes);
            }
            else
            {
                keepUserData = !full;
            }

            Log("targetDir=" + targetDir + " keepUserData=" + keepUserData + " test=" + test);

            // 从安装目录自我复制到 %TEMP% 再继续，
            // 否则正在运行的 exe 会锁住文件，官方卸载器无法清空 {app}。
            string tempExe = Path.Combine(Path.GetTempPath(),
                AppName.Replace(" ", "") + "-CleanUninstall-tmp.exe");
            if (selfPath.StartsWith(targetDir, StringComparison.OrdinalIgnoreCase)
                && !selfPath.Equals(tempExe, StringComparison.OrdinalIgnoreCase))
            {
                Log("relaunching from temp: " + tempExe);
                try
                {
                    File.Copy(selfPath, tempExe, true);
                    var psi = new ProcessStartInfo(tempExe, OriginalArgs(args))
                    {
                        UseShellExecute = false
                    };
                    Process.Start(psi);
                    return 0;
                }
                catch (Exception ex)
                {
                    Log("temp relaunch failed (" + ex.Message + ") — continuing in place");
                }
            }

            // 读取工作区路径（workdir.txt 在 {app}\scripts 下，须在删除前读出）
            string workDir = null;
            string workDirCfg = Path.Combine(targetDir, "scripts", "workdir.txt");
            if (File.Exists(workDirCfg))
            {
                try
                {
                    workDir = File.ReadAllLines(workDirCfg)[0].Trim();
                }
                catch { }
            }

            // ---- Step 1: 结束相关进程 ----
            if (!test) KillDshProcesses(targetDir);
            else Log("Step 1 skipped (test mode)");

            // ---- Step 2: 运行官方卸载器（清除已安装文件、快捷方式、注册表卸载项）----
            Log("Step: running official uninstaller");
            string unins = Path.Combine(targetDir, "unins000.exe");
            if (File.Exists(unins))
            {
                try
                {
                    var psi = new ProcessStartInfo(unins,
                        "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART")
                    {
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                    using (var p = Process.Start(psi))
                    {
                        if (!p.WaitForExit(120000))
                        {
                            // 挂死的卸载器会锁住 {app}，先杀掉再清残留
                            Log("  WARNING: uninstaller did not exit within 120s — killing it");
                            try { p.Kill(); } catch { }
                            p.WaitForExit(5000);
                        }
                        else
                            Log("  unins000 exited with code " + p.ExitCode);
                    }
                }
                catch (Exception ex) { Log("  unins000 failed: " + ex.Message); }
            }
            else
            {
                Log("  unins000.exe not found — skipping");
            }

            // ---- Step 3: 删除残留文件（运行期生成的日志/profile 等）----
            Log("Step: removing leftover files");
            if (Directory.Exists(targetDir))
            {
                if (DeleteDir(targetDir))
                    Log("  removed " + targetDir);
                else
                    Log("  WARNING: could not fully remove " + targetDir);
            }
            else
            {
                Log("  target dir already gone");
            }

            // ---- Step 4: 删除快捷方式（官方卸载器通常已删，兜底再清一次）----
            if (!test)
            {
                Log("Step: removing shortcuts");
                try
                {
                    string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                    string lnk = Path.Combine(desktop, AppName + ".lnk");
                    if (File.Exists(lnk)) { File.Delete(lnk); Log("  removed " + lnk); }

                    string group = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
                        "Programs", AppName);
                    if (Directory.Exists(group) && DeleteDir(group))
                        Log("  removed " + group);
                }
                catch (Exception ex) { Log("  shortcut cleanup failed: " + ex.Message); }
            }
            else Log("Step 4 skipped (test mode)");

            // ---- Step 5: 注册表与环境变量兜底清理 ----
            if (!test)
            {
                Log("Step: cleaning registry and environment");
                try
                {
                    using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                        @"Software\Microsoft\Windows\CurrentVersion\Uninstall", true))
                    {
                        if (k != null)
                        {
                            bool found = false;
                            foreach (string name in k.GetSubKeyNames())
                            {
                                if (string.Equals(name, AppId, StringComparison.OrdinalIgnoreCase))
                                {
                                    found = true;
                                    break;
                                }
                            }
                            if (found)
                            {
                                k.DeleteSubKeyTree(AppId);
                                Log("  deleted uninstall key " + AppId);
                            }
                        }
                    }
                }
                catch (Exception ex) { Log("  uninstall key cleanup: " + ex.Message); }

                try
                {
                    using (var env = Microsoft.Win32.Registry.CurrentUser.OpenSubKey("Environment", true))
                    {
                        if (env != null && env.GetValue("DSH_HOME") != null)
                        {
                            env.DeleteValue("DSH_HOME");
                            Log("  deleted user env var DSH_HOME");
                        }
                    }
                    BroadcastEnvironmentChange();
                }
                catch (Exception ex) { Log("  env cleanup: " + ex.Message); }
            }
            else Log("Step 5 skipped (test mode)");

            // ---- Step 6: 用户数据（仅在"完全卸载"时）----
            if (!keepUserData && !test)
            {
                Log("Step: removing user data (full uninstall)");
                string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                string dshHome = Path.Combine(home, ".dsh");

                if (Directory.Exists(Path.Combine(dshHome, ".git")))
                {
                    // 安全护栏：~/.dsh 是开发仓库（含 .git）时绝不能删
                    Log("  SKIPPED " + dshHome + " — looks like a development repository (.git present)");
                }
                else if (Directory.Exists(dshHome))
                {
                    Log("  remove " + (DeleteDir(dshHome) ? "OK " : "FAILED ") + dshHome);
                }

                if (!string.IsNullOrEmpty(workDir) && Directory.Exists(workDir))
                {
                    if (Directory.Exists(Path.Combine(workDir, ".git")))
                        Log("  SKIPPED workspace " + workDir + " — .git present");
                    else
                        Log("  remove workspace " + (DeleteDir(workDir) ? "OK " : "FAILED ") + workDir);
                }
            }
            else if (test)
            {
                Log("Step 6 skipped (test mode)");
            }
            else
            {
                Log("Step: user data kept (standard uninstall)");
            }

            // ---- 收尾 ----
            Log("=== Clean uninstall finished ===");

            // 删除 %TEMP% 里的自身副本
            if (selfPath.StartsWith(Path.GetTempPath(), StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    var psi = new ProcessStartInfo("cmd.exe",
                        "/d /c ping -n 2 127.0.0.1 > nul & del /f /q \"" +
                        Process.GetCurrentProcess().MainModule.FileName + "\"")
                    {
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                    Process.Start(psi);
                }
                catch { }
            }

            if (!silent)
            {
                string done = keepUserData
                    ? "卸载完成。\n\n已移除：程序文件、快捷方式、注册表项、DSH_HOME 环境变量。\n已保留：用户数据（~\\.dsh）——重装后配置仍然有效。"
                    : "完全卸载完成。\n\n已移除：程序文件、快捷方式、注册表项、环境变量与用户数据。";
                MessageBox.Show(done, "完全卸载 " + AppName,
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            return 0;
        }

        private static string OriginalArgs(string[] args)
        {
            var sb = new StringBuilder();
            foreach (string a in args)
            {
                if (sb.Length > 0) sb.Append(' ');
                if (a.IndexOf(' ') >= 0) sb.Append('"').Append(a).Append('"');
                else sb.Append(a);
            }
            return sb.ToString();
        }
    }
}
