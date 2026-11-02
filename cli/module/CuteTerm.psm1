# CuteTerm CLI module. Requires PowerShell 7. Windows Terminal owns the tabs/window.
Set-StrictMode -Version Latest
$script:Root = if ($env:CUTETERM_HOME) { $env:CUTETERM_HOME } else { Join-Path $env:LOCALAPPDATA 'CuteTerm' }
$script:Catalog = [ordered]@{}
$script:Palette = $null

function Register-CuteTermCommand {
    param([string]$Name, [string]$Category, [string]$Description)
    $script:Catalog[$Name] = [pscustomobject]@{ Name = $Name; Category = $Category; Description = $Description }
}
function Get-CuteTermConfig {
    $path = Join-Path $script:Root 'config.json'
    if (Test-Path -LiteralPath $path) {
        try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop) }
        catch { Write-Warning "CuteTerm config is invalid: $_" }
    }
    return @{ Theme = 'arctic'; Animation = 'soft'; Startup = $true; GitPrompt = $true; Opacity = 82 }
}
function Set-CuteTermConfig {
    param([System.Collections.IDictionary]$Config)
    $path = Join-Path $script:Root 'config.json'
    $Config | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $path -Encoding utf8
}
function Get-CuteTermPalette {
    if ($null -ne $script:Palette) { return $script:Palette }
    $config = Get-CuteTermConfig
    $themeFile = Join-Path $script:Root ("themes/{0}.json" -f $config.Theme)
    if (-not (Test-Path -LiteralPath $themeFile)) { $themeFile = Join-Path $script:Root 'themes/arctic.json' }
    $script:Palette = Get-Content -LiteralPath $themeFile -Raw | ConvertFrom-Json -AsHashtable
    return $script:Palette
}
function Write-CuteTerm {
    param([string]$Text, [string]$Color = 'foreground', [switch]$NoNewline)
    $palette = Get-CuteTermPalette
    $hex = [string]$palette[$Color]
    if ($hex -match '^#([0-9a-fA-F]{6})$' -and $Host.UI.SupportsVirtualTerminal) {
        $rgb = $Matches[1]
        $r = [Convert]::ToInt32($rgb.Substring(0, 2),16)
        $g = [Convert]::ToInt32($rgb.Substring(2, 2),16)
        $b = [Convert]::ToInt32($rgb.Substring(4, 2),16)
        $esc = [char]27
        Write-Host ('{0}[38;2;{1};{2};{3}m{4}{0}[0m' -f $esc,$r,$g,$b,$Text) -NoNewline:$NoNewline
    } else { Write-Host $Text -NoNewline:$NoNewline }
}
function Get-CuteTermPrompt {
    $cfg = Get-CuteTermConfig
    $path = (Get-Location).Path
    $homePath = [Environment]::GetFolderPath('UserProfile')
    if ($path.StartsWith($homePath, [StringComparison]::OrdinalIgnoreCase)) { $path = '~' + $path.Substring($homePath.Length) }
    $branch = ''
    if ($cfg.GitPrompt -and (Get-Command git -ErrorAction Ignore)) {
        $dir = (Get-Location).Path
        while ($dir -and -not (Test-Path -LiteralPath (Join-Path $dir '.git'))) {
            $parent = Split-Path -Path $dir -Parent
            if (-not $parent -or $parent -eq $dir) { $dir = $null; break }
            $dir = $parent
        }
        if ($dir) {
            $currentBranch = & git branch --show-current 2>$null
            if ($LASTEXITCODE -eq 0 -and $currentBranch) { $branch = "  git:$currentBranch" }
        }
    }
    $p = Get-CuteTermPalette
    $esc = [char]27
    function Tint([string]$value, [string]$hex) {
        $hex = $hex.TrimStart('#')
        $r=[Convert]::ToInt32($hex.Substring(0,2),16)
        $g=[Convert]::ToInt32($hex.Substring(2,2),16)
        $b=[Convert]::ToInt32($hex.Substring(4,2),16)
        return ('{0}[38;2;{1};{2};{3}m{4}{0}[0m' -f $esc,$r,$g,$b,$value)
    }
    return ((Tint '┌─' $p.muted) + (Tint " $env:USERNAME " $p.pink) + (Tint 'in ' $p.muted) + (Tint $path $p.cyan) + (Tint $branch $p.green) + [Environment]::NewLine + (Tint '└─❯ ' $p.pink))
}
function Show-CuteTermStartup {
    $cfg = Get-CuteTermConfig
    if (-not $cfg.Startup) { return }
    $art = @(
        '    ✦         .      *'
        '       /\_/\    .'
        '   .  ( o.o )       ✦'
        '       > ^ <       '
        '  ──────────────────'
    )
    $colors = @('pink','cyan','pink','yellow','muted')
    Write-Host ''
    for ($i=0; $i -lt $art.Count; $i++) {
        Write-CuteTerm ('  ' + $art[$i]) $colors[$i]
        if ($cfg.Animation -ne 'off') {
            Start-Sleep -Milliseconds $(if ($cfg.Animation -eq 'full') { 95 } else { 35 })
        }
    }
    Write-Host ''
    Write-CuteTerm '  CuteTerm  ✦  a softer side of PowerShell' 'pink'
    Write-CuteTerm ("  {0}@{1}   •   PowerShell {2}" -f $env:USERNAME,$env:COMPUTERNAME,$PSVersionTable.PSVersion) 'cyan'
    Write-CuteTerm ("  {0}   •   {1} logical processors" -f [System.Runtime.InteropServices.RuntimeInformation]::OSDescription,[Environment]::ProcessorCount) 'foreground'
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $total = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
        $used = [math]::Round(($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB,1)
        Write-CuteTerm ("  Memory: {0} / {1} GiB" -f $used,$total) 'green'
    } catch { }
    Write-CuteTerm '  ● ● ● ● ● ● ● ●' 'pink'
    Write-CuteTerm '  Try: ct help  |  ct commands  |  ct theme list  |  ct tab' 'muted'
    Write-Host ''
}
function ct {
    param([string]$Action='help', [Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments)
    $name = 'ct-' + $Action.ToLowerInvariant()
    $target = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
    if (-not $target) {
        Write-CuteTerm ("Unknown command: ct {0}. Try 'ct find {0}' or 'ct help'." -f $Action) 'red'
        return
    }
    & $target @Arguments
}
$helper = Join-Path $script:Root 'lib/TerminalProfile.ps1'
if (Test-Path -LiteralPath $helper) { . $helper }
$builtinDir = Join-Path $script:Root 'commands'
$userDir = Join-Path $script:Root 'user-commands'
if (Test-Path -LiteralPath $builtinDir) {
    Get-ChildItem -LiteralPath $builtinDir -File -Filter '*.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }
}
if (Test-Path -LiteralPath $userDir) {
    Get-ChildItem -LiteralPath $userDir -File -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
        try { . $_.FullName } catch { Write-Warning "Could not load custom command '$($_.Name)': $_" }
    }
}
Export-ModuleMember -Function ct,ct-*,Get-CuteTermPrompt,Show-CuteTermStartup
