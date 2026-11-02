# Example custom command. Copy to %LOCALAPPDATA%\CuteTerm\user-commands\hello.ps1,
# then run: ct command reload
function ct-hello {
    param([string]$Name='world')
    Write-Host ("✦ Hello, {0}! Your command is running inside PowerShell." -f $Name) -ForegroundColor Magenta
}
Register-CuteTermCommand 'ct-hello' 'custom' 'Show a personalized CuteTerm greeting.'
