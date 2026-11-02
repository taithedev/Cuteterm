# Executed by the Windows Terminal CuteTerm profile, or the cuteterm launcher.
$env:CUTETERM_HOME=Join-Path $env:LOCALAPPDATA 'CuteTerm'
$module=Join-Path $env:CUTETERM_HOME 'module/CuteTerm.psm1'
if (-not (Test-Path -LiteralPath $module)) {
    Write-Error "CuteTerm module missing: $module. Reinstall from the repository."
    return
}
Import-Module -Name $module -Global -Force -ErrorAction Stop
function global:prompt {
    try { return Get-CuteTermPrompt }
    catch { return 'PS> ' }
}
try { $Host.UI.RawUI.WindowTitle='✦ CuteTerm · PowerShell' } catch { }
Show-CuteTermStartup
