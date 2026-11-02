# CLI productivity and text tools. Data remains local to this user.
function Get-CTDataDir {
    $dir=Join-Path $script:Root 'data'
    [void](New-Item -Path $dir -ItemType Directory -Force)
    return $dir
}
function ct-note {
    param([string]$Action='list',[string]$Name,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Text)
    $dir=Join-Path (Get-CTDataDir) 'notes'
    [void](New-Item -Path $dir -ItemType Directory -Force)
    if ($Action -eq 'list') { Get-ChildItem -LiteralPath $dir -Filter '*.txt' | Select-Object BaseName,LastWriteTime; return }
    if (-not $Name -or $Name -notmatch '^[a-zA-Z0-9_-]{1,50}$') { Write-Warning 'Usage: ct note <new|show|delete> <safe-name> [text]'; return }
    $path=Join-Path $dir ($Name+'.txt')
    switch ($Action) {
        'new' {
            $value=if ($Text) { $Text -join ' ' } else { Read-Host 'Note contents' }
            Set-Content -LiteralPath $path -Value $value -Encoding utf8
            Write-Host "Saved note: $Name"
        }
        'show' { Get-Content -LiteralPath $path -ErrorAction Stop }
        'delete' { Remove-Item -LiteralPath $path -Confirm -ErrorAction Stop }
        default { Write-Host 'Usage: ct note <new|list|show|delete> [name] [text]' }
    }
}
function Get-CTTodos {
    $path=Join-Path (Get-CTDataDir) 'todos.json'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}
