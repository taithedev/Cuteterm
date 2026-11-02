# Custom commands

CuteTerm can run native PowerShell commands **and** your own command scripts. Custom scripts live in:

    %LOCALAPPDATA%\CuteTerm\user-commands

These files are kept when you reinstall CuteTerm. Only use scripts you wrote or reviewed; .ps1 files are executable code with the same permissions as your PowerShell session.

## Create one

In CuteTerm:

    ct command new hello

Open the file printed by the command. Replace it with:

```powershell
function ct-hello {
    param([string]$Name='world')
    Write-Host "Hello, $Name!" -ForegroundColor Cyan
}
Register-CuteTermCommand 'ct-hello' 'custom' 'Print a friendly greeting.'
```

Then:

    ct command reload
    ct hello Tai

The function must have a name starting with ct- to be exported by the CuteTerm module.

## Commands available

    ct command path
    ct command list
    ct command new mytool
    ct command reload
    ct command delete mytool
    ct commands
    ct count
    ct find git

Each loaded command runs in the same persistent PowerShell session. PowerShell cmdlets, applications, scripts, modules, pipeline input/output and ordinary PowerShell syntax remain available.

## Notes

- Custom scripts are loaded in alphabetical order.
- Installing CuteTerm never overwrites your user-commands folder.
- A broken user command prints a warning and the rest of the pack continues loading.
- Do not download and blindly execute remote .ps1 extensions.
