# User-level CuteTerm CLI uninstaller. Preserves a backup of user commands.
[CmdletBinding()]
param([switch]$Force)
$ErrorActionPreference='Stop'
$homeDir=Join-Path $env:LOCALAPPDATA 'CuteTerm'
if (-not (Test-Path -LiteralPath $homeDir)) { Write-Host 'CuteTerm is not installed.'; return }
if (-not $Force) {
    $choice=Read-Host 'Uninstall CuteTerm CLI and remove its Windows Terminal profile? Type YES'
    if ($choice -cne 'YES') { Write-Host 'Cancelled.'; return }
}
$commandDir=Join-Path $homeDir 'user-commands'
if (Test-Path -LiteralPath $commandDir) {
    $backup=Join-Path $env:USERPROFILE ("CuteTerm-user-commands-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $commandDir -Destination $backup -Recurse -Force
    Write-Host "Custom commands backed up to: $backup"
}
$helper=Join-Path $homeDir 'lib/TerminalProfile.ps1'
if (Test-Path -LiteralPath $helper) {
    . $helper
    Remove-CuteTermTerminalProfile
}
$binDir=Join-Path $homeDir 'bin'
$userPath=[string][Environment]::GetEnvironmentVariable('Path','User')
$filtered=@($userPath.Split(';') | Where-Object { $_ -and ($_ -ine $binDir) })
[Environment]::SetEnvironmentVariable('Path',($filtered -join ';'),'User')
Remove-Item -LiteralPath $homeDir -Recurse -Force
Write-Host 'CuteTerm CLI removed. Restart your terminal to refresh PATH.'
