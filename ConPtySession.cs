using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace CuteTerm;

/// <summary>
/// A real, persistent Windows pseudoconsole session. Interactive apps, VT colors,
/// prompt state and PowerShell variables live in the child process, not in the GUI.
/// Windows 10 1809+ is required; CuteTerm targets Windows 11.
/// </summary>
public sealed class ConPtySession : IDisposable
{
    private readonly string shell;
    private readonly string bootstrap;
    private readonly object gate = new();
    private FileStream? inputStream;
    private FileStream? outputStream;
    private IntPtr pseudoConsole;
    private IntPtr process;
    private bool disposed;
    public event Action<string>? Output;
    public event Action? Exited;

    public ConPtySession(string shell, string bootstrap)
    {
        this.shell = shell;
        this.bootstrap = bootstrap;
    }

    public static bool IsOnPath(string executable)
    {
        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            try { if (File.Exists(Path.Combine(directory.Trim('"'), executable))) return true; }
            catch { }
        }
        return false;
    }

    public void Start()
    {
        if (disposed) throw new ObjectDisposedException(nameof(ConPtySession));
        if (pseudoConsole != IntPtr.Zero) throw new InvalidOperationException("Session already started.");

        if (!ConPtyNative.CreatePipe(out var consoleInput, out var inputWriter, IntPtr.Zero, 0))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to create input pipe.");
        if (!ConPtyNative.CreatePipe(out var outputReader, out var consoleOutput, IntPtr.Zero, 0))
        {
            consoleInput.Dispose(); inputWriter.Dispose();
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to create output pipe.");
        }

        try
        {
            int result = ConPtyNative.CreatePseudoConsole(new ConPtyNative.Coord(100, 32), consoleInput, consoleOutput, 0, out pseudoConsole);
            if (result != 0) Marshal.ThrowExceptionForHR(result);
        }
        catch
        {
            inputWriter.Dispose(); outputReader.Dispose();
            throw;
        }
        finally
        {
            consoleInput.Dispose();
            consoleOutput.Dispose();
        }

        IntPtr attributes = IntPtr.Zero;
        try
        {
            IntPtr attributesSize = IntPtr.Zero;
            ConPtyNative.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributesSize);
            attributes = Marshal.AllocHGlobal(attributesSize);
            if (!ConPtyNative.InitializeProcThreadAttributeList(attributes, 1, 0, ref attributesSize))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot initialize process attributes.");
            IntPtr pc = pseudoConsole;
            if (!ConPtyNative.UpdateProcThreadAttribute(attributes, 0, (IntPtr)0x00020016, ref pc,
                    (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot attach pseudoconsole.");

            var startupInfo = new ConPtyNative.StartupInfoEx
            {
                StartupInfo = new ConPtyNative.StartupInfo { cb = Marshal.SizeOf<ConPtyNative.StartupInfoEx>() },
                AttributeList = attributes
            };
            var commandLine = new StringBuilder(BuildCommandLine());
            var workingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (!ConPtyNative.CreateProcessW(null, commandLine, IntPtr.Zero, IntPtr.Zero, false,
                    0x00080000, IntPtr.Zero, workingDirectory, ref startupInfo, out var processInfo))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to launch " + shell);
            process = processInfo.Process;
            ConPtyNative.CloseHandle(processInfo.Thread);
            inputStream = new FileStream(inputWriter, FileAccess.Write, 4096, false);
            outputStream = new FileStream(outputReader, FileAccess.Read, 4096, false);
            _ = Task.Run(ReadLoop);
        }
        catch
        {
            inputWriter.Dispose(); outputReader.Dispose();
            Dispose();
            throw;
        }
        finally
        {
            if (attributes != IntPtr.Zero)
            {
                ConPtyNative.DeleteProcThreadAttributeList(attributes);
                Marshal.FreeHGlobal(attributes);
            }
        }
    }

    private string BuildCommandLine()
    {
        if (shell == "cmd") return "cmd.exe /Q";
        string executable = shell == "pwsh" ? "pwsh.exe" : "powershell.exe";
        string psCommand = ". '" + bootstrap.Replace("'", "''") + "'";
        string encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(psCommand));
        // Bypass applies to this one child process, not the machine-wide policy.
        return executable + " -NoLogo -NoExit -ExecutionPolicy Bypass -EncodedCommand " + encoded;
    }

    private void ReadLoop()
    {
        var bytes = new byte[16384];
        var chars = new char[16384];
        var decoder = Encoding.UTF8.GetDecoder();
        try
        {
            while (true)
            {
                var stream = outputStream;
                if (stream is null) break;
                int count = stream.Read(bytes, 0, bytes.Length);
                if (count == 0) break;
                int length = decoder.GetChars(bytes, 0, count, chars, 0, flush: false);
                if (length > 0) Output?.Invoke(new string(chars, 0, length));
            }
        }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
        finally { Exited?.Invoke(); }
    }

    public void Write(string text)
    {
        lock (gate)
        {
            if (disposed || inputStream is null) return;
            try
            {
                var bytes = Encoding.UTF8.GetBytes(text);
                inputStream.Write(bytes, 0, bytes.Length);
                inputStream.Flush();
            }
            catch (IOException) { }
            catch (ObjectDisposedException) { }
        }
    }

    public void Resize(int cols, int rows)
    {
        lock (gate)
        {
            if (disposed || pseudoConsole == IntPtr.Zero) return;
            ConPtyNative.ResizePseudoConsole(pseudoConsole, new ConPtyNative.Coord(
                (short)Math.Clamp(cols, 20, 400), (short)Math.Clamp(rows, 8, 200)));
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            try { inputStream?.Dispose(); } catch { }
            if (pseudoConsole != IntPtr.Zero)
            {
                try { ConPtyNative.ClosePseudoConsole(pseudoConsole); } catch { }
                pseudoConsole = IntPtr.Zero;
            }
            try { outputStream?.Dispose(); } catch { }
            if (process != IntPtr.Zero) { ConPtyNative.CloseHandle(process); process = IntPtr.Zero; }
        }
    }
}

