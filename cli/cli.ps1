# One-shot CLI commands: cuteterm help, cuteterm count, cuteterm theme list, etc.
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$env:CUTETERM_HOME=Join-Path $env:LOCALAPPDATA 'CuteTerm'
$module=Join-Path $env:CUTETERM_HOME 'module/CuteTerm.psm1'
if (-not (Test-Path -LiteralPath $module)) { throw 'CuteTerm is not installed; run install.ps1.' }
Import-Module -Name $module -Force -ErrorAction Stop
if (-not $Arguments -or $Arguments.Count -eq 0) { ct help }
else { ct @Arguments }
