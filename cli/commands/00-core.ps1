# CuteTerm core: management, discoverability and customization.
function ct-help {
    Write-CuteTerm '  CuteTerm / command reference' 'pink'
    Write-CuteTerm '  Every native PowerShell command also works here.' 'muted'
    Write-Host ''
    Write-Host '  ct commands           List CuteTerm commands'
    Write-Host '  ct commands -All      List PowerShell + CuteTerm commands'
    Write-Host '  ct count              Count real available commands'
    Write-Host '  ct find <term>        Search command names and descriptions'
    Write-Host '  ct doctor             Verify installation and dependencies'
    Write-Host '  ct theme list         View available styles'
    Write-Host '  ct theme set arctic   Apply terminal appearance'
    Write-Host '  ct config             View preferences'
    Write-Host '  ct config set Animation off|soft|full'
    Write-Host '  ct command new hello  Create your own ct-hello command'
    Write-Host '  ct command reload     Load edited command files'
    Write-Host '  ct tab                New Windows Terminal tab'
    Write-Host '  ct split              Split the current terminal pane'
    Write-Host '  ct welcome            Replay the animated welcome'
    Write-Host '  ct update             Install latest verified GitHub release'
    Write-Host '  ct checkupdates       Check for a new Windows release'
    Write-Host '  ct config set UpdateMode auto|notify|off'
    Write-Host '  ct uninstall          Remove the CLI installation'
    Write-Host ''
    Write-CuteTerm '  Try Get-Help Get-ChildItem -Examples for native PowerShell.' 'cyan'
}
Register-CuteTermCommand 'ct-help' 'core' 'Show built-in help and examples.'

function ct-commands {
    param([switch]$All,[string]$Category)
    if ($All) {
        Get-Command -ErrorAction SilentlyContinue |
          Sort-Object Name -Unique |
          Select-Object Name,CommandType,Source |
          Format-Table -AutoSize
        return
    }
    $list = @($script:Catalog.Values | Sort-Object Category,Name)
    if ($Category) { $list = @($list | Where-Object Category -EQ $Category) }
    $list | Format-Table Name, Category, Description -AutoSize -Wrap
    Write-CuteTerm ("  {0} CuteTerm commands registered. Use 'ct commands -All' for native PowerShell commands." -f $list.Count) 'cyan'
}
Register-CuteTermCommand 'ct-commands' 'core' 'Discover CuteTerm commands with categories and descriptions.'

function ct-count {
    $commands = @(Get-Command -ErrorAction SilentlyContinue | Sort-Object Name -Unique)
    $cute = @($commands | Where-Object Name -Like 'ct-*')
    $native = @($commands | Where-Object { $_.Name -notlike 'ct-*' -and $_.Name -ne 'ct' })
    Write-CuteTerm ("  Total available command names: {0}" -f $commands.Count) 'green'
    Write-Host ("  Native and other installed commands: {0}" -f $native.Count)
    Write-Host ("  CuteTerm command functions: {0}" -f $cute.Count)
    Write-Host '  Counts are discovered live, not padded with placeholders.'
}
Register-CuteTermCommand 'ct-count' 'core' 'Count executable commands available in your environment.'

function ct-find {
    param([Parameter(Mandatory=$true,Position=0)][string]$Query)
    $matches = @($script:Catalog.Values | Where-Object { $_.Name -like "*$Query*" -or $_.Description -like "*$Query*" -or $_.Category -like "*$Query*" })
    $matches | Sort-Object Name | Format-Table Name, Category, Description -AutoSize -Wrap
    Write-CuteTerm ("  {0} matching CuteTerm commands; native matches:" -f $matches.Count) 'muted'
    Get-Command -Name "*$Query*" -ErrorAction SilentlyContinue | Where-Object Name -NotLike 'ct-*' |
        Sort-Object Name -Unique | Select-Object -First 25 Name,CommandType | Format-Table -AutoSize
}
Register-CuteTermCommand 'ct-find' 'core' 'Search commands, categories, and descriptions.'

function ct-version {
    Write-CuteTerm ("  CuteTerm CLI {0}  •  PowerShell-native" -f (Get-CuteTermCurrentVersion)) 'pink'
    Write-Host ("  PowerShell {0}; {1}" -f $PSVersionTable.PSVersion,[System.Runtime.InteropServices.RuntimeInformation]::OSDescription)
}
Register-CuteTermCommand 'ct-version' 'core' 'Display CuteTerm and PowerShell versions.'

