# Developer shortcuts. Each command calls the installed real tool, with original arguments.
function Assert-CuteTermTool {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction Ignore)) { throw "Missing $Name. Install the tool first." }
}
function ct-git { Assert-CuteTermTool git; & git @args }
function ct-gstatus { Assert-CuteTermTool git; & git status --short --branch }
function ct-glog { param([int]$Count=12); Assert-CuteTermTool git; & git log "--max-count=$Count" --graph --pretty=format:'%h %ad %s [%an]' --date=short }
function ct-groot { Assert-CuteTermTool git; & git rev-parse --show-toplevel }
function ct-gbranch { Assert-CuteTermTool git; & git branch --show-current }
function ct-gbranches { Assert-CuteTermTool git; & git branch --all }
function ct-gdiff { Assert-CuteTermTool git; & git diff @args }
function ct-gstage { Assert-CuteTermTool git; & git add @args }
function ct-gcommit { param([Parameter(Mandatory=$true)][string]$Message); Assert-CuteTermTool git; & git commit -m $Message }
function ct-gpull { Assert-CuteTermTool git; & git pull --ff-only }
function ct-gpush { Assert-CuteTermTool git; & git push }
function ct-gfetch { Assert-CuteTermTool git; & git fetch --all --prune }
function ct-gstash { Assert-CuteTermTool git; & git stash push @args }
function ct-guntracked { Assert-CuteTermTool git; & git ls-files --others --exclude-standard }
function ct-gremote { Assert-CuteTermTool git; & git remote -v }
function ct-gtags { Assert-CuteTermTool git; & git tag --list }
function ct-gblame { param([Parameter(Mandatory=$true)][string]$Path); Assert-CuteTermTool git; & git blame -- $Path }
function ct-npm { Assert-CuteTermTool npm; & npm.cmd @args }
function ct-npx { Assert-CuteTermTool npx; & npx.cmd @args }
function ct-node { Assert-CuteTermTool node; & node @args }
function ct-bun { Assert-CuteTermTool bun; & bun @args }
function ct-dotnet { Assert-CuteTermTool dotnet; & dotnet @args }
function ct-py {
    if (Get-Command py -ErrorAction Ignore) { & py @args }
    elseif (Get-Command python -ErrorAction Ignore) { & python @args }
    else { throw 'Python was not found.' }
}
function ct-pip { ct-py -m pip @args }
function ct-lua { Assert-CuteTermTool lua; & lua @args }
function ct-java { Assert-CuteTermTool java; & java @args }
function ct-cargo { Assert-CuteTermTool cargo; & cargo @args }
function ct-go { Assert-CuteTermTool go; & go @args }
function ct-docker { Assert-CuteTermTool docker; & docker @args }
function ct-gh { Assert-CuteTermTool gh; & gh @args }
function ct-code { Assert-CuteTermTool code; & code @args }
function ct-wt { Assert-CuteTermTool wt; & wt @args }
function ct-winget { Assert-CuteTermTool winget; & winget @args }
function ct-psversion { $PSVersionTable | Format-List }
function ct-dotnetinfo { Assert-CuteTermTool dotnet; & dotnet --info }
function ct-nodeversion { Assert-CuteTermTool node; & node --version }
function ct-pyversion { ct-py --version }
function ct-gitversion { Assert-CuteTermTool git; & git --version }
function ct-tool { param([Parameter(Mandatory=$true)][string]$Name); Get-Command -Name $Name -ErrorAction Stop | Select-Object Name,Version,Source,CommandType }
function ct-jsonvalidate {
    param([Parameter(Mandatory=$true)][string]$Path)
    try {
        $null=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
        Write-Host 'Valid JSON' -ForegroundColor Green
    } catch { Write-Warning ("Invalid JSON: " + $_.Exception.Message) }
}
function ct-http {
    param([Parameter(Mandatory=$true)][string]$Uri,[ValidateSet('GET','HEAD','POST','PUT','PATCH','DELETE')][string]$Method='GET')
    Invoke-WebRequest -Uri $Uri -Method $Method -ErrorAction Stop
}
function ct-httpstatus {
    param([Parameter(Mandatory=$true)][string]$Uri)
    try { (Invoke-WebRequest -Uri $Uri -Method Head -ErrorAction Stop).StatusCode }
    catch { Write-Warning $_.Exception.Message }
}
function ct-porttest {
    param([Parameter(Mandatory=$true)][string]$HostName,[Parameter(Mandatory=$true)][int]$Port)
    Test-NetConnection -ComputerName $HostName -Port $Port
}
function ct-guid { [guid]::NewGuid().ToString() }
function ct-urlencode { param([Parameter(Mandatory=$true)][string]$Value); [uri]::EscapeDataString($Value) }
function ct-urldecode { param([Parameter(Mandatory=$true)][string]$Value); [uri]::UnescapeDataString($Value) }
function ct-base64encode { param([Parameter(Mandatory=$true)][string]$Value); [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value)) }
function ct-base64decode {
    param([Parameter(Mandatory=$true)][string]$Value)
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}
function ct-hexencode { param([Parameter(Mandatory=$true)][string]$Value); [Convert]::ToHexString([Text.Encoding]::UTF8.GetBytes($Value)) }
function ct-hexdecode { param([Parameter(Mandatory=$true)][string]$Value); [Text.Encoding]::UTF8.GetString([Convert]::FromHexString($Value)) }
function ct-sha256text {
    param([Parameter(Mandatory=$true)][string]$Value)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}
