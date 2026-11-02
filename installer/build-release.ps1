# Builds both release assets on Windows using Inno Setup 6.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if (-not $IsWindows) { throw 'Windows releases must be built on Windows.' }

$repo=Split-Path -Parent $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $repo 'cli/version.txt') -Raw -ErrorAction Stop).Trim()
if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw "Invalid CuteTerm release version: $version" }
$iss=Join-Path $PSScriptRoot 'CuteTerm.iss'
$issText=Get-Content -LiteralPath $iss -Raw -ErrorAction Stop
if ($issText -notmatch ('#define MyAppVersion "' + [regex]::Escape($version) + '"')) {
    throw 'The Inno Setup version and cli/version.txt do not match.'
}
$dist=Join-Path $repo 'dist'
[void](New-Item -ItemType Directory -Path $dist -Force)

# Create a controlled ZIP: no test output, Git metadata, personal config or development secrets.
$stage=Join-Path ([IO.Path]::GetTempPath()) ('CuteTerm-release-' + [guid]::NewGuid().ToString('N'))
try {
    $payload=Join-Path $stage 'payload'
    $payloadCli=Join-Path $payload 'cli'
    [void](New-Item -ItemType Directory -Path $payloadCli -Force)
    foreach ($file in @('install.ps1','uninstall.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $payload -ErrorAction Stop
    }
    foreach ($dir in @('commands','docs','examples','lib','module','themes','updater')) {
        Copy-Item -LiteralPath (Join-Path $repo ('cli/'+$dir)) -Destination $payloadCli -Recurse -ErrorAction Stop
    }
    foreach ($file in @('start.ps1','cli.ps1','version.txt')) {
        Copy-Item -LiteralPath (Join-Path $repo ('cli/'+$file)) -Destination $payloadCli -ErrorAction Stop
    }
    $zipName='CuteTerm-CLI-Windows.zip'
    $zip=Join-Path $dist $zipName
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    ("{0} *{1}" -f $hash,$zipName) | Set-Content -LiteralPath (Join-Path $dist ($zipName+'.sha256')) -Encoding ascii
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

$iscc=Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $iscc) {
    $bases=@([Environment]::GetFolderPath('ProgramFiles'),[Environment]::GetFolderPath('ProgramFilesX86')) | Where-Object { $_ }
    foreach ($base in $bases) {
        $matches=@(Get-ChildItem -Path $base -Filter 'Inno Setup *' -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'ISCC.exe' } |
            Where-Object { Test-Path -LiteralPath $_ })
        if ($matches.Count) { $iscc=$matches[0]; break }
    }
}
if (-not $iscc) { throw 'ISCC.exe was not found. Install Inno Setup 6 before building.' }
Write-Host "Building CuteTerm Windows $version using $iscc"
& $iscc $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup returned $LASTEXITCODE" }
$filename="CuteTerm-Windows-Setup-$version.exe"
$sourceExe=Join-Path $PSScriptRoot ("Output/"+$filename)
if (-not (Test-Path -LiteralPath $sourceExe)) { throw "Missing installer output $sourceExe" }
Copy-Item -LiteralPath $sourceExe -Destination (Join-Path $dist $filename) -Force
$exeHash=(Get-FileHash -LiteralPath (Join-Path $dist $filename) -Algorithm SHA256).Hash.ToLowerInvariant()
("{0} *{1}" -f $exeHash,$filename) | Set-Content -LiteralPath (Join-Path $dist ($filename+'.sha256')) -Encoding ascii
Get-ChildItem -LiteralPath $dist -File | Select-Object Name,Length | Format-Table -AutoSize
Write-Host "Release assets ready for tag v$version." -ForegroundColor Green
