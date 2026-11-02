# CuteTerm 0.5.0 — Rust-native Windows terminal workbench

This release replaces the PowerShell-first CuteTerm CLI with a standalone **Rust executable**.

## New in 0.5.0

- Polished Claude Code-inspired terminal workbench: animated startup, original ASCII cat, system sidebar, custom-colored output and input panel.
- Rust / Ratatui / Crossterm implementation: no PowerShell runtime dependency.
- Real native Windows command execution with process output and cancellation.
- Multiple independent in-app workspaces: Ctrl+T, Ctrl+W, Alt+1–9, history and custom working directories.
- A command palette with slash commands such as `/help`, `/commands`, `/theme`, `/system`, `/shell`, `/plugin` and `/update`.
- Five built-in themes: Arctic, Blossom, Midnight, Mint and OLED.
- Optional full interactive cmd.exe shell via `/shell`; Windows Terminal remains responsible for genuine native window tabs and acrylic blur.
- User-created JSON command manifests kept in `%LOCALAPPDATA%\CuteTerm\commands` and bundled example commands.
- Automatic update checks against official GitHub Releases, with GitHub asset SHA-256 verification and standalone updater executable. Use `/update auto`, `/update notify`, `/update off`.
- Windows x64 per-user EXE installer, Windows Terminal JSON fragment, and standalone ZIP updates.

## Requirements

Windows 10/11 x64. Windows Terminal is recommended for Arctic acrylic blur; the application itself is a CLI/TUI executable. PowerShell and Python are not runtime requirements. No admin privileges are normally needed for a per-user installation.

## Notes

The in-app output panel captures ordinary subprocess output. Programs requiring a full interactive console should be run via `/shell`. This release does not claim fully embedded ConPTY sessions, split real PTYs, an AI model backend or 355 independently implemented native Rust commands. The `/commands` output distinguishes built-in actions, custom command manifests, and actual installed tools.

Code signing is not yet configured; Windows may identify the installer as an unsigned publisher.
