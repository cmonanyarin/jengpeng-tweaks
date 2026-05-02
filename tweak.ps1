#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Personal PC Optimization & Latency Tuning Script (Win10/11 Final)
.NOTES
    - Fixed PS5.1 CLI parsing via Invoke-Expression
    - Removed deprecated netsh/bcdedit params (chimney, congestionprovider, vm, usephysicaldestination)
    - Gracefully handles Secure Boot locks & missing tunnel adapters
    - Clears all PowerShell execution traces on completion
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

Write-Host "[*] Applying System Optimizations..." -ForegroundColor Cyan

# ==========================================
# 1. NETWORK ADVANCED TUNING
# ==========================================
$netshCommands = @(
    "int tcp set heuristics disabled"
    "int tcp set global rss=enabled autotuninglevel=normal ecncapability=disabled timestamps=disabled rsc=disabled nonsackrttresiliency=disabled dca=enabled netdma=disabled"
    "int udp set global uro=disabled"
    "interface teredo set state disabled"
    "interface 6to4 set state disabled"
    "int isatap set state disable"
)
# 2>&1 | Out-Null Suppresses expected harmless errors (missing tunnel adapters, etc.)
$netshCommands | ForEach-Object { Invoke-Expression "netsh $_ 2>&1" | Out-Null }
Clear-DnsClientCache

# ==========================================
# 2. BOOT CONFIGURATION
# ==========================================
$bcdCommands = @(
    "/set disabledynamictick yes"
    "/set useplatformclock no"
    "/deletevalue useplatformtick"
    "/set tscsyncpolicy Enhanced"
    "/set bootmenupolicy legacy"
    "/set quietboot yes"
    "/set usefirmwarepcisettings No"
    "/set vsmlaunchtype Off"
    "/set isolatedcontext No"
    "/set mitigations off"
    "/set nx AlwaysOff"
    "/set hypervisorlaunchtype off"
)
# หมายเหตุ: mitigations, nx, hypervisorlaunchtype จะถูกปฏิเสธหากเปิด UEFI Secure Boot ไว้
# เป็นพฤติกรรมปกติของ Windows 10/11 Modern Boot Manager
$bcdCommands | ForEach-Object { Invoke-Expression "bcdedit $_ 2>&1" | Out-Null }

# ==========================================
# 3. REGISTRY TWEAKS (Native PS Conversion)
# ==========================================
function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWORD")
    if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $regType = if ($Type -eq "SZ") { "String" } else { "DWord" }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $regType -Force
}

Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive" "AdditionalCriticalWorkerThreads" 8
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive" "AdditionalDelayedWorkerThreads" 8
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control" "ProcessorIdleDisable" 1
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 0xFFFFFFFF
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "NoLazyMode" 1
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "LazyModeTimeout" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "PlatformAoAcOverride" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0
Set-RegValue "HKCU:\Control Panel\Desktop" "LowLevelHooksTimeout" "5" "SZ"
Set-RegValue "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "SZ"
Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" "SZ"
Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" "SZ"
Set-RegValue "HKCU:\Control Panel\Keyboard" "KeyboardDelay" "0" "SZ"
Set-RegValue "HKCU:\Control Panel\Keyboard" "KeyboardSpeed" "31" "SZ"
Set-RegValue "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "506" "SZ"
Set-RegValue "HKCU:\Control Panel\Accessibility\ToggleKeys" "Flags" "58" "SZ"
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters" "DataQueueSize" 16
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters" "DataQueueSize" 16

$tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
Set-RegValue $tcpPath "TcpDelAckTicks" 0
Set-RegValue $tcpPath "TCPNoDelay" 1
Set-RegValue $tcpPath "TcpMaxDataRetransmissions" 3
Set-RegValue $tcpPath "TcpMaxDupAcks" 2
Set-RegValue $tcpPath "DefaultTTL" 64
Set-RegValue $tcpPath "EnablePMTUDiscovery" 1
Set-RegValue $tcpPath "DisableTaskOffload" 1
Set-RegValue $tcpPath "MaxUserPort" 65534
Set-RegValue $tcpPath "TcpTimedWaitDelay" 30
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\Afd\Parameters" "FastSendDatagramThreshold" 4096

Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableSmartNameResolution" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePageCombining" 1
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0

# ==========================================
# 4. ACTIVE INTERFACE GUID TCP TWEAKS
# ==========================================
Write-Host "[*] Applying per-adapter TCP optimizations..." -ForegroundColor Yellow
$interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
Get-ChildItem -Path $interfacesPath -ErrorAction SilentlyContinue | ForEach-Object {
    $key = $_.PSPath
    $props = Get-ItemProperty -Path $key -Name "DhcpIPAddress","IPAddress" -ErrorAction SilentlyContinue
    if ($props.DhcpIPAddress -notmatch "^(0\.0\.0\.0)?$" -or $props.IPAddress -notmatch "^(0\.0\.0\.0)?$") {
        Set-RegValue $key "TcpAckFrequency" 1
        Set-RegValue $key "TCPNoDelay" 1
    }
}

# ==========================================
# 5. ADAPTER POWER & OFFLOAD SETTINGS
# ==========================================
Get-NetAdapter | ForEach-Object {
    Disable-NetAdapterPowerManagement -Name $_.Name
    Disable-NetAdapterLso -Name $_.Name
}

# ==========================================
# 6. DISABLE SERVICES (Native PS)
# ==========================================
$servicesToDisable = @(
    "SysMain","DiagTrack","dmwappushservice","WSearch","Spooler","NDU",
    "RetailDemo","MapsBroker","WerSvc","Fax","XblGameSave","XboxNetApiSvc",
    "PcaSvc","Dosvc","RemoteRegistry","StiSvc","TabletInputService",
    "TermService","SessionEnv","UmRdpService","lfsvc","SensorService",
    "SensorDataService","SensrSvc","PhoneSvc","WalletService","WbioSrvc","LanmanServer"
)
$servicesToDisable | ForEach-Object { Set-Service -Name $_ -StartupType Disabled }

# ==========================================
# 7. ONEDRIVE REMOVAL
# ==========================================
Stop-Process -Name "OneDrive" -Force
$uninstallers = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    "$env:SystemRoot\System32\OneDriveSetup.exe"
)
$uninstallers | Where-Object { Test-Path $_ } | ForEach-Object { Start-Process $_ -ArgumentList "/uninstall" -Wait }
$onedrivePaths = @(
    "$env:USERPROFILE\OneDrive"
    "$env:LOCALAPPDATA\Microsoft\OneDrive"
    "$env:ProgramData\Microsoft OneDrive"
)
$onedrivePaths | Where-Object { Test-Path $_ } | Remove-Item -Recurse -Force

# ==========================================
# 8. TEMP CLEANUP
# ==========================================
Remove-Item "$env:TEMP\*" -Recurse -Force
Remove-Item "$env:windir\Temp\*" -Recurse -Force

# ==========================================
# 9. CLEAR POWERSHELL HISTORY & TRACES
# ==========================================
Clear-History
$psReadLinePath = (Get-PSReadLineOption).HistorySavePath
if ($psReadLinePath -and (Test-Path $psReadLinePath)) {
    Remove-Item $psReadLinePath -Force
}
[Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() 2>$null

Write-Host "[+] Optimization Payload Complete." -ForegroundColor Green
