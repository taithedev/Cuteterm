using System.Runtime.InteropServices;
using System.Text.Json;

namespace CuteTerm;

public sealed class AppSettings
{
    public string Theme { get; set; } = "arctic";
    public int FontSize { get; set; } = 14;
    public bool Blur { get; set; } = true;
    public string DefaultShell { get; set; } = "pwsh";

    public static AppSettings Load(string path)
    {
        try
        {
            if (File.Exists(path)) return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path)) ?? new AppSettings();
        }
        catch { /* A damaged settings file must not prevent startup. */ }
        return new AppSettings();
    }
    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }
}

internal static class NativeMethods
{
    [DllImport("dwmapi.dll")]
    internal static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int valueSize);
    [DllImport("user32.dll")]
    internal static extern bool ReleaseCapture();
    [DllImport("user32.dll")]
    internal static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);

    [StructLayout(LayoutKind.Sequential)]
    internal struct MemoryStatus
    {
        public uint Size;
        public uint MemoryLoad;
        public ulong TotalPhysical;
        public ulong AvailablePhysical;
        public ulong TotalPageFile;
        public ulong AvailablePageFile;
        public ulong TotalVirtual;
        public ulong AvailableVirtual;
        public ulong AvailableExtendedVirtual;
    }

    internal static (uint UsedPercent, double UsedGiB, double TotalGiB) Memory()
    {
        var status = new MemoryStatus { Size = (uint)Marshal.SizeOf<MemoryStatus>() };
        if (!GlobalMemoryStatusEx(ref status)) return (0, 0, 0);
        const double gib = 1024d * 1024 * 1024;
        return (status.MemoryLoad, Math.Round((status.TotalPhysical - status.AvailablePhysical) / gib, 1), Math.Round(status.TotalPhysical / gib, 1));
    }
}

internal static class MemoryInfo
{
    public static (uint UsedPercent, double UsedGiB, double TotalGiB) Read() => NativeMethods.Memory();
}
