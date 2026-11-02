# ✦ CuteTerm

**Native Rust terminal workbench for Windows.** A Claude Code–style interactive command experience with the Arctic-glass visual direction from your reference: original pastel ASCII cat, animated startup, system sidebar, colored output, command palette, tabs, and custom commands.

CuteTerm is **not** a PowerShell wrapper and has **no PowerShell runtime requirement**. The application is written in Rust with Ratatui and Crossterm. Windows Terminal supplies the outer acrylic window and native window tabs.

## Windows download

[Download the latest Windows release](https://github.com/taithedev/Cuteterm/releases/latest). Choose the `CuteTerm-Windows-Setup-0.5.0.exe` file for the Rust rewrite.

After installation, open **CuteTerm** from Start or type `cuteterm.exe` from its installation directory. A Windows Terminal profile named **CuteTerm** is also installed as a JSON fragment. Windows Terminal must be installed separately to obtain true acrylic blur.

Windows 10/11 x64 is required. The user-level installer does not require administrator rights. The executable and updater are native Rust; Python is only used to package releases in CI.

## Run the Rust project from source

Install the stable Rust toolchain, then:

```cmd
git clone https://github.com/taithedev/Cuteterm.git
cd Cuteterm
cargo run --release
```

To build native Windows executables:

```cmd
cargo build --release
target\release\cuteterm.exe
```

## How to use the interface

Enter a real Windows command normally (like `dir`, `git status`, `cargo build`, `dotnet test`, or `lua -v`). CuteTerm runs it with the operating system's command processor and captures output in the active workspace. `cd`, `pwd`, `cls` and `clear` are supported natively.

Use slash commands for the interactive control layer:

```text
/help
/commands
/find git
/new
/tabs
/tab 2
/rename backend
/theme arctic
/theme oled
/animate off
/system
/cwd
/cd C:\Projects
/shell
/shell cmd.exe
/window
/split
/plugins
/plugin new hello cmd.exe
/plugin reload
/update check
/update install
/update auto
/update notify
/update off
/exit
```

**Shortcuts:** Ctrl+T new workspace, Ctrl+W close, Alt+1–9 switch tabs, Up/Down command history, Tab slash completion, PageUp/PageDown output scroll, Ctrl+C cancel running process, Ctrl+Q quit.

Regular shell commands work inside each workspace. Commands that require a fully interactive terminal (such as TUIs and REPLs) should use `/shell`, which temporarily hands the real console to `cmd.exe` or another shell, then returns to CuteTerm. An embedded ConPTY emulator is not part of v0.5.0.

## Custom commands

The repository's `commands/` folder includes examples for Git, Cargo, .NET, Lua and CMD. Your private extensions live in `%LOCALAPPDATA%\CuteTerm\commands`.

Custom extensions use JSON manifests so you can add commands without compiling Rust:

```json
{
  "name": "git-status",
  "description": "Show current Git status",
  "program": "git.exe",
  "args": ["status", "--short", "--branch"]
}
```

Save as `%LOCALAPPDATA%\CuteTerm\commands\git-status.json`, run `/plugin reload`, then `/git-status`. Commands run with your existing Windows user permissions. Only install custom command manifests from sources you trust.

**Command counts are real.** `/commands` distinguishes implemented CuteTerm actions, custom commands and executables actually found on your PATH. This release does not pretend that 355 separately implemented Rust commands exist. Windows, Git, Rust, Node, Python, C# tools, and other programs can be used when they are installed.

## Themes, tabs and Arctic blur

Five themes are included: **Arctic, Blossom, Midnight, Mint, OLED**. Type `/theme arctic` to choose Arctic.

The Windows installer adds `terminal/CuteTerm.json` to your per-user Windows Terminal **Fragments** directory. It contributes a modern pastel profile with real Windows Terminal acrylic blur, saved opacity and colors without modifying your other profiles. Your personal settings in `%LOCALAPPDATA%\CuteTerm` survive updates.

In-app tabs are independent Rust workspaces with separate working directories and process logs. The `/window` and `/split` commands request real Windows Terminal tabs and split panes.

## Verified auto-updates

CuteTerm checks [official GitHub Releases](https://github.com/taithedev/Cuteterm/releases) at startup up to once per 24 hours. If the release contains a newer `CuteTerm-Windows-x64.zip` with a matching GitHub SHA-256 digest, it launches the separate `cuteterm-updater.exe` and exits before the executable is replaced. An invalid checksum aborts the update.

You control the behavior with `/update auto`, `/update notify` or `/update off`. Custom commands and settings are stored outside the program folder, so updates preserve them. Automatic updates require network access and write permissions to the per-user install folder.

Windows installer assets are currently unsigned. Only download from the official GitHub Releases page.

## Repository layout

```text
src/
  main.rs                Rust CLI entrypoint
  app.rs                 Ratatui workspace UI + keyboard controls
  commands.rs            Process execution and command packs
  theme.rs               Pastel palettes
  config.rs              User config and history paths
  update.rs              Verified GitHub release auto-updates
  bin/cuteterm-updater.rs Separate Windows update helper
commands/                 Built-in JSON command examples
terminal/CuteTerm.json    Windows Terminal acrylic fragment
installer/CuteTerm.iss    Native Windows EXE installer
installer/package.py      Build-time packaging (not runtime)
.github/workflows/        Rust Windows build, smoke tests and release
```

Note: the repo's Git history contains a previous PowerShell/C# prototype. v0.5.0 replaces that architecture with the Rust executable.

**Project:** [taithedev/Cuteterm](https://github.com/taithedev/Cuteterm) · [Windows downloads](https://github.com/taithedev/Cuteterm/releases/latest)
