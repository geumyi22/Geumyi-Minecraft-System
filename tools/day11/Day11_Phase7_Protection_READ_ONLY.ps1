param(
    [string]$BaseUrl = "http://127.0.0.1:8790",
    [string]$OutDir = "$env:TEMP\Geumyi-Day11-Phase7"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$BaseUrl = $BaseUrl.TrimEnd('/')

function Get-Json([string]$Path) {
    Invoke-RestMethod -Uri ($BaseUrl + $Path) -Method GET -TimeoutSec 30
}

function Post-Json([string]$Path, [object]$Body) {
    Invoke-RestMethod -Uri ($BaseUrl + $Path) -Method POST -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 10 -Compress) -TimeoutSec 60
}

function Expected-HttpStatus([string]$Path, [object]$Body, [int]$Expected) {
    try {
        $null = Invoke-WebRequest -UseBasicParsing -Uri ($BaseUrl + $Path) -Method POST -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 8 -Compress) -TimeoutSec 30
        return [ordered]@{ pass = $false; status = 200; expected = $Expected; message = "request unexpectedly succeeded" }
    } catch {
        $status = 0
        try { $status = [int]$_.Exception.Response.StatusCode } catch {}
        return [ordered]@{ pass = ($status -eq $Expected); status = $status; expected = $Expected; message = [string]$_.Exception.Message }
    }
}

Write-Host "============================================================"
Write-Host " Geumyi Minecraft System - Day 11 Phase 7 / PROTECTION READ ONLY"
Write-Host "============================================================"
Write-Host "- Reads backup/trash inventory and retention dry-runs."
Write-Host "- Calls restore PRE-FLIGHT only; it never restores data."
Write-Host "- Probes permanent-delete confirmation with an impossible filename only."
Write-Host "- Does NOT create/delete/move/restore backups, stop/start/restart servers, or edit worlds."
Write-Host ""

$status = Get-Json "/api/status"
$fleet = Get-Json "/api/v4/update/fleet"
$serverIds = @($fleet.servers | ForEach-Object { [string]$_.server_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$rows = @()
$protectedCandidateViolation = $false
$inventoryOK = $true
$retentionOK = $true
$preflightAPISeen = $false

foreach ($id in $serverIds) {
    try {
        $activeResult = Get-Json ("/api/v4/backups?id=" + [uri]::EscapeDataString($id))
        $trashResult = Get-Json ("/api/v4/backups/trash?id=" + [uri]::EscapeDataString($id))
        $retention = Post-Json "/api/v4/backup/retention/dry-run" @{ id = $id; keep_latest = 2 }

        $active = @($activeResult.backups)
        $trash = @($trashResult.backups)
        $candidates = @($retention.candidates)

        $protectedNames = @($active | Where-Object { [bool]$_.protected -or [string]$_.kind -eq "checkpoint" } | ForEach-Object { [string]$_.file })
        $candidateNames = @($candidates | ForEach-Object { [string]$_.file })
        $bad = @($candidateNames | Where-Object { $protectedNames -contains $_ })
        if ($bad.Count -gt 0) { $protectedCandidateViolation = $true }

        $preflight = $null
        if ($active.Count -gt 0) {
            $preflight = Post-Json "/api/v4/restore/preflight" @{ id = $id; file = [string]$active[0].file }
            $preflightAPISeen = $true
        }

        $rows += [ordered]@{
            server_id = $id
            active_count = $active.Count
            trash_count = $trash.Count
            protected_count = @($active | Where-Object { [bool]$_.protected }).Count
            checkpoint_count = @($active | Where-Object { [string]$_.kind -eq "checkpoint" }).Count
            provenance_count = @($active | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.source_reason) }).Count
            retention_candidates = $candidateNames
            retention_reclaim_bytes = [int64]$retention.reclaim_bytes
            retention_blocked_reason = [string]$retention.blocked_reason
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
                    checks = @($preflight.checks)
                }
            })
        }
    } catch {
        $inventoryOK = $false
        $retentionOK = $false
        $rows += [ordered]@{
            server_id = $id
            error = [string]$_.Exception.Message
        }
    }
}

$confirmProbe = $null
if ($serverIds.Count -gt 0) {
    $confirmProbe = Expected-HttpStatus "/api/v4/backup/action" @{
        id = $serverIds[0]
        file = "__day11_phase7_confirmation_probe_DOES_NOT_EXIST__.zip"
        action = "delete-permanent"
    } 400
}

$checks = [ordered]@{
    gsc_version_4_3_8 = ([string]$status.app_version -eq "4.3.8")
    four_or_more_servers = ($serverIds.Count -ge 4)
    backup_inventory_readable = $inventoryOK
    retention_dry_run_readable = $retentionOK
    protected_and_checkpoints_exempt = (-not $protectedCandidateViolation)
    restore_preflight_endpoint = $preflightAPISeen
    permanent_delete_server_confirmation_gate = ($null -ne $confirmProbe -and [bool]$confirmProbe.pass)
}

$allPass = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value }).Count -eq 0

$report = [ordered]@{
    schema = 1
    phase = "11.7"
    mode = "READ_ONLY"
    generated = (Get-Date).ToString("o")
    result = $(if ($allPass) { "PASS" } else { "CHECK" })
    gsc_version = [string]$status.app_version
    servers = $rows
    permanent_delete_confirmation_probe = $confirmProbe
    mutation_performed = $false
    server_lifecycle_action_performed = $false
    restore_performed = $false
    permanent_delete_performed = $false
    checks = $checks
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$path = Join-Path $OutDir ("Geumyi-Day11-Phase7-READ-ONLY-" + $stamp + ".json")
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8

Write-Host ("GSC VERSION : " + $report.gsc_version)
Write-Host ("SERVERS     : " + $serverIds.Count)
foreach ($row in $rows) {
    if ($null -ne $row.error) {
        Write-Host ("{0,-12} ERROR {1}" -f $row.server_id,$row.error)
        continue
    }
    $pf = $row.restore_preflight
    $pfText = "none"
    if ($null -ne $pf) {
        $pfText = "ready=" + [string]$pf.ready
        if (-not [string]::IsNullOrWhiteSpace([string]$pf.blocked_reason)) { $pfText += " (" + [string]$pf.blocked_reason + ")" }
    }
    Write-Host ("{0,-12} active={1,-4} trash={2,-4} protected={3,-3} retention={4,-3} preflight={5}" -f $row.server_id,$row.active_count,$row.trash_count,$row.protected_count,@($row.retention_candidates).Count,$pfText)
}
Write-Host ""
foreach ($entry in $checks.GetEnumerator()) {
    Write-Host ("{0,-44} {1}" -f $entry.Key,$(if($entry.Value){"PASS"}else{"CHECK"}))
}
Write-Host ""
Write-Host ("RESULT      : " + $report.result)
Write-Host ("MUTATION    : false")
Write-Host ("REPORT      : " + $path)
