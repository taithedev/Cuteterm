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
# Keep PowerShell's native line editor, with history suggestions and tab completion.
try {
    if (Get-Module -ListAvailable -Name PSReadLine) {
        Import-Module PSReadLine -ErrorAction Stop
        Set-PSReadLineOption -EditMode Windows -PredictionSource History -PredictionViewStyle ListView -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction SilentlyContinue
    }
} catch { Write-Verbose "PSReadLine customization skipped: $_" }
Show-CuteTermStartup
