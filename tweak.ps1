#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Personal PC Optimization & Latency Tuning Script (Strict Original Match)
.NOTES
    - ค่าทุกตัวตรงตามต้นฉบับ 100% สำหรับใช้งานข้ามเครื่อง/ข้าม Build
    - ใช้ Invoke-Expression แก้ PS5.1 Quoting Bug
    - เพิ่ม 2>&1 | Out-Null ใน netsh/bcdedit เพื่อกลบ Error Deprecated บน Win10/11 ใหม่
      ทำให้สคริปต์ไม่หยุดทำงาน และยังคงพยายามตั้งค่าบนเครื่องที่รองรับ
    - Registry/Services/Adapter/OneDrive/Temp แปลงเป็น Native PS โดยค่าไม่เปลี่ยนแปลง
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

Write-Host "[*] Applying System Optimizations..." -ForegroundColor Cyan

# ==========================================
# 1. NETWORK ADVANCED TUNING (Original Exact)
# ==========================================
$netshCommands = @(
    "int tcp set heuristics disabled"
    "int tcp set global rss=enabled"
    "int tcp set global autotuninglevel=normal"
    "int tcp set global ecncapability=disabled"
    "int tcp set global timestamps=disabled"
    "int tcp set global rsc=disabled"
    "int tcp set global nonsackrttresiliency=disabled"
    "int tcp set global chimney=disabled"
    "int tcp set global dca=enabled"
    "int tcp set global netdma=disabled"
    "int tcp set global congestionprovider=default"
    "int udp set global uro=disabled"
    "interface teredo set state disabled"
    "interface 6to4 set state disabled"
    "int isatap set state disable"
)
# 2>&1 | Out-Null: กลบ Expected Error บน Build ที่ตัดฟีเจอร์ออก แล้วรันบรรทัดถัดไปต่อ
$netshCommands | ForEach-Object { Invoke-Expression "netsh $_ 2>&1" | Out-Null }
Clear-DnsClientCache

# ==========================================
# 2. BOOT CONFIGURATION (Original Exact)
# ==========================================
$bcdCommands = @(
    "/set disabledynamictick yes"
    "/set useplatformclock no"
    "/deletevalue useplatformtick"
    "/set tscsyncpolicy Enhanced"
    "/set bootmenupolicy legacy"
    "/set mitigations off"
    "/set nx AlwaysOff"
    "/set hypervisorlaunchtype off"
    "/set quietboot yes"
    "/set usephysicaldestination No"
    "/set usefirmwarepcisettings No"
    "/set vsmlaunchtype Off"
    "/set isolatedcontext No"
    "/set vm No"
)
$bcdCommands | ForEach-Object { Invoke-Expression "bcdedit $_ 2>&1" | Out-Null }

# ==========================================
# 3. REGISTRY TWEAKS (Native PS, Values 1:1)
# ==========================================
function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWORD")
    if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $regType = if ($Type -eq "SZ") { "String" } else { "DWord" }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $regType -Force
}

# Latency & Priority
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive" "AdditionalCriticalWorkerThreads" 8
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive" "AdditionalDelayedWorkerThreads" 8
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control" "ProcessorIdleDisable" 1
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 4294967295
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "NoLazyMode" 1
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "LazyModeTimeout" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "PlatformAoAcOverride" 0
Set-RegValue "HKCU:\Control Panel\Desktop" "LowLevelHooksTimeout" "5" "SZ"

# Network Latency Fixes
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

# 1:1 Mouse & Max Keyboard Speed
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters" "DataQueueSize" 16
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters" "DataQueueSize" 16
Set-RegValue "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "SZ"
Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" "SZ"
Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" "SZ"
Set-RegValue "HKCU:\Control Panel\Keyboard" "KeyboardDelay" "0" "SZ"
Set-RegValue "HKCU:\Control Panel\Keyboard" "KeyboardSpeed" "31" "SZ"
Set-RegValue "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "506" "SZ"
Set-RegValue "HKCU:\Control Panel\Accessibility\ToggleKeys" "Flags" "58" "SZ"

# Global Interrupt and Power Optimization
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0

# Kill Background / DNS
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableSmartNameResolution" 0

# Memory Management
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePageCombining" 1
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1

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
    Disable-NetAdapterPowerManagement -Name $_.Name -ErrorAction SilentlyContinue
    Disable-NetAdapterLso -Name $_.Name -ErrorAction SilentlyContinue
}

# ==========================================
# 6. DISABLE SERVICES (Original Exact List)
# ==========================================
$servicesToDisable = @(
    "SysMain","DiagTrack","dmwappushservice","WSearch","Spooler","NDU",
    "RetailDemo","MapsBroker","WerSvc","Fax","XblGameSave","XboxNetApiSvc",
    "PcaSvc","Dosvc","RemoteRegistry","StiSvc","TabletInputService",
    "TermService","SessionEnv","UmRdpService","lfsvc","SensorService",
    "SensorDataService","SensrSvc","PhoneSvc","WalletService","WbioSrvc","LanmanServer"
)
$servicesToDisable | ForEach-Object { Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue }

# ==========================================
# 7. ONEDRIVE REMOVAL
# ==========================================
Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
$uninstallers = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    "$env:SystemRoot\System32\OneDriveSetup.exe"
)
$uninstallers | Where-Object { Test-Path $_ } | ForEach-Object { Start-Process $_ -ArgumentList "/uninstall" -Wait -NoNewWindow }
$onedrivePaths = @(
    "$env:USERPROFILE\OneDrive"
    "$env:LOCALAPPDATA\Microsoft\OneDrive"
    "$env:ProgramData\Microsoft OneDrive"
)
$onedrivePaths | Where-Object { Test-Path $_ } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# ==========================================
# 8. TEMP CLEANUP
# ==========================================
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:windir\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# ==========================================
# 9. CLEAR POWERSHELL HISTORY & TRACES
# ==========================================
Clear-History
$psReadLinePath = (Get-PSReadLineOption).HistorySavePath
if ($psReadLinePath -and (Test-Path $psReadLinePath)) {
    Remove-Item $psReadLinePath -Force -ErrorAction SilentlyContinue
}
[Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() 2>$null

Write-Host "[+] Optimization Payload Complete." -ForegroundColor Green
