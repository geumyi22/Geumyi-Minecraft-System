param(
    [string]$BaseUrl = "http://127.0.0.1:8790",
    [string]$OutDir = "$env:TEMP\Geumyi-Day11-Phase6"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-Json([string]$Path) {
    Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/') + $Path) -Method GET -TimeoutSec 20
}

function Post-Json([string]$Path, [object]$Body) {
    Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/') + $Path) -Method POST -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 8 -Compress) -TimeoutSec 45
}

Write-Host "============================================================"
Write-Host " Geumyi Minecraft System - Day 11 Phase 6 / FLEET READ ONLY"
Write-Host "============================================================"
Write-Host "- Reads GSC status, fleet policy, update audit events."
Write-Host "- Performs signed update dry-run only."
Write-Host "- Does NOT save policy, download/apply updates, restart servers, or edit worlds."
Write-Host ""

$status = Get-Json "/api/status"
$fleet = Get-Json "/api/v4/update/fleet"
$eventsResult = Get-Json "/api/v4/events?limit=120"
$dry = Post-Json "/api/v4/update/dry-run" @{}

$serverRows = @($fleet.servers | ForEach-Object {
    $st = $_.status
    [ordered]@{
        server_id = [string]$_.server_id
        name = [string]$_.name
        role = [string]$_.role
        online = [bool]$_.online
        policy = [string]$_.policy
        configured_channel = [string]$_.channel
        effective_channel = [string]$_.effective_channel
        pin_set = -not [string]::IsNullOrWhiteSpace([string]$_.pin)
        update_phase = [string]$st.phase
        update_message = [string]$st.message
    }
})

$dryServers = @($dry.servers | ForEach-Object {
    [ordered]@{
        server_id = [string]$_.server_id
        name = [string]$_.name
        online = [bool]$_.online
        players = [int]$_.players
        player_aware_block = [bool]$_.player_aware_block
        restart_safe = [bool]$_.restart_safe
        available_items = @($_.items).Count
        error = [string]$_.error
    }
})

$policyOK = @($serverRows | Where-Object { $_.policy -notin @("managed","manual","hold") }).Count -eq 0
$channelOK = @($serverRows | Where-Object { $_.configured_channel -notin @("inherit","stable","beta","canary") }).Count -eq 0
$effectiveChannelOK = @($serverRows | Where-Object { $_.effective_channel -notin @("stable","beta","canary") }).Count -eq 0
$playerSafetyOK = $true
foreach ($s in $dryServers) {
    if ($s.online -and $s.players -gt 0 -and -not $s.player_aware_block) { $playerSafetyOK = $false }
    if ($s.players -eq 0 -and -not $s.restart_safe) { $playerSafetyOK = $false }
}

$updateEvents = @($eventsResult.events | Where-Object { [string]$_.category -eq "update" } | Select-Object -Last 25 | ForEach-Object {
    [ordered]@{
        time = [string]$_.time
        level = [string]$_.level
        server_id = [string]$_.server_id
        message = [string]$_.message
    }
})

$checks = [ordered]@{
    gsc_version_4_3_2 = ([string]$status.app_version -eq "4.3.2")
    fleet_schema_1 = ([int]$fleet.schema -eq 1)
    four_or_more_servers = ($serverRows.Count -ge 4)
    policies_valid = $policyOK
    channels_valid = $channelOK
    effective_channels_valid = $effectiveChannelOK
    dry_run_flag = [bool]$dry.dry_run
    dry_run_no_install = (-not [bool]$dry.install_performed)
    dry_run_no_restart = (-not [bool]$dry.restart_performed)
    signed_manifest_verified = [bool]$dry.signature_verified
    player_aware_safety = $playerSafetyOK
    update_audit_visible = ($updateEvents.Count -gt 0)
}

$allPass = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value }).Count -eq 0

$report = [ordered]@{
    schema = 1
    phase = "11.6"
    mode = "READ_ONLY"
    generated = (Get-Date).ToString("o")
    result = $(if ($allPass) { "PASS" } else { "CHECK" })
    gsc_version = [string]$status.app_version
    fleet_global = [ordered]@{
        enabled = [bool]$fleet.global.enabled
        channel = [string]$fleet.global.channel
        repository = [string]$fleet.global.repository
        github_authenticated = [bool]$fleet.global.github_authenticated
    }
    servers = $serverRows
    dry_run = [ordered]@{
        release = [string]$dry.release
        signature_verified = [bool]$dry.signature_verified
        available_count = [int]$dry.available_count
        blocked_servers = [int]$dry.blocked_servers
        install_performed = [bool]$dry.install_performed
        restart_performed = [bool]$dry.restart_performed
        servers = $dryServers
    }
    update_events = $updateEvents
    checks = $checks
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$path = Join-Path $OutDir ("Geumyi-Day11-Phase6-" + $stamp + ".json")
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8

Write-Host "GSC VERSION : $($report.gsc_version)"
Write-Host "FLEET       : $($serverRows.Count) servers / global channel=$($report.fleet_global.channel)"
Write-Host "DRY-RUN     : release=$($report.dry_run.release) / signature=$($report.dry_run.signature_verified)"
Write-Host "CHANGES     : install=$($report.dry_run.install_performed) / restart=$($report.dry_run.restart_performed)"
Write-Host ""
foreach ($s in $dryServers) {
    Write-Host ("{0,-12} online={1,-5} players={2,-3} blocked={3,-5} restart_safe={4,-5} items={5}" -f $s.server_id,$s.online,$s.players,$s.player_aware_block,$s.restart_safe,$s.available_items)
}
Write-Host ""
foreach ($c in $checks.GetEnumerator()) {
    Write-Host ("{0,-30} {1}" -f $c.Key,$(if($c.Value){"PASS"}else{"CHECK"}))
}
Write-Host ""
Write-Host ("RESULT      : " + $report.result)
Write-Host ("REPORT      : " + $path)
