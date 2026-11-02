# Filesystem operations (uses actual PowerShell cmdlets and real filesystem state).
function ct-ls { param([string]$Path='.'); Get-ChildItem -LiteralPath $Path | Format-Table Mode,LastWriteTime,Length,Name -AutoSize }
function ct-la { param([string]$Path='.'); Get-ChildItem -LiteralPath $Path -Force | Format-Table Mode,LastWriteTime,Length,Name -AutoSize }
function ct-files { param([string]$Path='.'); Get-ChildItem -LiteralPath $Path -File | Sort-Object Name }
function ct-dirs { param([string]$Path='.'); Get-ChildItem -LiteralPath $Path -Directory | Sort-Object Name }
function ct-tree { param([string]$Path='.'); & tree.com (Resolve-Path -LiteralPath $Path).Path /F /A }
function ct-findfiles { param([string]$Filter='*',[string]$Path='.'); Get-ChildItem -LiteralPath $Path -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue }
function ct-finddirs { param([string]$Filter='*',[string]$Path='.'); Get-ChildItem -LiteralPath $Path -Recurse -Directory -Filter $Filter -ErrorAction SilentlyContinue }
function ct-du {
    param([string]$Path='.')
    $items=@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
    $bytes=($items | Measure-Object -Property Length -Sum).Sum
    [pscustomobject]@{ Path=(Resolve-Path -LiteralPath $Path).Path; Files=$items.Count; SizeMiB=[math]::Round([double]$bytes/1MB,2) }
}
function ct-size {
    param([Parameter(Mandatory=$true)][string]$Path)
    $item=Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) { ct-du $Path } else {
        [pscustomobject]@{ File=$item.FullName; Bytes=$item.Length; MiB=[math]::Round($item.Length/1MB,2) }
    }
}
function ct-bigfiles {
    param([string]$Path='.',[int]$Count=15)
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
      Sort-Object Length -Descending | Select-Object -First $Count FullName,@{N='MiB';E={[math]::Round($_.Length/1MB,2)}} | Format-Table -AutoSize -Wrap
}
function ct-filecount { param([string]$Path='.'); (Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count }
function ct-cat { param([Parameter(Mandatory=$true)][string]$Path); Get-Content -LiteralPath $Path }
function ct-head { param([Parameter(Mandatory=$true)][string]$Path,[int]$Count=10); Get-Content -LiteralPath $Path -TotalCount $Count }
function ct-tail { param([Parameter(Mandatory=$true)][string]$Path,[int]$Count=10); Get-Content -LiteralPath $Path -Tail $Count }
function ct-grep {
    param([Parameter(Mandatory=$true)][string]$Pattern,[Parameter(Mandatory=$true)][string]$Path)
    Select-String -Path $Path -Pattern $Pattern
}
function ct-findtext {
    param([Parameter(Mandatory=$true)][string]$Pattern,[string]$Path='.')
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Select-String -Pattern $Pattern -ErrorAction SilentlyContinue
}
function ct-lines { param([Parameter(Mandatory=$true)][string]$Path); (Get-Content -LiteralPath $Path | Measure-Object -Line).Lines }
function ct-words {
    param([Parameter(Mandatory=$true)][string]$Path)
    $contents=Get-Content -LiteralPath $Path -Raw
    if (-not $contents.Trim()) { return 0 }
    return @([regex]::Matches($contents,'\S+')).Count
}
function ct-hash { param([Parameter(Mandatory=$true)][string]$Path,[ValidateSet('SHA256','SHA1','SHA384','SHA512','MD5')][string]$Algorithm='SHA256'); Get-FileHash -LiteralPath $Path -Algorithm $Algorithm }
function ct-json { param([Parameter(Mandatory=$true)][string]$Path); Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function ct-jsonpretty { param([Parameter(Mandatory=$true)][string]$Path); Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 100 }
function ct-csv { param([Parameter(Mandatory=$true)][string]$Path); Import-Csv -LiteralPath $Path }
function ct-zip {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Destination)
    Compress-Archive -Path $Path -DestinationPath $Destination -ErrorAction Stop
}
function ct-unzip {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Destination)
    Expand-Archive -LiteralPath $Path -DestinationPath $Destination -ErrorAction Stop
}
function ct-touch {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).LastWriteTime=Get-Date }
    else { [void](New-Item -ItemType File -Path $Path -ErrorAction Stop) }
}
function ct-mkdir { param([Parameter(Mandatory=$true)][string]$Path); New-Item -Path $Path -ItemType Directory -Force }
function ct-fileinfo { param([Parameter(Mandatory=$true)][string]$Path); Get-Item -LiteralPath $Path | Format-List * }
function ct-copy { param([Parameter(Mandatory=$true)][string]$From,[Parameter(Mandatory=$true)][string]$To); Copy-Item -LiteralPath $From -Destination $To -ErrorAction Stop }
function ct-move { param([Parameter(Mandatory=$true)][string]$From,[Parameter(Mandatory=$true)][string]$To); Move-Item -LiteralPath $From -Destination $To -ErrorAction Stop }
function ct-rename { param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name); Rename-Item -LiteralPath $Path -NewName $Name -ErrorAction Stop }
function ct-remove {
    param([Parameter(Mandatory=$true)][string]$Path)
    Remove-Item -LiteralPath $Path -Confirm -ErrorAction Stop
}
function ct-diff {
    param([Parameter(Mandatory=$true)][string]$Left,[Parameter(Mandatory=$true)][string]$Right)
    Compare-Object (Get-Content -LiteralPath $Left) (Get-Content -LiteralPath $Right)
}
function ct-name { param([Parameter(Mandatory=$true)][string]$Path); Split-Path -Path $Path -Leaf }
function ct-extension { param([Parameter(Mandatory=$true)][string]$Path); [IO.Path]::GetExtension($Path) }
function ct-parent { param([string]$Path='.'); (Resolve-Path -LiteralPath (Join-Path $Path '..')).Path }
function ct-cd { param([string]$Path='~'); Set-Location -Path $Path }
function ct-up { Set-Location .. }
function ct-home { Set-Location ~ }
function ct-temp { [IO.Path]::GetTempPath() }
function ct-cls { Clear-Host }
function ct-open { param([string]$Path='.'); Invoke-Item -LiteralPath $Path }
function ct-clipset {
    param([Parameter(Mandatory=$true)][string]$Text)
    Set-Clipboard -Value $Text
}
function ct-emptydirs {
    param([string]$Path='.')
    Get-ChildItem -LiteralPath $Path -Directory -Recurse -ErrorAction SilentlyContinue |
      Where-Object { -not @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count } |
      Select-Object FullName
}
@(
,@('ct-ls','List directory contents.')
,@('ct-la','List hidden and regular directory entries.')
,@('ct-files','List files only.')
,@('ct-dirs','List directories only.')
,@('ct-tree','Show folder tree in text.')
,@('ct-findfiles','Find filenames recursively.')
,@('ct-finddirs','Find directory names recursively.')
,@('ct-du','Measure directory size.')
,@('ct-size','Get file or folder size.')
,@('ct-bigfiles','Find largest files.')
,@('ct-filecount','Count files recursively.')
,@('ct-cat','Print file contents.')
,@('ct-head','Print first lines of a file.')
,@('ct-tail','Print last lines of a file.')
,@('ct-grep','Find a regex pattern in a file.')
,@('ct-findtext','Recursively search file contents.')
,@('ct-lines','Count file lines.')
,@('ct-words','Count words in text file.')
,@('ct-hash','Calculate cryptographic file checksum.')
,@('ct-json','Parse JSON file.')
,@('ct-jsonpretty','Pretty-print JSON.')
,@('ct-csv','Import CSV rows.')
,@('ct-zip','Compress a file or folder.')
,@('ct-unzip','Extract a ZIP archive.')
,@('ct-touch','Create or update a file timestamp.')
,@('ct-mkdir','Create a folder.')
,@('ct-fileinfo','Inspect all file properties.')
,@('ct-copy','Copy a file or directory.')
,@('ct-move','Move a file or directory.')
,@('ct-rename','Rename a file.')
,@('ct-remove','Remove a path with confirmation.')
,@('ct-diff','Compare text files line by line.')
,@('ct-name','Get filename component of path.')
,@('ct-extension','Get file extension.')
,@('ct-parent','Find parent directory.')
,@('ct-cd','Change the current directory.')
,@('ct-up','Go to parent directory.')
,@('ct-home','Change to home directory.')
,@('ct-temp','Print temp directory path.')
,@('ct-cls','Clear terminal output.')
,@('ct-open','Open a path with the default application.')
,@('ct-clipset','Put text on the clipboard.')
,@('ct-emptydirs','Find empty directories.')
) | ForEach-Object { Register-CuteTermCommand $_[0] 'files' $_[1] }