internal static class ConPtyNative
{
    [StructLayout(LayoutKind.Sequential)]
    internal readonly struct Coord
    {
        public readonly short X;
        public readonly short Y;
        public Coord(short x, short y) { X = x; Y = y; }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct StartupInfo
    {
        public int cb;
        public IntPtr Reserved;
        public IntPtr Desktop;
        public IntPtr Title;
        public int X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute, Flags;
        public short ShowWindow, Reserved2;
        public IntPtr Reserved2Pointer, StdInput, StdOutput, StdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct StartupInfoEx
    {
        public StartupInfo StartupInfo;
        public IntPtr AttributeList;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct ProcessInformation
    {
        public IntPtr Process;
        public IntPtr Thread;
        public int ProcessId;
        public int ThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern bool CreatePipe(out SafeFileHandle readPipe, out SafeFileHandle writePipe, IntPtr pipeAttributes, int size);
    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern int CreatePseudoConsole(Coord size, SafeFileHandle input, SafeFileHandle output, uint flags, out IntPtr pseudoConsole);
    [DllImport("kernel32.dll")]
    internal static extern int ResizePseudoConsole(IntPtr pseudoConsole, Coord size);
    [DllImport("kernel32.dll")]
    internal static extern void ClosePseudoConsole(IntPtr pseudoConsole);
    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern bool InitializeProcThreadAttributeList(IntPtr attributeList, int attributeCount, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern bool UpdateProcThreadAttribute(IntPtr attributeList, uint flags, IntPtr attribute,
        ref IntPtr value, IntPtr size, IntPtr previousValue, IntPtr returnSize);
    [DllImport("kernel32.dll")]
    internal static extern void DeleteProcThreadAttributeList(IntPtr attributeList);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern bool CreateProcessW(string? applicationName, StringBuilder commandLine, IntPtr processAttributes,
        IntPtr threadAttributes, bool inheritHandles, uint creationFlags, IntPtr environment, string currentDirectory,
        ref StartupInfoEx startupInfo, out ProcessInformation processInformation);
    [DllImport("kernel32.dll")]
    internal static extern bool CloseHandle(IntPtr handle);
}
