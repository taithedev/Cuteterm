using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace CuteTerm;

public sealed class TerminalForm : Form
{
    private const int WM_NCHITTEST = 0x0084;
    private readonly WebView2 web = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.Transparent };
    private readonly Dictionary<string, ConPtySession> sessions = new();
    private readonly string appHome;
    private readonly string commandDirectory;
    private readonly string settingsPath;
    private readonly System.Windows.Forms.Timer systemTimer = new() { Interval = 2500 };
    private AppSettings settings;
    private bool webReady;

    public TerminalForm()
    {
        Text = "CuteTerm";
        Name = "CuteTerm";
        Width = 1200;
        Height = 770;
        MinimumSize = new Size(750, 470);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.None;
        BackColor = Color.FromArgb(31, 31, 46);
        DoubleBuffered = true;
        appHome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CuteTerm");
        commandDirectory = Path.Combine(appHome, "commands");
        settingsPath = Path.Combine(appHome, "settings.json");
        Directory.CreateDirectory(commandDirectory);
        InstallDefaultCommands();
        settings = AppSettings.Load(settingsPath);
        Environment.SetEnvironmentVariable("CUTETERM_HOME", appHome);
        Environment.SetEnvironmentVariable("CUTETERM_COMMANDS", commandDirectory);
        Controls.Add(web);
        Load += async (_, _) => await InitializeWebAsync();
        FormClosed += (_, _) =>
        {
            systemTimer.Stop();
            foreach (var session in sessions.Values.ToArray()) session.Dispose();
            sessions.Clear();
        };
        systemTimer.Tick += (_, _) =>
        {
            if (!webReady) return;
            var memory = MemoryInfo.Read();
            Send(new { type = "metrics", memoryPercent = memory.UsedPercent, memoryUsedGiB = memory.UsedGiB, memoryTotalGiB = memory.TotalGiB, time = DateTime.Now.ToString("HH:mm") });
        };
        Shown += (_, _) => ApplyBackdrop();
    }

    private void InstallDefaultCommands()
    {
        var defaults = Path.Combine(AppContext.BaseDirectory, "commands", "defaults");
        if (!Directory.Exists(defaults)) return;
        foreach (var source in Directory.EnumerateFiles(defaults, "*.ps1"))
        {
            var target = Path.Combine(commandDirectory, Path.GetFileName(source));
            if (!File.Exists(target)) File.Copy(source, target);
        }
    }

    private async Task InitializeWebAsync()
    {
        var root = Path.Combine(AppContext.BaseDirectory, "ui", "dist");
        if (!File.Exists(Path.Combine(root, "index.html")))
        {
            Controls.Clear();
            Controls.Add(new Label { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.White, Text = "CuteTerm UI assets are missing.\nRun scripts/build.ps1 and relaunch." });
            return;
        }
        try
        {
            await web.EnsureCoreWebView2Async();
            var core = web.CoreWebView2;
            core.SetVirtualHostNameToFolderMapping("cuteterm.local", root, CoreWebView2HostResourceAccessKind.DenyCors);
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.NavigationStarting += (_, e) =>
            {
                if (!e.Uri.StartsWith("https://cuteterm.local/", StringComparison.OrdinalIgnoreCase)) e.Cancel = true;
            };
            core.NewWindowRequested += (_, e) =>
            {
                e.Handled = true;
                if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp))
                {
                    try { Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true }); } catch { }
                }
            };
            core.WebMessageReceived += Receive;
            core.Navigate("https://cuteterm.local/index.html");
        }
        catch (Exception error)
        {
            Controls.Clear();
            Controls.Add(new Label { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.White,
                Text = "Cannot initialize WebView2. Install the Microsoft Edge WebView2 Runtime.\n\n" + error.Message });
        }
    }

    private void Receive(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            if (!e.Source.StartsWith("https://cuteterm.local/", StringComparison.OrdinalIgnoreCase)) return;
            using var doc = JsonDocument.Parse(e.WebMessageAsJson);
            var msg = doc.RootElement;
            if (msg.ValueKind != JsonValueKind.Object) return;
            string type = GetString(msg, "type", 40);
            string id = GetString(msg, "id", 80);
            switch (type)
            {
                case "ready":
                    webReady = true;
                    Send(new { type = "init", user = Environment.UserName, machine = Environment.MachineName, os = Environment.OSVersion.VersionString,
                        theme = settings.Theme, fontSize = settings.FontSize, blur = settings.Blur, appVersion = "0.2.0",
                        commandsFolder = commandDirectory, hasPwsh = ConPtySession.IsOnPath("pwsh.exe") });
                    NewTab(settings.DefaultShell);
                    systemTimer.Start();
                    break;
                case "newTab":
                    NewTab(GetString(msg, "shell", 30));
                    break;
                case "closeTab":
                    if (sessions.Remove(id, out var closed))
                    {
                        _ = Task.Run(closed.Dispose);
                        Send(new { type = "tabClosed", id });
                    }
                    break;
                case "input":
                    if (sessions.TryGetValue(id, out var inputSession))
                    {
                        string data = GetString(msg, "data", 131072);
                        if (data.Length > 0) inputSession.Write(data);
                    }
                    break;
                case "resize":
                    if (sessions.TryGetValue(id, out var resizeSession))
                    {
                        int cols = Math.Clamp(GetInt(msg, "cols", 100), 20, 400);
                        int rows = Math.Clamp(GetInt(msg, "rows", 30), 8, 200);
                        resizeSession.Resize(cols, rows);
                    }
                    break;
                case "window":
                    switch (GetString(msg, "action", 20))
                    {
                        case "drag":
                            if (WindowState == FormWindowState.Normal) { NativeMethods.ReleaseCapture(); NativeMethods.SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero); }
                            break;
                        case "minimize": WindowState = FormWindowState.Minimized; break;
                        case "maximize": WindowState = WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized; break;
                        case "close": Close(); break;
                        case "fullscreen": FormBorderStyle = FormBorderStyle.None; WindowState = WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized; break;
                    }
                    break;
                case "openCommands":
                    Process.Start(new ProcessStartInfo("explorer.exe", "\"" + commandDirectory + "\"") { UseShellExecute = true });
                    break;
                case "openSettings":
                    Process.Start(new ProcessStartInfo("notepad.exe", "\"" + settingsPath + "\"") { UseShellExecute = true });
                    break;
                case "settings":
                    string theme = GetString(msg, "theme", 30);
                    if (theme is "arctic" or "rose" or "midnight" or "forest") settings.Theme = theme;
                    settings.FontSize = Math.Clamp(GetInt(msg, "fontSize", settings.FontSize), 11, 22);
                    if (msg.TryGetProperty("blur", out var blur) && blur.ValueKind is JsonValueKind.True or JsonValueKind.False) settings.Blur = blur.GetBoolean();
                    settings.Save(settingsPath);
                    ApplyBackdrop();
                    Send(new { type = "settingsSaved", theme = settings.Theme, fontSize = settings.FontSize, blur = settings.Blur });
                    break;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine("WebView message error: " + ex);
        }
    }

    private void NewTab(string? requestedShell)
    {
        var shell = requestedShell switch
        {
            "cmd" => "cmd",
            "pwsh" when ConPtySession.IsOnPath("pwsh.exe") => "pwsh",
            "powershell" => "powershell",
            _ => ConPtySession.IsOnPath("pwsh.exe") ? "pwsh" : "powershell"
        };
        var id = Guid.NewGuid().ToString("N");
        var session = new ConPtySession(shell, Path.Combine(AppContext.BaseDirectory, "commands", "bootstrap.ps1"));
        session.Output += chunk => OnUiThread(() => Send(new { type = "output", id, data = chunk }));
        session.Exited += () => OnUiThread(() => Send(new { type = "sessionExited", id }));
        sessions[id] = session;
        Send(new { type = "tabCreated", id, shell });
        try { session.Start(); }
        catch (Exception ex)
        {
            Send(new { type = "output", id, data = "\r\n\u001b[31mCouldn't start terminal: " + ex.Message + "\u001b[0m\r\n" });
            Send(new { type = "sessionExited", id });
        }
    }

    private void OnUiThread(Action action)
    {
        if (IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(action); } catch (InvalidOperationException) { }
    }

    private void Send(object payload)
    {
        if (webReady && web.CoreWebView2 is not null)
            web.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(payload));
    }
    private static string GetString(JsonElement el, string name, int limit)
        => el.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? (value.GetString() ?? "")[..Math.Min(value.GetString()?.Length ?? 0, limit)] : "";
    private static int GetInt(JsonElement el, string name, int fallback)
        => el.TryGetProperty(name, out var value) && value.TryGetInt32(out var number) ? number : fallback;

    private void ApplyBackdrop()
    {
        try
        {
            int dark = 1, corners = 2, backdrop = settings.Blur ? 3 : 1;
            NativeMethods.DwmSetWindowAttribute(Handle, 20, ref dark, sizeof(int));
            NativeMethods.DwmSetWindowAttribute(Handle, 33, ref corners, sizeof(int));
            NativeMethods.DwmSetWindowAttribute(Handle, 38, ref backdrop, sizeof(int));
        }
        catch (DllNotFoundException) { }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_NCHITTEST && WindowState == FormWindowState.Normal)
        {
            var l = m.LParam.ToInt64();
            var position = PointToClient(new Point(unchecked((short)(l & 0xFFFF)), unchecked((short)((l >> 16) & 0xFFFF))));
            const int edge = 7;
            bool left = position.X < edge, right = position.X >= ClientSize.Width - edge;
            bool top = position.Y < edge, bottom = position.Y >= ClientSize.Height - edge;
            int hit = (left, right, top, bottom) switch
            {
                (true, _, true, _) => 13,
                (_, true, true, _) => 14,
                (true, _, _, true) => 16,
                (_, true, _, true) => 17,
                (true, _, _, _) => 10,
                (_, true, _, _) => 11,
                (_, _, true, _) => 12,
                (_, _, _, true) => 15,
                _ => 0
            };
            if (hit != 0) { m.Result = (IntPtr)hit; return; }
        }
        base.WndProc(ref m);
    }
}