function ct-doctor {
    $checks = @(
        [pscustomobject]@{ Check='PowerShell 7'; Status=($PSVersionTable.PSVersion.Major -ge 7) }
        [pscustomobject]@{ Check='Windows Terminal (wt.exe)'; Status=[bool](Get-Command wt.exe -ErrorAction Ignore) }
        [pscustomobject]@{ Check='Install files'; Status=(Test-Path (Join-Path $script:Root 'module/CuteTerm.psm1')) }
        [pscustomobject]@{ Check='Custom command folder'; Status=(Test-Path (Join-Path $script:Root 'user-commands')) }
        [pscustomobject]@{ Check='Git (optional)'; Status=[bool](Get-Command git -ErrorAction Ignore) }
    )
    $checks | ForEach-Object {
        Write-CuteTerm ("  {0}  {1}" -f $(if ($_.Status) {'PASS'} else {'CHECK'}), $_.Check) $(if ($_.Status) {'green'} else {'yellow'})
    }
    Write-Host ("  Installation: {0}" -f $script:Root)
    Write-CuteTerm '  Windows Terminal is optional for the shell, required for tabs/acrylic.' 'muted'
}
Register-CuteTermCommand 'ct-doctor' 'core' 'Check terminal integration, shell, Git and install files.'

function ct-config {
    param([string]$Action='list',[string]$Key,[string]$Value)
    $cfg=Get-CuteTermConfig
    if ($Action -eq 'list') { $cfg.GetEnumerator() | Sort-Object Name | Format-Table Name,Value -AutoSize; return }
    if ($Action -ne 'set' -or -not $Key) { Write-Host 'Usage: ct config set <Startup|Animation|GitPrompt|Opacity|UpdateMode|UpdateCheckHours> <value>'; return }
    $allowed=@('Startup','Animation','GitPrompt','Opacity','UpdateMode','UpdateCheckHours')
    $proper = @($allowed | Where-Object { $_ -ieq $Key })
    if ($proper.Count -ne 1) { Write-Warning ("Allowed: " + ($allowed -join ', ')); return }
    $Key = $proper[0]
    if ($Key -in @('Startup','GitPrompt')) {
        if ($Value -notin @('true','false','on','off')) { Write-Warning 'Use true/false or on/off.'; return }
        $cfg[$Key] = $Value -in @('true','on')
    } elseif ($Key -eq 'Opacity') {
        $number = 0
        if (-not [int]::TryParse($Value,[ref]$number) -or $number -lt 40 -or $number -gt 100) { Write-Warning 'Opacity must be 40..100.'; return }
        $cfg[$Key] = $number
    } elseif ($Key -eq 'UpdateMode') {
        if ($Value -notin @('auto','notify','off')) { Write-Warning 'UpdateMode: auto, notify or off.'; return }
        $cfg[$Key]=$Value
    } elseif ($Key -eq 'UpdateCheckHours') {
        $number=0
        if (-not [int]::TryParse($Value,[ref]$number) -or $number -lt 1 -or $number -gt 168) { Write-Warning 'UpdateCheckHours must be 1..168.'; return }
        $cfg[$Key]=$number
    } else {
        if ($Value -notin @('off','soft','full')) { Write-Warning 'Animation: off, soft, full.'; return }
        $cfg[$Key]=$Value
    }
    Set-CuteTermConfig $cfg
    if ($Key -eq 'Opacity' -and (Get-Command Set-CuteTermTerminalProfile -ErrorAction Ignore)) {
        Set-CuteTermTerminalProfile -Root $script:Root -Quiet
    }
    Write-CuteTerm ("  Saved {0} = {1}" -f $Key,$cfg[$Key]) 'green'
}
Register-CuteTermCommand 'ct-config' 'core' 'Read and change startup, animation, Git prompt and opacity.'

function ct-theme {
    param([string]$Action='list',[string]$Name)
    $themes = @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'themes') -Filter '*.json' -File | ForEach-Object BaseName)
    if ($Action -eq 'list') {
        $current=(Get-CuteTermConfig).Theme
        $themes | ForEach-Object { Write-Host ("  {0} {1}" -f $(if ($_ -eq $current) {'●'} else {'○'}),$_) }
        return
    }
    if ($Action -ne 'set' -or $Name -notin $themes) { Write-Warning ("Usage: ct theme set <" + ($themes -join '|') + ">"); return }
    $cfg=Get-CuteTermConfig
    $cfg.Theme=$Name
    Set-CuteTermConfig $cfg
    $script:Palette=$null
    if (Get-Command Set-CuteTermTerminalProfile -ErrorAction Ignore) {
        Set-CuteTermTerminalProfile -Root $script:Root -Quiet
    }
    Write-CuteTerm ("  Selected theme: {0}. Open a new tab if appearance did not refresh." -f $Name) 'green'
}
Register-CuteTermCommand 'ct-theme' 'core' 'Select color themes and sync the Windows Terminal profile.'