function Save-CTTodos {
    param([object[]]$Items)
    $path=Join-Path (Get-CTDataDir) 'todos.json'
    ConvertTo-Json -InputObject @($Items) -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
}
function ct-todo {
    param([string]$Action='list',[Parameter(ValueFromRemainingArguments=$true)][string[]]$Values)
    $items=@(Get-CTTodos)
    switch ($Action) {
        'add' {
            if (-not $Values) { Write-Warning 'Usage: ct todo add <description>'; return }
            $id=if ($items.Count) { (@($items | Measure-Object -Property Id -Maximum)[0].Maximum + 1) } else { 1 }
            $items+= [pscustomobject]@{ Id=[int]$id; Done=$false; Text=($Values -join ' '); Added=(Get-Date -Format o) }
            Save-CTTodos $items
            Write-Host "Added task $id."
        }
        'list' { $items | Select-Object Id,Done,Text,Added | Format-Table -Wrap -AutoSize }
        'done' {
            if (-not $Values) { Write-Warning 'Usage: ct todo done <id>'; return }
            $item=$items | Where-Object Id -EQ ([int]$Values[0]) | Select-Object -First 1
            if (-not $item) { Write-Warning 'Task not found.'; return }
            $item.Done=$true; Save-CTTodos $items
            Write-Host "Completed task $($item.Id)."
        }
        'remove' {
            if (-not $Values) { Write-Warning 'Usage: ct todo remove <id>'; return }
            $items=@($items | Where-Object Id -NE ([int]$Values[0]))
            Save-CTTodos $items
        }
        'clear' {
            $choice=Read-Host 'Clear all local tasks? Type YES'
            if ($choice -cne 'YES') { return }
            Save-CTTodos @()
        }
        default { Write-Host 'Usage: ct todo <add|list|done|remove|clear>' }
    }
}
function Get-CTBookmarks {
    $path=Join-Path (Get-CTDataDir) 'bookmarks.json'
    if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable) }
    return @{}
}
function ct-bookmark {
    param([string]$Action='list',[string]$Name,[string]$Path)
    $bookmarks=Get-CTBookmarks
    switch ($Action) {
        'list' { $bookmarks.GetEnumerator() | Sort-Object Name | Format-Table Name,Value -AutoSize }
        'add' {
            if ($Name -notmatch '^[a-zA-Z0-9_-]{1,40}$') { Write-Warning 'A bookmark name must be letters, digits, hyphens or underscores.'; return }
            $folder=if ($Path) { (Resolve-Path -LiteralPath $Path).Path } else { (Get-Location).Path }
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw 'Bookmark path must be a folder.' }
            $bookmarks[$Name]=$folder
            $bookmarks | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path (Get-CTDataDir) 'bookmarks.json') -Encoding utf8
        }
        'go' { if (-not $bookmarks.Contains($Name)) { Write-Warning 'Unknown bookmark.'; return }; Set-Location -LiteralPath $bookmarks[$Name] }
        'delete' {
            if ($bookmarks.Contains($Name)) { $bookmarks.Remove($Name) }
            $bookmarks | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path (Get-CTDataDir) 'bookmarks.json') -Encoding utf8
        }
        default { Write-Host 'Usage: ct bookmark <list|add|go|delete> [name] [path]' }
    }
}
function ct-calendar {
    param([ValidateRange(1,12)][int]$Month=(Get-Date).Month,[ValidateRange(1,9999)][int]$Year=(Get-Date).Year)
    $first=[datetime]::new($Year,$Month,1)
    $days=[datetime]::DaysInMonth($Year,$Month)
    Write-CuteTerm ("      " + $first.ToString('MMMM yyyy')) 'cyan'
    Write-Host 'Su Mo Tu We Th Fr Sa'
    $line=('   ' * [int]$first.DayOfWeek)
    for ($d=1;$d -le $days;$d++) {
        $line+=('{0,2} ' -f $d)
        if (($d+[int]$first.DayOfWeek)%7 -eq 0) { Write-Host $line; $line='' }
    }
    if ($line.Length -gt 0) { Write-Host $line }
}
function ct-clock { Get-Date -Format 'HH:mm:ss  dddd, MMMM dd, yyyy' }
function ct-timer {
    param([ValidateRange(1,3600)][int]$Seconds=10)
    Write-Host "Timer: $Seconds seconds (Ctrl+C to cancel)"
    for ($remaining=$Seconds; $remaining -gt 0; $remaining--) {
        Write-Progress -Activity 'CuteTerm timer' -Status "$remaining seconds remaining" -PercentComplete (100*(1-$remaining/$Seconds))
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity 'CuteTerm timer' -Completed
    Write-Host 'Timer finished.' -ForegroundColor Green
}
function ct-stopwatch {
    Write-Host 'Stopwatch running. Press Enter to stop.'
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $null=Read-Host
    $sw.Stop()
    $sw.Elapsed
}
function ct-calc {
    param([Parameter(Mandatory=$true)][string]$Expression)
    if ($Expression -notmatch '^[0-9+\-*/%.() ]+$') { Write-Warning 'Only arithmetic with numbers and + - * / % ( ) is allowed.'; return }
    $table=[Data.DataTable]::new()
    try { $table.Compute($Expression,$null) } finally { $table.Dispose() }
}
function ct-random { param([int]$Min=0,[int]$Max=100); if ($Min -ge $Max) { throw 'Min must be less than Max.' }; [Random]::Shared.Next($Min,$Max) }
function ct-pick {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Items)
    if (-not $Items -or $Items.Count -eq 0) { throw 'Provide choices: ct pick red blue green' }
    $Items[[Random]::Shared.Next(0,$Items.Count)]
}
function ct-upper { param([Parameter(Mandatory=$true)][string]$Text); $Text.ToUpperInvariant() }
function ct-lower { param([Parameter(Mandatory=$true)][string]$Text); $Text.ToLowerInvariant() }
function ct-titlecase { param([Parameter(Mandatory=$true)][string]$Text); [globalization.CultureInfo]::CurrentCulture.TextInfo.ToTitleCase($Text) }
function ct-reverse { param([Parameter(Mandatory=$true)][string]$Text); $chars=$Text.ToCharArray(); [Array]::Reverse($chars); return (-join $chars) }
function ct-trim { param([Parameter(Mandatory=$true)][string]$Text); $Text.Trim() }
function ct-slug {
    param([Parameter(Mandatory=$true)][string]$Text)
    (($Text.ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-'))
}
function ct-charcount { param([Parameter(Mandatory=$true)][string]$Text); $Text.Length }
function ct-wordcount { param([Parameter(Mandatory=$true)][string]$Text); @([regex]::Matches($Text,'\S+')).Count }
function ct-repeat {
    param([Parameter(Mandatory=$true)][string]$Text,[ValidateRange(1,100)][int]$Count=2)
    1..$Count | ForEach-Object { $Text }
}
function ct-wrap {
    param([Parameter(Mandatory=$true)][string]$Text,[int]$Width=70)
    if ($Width -lt 10) { throw 'Width must be >=10.' }
    for($i=0; $i -lt $Text.Length; $i+=$Width) { $Text.Substring($i,[math]::Min($Width,$Text.Length-$i)) }
}
function ct-echo { param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Values); $Values -join ' ' }
function ct-colors { ct-palette }
function ct-ascii {
    Write-CuteTerm '       /\_/\   ✦ ' 'pink'
    Write-CuteTerm '      ( o.o )    CuteTerm' 'cyan'
    Write-CuteTerm '       > ^ <  ✧  ' 'yellow'
}
function ct-spinner {
    param([ValidateRange(1,30)][int]$Seconds=2)
    $frames=@('|','/','-','\')
    $end=(Get-Date).AddSeconds($Seconds)
    $i=0
    while ((Get-Date) -lt $end) {
        Write-Host ("  Loading " + $frames[$i%$frames.Count]) -NoNewline
        Start-Sleep -Milliseconds 90
        Write-Host ([char]13) -NoNewline
        $i++
    }
    Write-Host '  Ready.    '
}
@(
@('ct-note','Create and read private local text notes.')
@('ct-todo','Manage a local task list.')
@('ct-bookmark','Save and jump to named folders.')
@('ct-calendar','Display a monthly calendar.')
@('ct-clock','Show current time.')
@('ct-timer','Run a terminal countdown timer.')
@('ct-stopwatch','Measure elapsed time until Enter.')
@('ct-calc','Evaluate basic arithmetic only.')
@('ct-random','Generate a random number.')
@('ct-pick','Pick a random supplied choice.')
@('ct-upper','Uppercase text.')
@('ct-lower','Lowercase text.')
@('ct-titlecase','Title-case text.')
@('ct-reverse','Reverse text.')
@('ct-trim','Trim leading/trailing spaces.')
@('ct-slug','Convert text to a URL-friendly slug.')
@('ct-charcount','Count characters.')
@('ct-wordcount','Count words.')
@('ct-repeat','Repeat text a specified number of times.')
@('ct-wrap','Wrap text by character width.')
@('ct-echo','Echo strings.')
@('ct-colors','Preview active colors.')
@('ct-ascii','Print original CuteTerm ASCII cat.')
@('ct-spinner','Preview a CLI loading animation.')
) | ForEach-Object { Register-CuteTermCommand $_[0] 'utility' $_[1] }
