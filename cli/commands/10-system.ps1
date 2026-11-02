# System diagnostics: real Windows/PowerShell commands, never simulated output.
function ct-sys {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $machine = Get-CimInstance Win32_ComputerSystem
    [pscustomobject]@{
        Computer=$env:COMPUTERNAME
        User=$env:USERNAME
        OS=$os.Caption
        Build=$os.BuildNumber
        CPU=$cpu.Name
        Cores=$cpu.NumberOfCores
        RAMGiB=[math]::Round($machine.TotalPhysicalMemory/1GB,2)
        PowerShell=$PSVersionTable.PSVersion.ToString()
    } | Format-List
}
function ct-os { Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,InstallDate,LastBootUpTime | Format-List }
function ct-cpu { Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,LoadPercentage | Format-List }
function ct-memory {
    $os=Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        TotalGiB=[math]::Round($os.TotalVisibleMemorySize/1MB,2)
        FreeGiB=[math]::Round($os.FreePhysicalMemory/1MB,2)
        UsedGiB=[math]::Round(($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB,2)
    } | Format-List
}
function ct-disks { Get-PSDrive -PSProvider FileSystem | Select-Object Name,Root,@{N='UsedGiB';E={[math]::Round($_.Used/1GB,2)}},@{N='FreeGiB';E={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize }
function ct-uptime {
    $boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    Write-Output ([DateTime]::Now-$boot)
}
function ct-top { param([int]$Count=15); Get-Process | Sort-Object CPU -Descending | Select-Object -First $Count Name,Id,CPU,@{N='MemoryMiB';E={[math]::Round($_.WorkingSet64/1MB,1)}} | Format-Table -AutoSize }
function ct-processes { param([string]$Name); if ($Name) { Get-Process -Name "*$Name*" -ErrorAction SilentlyContinue } else { Get-Process | Sort-Object Name } }
function ct-services { param([string]$Name='*'); Get-Service -Name "*$Name*" | Sort-Object Status,DisplayName | Format-Table Status,Name,DisplayName -AutoSize }
function ct-startupapps {
    Get-CimInstance Win32_StartupCommand | Select-Object Name,Location,Command | Format-Table -Wrap -AutoSize
}
function ct-battery { Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object Name,BatteryStatus,EstimatedChargeRemaining | Format-Table -AutoSize }
function ct-gpu { Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,VideoProcessor | Format-Table -Wrap -AutoSize }
function ct-board { Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer,Product,Version | Format-List }
function ct-bios { Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SMBIOSBIOSVersion,ReleaseDate | Format-List }
function ct-pid { "CuteTerm PowerShell process ID: $PID" }
function ct-machine { $env:COMPUTERNAME }
function ct-user { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
function ct-admin {
    $identity=[System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=[System.Security.Principal.WindowsPrincipal]::new($identity)
    $admin=$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Output $(if ($admin) {'PowerShell is elevated (Administrator).'} else {'PowerShell runs as a standard user. CuteTerm does not require elevation.'})
}
function ct-env { param([string]$Match='*'); Get-ChildItem Env: | Where-Object Name -Like "*$Match*" | Sort-Object Name }
function ct-envget { param([Parameter(Mandatory=$true)][string]$Name); [Environment]::GetEnvironmentVariable($Name,'Process') }
function ct-envset {
    param([Parameter(Mandatory=$true)][string]$Name,[string]$Value)
    [Environment]::SetEnvironmentVariable($Name,$Value,'Process')
    Write-Host "Set $Name for this session only."
}
function ct-which { param([Parameter(Mandatory=$true)][string]$Name); Get-Command $Name -All | Select-Object Name,CommandType,Source,Path | Format-Table -AutoSize }
function ct-path { $env:PATH -split ';' }
function ct-windowsfeatures { Get-WindowsOptionalFeature -Online -ErrorAction Stop | Select-Object FeatureName,State | Format-Table -AutoSize }
function ct-apps { Get-AppxPackage | Select-Object Name,Version | Sort-Object Name | Format-Table -AutoSize }
function ct-hotfixes { Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 30 HotFixID,Description,InstalledOn }
function ct-drivers { Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName,DriverVersion,Manufacturer | Sort-Object DeviceName | Format-Table -Wrap }
function ct-timezone { Get-TimeZone | Format-List }
function ct-localtime { Get-Date -Format 'dddd, MMMM d yyyy h:mm:ss tt' }
function ct-timestamp { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function ct-versions {
    foreach ($name in @('pwsh','git','node','npm','dotnet','python','bun','cargo','go','java')) {
        $cmd=Get-Command $name -ErrorAction Ignore
        if ($cmd) { "{0,-12} {1}" -f $name,$cmd.Source }
    }
}
function ct-network { Get-NetIPConfiguration | Format-List InterfaceAlias,IPv4Address,IPv6Address,IPv4DefaultGateway,DNSServer }
function ct-ip { Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -NotLike '169.254*' | Select-Object InterfaceAlias,IPAddress,PrefixLength | Format-Table -AutoSize }
function ct-ports {
    param([int]$Port)
    $sockets=Get-NetTCPConnection -State Listen -ErrorAction Stop
    if ($Port) { $sockets=$sockets | Where-Object LocalPort -EQ $Port }
    $sockets | Sort-Object LocalPort | Select-Object LocalAddress,LocalPort,OwningProcess | Format-Table -AutoSize
}
function ct-dns { param([Parameter(Mandatory=$true)][string]$HostName); Resolve-DnsName -Name $HostName }
function ct-ping { param([string]$HostName='1.1.1.1'); Test-Connection -TargetName $HostName -Count 4 }
function ct-route { Get-NetRoute -AddressFamily IPv4 | Select-Object -First 35 InterfaceAlias,DestinationPrefix,NextHop,RouteMetric | Format-Table -AutoSize }
function ct-netstat { Get-NetTCPConnection | Select-Object State,LocalAddress,LocalPort,RemoteAddress,RemotePort,OwningProcess | Format-Table -AutoSize }
function ct-wifi { & netsh wlan show interfaces }
function ct-profiles { Get-NetConnectionProfile | Format-List }
function ct-clipboard { Get-Clipboard }
function ct-cwd { (Get-Location).Path }
function ct-info { ct-sys }
@(
,@('ct-sys','Operating system, CPU, RAM and shell summary.')
,@('ct-os','Show Windows version and build.')
,@('ct-cpu','Show physical CPU details.')
,@('ct-memory','Show RAM usage.')
,@('ct-disks','Show drive usage.')
,@('ct-uptime','Show uptime since boot.')
,@('ct-top','Show top processes by CPU time.')
,@('ct-processes','List or filter running processes.')
,@('ct-services','List Windows services.')
,@('ct-startupapps','Inspect startup applications.')
,@('ct-battery','Show battery charge when available.')
,@('ct-gpu','Show graphics adapter details.')
,@('ct-board','Show motherboard information.')
,@('ct-bios','Show BIOS information.')
,@('ct-pid','Print current PowerShell process ID.')
,@('ct-machine','Print computer name.')
,@('ct-user','Show the current Windows account.')
,@('ct-admin','Check whether the process is elevated.')
,@('ct-env','List environment variables.')
,@('ct-envget','Read a process environment variable.')
,@('ct-envset','Set an environment variable for this process.')
,@('ct-which','Locate executable or PowerShell command.')
,@('ct-path','Print PATH directory entries.')
,@('ct-windowsfeatures','List optional Windows features.')
,@('ct-apps','List installed Appx applications.')
,@('ct-hotfixes','List recent Windows updates.')
,@('ct-drivers','List installed signed device drivers.')
,@('ct-timezone','Print timezone.')
,@('ct-localtime','Print current local date/time.')
,@('ct-timestamp','Print UTC Unix timestamp.')
,@('ct-versions','Find installed developer tools.')
,@('ct-network','View network configuration.')
,@('ct-ip','List IPv4 addresses.')
,@('ct-ports','List listening TCP ports.')
,@('ct-dns','Perform a DNS lookup.')
,@('ct-ping','Ping a destination.')
,@('ct-route','Show IPv4 routes.')
,@('ct-netstat','View active TCP connections.')
,@('ct-wifi','Display Wi-Fi interface state.')
,@('ct-profiles','List network connection profiles.')
,@('ct-clipboard','Read clipboard contents.')
,@('ct-cwd','Print current directory.')
,@('ct-info','Alias for system summary.')
) | ForEach-Object { Register-CuteTermCommand $_[0] 'system' $_[1] }