function ct-command {
    param([string]$Action='list',[string]$Name)
    $dir = Join-Path $script:Root 'user-commands'
    [void](New-Item -ItemType Directory -Path $dir -Force)
    if ($Action -eq 'path') { Write-Output $dir; return }
    if ($Action -eq 'reload') {
        Import-Module (Join-Path $script:Root 'module/CuteTerm.psm1') -Force -Global
        Write-CuteTerm '  Reloaded command packs.' 'green'
        return
    }
    if ($Action -eq 'list') {
        Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | Select-Object Name,Length | Format-Table -AutoSize
        return
    }
    if (-not $Name -or $Name -cnotmatch '^[a-z][a-z0-9-]{1,30}$') {
        Write-Warning 'Use: ct command new <name> or ct command delete <name>. Names: 2-31 lowercase letters, digits, hyphens.'
        return
    }
    $path=Join-Path $dir ($Name + '.ps1')
    if ($Action -eq 'new') {
        if (Test-Path -LiteralPath $path) { Write-Warning 'That command already exists.'; return }
        $template = @'
# Your commands run in your PowerShell session; edit this file to customize it.
function ct-NAME {
    param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Values)
    Write-Host "Hello from your own command!" -ForegroundColor Cyan
    if ($Values) { $Values }
}
Register-CuteTermCommand 'ct-NAME' 'custom' 'My custom CuteTerm command.'
'@
        $template.Replace('NAME',$Name) | Set-Content -LiteralPath $path -Encoding utf8
        Write-CuteTerm ("  Created: {0}" -f $path) 'green'
        Write-Host '  Edit the file, then run: ct command reload'
    } elseif ($Action -eq 'delete') {
        if (-not (Test-Path -LiteralPath $path)) { Write-Warning 'Command file not found.'; return }
        Remove-Item -LiteralPath $path -Confirm
        Write-Host 'Run ct command reload to unload the deleted command.'
    } else { Write-Host 'Usage: ct command <new|list|path|reload|delete> [name]' }
}
Register-CuteTermCommand 'ct-command' 'core' 'Create, list, reload and delete user-owned command scripts.'

function ct-tab {
    if (-not (Get-Command wt.exe -ErrorAction Ignore)) { Write-Warning 'Install Windows Terminal for tabs.'; return }
    & wt.exe -w 0 new-tab -p 'CuteTerm'
}
Register-CuteTermCommand 'ct-tab' 'terminal' 'Open a new Windows Terminal tab with CuteTerm.'

function ct-split {
    param([switch]$Vertical)
    if (-not (Get-Command wt.exe -ErrorAction Ignore)) { Write-Warning 'Install Windows Terminal for split panes.'; return }
    if ($Vertical) { & wt.exe -w 0 split-pane -V -p 'CuteTerm' }
    else { & wt.exe -w 0 split-pane -H -p 'CuteTerm' }
}
Register-CuteTermCommand 'ct-split' 'terminal' 'Split the current Windows Terminal pane.'

function ct-welcome { Show-CuteTermStartup }
Register-CuteTermCommand 'ct-welcome' 'terminal' 'Replay the animated welcome.'

function ct-palette {
    $p = Get-CuteTermPalette
    foreach ($k in @('pink','cyan','green','yellow','red','muted','foreground')) {
        Write-CuteTerm ("  ●  {0}  {1}" -f $k, $p[$k]) $k
    }
}
Register-CuteTermCommand 'ct-palette' 'terminal' 'Preview the current color palette.'

function ct-history { param([int]$Count=30); Get-History -Count $Count | Format-Table Id,CommandLine -AutoSize -Wrap }
Register-CuteTermCommand 'ct-history' 'core' 'Review current PowerShell history.'

function ct-profile {
    Write-Host ("  CuteTerm: {0}" -f $script:Root)
    Write-Host ("  Commands: {0}" -f (Join-Path $script:Root 'user-commands'))
    Write-Host ("  PowerShell: {0}" -f $PROFILE)
}
Register-CuteTermCommand 'ct-profile' 'core' 'Locate configuration, extension scripts and PowerShell profile.'

function ct-update {
    if (-not (Get-Command Invoke-CuteTermUpdate -ErrorAction Ignore)) {
        Write-Warning 'Release updater not installed. Reinstall CuteTerm.'
        return
    }
    [void](Invoke-CuteTermUpdate)
}
Register-CuteTermCommand 'ct-update' 'core' 'Install a verified newer release from GitHub.'

function ct-checkupdates {
    param([switch]$Auto)
    if (-not (Get-Command Get-CuteTermRelease -ErrorAction Ignore)) {
        Write-Warning 'Release updater not installed.'
        return
    }
    if ($Auto) { Test-CuteTermUpdatesAtStartup; return }
    try {
        $latest=Get-CuteTermRelease
        $current=Get-CuteTermCurrentVersion
        $target=[version]($latest.tag_name.Substring(1))
        if ($target -gt $current) {
            Write-CuteTerm ("  New CuteTerm release available: {0} (installed {1}). Run 'ct update'." -f $target,$current) 'yellow'
        } else {
            Write-CuteTerm ("  CuteTerm {0} is up to date." -f $current) 'green'
        }
    } catch { Write-Warning "Could not check releases: $_" }
}
Register-CuteTermCommand 'ct-checkupdates' 'core' 'Check current release and automatic update availability.'

function ct-uninstall {
    $scriptPath=Join-Path $script:Root 'uninstall.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) { Write-Warning "Missing $scriptPath"; return }
    & pwsh -NoProfile -File $scriptPath
}
Register-CuteTermCommand 'ct-uninstall' 'core' 'Start the interactive CuteTerm removal script.'
