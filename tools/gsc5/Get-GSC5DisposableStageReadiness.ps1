#requires -Version 5.1
<#
READ-ONLY inventory for a separate, disposable Windows test PC or VM.
Never installs, starts, stops, deletes, downloads, or changes anything.
Even a PASS does NOT establish machine isolation or authorize installation.
Do not publish machine-specific or credential-bearing output.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'GSC5 stage readiness requires Windows' }

$reasons = New-Object 'System.Collections.Generic.List[string]'
$serviceState = 'NOT_FOUND'
$servicePresent = $false
$taskCount = $null
$javaProcessCount = $null
$tcpListenerCount = $null
$udpEndpointCount = $null
$gscDataPresent = $false
$gscInstallPresent = $false
$gscClientConfigPresent = $false

# Check Windows service presence without disclosing its installed path.
try {
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
    if ($null -ne $svc) {
        $servicePresent = $true
        $serviceState = [string]$svc.State
        $reasons.Add('EXISTING_GSC_HOST_SERVICE: target is not a clean disposable install')
    }
} catch {
    $serviceState = 'QUERY_FAILED'
    $reasons.Add('HOST_SERVICE_INVENTORY_UNAVAILABLE')
}

# Enumerate tasks once to distinguish an absent task from inaccessible data.
try {
    $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
        $_.TaskName -like 'Geumyi Day10 Velocity *' -or
        $_.TaskName -eq 'Geumyi Server Center Host'
    })
    $taskCount = $tasks.Count
    if ($taskCount -gt 0) { $reasons.Add('EXISTING_GSC_OR_VELOCITY_TASKS') }
} catch {
    $reasons.Add('SCHEDULED_TASK_INVENTORY_UNAVAILABLE')
}

# Any Java workload could belong to Minecraft: do not stage on this machine.
try {
    $javaProcs = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
    $javaProcessCount = $javaProcs.Count
    if ($javaProcessCount -gt 0) { $reasons.Add('EXISTING_JAVA_PROCESSES') }
} catch {
    $reasons.Add('JAVA_PROCESS_INVENTORY_UNAVAILABLE')
}

# Canonical GSC / Java / Bedrock ports. Read only; unknown means BLOCKED.
$tcpPorts = @(8787, 18787, 8765, 8766, 8877, 25565, 25566, 25567, 25570, 25571, 25572, 25573, 25575, 25576)
$udpPorts = @(19132, 19133, 19134)
try {
    $tcp = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {
        $tcpPorts -contains [int]$_.LocalPort
    })
    $tcpListenerCount = $tcp.Count
    if ($tcpListenerCount -gt 0) { $reasons.Add('GSC_OR_MINECRAFT_TCP_LISTENERS_PRESENT') }
} catch {
    $reasons.Add('TCP_LISTENER_INVENTORY_UNAVAILABLE')
}
try {
    $udp = @(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object {
        $udpPorts -contains [int]$_.LocalPort
    })
    $udpEndpointCount = $udp.Count
    if ($udpEndpointCount -gt 0) { $reasons.Add('BEDROCK_UDP_ENDPOINTS_PRESENT') }
} catch {
    $reasons.Add('UDP_ENDPOINT_INVENTORY_UNAVAILABLE')
}

$programData = if ($env:PROGRAMDATA) { $env:PROGRAMDATA } else { 'C:\ProgramData' }
$gscDataPresent = Test-Path -LiteralPath (Join-Path $programData 'GeumyiServerCenter')
if ($gscDataPresent) { $reasons.Add('EXISTING_GSC_PROGRAMDATA') }

if ($env:ProgramFiles) {
    $gscInstallPresent = Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Geumyi Server Center')
    if ($gscInstallPresent) { $reasons.Add('EXISTING_GSC_INSTALL_DIRECTORY') }
} else {
    $reasons.Add('PROGRAMFILES_LOCATION_UNAVAILABLE')
}
if ($env:APPDATA) {
    $gscClientConfigPresent = Test-Path -LiteralPath (Join-Path $env:APPDATA 'GeumyiServerCenter')
    if ($gscClientConfigPresent) { $reasons.Add('EXISTING_GSC_CLIENT_PROFILE') }
} else {
    $reasons.Add('APPDATA_LOCATION_UNAVAILABLE')
}

$ready = ($reasons.Count -eq 0)
$report = [ordered]@{
    schema = 1
    check = 'GSC5_DISPOSABLE_STAGE_READ_ONLY'
    read_only = $true
    production_mutation_applied = $false
    status = if ($ready) { 'CLEAN_FOR_REVIEW' } else { 'BLOCKED_OR_UNKNOWN' }
    clean_for_disposable_test_review = $ready
    actual_machine_isolation_verified = $false
    installation_authorized = $false
    host_service_present = $servicePresent
    host_service_state = $serviceState
    matching_scheduled_tasks = $taskCount
    java_processes = $javaProcessCount
    matching_tcp_listeners = $tcpListenerCount
    matching_bedrock_udp_endpoints = $udpEndpointCount
    existing_programdata = $gscDataPresent
    existing_install_dir = $gscInstallPresent
    existing_client_profile = $gscClientConfigPresent
    constraints = @($reasons.ToArray())
    next_step = 'Confirm this is a disposable, network-isolated Windows VM with a reversible snapshot before any separately approved staged installer test.'
}
Write-Output 'GSC5_DISPOSABLE_STAGE_READ_ONLY_REPORT'
Write-Output ($report | ConvertTo-Json -Depth 5 -Compress)
