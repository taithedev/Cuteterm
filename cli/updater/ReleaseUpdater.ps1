# CuteTerm release updater. Fetches only from the official public GitHub release.
# An update ZIP must match its published SHA-256 and the version inside its package.
$script:CuteTermReleaseApi='https://api.github.com/repos/taithedev/Cuteterm/releases/latest'
$script:CuteTermReleaseBase='https://github.com/taithedev/Cuteterm/releases/download/'
$script:CuteTermZipName='CuteTerm-CLI-Windows.zip'

function Get-CuteTermCurrentVersion {
    $versionFile=Join-Path $script:Root 'version.txt'
    if (Test-Path -LiteralPath $versionFile) {
        return [version]((Get-Content -LiteralPath $versionFile -Raw -ErrorAction Stop).Trim())
    }
    $cfg=Get-CuteTermConfig
    if ($cfg.Version) { return [version]$cfg.Version }
    return [version]'0.0.0'
}

function Get-CuteTermRelease {
    $headers=@{ 'User-Agent'='CuteTerm-Updater'; 'Accept'='application/vnd.github+json' }
    $release=Invoke-RestMethod -Uri $script:CuteTermReleaseApi -Method Get -Headers $headers -TimeoutSec 8 -ErrorAction Stop
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v([0-9]+)\.([0-9]+)\.([0-9]+)$') {
        throw 'Latest published release has an invalid tag or is not a stable release.'
    }
    return $release
}

function Invoke-CuteTermUpdate {
    [CmdletBinding()]
    param([switch]$Quiet)
    $current=Get-CuteTermCurrentVersion
    try { $release=Get-CuteTermRelease }
    catch {
        if (-not $Quiet) { Write-Warning "Couldn't check GitHub Releases: $_" }
        return $false
    }
    $latest=[version]$release.tag_name.Substring(1)
    if ($latest -le $current) {
        if (-not $Quiet) { Write-CuteTerm "CuteTerm $current is already up to date." 'green' }
        return $false
    }
    $zipAsset=@($release.assets | Where-Object name -EQ $script:CuteTermZipName | Select-Object -First 1)
    $hashAsset=@($release.assets | Where-Object name -EQ ($script:CuteTermZipName + '.sha256') | Select-Object -First 1)
    if ($zipAsset.Count -ne 1 -or $hashAsset.Count -ne 1) {
        Write-Warning 'Release is missing the verified CuteTerm Windows ZIP or SHA-256 manifest. No update was installed.'
        return $false
    }
    foreach ($asset in @($zipAsset[0],$hashAsset[0])) {
        if (-not $asset.browser_download_url -or
            -not ([string]$asset.browser_download_url).StartsWith(
                ($script:CuteTermReleaseBase + $release.tag_name + '/'),[StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning 'Release URL did not match the official CuteTerm repository. No update was installed.'
            return $false
        }
    }
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('CuteTerm-update-' + [guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -ItemType Directory -Path $temp -Force)
        $zip=Join-Path $temp $script:CuteTermZipName
        $manifest=Join-Path $temp ($script:CuteTermZipName + '.sha256')
        Write-CuteTerm "CuteTerm $latest is available. Installing the verified Windows update..." 'cyan'
        Invoke-WebRequest -Uri $zipAsset[0].browser_download_url -OutFile $zip -MaximumRedirection 5 -TimeoutSec 40 -ErrorAction Stop
        Invoke-WebRequest -Uri $hashAsset[0].browser_download_url -OutFile $manifest -MaximumRedirection 5 -TimeoutSec 15 -ErrorAction Stop
        $line=(Get-Content -LiteralPath $manifest -Raw -ErrorAction Stop).Trim()
        if ($line -notmatch ('^(?<hash>[a-fA-F0-9]{64})\s+\*?' + [regex]::Escape($script:CuteTermZipName) + '$')) {
            throw 'The release checksum manifest is malformed.'
        }
        $expected=$Matches.hash.ToLowerInvariant()
        $actual=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -ne $actual) { throw 'Downloaded release failed SHA-256 verification.' }
        $digestProperty=$zipAsset[0].PSObject.Properties['digest']
        if ($digestProperty -and $digestProperty.Value) {
            $githubDigest=[string]$digestProperty.Value
            if (-not $githubDigest.StartsWith('sha256:',[StringComparison]::OrdinalIgnoreCase)) { throw 'GitHub asset digest uses an unsupported algorithm.' }
            $githubHash=$githubDigest.Substring(7).ToLowerInvariant()
            if ($githubHash.Length -ne 64 -or $actual -ne $githubHash) { throw 'GitHub asset checksum mismatch.' }
        }
        $extract=Join-Path $temp 'payload'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force -ErrorAction Stop
        $install=Join-Path $extract 'install.ps1'
        $releaseVersion=Join-Path $extract 'cli/version.txt'
        $module=Join-Path $extract 'cli/module/CuteTerm.psm1'
        if (-not (Test-Path -LiteralPath $install) -or
            -not (Test-Path -LiteralPath $module) -or
            -not (Test-Path -LiteralPath $releaseVersion)) { throw 'Downloaded release is missing required installer files.' }
        $packageVersion=(Get-Content -LiteralPath $releaseVersion -Raw -ErrorAction Stop).Trim()
        if ($packageVersion -ne $latest.ToString()) { throw 'Downloaded version does not match the published release tag.' }

        # A fresh PowerShell process performs the update. Existing tab stays usable.
        & pwsh -NoLogo -NoProfile -NonInteractive -File $install -SkipTerminalProfile
        if ($LASTEXITCODE -ne 0) { throw "Installer returned exit code $LASTEXITCODE." }
        Write-CuteTerm "CuteTerm $latest installed. Open a new tab to load updated commands." 'green'
        return $true
    }
    catch {
        Write-Warning ("CuteTerm update cancelled: " + $_.Exception.Message)
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-CuteTermUpdatesAtStartup {
    $cfg=Get-CuteTermConfig
    $mode=if ($cfg.UpdateMode -in @('auto','notify','off')) { $cfg.UpdateMode } else { 'notify' }
    if ($mode -eq 'off') { return }
    $hours=24
    if ($cfg.UpdateCheckHours) { $hours=[math]::Max(1,[math]::Min(168,[int]$cfg.UpdateCheckHours)) }
    $dir=Join-Path $script:Root 'data'
    [void](New-Item -Path $dir -ItemType Directory -Force)
    $cache=Join-Path $dir 'last-update-check.txt'
    if (Test-Path -LiteralPath $cache) {
        $last=[datetime]::MinValue
        $value=(Get-Content -LiteralPath $cache -Raw -ErrorAction SilentlyContinue)
        if ([datetime]::TryParse($value,[ref]$last) -and
            [datetime]::UtcNow.Subtract($last.ToUniversalTime()).TotalHours -lt $hours) { return }
    }
    [datetime]::UtcNow.ToString('o') | Set-Content -LiteralPath $cache -Encoding ascii
    if ($mode -eq 'auto') {
        [void](Invoke-CuteTermUpdate -Quiet)
        return
    }
    try {
        $latest=Get-CuteTermRelease
        $current=Get-CuteTermCurrentVersion
        if ([version]($latest.tag_name.Substring(1)) -gt $current) {
            Write-CuteTerm "CuteTerm $($latest.tag_name) available. Run 'ct update' to install." 'yellow'
        }
    } catch { } # Offline is normal; never block shell startup.
}
