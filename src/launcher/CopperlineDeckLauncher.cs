using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("Copperline Deck Launcher")]
[assembly: System.Reflection.AssemblyProduct("Copperline Deck")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.0.0.0")]

static class Program
{
    [STAThread]
    static int Main()
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            string script = Path.Combine(root, "CopperlineDeck.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("CopperlineDeck.ps1 not found", script);

            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");

            var psi = new ProcessStartInfo();
            psi.FileName = powershell;
            psi.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"";
            psi.WorkingDirectory = root;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;

            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Copperline Deck", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}