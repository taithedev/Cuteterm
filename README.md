# ✦ CuteTerm

**A CLI-first PowerShell 7 environment for Windows 11.** Inspired by modern pastel terminal screenshots: original animated intro art, a custom Git-aware prompt, Arctic-style acrylic blur, modern tabs, split panes, five color themes, and your own installable command scripts.

**No standalone GUI is required.** Windows Terminal provides the tabs, rendering, accessibility and blur. The shell remains a real, persistent PowerShell session rather than spawning one process per command. The old WinForms/WebView2 experiment is preserved in the repository but is not used by this CLI installer.

## Install from another CLI

In PowerShell 7:

    git clone https://github.com/taithedev/Cuteterm.git
    cd Cuteterm
    pwsh -File .\install.ps1

If PowerShell 7 is missing, install it with Windows Package Manager from your existing PowerShell console:

    winget install --id Microsoft.PowerShell -e

Windows Terminal is recommended for the tabs and Arctic blur. Open Windows Terminal at least once so that its settings file exists.

After installation, open a new CMD/PowerShell/Windows Terminal session and launch:

    cuteterm

Alternatively select the **CuteTerm** profile from the Windows Terminal tab menu. The CuteTerm CLI installer writes to your user profile and does not need administrator privileges; dependency installation may have different requirements.

Use one-shot commands from another shell:

    cuteterm help
    cuteterm count
    cuteterm theme list

## Real commands

Inside CuteTerm:

    ct help
    ct commands
    ct commands -All
    ct count
    ct find git
    ct doctor

    ct sys
    ct cpu
    ct memory
    ct disks
    ct wifi
    ct ports
    ct ls
    ct findfiles *.cs
    ct grep 'TODO' .\Program.cs
    ct hash .\Program.cs

    ct gstatus
    ct glog
    ct dotnet --info
    ct lua -v
    ct node --version

    ct note new ideas "My first note"
    ct todo add finish CuteTerm
    ct bookmark add project
    ct bookmark go project

    ct theme list
    ct theme set arctic
    ct config set Opacity 78
    ct config set Animation full
    ct tab
    ct split

CuteTerm includes **over 150 named command functions** in the cli/commands folder. You can also run **every real command exposed by your installed PowerShell and external tools**, including cmdlets, aliases, modules, applications, pipelines and interactive tools. On a typical Windows PowerShell 7 installation, this gives far more than 355 usable commands; the exact count varies by installed modules. Run **ct count** for the *actual live count*, and **ct commands -All** for the names. Counts are never inflated with placeholder commands.

See [System commands](cli/commands/10-system.ps1), [Files commands](cli/commands/20-files.ps1), [Developer commands](cli/commands/30-developer.ps1) and [Utility commands](cli/commands/40-utility.ps1).

Some developer shortcuts need their real tools installed first: Git, Lua, Node, Python, .NET, etc.

## Your custom commands

    ct command new hello
    ct command path
    ct command reload
    ct hello

Editable PowerShell scripts live in the user-commands folder below your local AppData CuteTerm installation. Reinstalling does not overwrite this folder. Each script can declare its own ct-prefixed functions and command descriptions. See [Custom Commands Guide](cli/docs/CUSTOM-COMMANDS.md) and [example command](cli/examples/hello.ps1).

**Security:** Custom scripts run with your current Windows account permissions. Use scripts you wrote or reviewed. CuteTerm never automatically elevates, disables execution policies, or downloads and executes remote scripts during startup.

## Arctic blur and themes

Five built-in palettes: **Arctic, Blossom, Midnight, Mint and OLED**. The Windows Terminal profile uses official useAcrylic and opacity settings rather than attempting to fake blur in a text-only process. On installation CuteTerm backs up Windows Terminal settings before patching them. Existing JSONC comments can be lost when the file is reformatted; the original is preserved in the timestamped backup. A damaged settings file is not overwritten.

Windows may disable acrylic during remote sessions, battery saving, or unsupported GPU/composition conditions. The screenshot is an art-direction reference, not a pixel-identical rendering.

## Update / uninstall

    ct update
    ct uninstall

Update uses the recorded Git checkout, does a fast-forward-only pull, then reinstalls the CLI. You can also rerun install.ps1 manually. Uninstall backs up your user-created commands and removes the CuteTerm CLI Windows Terminal profile and PATH entry. It does not attempt to reset unrelated global Terminal preferences.

## Quality and known limitations

- Target: Windows 11 and PowerShell 7. Windows Terminal is optional for the shell itself but required for integrated tabs and acrylic.
- The intro animations are CLI-based, not GPU animations.
- Live command count depends on your actual PowerShell installation.
- Custom commands are local .ps1 scripts, with no sandbox.
- A Windows PowerShell parsing and command smoke-test workflow is included. Passing it cannot guarantee every optional CLI tool works on every user's machine.
- The older GUI source is preserved for reference; the CLI installer does not use or compile it.

Run the tests from the repo root:

    pwsh -File .\cli\tests\Smoke.ps1

[Repository and issues](https://github.com/taithedev/Cuteterm)
