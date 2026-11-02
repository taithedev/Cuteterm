# CuteTerm — Rust native Windows ConPTY terminal

CuteTerm v0.6.1 is a native Rust CLI/TUI with a Claude Code-style control palette and the pastel Arctic look from the project reference. It is NOT a PowerShell wrapper. Each internal tab runs its own real, persistent Windows ConPTY session.

## Windows download and installation

Use the latest official release: https://github.com/taithedev/Cuteterm/releases/latest

Choose CuteTerm-Windows-Setup-0.6.1.exe for the Windows x64 installer. It creates Start menu entries, adds the native executable to your user PATH, and optionally adds an "Open CuteTerm Here" entry to File Explorer. Launch in a new CMD or Windows Terminal window using:

    cuteterm

PowerShell is not needed. Windows Terminal is optional but is recommended for acrylic blur and native window tabs. Supported: Windows 10 1809+ and Windows 11 x64. The setup is unsigned, so use only official repository releases.

## Native Windows shell

CuteTerm starts a persistent cmd.exe shell inside its ConPTY renderer. Shell variables, current directory and interactive command input persist. Type regular Windows commands directly:

    dir
    cd Projects
    echo Hello from CuteTerm
    git status
    cargo build
    dotnet test
    python --version
    winget list

Tools such as Git, Rust, .NET, Python and WSL must be installed separately to work. Native CMD commands do not require PowerShell.

Start the app with a different installed shell:

    cuteterm shell cmd.exe
    cuteterm shell pwsh.exe
    cuteterm shell wsl.exe

Open at a specific folder:

    cuteterm --cwd "C:\Projects"

Show diagnostics and commands without opening the TUI:

    cuteterm doctor
    cuteterm commands
    cuteterm themes
    cuteterm help
    cuteterm check-updates

## CuteTerm command palette

Press Ctrl+G inside CuteTerm to open its command palette; ordinary typing goes directly to the native Windows shell. Examples:

    help
    new
    shell cmd.exe
    shell pwsh.exe
    tabs
    tab 2
    rename my-project
    close
    theme arctic
    theme oled
    sidebar off
    animate off
    system
    commands
    find git
    config
    plugins
    plugin path
    plugin new hello cmd.exe
    plugin reload
    run hello
    window
    split
    update check
    update install
    update auto
    update notify
    update off
    exit

Keyboard: Ctrl+G opens/closes palette, Ctrl+T opens a tab, Ctrl+W closes it, Alt+1–9 selects tabs, Ctrl+Q quits, F1 shows help, mouse wheel/Shift+PgUp/Shift+PgDn scroll terminal output. Other keys are forwarded to the interactive shell.

## Plugins and real command count

CuteTerm supports external command manifests (JSON) in the repository's commands/ folder and your local %LOCALAPPDATA%\CuteTerm\commands directory. An example command looks like this:

    {
      "name": "git-status",
      "description": "Show repository changes",
      "program": "git.exe",
      "args": ["status", "--short", "--branch"]
    }

The Ctrl+G palette's plugin reload action loads changes. Program execution uses your normal Windows account permissions; review manifests you install.

The command count is based on real executables found on Windows PATH. CuteTerm does not claim 355 independently implemented Rust commands.

## Appearance and Windows integration

The Rust terminal has five color palettes, a two-column system panel on wide screens, native tabs and animated pastel artwork. Windows Terminal's official profile fragment in terminal/CuteTerm.json provides real acrylic blur around the CLI and supports separate Windows Terminal tabs/panes. The standalone CLI also works in standard Windows consoles.

The installer can add an optional context-menu action to open at a selected Explorer directory. It installs for the current user, generally without elevation.

## Updates and development

CuteTerm checks GitHub Releases for newer Windows builds (default: auto, at most once every 24 hours). It validates the official asset SHA-256 digest before passing the ZIP to its standalone updater. Open a new terminal session after updating; custom commands and configuration in LocalAppData are preserved.

To build from source with the stable Rust toolchain:

    cargo test --all-targets
    cargo build --release

Source layout:
- src/app.rs — Ratatui UI, tabs, palette, keyboard forwarding
- src/pty.rs — Windows ConPTY shell sessions and VT100 parser
- src/commands.rs — custom command packs and executable discovery
- src/config.rs — settings and user paths
- src/theme.rs — palettes
- src/update.rs — verified release updater
- installer/CuteTerm.iss — Windows x64 installer
- .github/workflows/windows-release.yml — automated tests and release

Please report compatibility issues at https://github.com/taithedev/Cuteterm/issues. Advanced terminal applications may have untested edge cases.
