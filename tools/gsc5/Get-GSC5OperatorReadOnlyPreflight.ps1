# GSC 5 beta operator preflight (Windows PowerShell 5.1).
# READ ONLY: does not start/stop services, alter tasks/firewalls/config,
# read Minecraft worlds, inspect secrets, or approve a Stable release.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($env:OS -ne "Windows_NT") { throw "Requires Windows" }

function Get-BinaryPathFromServiceCommand([string]$commandLine) {
    if ([string]::IsNullOrWhiteSpace($commandLine)) { return $null }
    if ($commandLine -match '^\s*"([^"]+?\.exe)"(?:\s|$)') {
        return $Matches[1]
    }
    if ($commandLine -match '^\s*(.+?\.exe)(?:\s|$)') {
        return $Matches[1]
    }
    return $null
}

$serviceName = "Geumyi Server Center Host"
$serviceState = "NOT_FOUND"
$serviceBinarySHA256 = $null
$serviceBinaryPresent = $false
$binaryInspection = "UNAVAILABLE"
try {
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
    if ($null -ne $svc) {
        $serviceState = [string]$svc.State
        $binaryPath = Get-BinaryPathFromServiceCommand ([string]$svc.PathName)
        if ($binaryPath -and (Test-Path -LiteralPath $binaryPath -PathType Leaf)) {
            $serviceBinaryPresent = $true
            $serviceBinarySHA256 = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $binaryInspection = "HASHED"
        } else {
            $binaryInspection = "BINARY_NOT_RESOLVED"
        }
    } else {
        $binaryInspection = "SERVICE_NOT_FOUND"
    }
} catch {
    $binaryInspection = "SERVICE_QUERY_ERROR"
}

$healthVersion = $null
$healthStatus = "UNREACHABLE_OR_INVALID"
$healthClaimsService = $false
try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:8787/api/health" -UseBasicParsing -Method Get -TimeoutSec 3 -ErrorAction Stop
    if ([int]$response.StatusCode -eq 200) {
        $obj = ConvertFrom-Json -InputObject $response.Content -ErrorAction Stop
        if ($obj.ok -eq $true -and [int]$obj.generation -eq 4 -and
            $obj.version -match '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
            $healthVersion = [string]$obj.version
            $healthClaimsService = ($obj.service -eq $true)
            $healthStatus = "GSC_HEALTH_SHAPE_VALID_NOT_IDENTITY_PROOF"
        }
    }
} catch {
    # A refused/unavailable loopback health check is UNKNOWN, never PASS.
}

$velocityTasks = @()
foreach ($id in @("wild", "playground", "other")) {
    $taskName = "Geumyi Day10 Velocity $id"
    $status = "UNKNOWN"
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        if ($null -ne $task) { $status = [string]$task.State }
    } catch { $status = "NOT_FOUND_OR_INACCESSIBLE" }
    $velocityTasks += [ordered]@{ id = $id; scheduler_state = $status }
}

$canaryObserved = ($healthVersion -match '^4\.5\.2(?:[-+]|$)')
$velocityTasksKnown = (@($velocityTasks | Where-Object {
    $_.scheduler_state -eq "UNKNOWN" -or $_.scheduler_state -eq "NOT_FOUND_OR_INACCESSIBLE"
}).Count -eq 0)
$reasons = @()
if ($canaryObserved) {
    $reasons += "ACTIVE_4_5_2_CANARY: no documented automatic migration to the 4.5.1-based beta"
}
if ($healthStatus -ne "GSC_HEALTH_SHAPE_VALID_NOT_IDENTITY_PROOF") {
    $reasons += "HEALTH_UNKNOWN: runtime version needs operator verification"
}
if (-not $serviceBinaryPresent) {
    $reasons += "HOST_BINARY_UNVERIFIED: service installation and exact source are not established"
}
if (-not $velocityTasksKnown) {
    $reasons += "SCHEDULER_TASK_INVENTORY_INCOMPLETE: three original proxy owners need confirmation"
}
$reasons += "LIVE_QA_AND_FORMAL_STABLE_GATES_NOT_PASSED"

$result = [ordered]@{
    schema = 1
    check = "GSC5_OPERATOR_READ_ONLY_PREFLIGHT"
    read_only = $true
    production_mutation_applied = $false
    gsc5_stable_install_authorized = $false
    release_gate_stable_allowed = $false
    system_install_or_upgrade_attempted = $false
    host_service_state = $serviceState
    host_service_binary_present = $serviceBinaryPresent
    host_binary_sha256 = $serviceBinarySHA256
    host_binary_readback = $binaryInspection
    loopback_health_state = $healthStatus
    loopback_health_reported_version = $healthVersion
    loopback_health_reports_service = $healthClaimsService
    canary_452_reported_by_health = [bool]$canaryObserved
    velocity_tasks = $velocityTasks
    constraints = $reasons
    next_step = "Use a disposable Windows test system for actual installer upgrade/rollback. Never run this beta on the operational Host without separate review."
}
Write-Output "GSC5_OPERATOR_READ_ONLY_PREFLIGHT"
Write-Output ($result | ConvertTo-Json -Depth 5)
