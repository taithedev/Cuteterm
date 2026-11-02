# Project creation and common build/test flows for real toolchains.
function ct-newproject {
    param([ValidateSet('csharp','lua','python','node')][string]$Language='csharp',[Parameter(Mandatory=$true)][string]$Name)
    if ($Name -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{1,49}$') { throw 'Project names must be 2-50 letters/digits/underscores/hyphens, beginning with a letter.' }
    $path=Join-Path (Get-Location).Path $Name
    if (Test-Path -LiteralPath $path) { throw "Project path already exists: $path" }
    if ($Language -eq 'csharp') {
        Assert-CuteTermTool dotnet
        & dotnet new console --name $Name --output $path
        if ($LASTEXITCODE -ne 0) { throw '.NET project creation failed.' }
    } else {
        [void](New-Item -ItemType Directory -Path $path)
        switch ($Language) {
            'lua' { Set-Content -LiteralPath (Join-Path $path 'main.lua') -Value 'print("Hello from CuteTerm!")' -Encoding utf8 }
            'python' { Set-Content -LiteralPath (Join-Path $path 'main.py') -Value 'print("Hello from CuteTerm!")' -Encoding utf8 }
            'node' {
                $pkg=[ordered]@{ name=$Name.ToLowerInvariant(); version='0.1.0'; private=$true; scripts=@{start='node index.js'} }
                $pkg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $path 'package.json') -Encoding utf8
                Set-Content -LiteralPath (Join-Path $path 'index.js') -Value 'console.log("Hello from CuteTerm!");' -Encoding utf8
            }
        }
    }
    Write-CuteTerm ("Created {0} project: {1}" -f $Language,$path) 'green'
}
function ct-newclass {
    param([Parameter(Mandatory=$true)][string]$Name,[string]$Namespace='CuteTermApp')
    if ($Name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $Namespace -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]*$') { throw 'Invalid C# identifier.' }
    $path="$Name.cs"
    if (Test-Path $path) { throw 'File already exists.' }
    $content="namespace $Namespace;" + [Environment]::NewLine + [Environment]::NewLine + "public sealed class $Name" + [Environment]::NewLine + '{' + [Environment]::NewLine + '}' 
    Set-Content -LiteralPath $path -Value $content -Encoding utf8
    Get-Item -LiteralPath $path
}
function ct-newlua { param([Parameter(Mandatory=$true)][string]$Name); ct-touch $Name; Set-Content -LiteralPath $Name -Value 'print("Hello from Lua!")' -Encoding utf8 }
function ct-newpython { param([Parameter(Mandatory=$true)][string]$Name); ct-touch $Name; Set-Content -LiteralPath $Name -Value 'print("Hello from Python!")' -Encoding utf8 }
function ct-newps {
    param([Parameter(Mandatory=$true)][string]$Name)
    if (-not $Name.EndsWith('.ps1')) { $Name+='.ps1' }
    if (Test-Path $Name) { throw 'File already exists.' }
    Set-Content -LiteralPath $Name -Value 'param()' -Encoding utf8
}
function ct-newjson {
    param([Parameter(Mandatory=$true)][string]$Name)
    if (Test-Path $Name) { throw 'File already exists.' }
    Set-Content -LiteralPath $Name -Value '{}' -Encoding utf8
}
function ct-newreadme {
    param([string]$Title=(Split-Path (Get-Location).Path -Leaf))
    if (Test-Path 'README.md') { throw 'README.md already exists.' }
    Set-Content -LiteralPath 'README.md' -Value ("# " + $Title + [Environment]::NewLine + [Environment]::NewLine + "Made with CuteTerm.") -Encoding utf8
}
function ct-newgitignore {
    if (Test-Path '.gitignore') { throw '.gitignore already exists.' }
    @('bin/','obj/','node_modules/','dist/','.venv/','__pycache__/','.env','.env.local','*.user','*.log') | Set-Content -LiteralPath '.gitignore' -Encoding utf8
}
function ct-dotnetnew { Assert-CuteTermTool dotnet; & dotnet new @args }
function ct-dotnetbuild { Assert-CuteTermTool dotnet; & dotnet build @args }
function ct-dotnetrun { Assert-CuteTermTool dotnet; & dotnet run @args }
function ct-dotnettest { Assert-CuteTermTool dotnet; & dotnet test @args }
function ct-dotnetclean { Assert-CuteTermTool dotnet; & dotnet clean @args }
function ct-dotnetrestore { Assert-CuteTermTool dotnet; & dotnet restore @args }
function ct-dotnetformat { Assert-CuteTermTool dotnet; & dotnet format @args }
function ct-dotnetpublish { Assert-CuteTermTool dotnet; & dotnet publish @args }
function ct-dotnetlist { Assert-CuteTermTool dotnet; & dotnet list @args }
function ct-dotnetsdk { Assert-CuteTermTool dotnet; & dotnet --list-sdks }
function ct-dotnetruntimes { Assert-CuteTermTool dotnet; & dotnet --list-runtimes }
function ct-npminit { Assert-CuteTermTool npm; & npm.cmd init @args }
function ct-npminstall { Assert-CuteTermTool npm; & npm.cmd install @args }
function ct-npmrun { param([Parameter(Mandatory=$true)][string]$Name); Assert-CuteTermTool npm; & npm.cmd run $Name @args }
function ct-npmtest { Assert-CuteTermTool npm; & npm.cmd test @args }
function ct-npmlist { Assert-CuteTermTool npm; & npm.cmd ls --depth=0 @args }
function ct-npmaudit { Assert-CuteTermTool npm; & npm.cmd audit @args }
function ct-npmoutdated { Assert-CuteTermTool npm; & npm.cmd outdated @args }
function ct-buninstall { Assert-CuteTermTool bun; & bun install @args }
function ct-bunrun { param([Parameter(Mandatory=$true)][string]$Script); Assert-CuteTermTool bun; & bun run $Script @args }
function ct-buntest { Assert-CuteTermTool bun; & bun test @args }
function ct-bunx { Assert-CuteTermTool bunx; & bunx @args }
function ct-venv {
    param([string]$Path='.venv')
    ct-py -m venv $Path
    Write-Host ("To activate: . {0}" -f (Join-Path $Path 'Scripts/Activate.ps1'))
}
function ct-piplist { ct-py -m pip list @args }
function ct-pipfreeze { ct-py -m pip freeze @args }
function ct-luarun { param([Parameter(Mandatory=$true)][string]$File); Assert-CuteTermTool lua; & lua $File @args }
function ct-localserve {
    param([ValidateRange(1025,65535)][int]$Port=8000)
    Write-Host "Serving the current folder on http://127.0.0.1:$Port (Ctrl+C to stop)"
    ct-py -m http.server $Port --bind 127.0.0.1
}
function ct-psparse {
    param([Parameter(Mandatory=$true)][string]$Path)
    $tokens=$null; $issues=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).Path,[ref]$tokens,[ref]$issues)
    if (-not $issues -or $issues.Count -eq 0) { Write-Host 'PowerShell syntax valid.' -ForegroundColor Green }
    else { $issues | Format-Table Message,Extent -Wrap }
}
function ct-projectfiles {
    Get-ChildItem -Force -File | Where-Object { $_.Name -match '(\.csproj|\.sln|package\.json|Cargo\.toml|go\.mod|requirements\.txt|pyproject\.toml|\.lua)$' } | Select-Object Name,Length
}
function ct-projectinfo {
    Write-Host ("Project directory: {0}" -f (Get-Location).Path)
    ct-projectfiles
    if (Get-Command git -ErrorAction Ignore) { & git status --short --branch 2>$null }
}
function ct-tools {
    foreach($tool in @('git','dotnet','lua','node','npm','bun','python','py','go','cargo','code','docker','gh','wt')) {
        [pscustomobject]@{ Tool=$tool; Installed=[bool](Get-Command $tool -ErrorAction Ignore) }
    }
}
@(
,@('ct-newproject','Create real C#, Lua, Python or Node project skeleton.')
,@('ct-newclass','Generate a simple C# class.')
,@('ct-newlua','Create a Lua starter file.')
,@('ct-newpython','Create a Python starter file.')
,@('ct-newps','Create a PowerShell starter file.')
,@('ct-newjson','Create an empty JSON file.')
,@('ct-newreadme','Create a README in the current folder.')
,@('ct-newgitignore','Create sensible C#/JS/Python ignore defaults.')
,@('ct-dotnetnew','Run dotnet new.')
,@('ct-dotnetbuild','Build a .NET project.')
,@('ct-dotnetrun','Run a .NET project.')
,@('ct-dotnettest','Run .NET tests.')
,@('ct-dotnetclean','Clean a .NET build.')
,@('ct-dotnetrestore','Restore .NET packages.')
,@('ct-dotnetformat','Run dotnet format.')
,@('ct-dotnetpublish','Publish a .NET project.')
,@('ct-dotnetlist','List .NET project references/packages.')
,@('ct-dotnetsdk','Show installed .NET SDKs.')
,@('ct-dotnetruntimes','Show installed .NET runtimes.')
,@('ct-npminit','Initialize an npm package.')
,@('ct-npminstall','Install npm dependencies.')
,@('ct-npmrun','Run an npm script.')
,@('ct-npmtest','Run npm tests.')
,@('ct-npmlist','List npm dependencies.')
,@('ct-npmaudit','Inspect npm security advisories.')
,@('ct-npmoutdated','List outdated npm dependencies.')
,@('ct-buninstall','Install Bun dependencies.')
,@('ct-bunrun','Run a Bun script.')
,@('ct-buntest','Run Bun tests.')
,@('ct-bunx','Run Bun package binaries.')
,@('ct-venv','Create Python virtual environment.')
,@('ct-piplist','List Python pip packages.')
,@('ct-pipfreeze','Export pip package list to stdout.')
,@('ct-luarun','Run a Lua script.')
,@('ct-localserve','Serve current folder on localhost only.')
,@('ct-psparse','Parse a PowerShell script and show syntax errors.')
,@('ct-projectfiles','Find common project manifest files.')
,@('ct-projectinfo','Summarize working project context.')
,@('ct-tools','Show which development CLIs are installed.')
) | ForEach-Object { Register-CuteTermCommand $_[0] 'projects' $_[1] }
