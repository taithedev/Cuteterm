# CuteTerm v0.6.0 — Full Windows ConPTY CLI

CuteTerm now uses persistent Windows pseudo-terminal (ConPTY) sessions inside its native Rust TUI. Windows commands run in a real interactive shell, not a new child shell for every line.

Changes:
- Independent shell tabs with Ctrl+T, Ctrl+W, Alt+1–9.
- Default CMD shell; use the Ctrl+G command palette to launch optional PowerShell, WSL or other installed shells.
- ANSI/VT100 colors, interactive keyboard input, resizing, cursor movement, 2,500-line scrollback, bracketed paste and native command state.
- Pastel Arctic, OLED, Blossom, Mint and Midnight themes, moving artwork, real system information and terminal status.
- Ctrl+G command palette with themes, tabs, plugin manifests, Windows Terminal tabs/panes and update controls.
- Windows x64 per-user installer; adds CLI directory to user PATH and optional Explorer "Open CuteTerm Here".
- Signed-digest (SHA-256) release ZIP updater; settings and custom scripts remain in LocalAppData.

Run cuteterm help from CMD or press Ctrl+G inside CuteTerm, type help, and press Enter.

Requirements: Windows 10 1809+ or Windows 11 x64. Windows Terminal is optional for Arctic acrylic blur; PowerShell is not required. The installer is currently unsigned.

This is an actively developed terminal emulator; not every advanced full-screen application or custom Windows console behavior is guaranteed to work perfectly.
