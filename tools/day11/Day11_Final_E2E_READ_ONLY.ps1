param(
    [string]$BaseUrl = "http://127.0.0.1:8790",
    [string]$OutDir = "$env:TEMP\Geumyi-Day11-Final"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd('/')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-Json([string]$Path, [int]$TimeoutSec = 45) {
    Invoke-RestMethod -Uri ($BaseUrl + $Path) -Method GET -TimeoutSec $TimeoutSec
}

function Post-Json([string]$Path, [object]$Body, [int]$TimeoutSec = 90) {
    Invoke-RestMethod -Uri ($BaseUrl + $Path) -Method POST -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 12 -Compress) -TimeoutSec $TimeoutSec
}

Write-Host "============================================================"
Write-Host " Geumyi Minecraft System - DAY 11 FINAL E2E / READ ONLY"
Write-Host "============================================================"
Write-Host "- Verifies GSC Client/Host, Control API, fleet, signed update dry-run,"
Write-Host "  network entry readiness, GSCM/mobile security, health and recovery inventory."
Write-Host "- POST calls are restricted to documented DRY-RUN / PRE-FLIGHT endpoints."
Write-Host "- Does NOT stage/apply updates, change policy, stop/start/restart servers,"
Write-Host "  restore Minecraft data, move/delete backups, or edit worlds/configs."
Write-Host ""

$errors = New-Object System.Collections.ArrayList

function Safe-Get([string]$Path, [string]$Name) {
    try { return Get-Json $Path }
    catch {
        [void]$errors.Add([ordered]@{ name=$Name; error=[string]$_.Exception.Message })
        return $null
    }
}
function Safe-Post([string]$Path, [object]$Body, [string]$Name, [int]$TimeoutSec=90) {
    try { return Post-Json $Path $Body $TimeoutSec }
    catch {
        [void]$errors.Add([ordered]@{ name=$Name; error=[string]$_.Exception.Message })
        return $null
    }
}

$client = Safe-Get "/client/config" "client-config"
$status = Safe-Get "/api/status" "host-status"
$info = Safe-Get "/api/v1/info" "control-info"
$snapshot = Safe-Get "/api/v1/snapshot" "control-snapshot"
$mobile = Safe-Get "/api/v1/mobile" "mobile-status"
$fleet = Safe-Get "/api/v4/update/fleet" "update-fleet"
$updateStatus = Safe-Get "/api/v4/update/status" "update-status"
$selfUpdate = Safe-Get "/api/v4/update/self/status?fresh=1" "gsc-self-update"
$rollout = Safe-Get "/api/v4/update/canary-rollout" "canary-rollout"
$notifications = Safe-Get "/api/v4/update/notifications?limit=25" "update-notifications"
$external = Safe-Get "/api/v4/update/external/status" "external-update-status"
$network = Safe-Get "/api/v4/network/entry-status" "network-entry-status"
$health = Safe-Get "/api/v4/health" "v4-health"
$events = Safe-Get "/api/v4/events?limit=120" "events"
$audit = Safe-Get "/api/v1/audit?limit=120" "audit"

# Signed manifest discovery + planning only. Host source explicitly defines this endpoint
# as no download/install/profile edit/server restart/policy change.
$dry = Safe-Post "/api/v4/update/dry-run" @{} "signed-update-dry-run" 120