function ct-bytecount { param([Parameter(Mandatory=$true)][string]$Value); [Text.Encoding]::UTF8.GetByteCount($Value) }
function ct-shells { Get-Command pwsh,powershell,cmd,wsl -ErrorAction SilentlyContinue | Select-Object Name,Source }
@(
@('ct-git','Run git with arguments.')
@('ct-gstatus','Show short Git working-tree status.')
@('ct-glog','Show a recent Git commit graph.')
@('ct-groot','Show repository root.')
@('ct-gbranch','Print active branch.')
@('ct-gbranches','List local and remote Git branches.')
@('ct-gdiff','View Git working diff.')
@('ct-gstage','Stage Git files explicitly.')
@('ct-gcommit','Commit staged changes with a message.')
@('ct-gpull','Fast-forward pull current branch.')
@('ct-gpush','Push current branch.')
@('ct-gfetch','Fetch all Git remotes.')
@('ct-gstash','Stash working changes.')
@('ct-guntracked','List untracked Git files.')
@('ct-gremote','List configured Git remotes.')
@('ct-gtags','List Git tags.')
@('ct-gblame','Show per-line Git blame.')
@('ct-npm','Run installed npm.')
@('ct-npx','Run installed npx.')
@('ct-node','Run Node.js.')
@('ct-bun','Run Bun.')
@('ct-dotnet','Run .NET SDK.')
@('ct-py','Run the installed Python interpreter.')
@('ct-pip','Run Python pip.')
@('ct-lua','Run installed Lua.')
@('ct-java','Run installed Java.')
@('ct-cargo','Run installed Rust cargo.')
@('ct-go','Run installed Go toolchain.')
@('ct-docker','Run installed Docker CLI.')
@('ct-gh','Run GitHub CLI.')
@('ct-code','Launch Visual Studio Code CLI.')
@('ct-wt','Run Windows Terminal CLI.')
@('ct-winget','Run Windows package manager.')
@('ct-psversion','Show PowerShell version table.')
@('ct-dotnetinfo','Show .NET SDK details.')
@('ct-nodeversion','Show Node.js version.')
@('ct-pyversion','Show Python version.')
@('ct-gitversion','Show Git version.')
@('ct-tool','Inspect a command.')
@('ct-jsonvalidate','Check that a JSON file parses.')
@('ct-http','Perform an HTTP request.')
@('ct-httpstatus','Get response HTTP status.')
@('ct-porttest','Check remote TCP port connectivity.')
@('ct-guid','Create random GUID.')
@('ct-urlencode','Encode a URL component.')
@('ct-urldecode','Decode a URL component.')
@('ct-base64encode','Base64 encode UTF-8 text.')
@('ct-base64decode','Decode Base64 UTF-8 text.')
@('ct-hexencode','Hex encode UTF-8 text.')
@('ct-hexdecode','Decode hex UTF-8 text.')
@('ct-sha256text','Hash a string with SHA256.')
@('ct-bytecount','Count UTF-8 bytes.')
@('ct-shells','Show installed shell commands.')
) | ForEach-Object { Register-CuteTermCommand $_[0] 'developer' $_[1] }
