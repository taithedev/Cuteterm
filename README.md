# CuteTerm

A native Windows C# terminal-inspired PowerShell command runner with pastel styling, modern tabs, a custom welcome screen, and Windows 11 system backdrop.

## Build

Install the .NET 8 SDK on Windows, then run:

```powershell
dotnet build -c Release
dotnet run
```

## Current capabilities
- Native Windows Forms desktop app (no Electron)
- Multiple PowerShell command tabs
- PowerShell cmdlets and scripts (one process per command)
- Working-directory persistence between commands
- Command history with Up/Down
- Colored output, custom welcome display, dark theme
- Windows 11 DWM backdrop request (subject to OS support)
- Error output and clear/cls

## Important limitations
This is an initial functional preview, **not yet a complete terminal emulator**. Interactive commands such as vim, ssh sessions, and full-screen terminal programs require a ConPTY-based terminal renderer. PowerShell variables, functions and aliases defined in one command do not persist into subsequent commands, since each command runs in a separate PowerShell process. There is no verified count of 355 custom CuteTerm commands. Acrylic blur is best-effort and depends on Windows composition support.

## Roadmap
- ConPTY backend with persistent interactive shell sessions
- VT/ANSI escape sequence renderer and terminal resize
- Close-tab UI and shell profile switching
- Animated startup and live system information
- Settings, themes, transparency, command palette, splits
- Signed Windows installer and automated releases
