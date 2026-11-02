# Installs CuteTerm CLI for the current user. Does not require elevation.
[CmdletBinding()]
param([switch]$SkipTerminalProfile)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'CuteTerm CLI requires PowerShell 7+. Install it using: winget install Microsoft.PowerShell' }
if (-not $IsWindows) { throw 'CuteTerm currently supports Windows only.' }
$source=$PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $source 'cli/module/CuteTerm.psm1'))) {
    throw 'Run install.ps1 from the root of the Cuteterm Git repository.'
}
$homeDir=Join-Path $env:LOCALAPPDATA 'CuteTerm'
[void](New-Item -Path $homeDir -ItemType Directory -Force)
foreach ($dir in @('commands','module','lib','themes','updater')) {
    $destination=Join-Path $homeDir $dir
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    [void](New-Item -Path $destination -ItemType Directory -Force)
    Copy-Item -Path (Join-Path (Join-Path $source 'cli') "$dir/*") -Destination $destination -Recurse -Force
}
foreach ($file in @('start.ps1','cli.ps1','version.txt')) {
    Copy-Item -LiteralPath (Join-Path $source "cli/$file") -Destination (Join-Path $homeDir $file) -Force
}
Copy-Item -LiteralPath (Join-Path $source 'uninstall.ps1') -Destination (Join-Path $homeDir 'uninstall.ps1') -Force
[void](New-Item -Path (Join-Path $homeDir 'user-commands') -ItemType Directory -Force)

$configPath=Join-Path $homeDir 'config.json'
$cfg = @{ Theme='arctic'; Animation='soft'; Startup=$true; GitPrompt=$true; Opacity=82; UpdateMode='auto'; UpdateCheckHours=24 }
if (Test-Path -LiteralPath $configPath) {
    try {
        $previous=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
        foreach ($key in @('Theme','Animation','Startup','GitPrompt','Opacity','UpdateMode','UpdateCheckHours')) {
            if ($previous.Contains($key)) { $cfg[$key]=$previous[$key] }
        }
    } catch { Write-Warning 'Old config could not be read; applying defaults.' }
}
$cfg['Source']=$source
$cfg['Version']=(Get-Content -LiteralPath (Join-Path $homeDir 'version.txt') -Raw -ErrorAction Stop).Trim()
$cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding utf8

$binDir=Join-Path $homeDir 'bin'
[void](New-Item -ItemType Directory -Path $binDir -Force)
$launcher=Join-Path $binDir 'cuteterm.cmd'
$batch=@(
    '@echo off'
    'if "%~1"=="" ('
    '    pwsh.exe -NoLogo -NoExit -File "%LOCALAPPDATA%\CuteTerm\start.ps1"'
    ') else ('
    '    pwsh.exe -NoLogo -NoProfile -File "%LOCALAPPDATA%\CuteTerm\cli.ps1" %*'
    ')'
) -join [Environment]::NewLine
Set-Content -LiteralPath $launcher -Value $batch -Encoding ascii

$userPath=[string][Environment]::GetEnvironmentVariable('Path','User')
$entries=@($userPath.Split(';') | Where-Object { $_ })
if ($entries -notcontains $binDir) {
    $newPath=(@($entries)+@($binDir)) -join ';'
    [Environment]::SetEnvironmentVariable('Path',$newPath,'User')
}
if (($env:Path -split ';') -notcontains $binDir) { $env:Path += (';' + $binDir) }

$profileOk=$false
if (-not $SkipTerminalProfile) {
    . (Join-Path $homeDir 'lib/TerminalProfile.ps1')
    $profileOk=Set-CuteTermTerminalProfile -Root $homeDir
}
Write-Host ''
Write-Host '  ✦ CuteTerm CLI installed for this Windows user.' -ForegroundColor Magenta
Write-Host "  Installed at: $homeDir"
Write-Host "  Custom commands: $(Join-Path $homeDir 'user-commands')"
if ($profileOk) {
    Write-Host '  Launch a new CuteTerm tab in Windows Terminal, or run: cuteterm'
} else {
    Write-Host '  Run: cuteterm  (works in PowerShell, CMD and Windows Terminal)'
    Write-Host '  For tabs/acrylic, open Windows Terminal once and run: cuteterm theme set arctic'
}
Write-Host '  Open a NEW shell if cuteterm is not immediately found on PATH.'
Write-Host '  No administrator permissions required.' -ForegroundColor DarkGray
