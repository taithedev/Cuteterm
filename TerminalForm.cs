using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace CuteTerm;

public sealed class TerminalForm : Form
{
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    private readonly TabControl tabs = new() { Dock = DockStyle.Fill };
    private readonly Label heading = new() { Text = "✦  CuteTerm", ForeColor = Color.FromArgb(255, 194, 218), Font = new Font("Segoe UI", 15, FontStyle.Bold), AutoSize = true };
    private readonly Button add = new() { Text = "+  New tab", FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(56, 54, 74), ForeColor = Color.White, Width = 104, Height = 32 };
    private readonly Label status = new() { Text = "PowerShell  •  Ready", AutoSize = true, ForeColor = Color.FromArgb(169, 213, 193) };
    private readonly Dictionary<TabPage, Session> sessions = new();
    private sealed class Session
    {
        public required RichTextBox Output;
        public required TextBox Input;
        public string Directory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        public readonly List<string> History = new();
        public int HistoryIndex;
        public bool Busy;
    }

    public TerminalForm()
    {
        Text = "CuteTerm"; Width = 1120; Height = 720; MinimumSize = new Size(700, 450);
        BackColor = Color.FromArgb(28, 28, 43); ForeColor = Color.White;
        Font = new Font("Segoe UI", 10);
        var dark = 1; DwmSetWindowAttribute(Handle, 20, ref dark, sizeof(int));
        var backdrop = 3; DwmSetWindowAttribute(Handle, 38, ref backdrop, sizeof(int));
        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 57, Padding = new Padding(15, 10, 0, 0), BackColor = Color.FromArgb(39, 37, 55) };
        heading.Margin = new Padding(0, 3, 28, 0);
        add.FlatAppearance.BorderSize = 0; add.Click += (_, _) => NewTab();
        top.Controls.Add(heading); top.Controls.Add(add);
        var bottom = new Panel { Dock = DockStyle.Bottom, Height = 31, Padding = new Padding(14, 6, 0, 0), BackColor = Color.FromArgb(39, 37, 55) };
        bottom.Controls.Add(status);
        tabs.DrawMode = TabDrawMode.OwnerDrawFixed; tabs.ItemSize = new Size(155, 33);
        tabs.DrawItem += (_, e) => {
            var rect = e.Bounds;
            using var brush = new SolidBrush(e.Index == tabs.SelectedIndex ? Color.FromArgb(66, 61, 84) : Color.FromArgb(39, 37, 55));
            e.Graphics.FillRectangle(brush, rect);
            TextRenderer.DrawText(e.Graphics, tabs.TabPages[e.Index].Text, Font, rect, Color.FromArgb(245, 213, 229), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        };
        Controls.Add(tabs); Controls.Add(bottom); Controls.Add(top);
        NewTab();
    }

