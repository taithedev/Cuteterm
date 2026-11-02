# CuteTerm 0.4.0 — Windows installer and automatic updates

First Windows-only installer release of CuteTerm's CLI edition.

- Windows setup executable that installs the CuteTerm PowerShell 7 CLI per user.
- Windows Terminal profile with Arctic acrylic blur, tabs, split panes and color themes.
- More than 200 CuteTerm commands and native PowerShell command support.
- Original animated startup and system-information display.
- Verified automatic updates from this repository's official GitHub Releases.
- SHA-256 checked Windows CLI update packages.
- `ct update` and `ct checkupdates` for manual checks.
- Update settings: `ct config set UpdateMode auto|notify|off`.
- Per-user custom commands, preferences and notes survive updates.
- Clean uninstall with user-command backup.

## Requirements

Windows 10/11 and PowerShell 7+. Windows Terminal is recommended for Arctic blur and tabs. PowerShell 7 can be installed via:

```powershell
winget install --id Microsoft.PowerShell -e
```

Download `CuteTerm-Windows-Setup-0.4.0.exe`, run the installer, then launch CuteTerm from your Start menu or enter `cuteterm` in a newly opened terminal.

The installer is currently **unsigned** and may display a Windows SmartScreen warning. Only download from this project's official GitHub Releases page; never bypass warnings for downloads from unknown publishers.

Auto-updating uses the packaged CLI ZIP rather than reinstalling the Windows Apps entry each time. New terminal tabs pick up updated commands; your existing running PowerShell sessions are not force-closed.