$serverIds = @()
if ($null -ne $fleet) {
    $serverIds = @($fleet.servers | ForEach-Object { [string]$_.server_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$backupRows = @()
$backupReadable = $true
$retentionReadable = $true
$protectedCandidateViolation = $false
$restorePreflightSeen = $false
$provenanceSeen = $false
$phase7DisposableInTrash = $false

foreach ($id in $serverIds) {
    try {
        $activeResult = Get-Json ("/api/v4/backups?id=" + [uri]::EscapeDataString($id))
        $trashResult = Get-Json ("/api/v4/backups/trash?id=" + [uri]::EscapeDataString($id))
        $retention = Post-Json "/api/v4/backup/retention/dry-run" @{ id=$id; keep_latest=2 } 60

        $active = @($activeResult.backups)
        $trash = @($trashResult.backups)
        $protected = @($active | Where-Object { [bool]$_.protected -or [string]$_.kind -eq "checkpoint" })
        $candidateNames = @($retention.candidates | ForEach-Object { [string]$_.file })
        $protectedNames = @($protected | ForEach-Object { [string]$_.file })
        $bad = @($candidateNames | Where-Object { $protectedNames -contains $_ })
        if ($bad.Count -gt 0) { $protectedCandidateViolation = $true }

        $allBackups = @($active) + @($trash)
        if (@($allBackups | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.source_reason) }).Count -gt 0) {
            $provenanceSeen = $true
        }
        if (@($trash | Where-Object { [string]$_.source_reason -eq "day11-phase7-disposable-e2e" }).Count -gt 0) {
            $phase7DisposableInTrash = $true
        }

        $preflight = $null
        if ($active.Count -gt 0) {
            $preflight = Post-Json "/api/v4/restore/preflight" @{ id=$id; file=[string]$active[0].file } 90
            $restorePreflightSeen = $true
        }

        $backupRows += [ordered]@{
            server_id = $id
            active_count = $active.Count
            trash_count = $trash.Count
            protected_or_checkpoint_count = $protected.Count
            provenance_count = @($allBackups | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.source_reason) }).Count
            retention_candidate_count = $candidateNames.Count
            protected_candidate_violation = @($bad)
            restore_preflight = $(if ($null -eq $preflight) { $null } else {
                [ordered]@{
                    file = [string]$preflight.file
                    ready = [bool]$preflight.ready
                    server_offline = [bool]$preflight.server_offline
                    backup_verified = [bool]$preflight.backup_verified
                    server_match = [bool]$preflight.server_match
                    checkpoint_ready = [bool]$preflight.checkpoint_ready
                    pending_update = [bool]$preflight.pending_update
                    blocked_reason = [string]$preflight.blocked_reason
                }
            })
        }
    } catch {
        $backupReadable = $false
        $retentionReadable = $false
        $backupRows += [ordered]@{ server_id=$id; error=[string]$_.Exception.Message }
    }
}

$features = @()
if ($null -ne $info) { $features = @($info.features | ForEach-Object { [string]$_ }) }
$requiredFeatures = @("server-state","job-queue","audit-log","websocket","pairing-v2","device-management","backups","restore","server-extensions")
$featureMissing = @($requiredFeatures | Where-Object { $features -notcontains $_ })

$fleetRows = @()
if ($null -ne $fleet) { $fleetRows = @($fleet.servers) }
$policyBad = @($fleetRows | Where-Object { [string]$_.policy -ne "managed" })
$channelBad = @($fleetRows | Where-Object { [string]$_.channel -ne "inherit" })
$pinBad = @($fleetRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.pin) })
$effectiveBad = @($fleetRows | Where-Object { [string]$_.effective_channel -ne "beta" })
$unsafeUpdatePhase = @($fleetRows | Where-Object {
    $p = [string]$_.status.phase
    [bool]$_.status.block_start -or $p -in @("blocked","rollback_failed","rolling_back","pending_health","downloading")
})

$networkRows = @()
if ($null -ne $network) { $networkRows = @($network.endpoints) }
$networkBad = @($networkRows | Where-Object { -not [bool]$_.java_responding -or -not [bool]$_.bedrock_raknet_pong })

$healthRows = @()
if ($null -ne $health) { $healthRows = @($health.servers) }
$healthFail = @($healthRows | Where-Object { [string]$_.overall -eq "fail" })
$activeOperations = @($healthRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.operation) })

$mobileSecurity = $null
if ($null -ne $mobile) { $mobileSecurity = $mobile.security }
$trustedCount = 0
if ($null -ne $mobile) { $trustedCount = @($mobile.trusted_devices).Count }

$dryServers = @()
if ($null -ne $dry) { $dryServers = @($dry.servers) }
$playerSafetyOK = $true
foreach ($s in $dryServers) {
    if ([bool]$s.online -and [int]$s.players -gt 0 -and -not [bool]$s.player_aware_block) { $playerSafetyOK = $false }
    if ([int]$s.players -eq 0 -and -not [bool]$s.restart_safe) { $playerSafetyOK = $false }
}

$selfLast = $null
if ($null -ne $selfUpdate) { $selfLast = $selfUpdate.last_apply }