    private void NewTab()
    {
        var page = new TabPage("❯ PowerShell") { BackColor = Color.FromArgb(29, 28, 44), Padding = new Padding(12) };
        var output = new RichTextBox { Dock = DockStyle.Fill, ReadOnly = true, BorderStyle = BorderStyle.None, BackColor = page.BackColor, ForeColor = Color.FromArgb(220, 220, 236), Font = new Font("Cascadia Mono", 10), DetectUrls = true, WordWrap = false };
        var input = new TextBox { Dock = DockStyle.Bottom, Height = 32, BorderStyle = BorderStyle.None, BackColor = Color.FromArgb(43, 41, 61), ForeColor = Color.FromArgb(248, 221, 234), Font = new Font("Cascadia Mono", 11), PlaceholderText = "❯  Enter a PowerShell command..." };
        page.Controls.Add(output); page.Controls.Add(input);
        var session = new Session { Output = output, Input = input };
        sessions[page] = session;
        input.KeyDown += async (_, e) => {
            if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; await Execute(session); }
            else if (e.KeyCode == Keys.Up && session.History.Count > 0) { e.SuppressKeyPress = true; session.HistoryIndex = Math.Max(0, session.HistoryIndex - 1); input.Text = session.History[session.HistoryIndex]; input.SelectionStart = input.Text.Length; }
            else if (e.KeyCode == Keys.Down && session.History.Count > 0) { e.SuppressKeyPress = true; session.HistoryIndex = Math.Min(session.History.Count, session.HistoryIndex + 1); input.Text = session.HistoryIndex == session.History.Count ? "" : session.History[session.HistoryIndex]; input.SelectionStart = input.Text.Length; }
        };
        tabs.TabPages.Add(page); tabs.SelectedTab = page;
        Write(session, "  ✦ CuteTerm  •  Your space to create\n", Color.FromArgb(255, 180, 207));
        Write(session, "  PowerShell command runner  |  Type help for commands\n\n", Color.FromArgb(156, 201, 216));
        Write(session, "  " + Environment.UserName + " @ " + Environment.MachineName + "\n", Color.FromArgb(187, 224, 204));
        Write(session, "  Windows " + Environment.OSVersion.Version + "  •  " + Environment.ProcessorCount + " logical processors\n\n", Color.FromArgb(187, 192, 213));
        input.Focus();
    }

    private void Write(Session s, string text, Color color)
    {
        if (s.Output.IsDisposed) return;
        s.Output.SelectionStart = s.Output.TextLength;
        s.Output.SelectionLength = 0;
        s.Output.SelectionColor = color;
        s.Output.AppendText(text);
        s.Output.SelectionColor = s.Output.ForeColor;
        s.Output.ScrollToCaret();
    }

    private async Task Execute(Session s)
    {
        if (s.Busy) return;
        string command = s.Input.Text.Trim();
        s.Input.Clear();
        if (command.Length == 0) return;
        s.History.Add(command); s.HistoryIndex = s.History.Count;
        Write(s, "❯ " + command + "\n", Color.FromArgb(249, 177, 210));
        if (command.Equals("clear", StringComparison.OrdinalIgnoreCase) || command.Equals("cls", StringComparison.OrdinalIgnoreCase)) { s.Output.Clear(); return; }
        if (command.Equals("cuteterm", StringComparison.OrdinalIgnoreCase)) { Write(s, "CuteTerm • Native Windows C# preview\n", Color.LightPink); return; }
        s.Busy = true; s.Input.Enabled = false; status.Text = "PowerShell  •  Running";
        try
        {
            // This preview executes one command per PowerShell process. Interactive TUIs are not supported.
            var script = "Set-Location -LiteralPath " + Quote(s.Directory) + "; " + command + "; Write-Output ('__CUTETERM_PWD__' + (Get-Location).Path)";
            var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
            var psi = new ProcessStartInfo("powershell.exe", "-NoLogo -NoProfile -NonInteractive -EncodedCommand " + encoded)
            {
                RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false,
                CreateNoWindow = true, WorkingDirectory = s.Directory,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            using var p = new Process { StartInfo = psi };
            p.Start();
            var stdout = p.StandardOutput.ReadToEndAsync();
            var stderr = p.StandardError.ReadToEndAsync();
            await p.WaitForExitAsync();
            var outText = await stdout; var errText = await stderr;
            foreach (var line in outText.Split('\n'))
            {
                var clean = line.TrimEnd('\r');
                if (clean.StartsWith("__CUTETERM_PWD__")) { var next = clean["__CUTETERM_PWD__".Length..]; if (Directory.Exists(next)) s.Directory = next; }
                else if (clean.Length > 0) Write(s, clean + "\n", Color.FromArgb(221, 222, 235));
            }
            if (!string.IsNullOrWhiteSpace(errText)) Write(s, errText + "\n", Color.FromArgb(255, 145, 158));
        }
        catch (Exception ex) { Write(s, ex.Message + "\n", Color.FromArgb(255, 145, 158)); }
        finally { s.Busy = false; s.Input.Enabled = true; status.Text = "PowerShell  •  Ready"; s.Input.Focus(); }
    }
    private static string Quote(string value) => "'" + value.Replace("'", "''") + "'";
}