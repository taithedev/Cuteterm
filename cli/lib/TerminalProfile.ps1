# Windows Terminal integration. Only edits its JSON configuration after making a backup.
$script:CuteTermProfileGuid = '{D89D9A8D-4C22-4B8C-91D5-21B4BC869C70}'

function Get-CuteTermTerminalSettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json')
        (Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json')
        (Join-Path $env:LOCALAPPDATA 'Microsoft/Windows Terminal/settings.json')
    )
    foreach ($path in $candidates) { if (Test-Path -LiteralPath $path) { return $path } }
    return $null
}
function Read-CuteTermTerminalSettings {
    param([string]$Path)
    $raw=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $opts=[System.Text.Json.JsonDocumentOptions]::new()
    $opts.CommentHandling=[System.Text.Json.JsonCommentHandling]::Skip
    $opts.AllowTrailingCommas=$true
    $doc=[System.Text.Json.JsonDocument]::Parse($raw,$opts)
    try {
        # Normalize JSONC to standard JSON without changing actual settings values.
        $clean=[System.Text.Json.JsonSerializer]::Serialize($doc.RootElement)
        return ($clean | ConvertFrom-Json -AsHashtable)
    }
    finally { $doc.Dispose() }
}
function Save-CuteTermTerminalSettings {
    param([string]$Path,[System.Collections.IDictionary]$Settings)
    $backup=("{0}.cuteterm-{1}.bak" -f $Path,(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    Copy-Item -LiteralPath $Path -Destination $backup -ErrorAction Stop
    $json=$Settings | ConvertTo-Json -Depth 80
    $temp="$Path.cuteterm.tmp"
    try {
        Set-Content -LiteralPath $temp -Value $json -Encoding utf8 -ErrorAction Stop
        # Validate before replacing.
        $null = Get-Content -LiteralPath $temp -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
    return $backup
}
function Set-CuteTermTerminalProfile {
    param([string]$Root,[switch]$Quiet)
    $path=Get-CuteTermTerminalSettingsPath
    if (-not $path) {
        if (-not $Quiet) { Write-Warning 'Windows Terminal settings.json was not found. Open Windows Terminal once, then run ct theme set arctic.' }
        return $false
    }
    try {
        $settings=Read-CuteTermTerminalSettings -Path $path
        if (-not $settings.Contains('profiles') -or $null -eq $settings.profiles) { $settings.profiles=@{} }
        if (-not $settings.profiles.Contains('list') -or $null -eq $settings.profiles.list) { $settings.profiles.list=@() }
        if (-not $settings.Contains('schemes') -or $null -eq $settings.schemes) { $settings.schemes=@() }
        $cfgPath=Join-Path $Root 'config.json'
        $cfg=Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json -AsHashtable
        $themePath=Join-Path $Root ("themes/{0}.json" -f $cfg.Theme)
        $palette=Get-Content -LiteralPath $themePath -Raw | ConvertFrom-Json -AsHashtable
        $schemeName='CuteTerm ' + $cfg.Theme
        $scheme=[ordered]@{
            name=$schemeName; background=$palette.background; foreground=$palette.foreground
            cursorColor=$palette.pink; selectionBackground=$palette.selection
            black='#171625'; red=$palette.red; green=$palette.green; yellow=$palette.yellow
            blue=$palette.cyan; purple=$palette.pink; cyan=$palette.cyan; white='#DBE3F0'
            brightBlack=$palette.muted; brightRed=$palette.red; brightGreen=$palette.green
            brightYellow=$palette.yellow; brightBlue=$palette.cyan; brightPurple=$palette.pink
            brightCyan=$palette.cyan; brightWhite='#FFFFFF'
        }
        $schemeList=@($settings.schemes | Where-Object { $_.name -ne $schemeName })
        $settings.schemes=@($schemeList)+@($scheme)
        $shell='pwsh.exe -NoLogo -NoExit -File "' + (Join-Path $Root 'start.ps1') + '"'
        $profile=[ordered]@{
            guid=$script:CuteTermProfileGuid; name='CuteTerm'; hidden=$false
            commandline=$shell; startingDirectory='%USERPROFILE%'
            colorScheme=$schemeName; tabTitle='✦ CuteTerm'; tabColor=$palette.pink
            useAcrylic=$true; opacity=[int]$cfg.Opacity
            cursorShape='bar'; padding='15, 12, 15, 12'
            font=@{ face='Cascadia Mono'; size=11 }
            historySize=9001
        }
        $profiles=@($settings.profiles.list | Where-Object { $_.guid -ne $script:CuteTermProfileGuid -and $_.name -ne 'CuteTerm' })
        $settings.profiles.list=@($profiles)+@($profile)
        $settings['alwaysShowTabs']=$true
        $settings['showTabsInTitlebar']=$true
        $settings['useAcrylicInTabRow']=$true
        $backup=Save-CuteTermTerminalSettings -Path $path -Settings $settings
        if (-not $Quiet) { Write-Host "Windows Terminal CuteTerm profile installed. Backup: $backup" }
        return $true
    }
    catch {
        Write-Warning "Could not apply Windows Terminal profile: $_"
        return $false
    }
}
function Remove-CuteTermTerminalProfile {
    $path=Get-CuteTermTerminalSettingsPath
    if (-not $path) { return }
    try {
        $settings=Read-CuteTermTerminalSettings -Path $path
        if ($settings.profiles -and $settings.profiles.list) {
            $settings.profiles.list=@($settings.profiles.list | Where-Object { $_.guid -ne $script:CuteTermProfileGuid })
            $backup=Save-CuteTermTerminalSettings -Path $path -Settings $settings
            Write-Host "Removed CuteTerm profile; settings backup: $backup"
        }
    } catch { Write-Warning "Could not remove terminal profile: $_" }
}
