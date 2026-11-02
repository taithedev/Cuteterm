# Parse + execute core CuteTerm commands on Windows PowerShell 7.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPaths=@((Join-Path $repo 'install.ps1'),(Join-Path $repo 'uninstall.ps1'))
$scriptPaths+=@(Get-ChildItem -LiteralPath (Join-Path $repo 'cli') -Recurse -File | Where-Object Extension -In @('.ps1','.psm1') | ForEach-Object FullName)
$scriptPaths+=@(Get-ChildItem -LiteralPath (Join-Path $repo 'installer') -Recurse -File -Filter '*.ps1' | ForEach-Object FullName)
foreach ($path in $scriptPaths) {
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw ("PowerShell syntax error in {0}: {1}" -f $path,($parseErrors -join '; ')) }
}
Write-Host ("Parsed {0} PowerShell files." -f $scriptPaths.Count)

$env:CUTETERM_HOME=Join-Path $repo 'cli'
Import-Module (Join-Path $repo 'cli/module/CuteTerm.psm1') -Force -ErrorAction Stop
$packCommands=@(Get-Command -Name 'ct-*' -CommandType Function)
if ($packCommands.Count -lt 200) { throw "Expected >=200 real CuteTerm command functions; got $($packCommands.Count)" }
if ((Get-Content -LiteralPath (Join-Path $env:CUTETERM_HOME 'version.txt') -Raw).Trim() -ne '0.4.0') { throw 'CuteTerm release version did not load.' }
ct version
if (-not (Get-Command ct-checkupdates -ErrorAction Ignore)) { throw 'Release updater command was not exported.' }
$allCommands=@(Get-Command -ErrorAction SilentlyContinue | Sort-Object Name -Unique)
if ($allCommands.Count -lt 356) { throw "Expected >=356 real command names on Windows runner; got $($allCommands.Count)" }
if ((ct upper hello) -ne 'HELLO') { throw 'ct upper failed' }
if ((ct lower HELLO) -ne 'hello') { throw 'ct lower failed' }
if ((ct charcount sample) -ne 6) { throw 'ct charcount failed' }
if ((ct bytecount hello) -ne 5) { throw 'ct bytecount failed' }
if ((ct base64decode (ct base64encode 'hello')) -ne 'hello') { throw 'ct base64 roundtrip failed' }
if ((ct slug 'Hello, New World!') -ne 'hello-new-world') { throw 'ct slug failed' }
if ((ct random 2 3) -ne 2) { throw 'ct random failed' }
if (-not (Get-CuteTermPrompt)) { throw 'Prompt failed to render' }
ct theme list
ct command new smokecommand
Import-Module (Join-Path $repo 'cli/module/CuteTerm.psm1') -Force
if (-not (Get-Command ct-smokecommand -ErrorAction Ignore)) { throw 'Custom command did not load' }
ct todo add 'smoke test item'
ct todo list
ct count
Write-Host ("Passed: $($packCommands.Count) CuteTerm functions and $($allCommands.Count) available commands.") -ForegroundColor Green