$checks = [ordered]@{
    local_client_4_3_8 = ($null -ne $client -and [string]$client.version -eq "4.3.8")
    host_4_3_8 = ($null -ne $status -and [string]$status.app_version -eq "4.3.8")
    control_api_v1_ok = ($null -ne $info -and [bool]$info.ok -and [int]$info.api_version -ge 1 -and [string]$info.gsc_version -eq "4.3.8")
    required_control_features = ($featureMissing.Count -eq 0)
    four_server_snapshot = ($null -ne $snapshot -and @($snapshot.servers).Count -ge 4)
    no_active_control_jobs = ($null -ne $snapshot -and [int]$snapshot.active_jobs -eq 0)

    fleet_schema_1 = ($null -ne $fleet -and [int]$fleet.schema -eq 1)
    fleet_four_servers = ($serverIds.Count -ge 4)
    global_update_beta_enabled = ($null -ne $fleet -and [bool]$fleet.global.enabled -and [string]$fleet.global.channel -eq "beta")
    fleet_policy_managed = ($policyBad.Count -eq 0)
    fleet_channel_inherit = ($channelBad.Count -eq 0)
    fleet_no_pins = ($pinBad.Count -eq 0)
    fleet_effective_beta = ($effectiveBad.Count -eq 0)
    no_blocked_update_transaction = ($unsafeUpdatePhase.Count -eq 0)

    host_self_update_current = ($null -ne $selfUpdate -and [string]$selfUpdate.installed -eq "4.3.8" -and [string]$selfUpdate.latest -eq "4.3.8" -and [bool]$selfUpdate.signature_verified -and -not [bool]$selfUpdate.available -and -not [bool]$selfUpdate.downgrade_blocked)
    signed_update_dry_run = ($null -ne $dry -and [bool]$dry.dry_run -and [bool]$dry.signature_verified)
    dry_run_no_install = ($null -ne $dry -and -not [bool]$dry.install_performed)
    dry_run_no_restart = ($null -ne $dry -and -not [bool]$dry.restart_performed)
    player_aware_safety = $playerSafetyOK

    canary_not_active = ($null -ne $rollout -and -not [bool]$rollout.active)
    canary_completed = ($null -ne $rollout -and [bool]$rollout.completed)
    canary_policy_only = ($null -ne $rollout -and [bool]$rollout.policy_only -and -not [bool]$rollout.server_restart_performed)

    network_three_public_entries = ($networkRows.Count -eq 3)
    java_and_bedrock_entry_probes = ($networkRows.Count -eq 3 -and $networkBad.Count -eq 0)
    health_has_no_fail = ($healthRows.Count -ge 4 -and $healthFail.Count -eq 0)
    no_v4_operation_active = ($activeOperations.Count -eq 0)

    mobile_api_enabled = ($null -ne $mobile -and [bool]$mobile.enabled)
    mobile_security_boundary = ($null -ne $mobileSecurity -and [bool]$mobileSecurity.auth_required -and -not [bool]$mobileSecurity.rcon_exposed -and -not [bool]$mobileSecurity.gds_exposed)
    trusted_mobile_device_present = ($trustedCount -ge 1)

    external_status_read_only = ($null -ne $external -and [string]$external.mode -eq "read-only" -and -not [bool]$external.live_files_modified)
    paper_manual_approval_policy = ($null -ne $external -and [string]$external.paper_policy -eq "notify/manual-approve")

    backup_inventory_readable = $backupReadable
    retention_dry_run_readable = $retentionReadable
    protected_backups_exempt_from_retention = (-not $protectedCandidateViolation)
    backup_provenance_visible = $provenanceSeen
    phase7_disposable_remains_recoverable = $phase7DisposableInTrash
    restore_preflight_available = $restorePreflightSeen

    notifications_api = ($null -ne $notifications -and [int]$notifications.schema -eq 1)
    event_history_visible = ($null -ne $events -and @($events.events).Count -gt 0)
    audit_history_visible = ($null -ne $audit -and @($audit.audit).Count -gt 0)
    all_required_api_calls_succeeded = ($errors.Count -eq 0)
}

$failed = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value })
$allPass = ($failed.Count -eq 0)

