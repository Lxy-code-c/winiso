// winiso.exe —— 图形界面启动器（C# WinForms，编译自 launcher/WinIsoLauncher.cs）
// 作用：找到同目录下的 gui\WinIsoGui.ps1，用 STA 的 Windows PowerShell 打开 WPF 界面。
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

class WinIsoLauncher
{
    [STAThread]
    static void Main(string[] argv)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string gui = Path.Combine(Path.Combine(dir, "gui"), "WinIsoGui.ps1");
        if (!File.Exists(gui)) gui = Path.Combine(dir, "WinIsoGui.ps1");
        if (!File.Exists(gui))
        {
            MessageBox.Show("找不到 gui\\WinIsoGui.ps1。\n请把 winiso.exe 放在 winiso 目录里（与 lib、data 同级）。",
                "winiso", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        string exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        if (!File.Exists(exe)) exe = "powershell.exe";

        var psi = new ProcessStartInfo();
        psi.FileName = exe;
        psi.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + gui + "\"";
        psi.WorkingDirectory = dir;
        psi.UseShellExecute = false;
        try
        {
            var p = Process.Start(psi);
            p.WaitForExit();
            if (p.ExitCode != 0)
                MessageBox.Show("界面退出，代码 " + p.ExitCode, "winiso", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        catch (Exception e)
        {
            MessageBox.Show("启动失败: " + e.Message, "winiso", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