$report = [ordered]@{
    schema = 1
    phase = "Day11-Final-E2E"
    mode = "READ_ONLY"
    generated = (Get-Date).ToString("o")
    result = $(if ($allPass) { "PASS" } else { "CHECK" })

    versions = [ordered]@{
        local_client = $(if($null -ne $client){[string]$client.version}else{""})
        host = $(if($null -ne $status){[string]$status.app_version}else{""})
        control_api = $(if($null -ne $info){[int]$info.api_version}else{0})
        signed_release = $(if($null -ne $selfUpdate){[string]$selfUpdate.release}else{""})
        verified_latest = $(if($null -ne $selfUpdate){[string]$selfUpdate.latest}else{""})
        self_update_last = $selfLast
    }

    fleet = [ordered]@{
        global_enabled = $(if($null -ne $fleet){[bool]$fleet.global.enabled}else{$false})
        global_channel = $(if($null -ne $fleet){[string]$fleet.global.channel}else{""})
        servers = @($fleetRows | ForEach-Object {
            [ordered]@{
                server_id=[string]$_.server_id
                role=[string]$_.role
                online=[bool]$_.online
                policy=[string]$_.policy
                channel=[string]$_.channel
                effective_channel=[string]$_.effective_channel
                pin=[string]$_.pin
                update_phase=[string]$_.status.phase
                block_start=[bool]$_.status.block_start
            }
        })
    }

    signed_update_dry_run = $(if($null -eq $dry){$null}else{
        [ordered]@{
            release=[string]$dry.release
            manifest_sha256=[string]$dry.manifest_sha256
            signature_verified=[bool]$dry.signature_verified
            available_count=[int]$dry.available_count
            blocked_servers=[int]$dry.blocked_servers
            install_performed=[bool]$dry.install_performed
            restart_performed=[bool]$dry.restart_performed
            servers=@($dryServers | ForEach-Object {
                [ordered]@{
                    server_id=[string]$_.server_id
                    online=[bool]$_.online
                    players=[int]$_.players
                    player_aware_block=[bool]$_.player_aware_block
                    restart_safe=[bool]$_.restart_safe
                    available_items=@($_.items).Count
                    error=[string]$_.error
                }
            })
        }
    })

    canary = $(if($null -eq $rollout){$null}else{
        [ordered]@{
            active=[bool]$rollout.active
            completed=[bool]$rollout.completed
            release=[string]$rollout.release
            policy_only=[bool]$rollout.policy_only
            server_restart_performed=[bool]$rollout.server_restart_performed
            promoted=@($rollout.promoted)
            order=@($rollout.order)
        }
    })

    network_entry_smoke = @($networkRows | ForEach-Object {
        [ordered]@{
            id=[string]$_.id
            java_tcp=[int]$_.java_tcp
            java_responding=[bool]$_.java_responding
            bedrock_udp=[int]$_.bedrock_udp
            bedrock_raknet_pong=[bool]$_.bedrock_raknet_pong
        }
    })
    network_note = "Port/RakNet readiness only; real Java/Bedrock login/routing remains a separate user client smoke gate."

    health = @($healthRows | ForEach-Object {
        [ordered]@{
            server_id=[string]$_.server_id
            overall=[string]$_.overall
            operation=[string]$_.operation
            failed_checks=@($_.checks | Where-Object { [string]$_.status -eq "fail" } | ForEach-Object { [string]$_.key })
            warning_checks=@($_.checks | Where-Object { [string]$_.status -eq "warn" } | ForEach-Object { [string]$_.key })
        }
    })

    mobile = [ordered]@{
        enabled=$(if($null -ne $mobile){[bool]$mobile.enabled}else{$false})
        trusted_devices=$trustedCount
        security=$mobileSecurity
    }

    external = [ordered]@{
        mode=$(if($null -ne $external){[string]$external.mode}else{""})
        live_files_modified=$(if($null -ne $external){[bool]$external.live_files_modified}else{$true})
        paper_policy=$(if($null -ne $external){[string]$external.paper_policy}else{""})
        component_count=$(if($null -ne $external){@($external.components).Count}else{0})
        metadata_errors=$(if($null -ne $external){@($external.errors)}else{@()})
    }

    protection_recovery = $backupRows

    evidence_counts = [ordered]@{
        notifications=$(if($null -ne $notifications){@($notifications.events).Count}else{0})
        events=$(if($null -ne $events){@($events.events).Count}else{0})
        audit=$(if($null -ne $audit){@($audit.audit).Count}else{0})
    }

    checks = $checks
    failed_checks = @($failed | ForEach-Object { [string]$_.Key })
    api_errors = @($errors)

    mutation_performed = $false
    update_stage_or_apply_performed = $false
    policy_change_performed = $false
    server_lifecycle_action_performed = $false
    minecraft_data_restore_performed = $false
    backup_move_or_delete_performed = $false
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$path = Join-Path $OutDir ("Geumyi-Day11-Final-E2E-" + $stamp + ".json")
$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $path -Encoding UTF8

Write-Host "LOCAL CLIENT : $($report.versions.local_client)"
Write-Host "SERVER HOST  : $($report.versions.host)"
Write-Host "SIGNED REL   : $($report.versions.signed_release)"
Write-Host "FLEET        : $($serverIds.Count) servers / $($report.fleet.global_channel)"
Write-Host "NETWORK      : $($networkRows.Count) public entries / failed=$($networkBad.Count)"
Write-Host "HEALTH       : fail=$($healthFail.Count) / active-operations=$($activeOperations.Count)"
Write-Host "MOBILE       : enabled=$($report.mobile.enabled) / trusted=$trustedCount"
Write-Host "BACKUP E2E   : phase7 disposable recoverable=$phase7DisposableInTrash"
Write-Host ""
foreach ($entry in $checks.GetEnumerator()) {
    Write-Host ("{0,-48} {1}" -f $entry.Key,$(if($entry.Value){"PASS"}else{"CHECK"}))
}
Write-Host ""
Write-Host ("RESULT       : " + $report.result)
Write-Host ("MUTATION     : false")
Write-Host ("REPORT       : " + $path)
Write-Host ""
Write-Host "IMPORTANT: Network probes above are not a real player login."
Write-Host "After a PASS report, do the short Java + Bedrock real-client smoke gate before Day 11 closure."

if (-not $allPass) { exit 2 }
