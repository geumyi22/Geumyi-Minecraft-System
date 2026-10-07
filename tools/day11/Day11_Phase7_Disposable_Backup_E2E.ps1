param(
    [string]$BaseUrl = "http://127.0.0.1:8790",
    [string]$ServerId = "other",
    [string]$OutDir = "$env:TEMP\Geumyi-Day11-Phase7",
    [string]$Confirm = ""
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd('/')
if ($Confirm -ne "RUN_DISPOSABLE_BACKUP_E2E") {
    Write-Host "[BLOCKED] This test creates and moves ONE disposable config backup only."
    Write-Host "It does not stop/start/restart a server and does not restore Minecraft data."
    Write-Host 'Re-run with: -Confirm "RUN_DISPOSABLE_BACKUP_E2E"'
    exit 23
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-Json([string]$Path) {
    Invoke-RestMethod -Uri ($BaseUrl + $Path) -Method GET -TimeoutSec 30
}
function Post-Json([string]$Path, [object]$Body, [int]$TimeoutSec = 120) {
    Invoke-RestMethod -Uri ($BaseUrl + $Path) -Method POST -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 10 -Compress) -TimeoutSec $TimeoutSec
}
function Expected-Status([string]$Path, [object]$Body, [int]$Expected) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri ($BaseUrl + $Path) -Method POST -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 8 -Compress) -TimeoutSec 45
        return [ordered]@{ pass = $false; status = [int]$r.StatusCode; expected = $Expected; message = "unexpected success" }
    } catch {
        $status = 0
        try { $status = [int]$_.Exception.Response.StatusCode } catch {}
        return [ordered]@{ pass = ($status -eq $Expected); status = $status; expected = $Expected; message = [string]$_.Exception.Message }
    }
}

Write-Host "============================================================"
Write-Host " Day 11 Phase 7 - DISPOSABLE CONFIG BACKUP E2E"
Write-Host "============================================================"
Write-Host "Target server : $ServerId"
Write-Host "Safety        : backup-storage mutations only"
Write-Host "Server stop   : NEVER"
Write-Host "Data restore  : NEVER"
Write-Host "Permanent del : NEVER (missing-confirm gate only)"
Write-Host ""

$status = Get-Json "/api/status"
if ([string]$status.app_version -ne "4.3.8") {
    throw "GSC 4.3.8 required; installed=$([string]$status.app_version)"
}

$fleet = Get-Json "/api/v4/update/fleet"
$target = @($fleet.servers | Where-Object { [string]$_.server_id -eq $ServerId } | Select-Object -First 1)
if ($target.Count -eq 0) { throw "Unknown server id: $ServerId" }

$steps = New-Object System.Collections.ArrayList
$file = ""
$finalLocation = "unknown"
$unexpectedPermanentDelete = $false

try {
    Write-Host "[1/10] Creating disposable CONFIG backup..."
    $created = Post-Json "/api/v4/backup" @{
        id = $ServerId
        scope = "config"
        reason = "day11-phase7-disposable-e2e"
    } 600
    $file = [string]$created.backup.file
    if ([string]::IsNullOrWhiteSpace($file)) { throw "backup filename missing" }
    [void]$steps.Add([ordered]@{ step="create"; pass=$true; file=$file; reason=[string]$created.backup.source_reason })

    Write-Host "[2/10] Verifying SHA/ZIP..."
    $verified = Post-Json "/api/v4/backup/verify" @{ id=$ServerId; file=$file } 600
    if (-not [bool]$verified.backup.verified) { throw "backup verify returned false" }
    [void]$steps.Add([ordered]@{ step="verify"; pass=$true; sha256=[string]$verified.backup.sha256 })

    Write-Host "[3/10] Protecting disposable backup..."
    $null = Post-Json "/api/v4/backup/action" @{ id=$ServerId; file=$file; action="protect" }
    [void]$steps.Add([ordered]@{ step="protect"; pass=$true })

    Write-Host "[4/10] Confirming protected backup cannot enter Trash..."
    $protectedBlock = Expected-Status "/api/v4/backup/action" @{ id=$ServerId; file=$file; action="trash" } 409
    if (-not [bool]$protectedBlock.pass) {
        # If an implementation bug moved it, recover the disposable backup immediately.
        $trashNow = Get-Json ("/api/v4/backups/trash?id=" + [uri]::EscapeDataString($ServerId))
        if (@($trashNow.backups | Where-Object { [string]$_.file -eq $file }).Count -gt 0) {
            $null = Post-Json "/api/v4/backup/action" @{ id=$ServerId; file=$file; action="restore-trash" }
        }
        throw "protected-trash gate failed: HTTP $($protectedBlock.status)"
    }
    [void]$steps.Add([ordered]@{ step="protected_trash_block"; pass=$true; http_status=$protectedBlock.status })

    Write-Host "[5/10] Unprotect -> Trash..."
    $null = Post-Json "/api/v4/backup/action" @{ id=$ServerId; file=$file; action="unprotect" }
    $null = Post-Json "/api/v4/backup/action" @{ id=$ServerId; file=$file; action="trash" }
    $trash = Get-Json ("/api/v4/backups/trash?id=" + [uri]::EscapeDataString($ServerId))
    if (@($trash.backups | Where-Object { [string]$_.file -eq $file }).Count -ne 1) { throw "backup not found in Trash" }
    $finalLocation = "trash"
    [void]$steps.Add([ordered]@{ step="trash"; pass=$true })

    Write-Host "[6/10] Probing permanent-delete server confirmation gate (NO confirm token)..."
    $deleteBlock = Expected-Status "/api/v4/backup/action" @{ id=$ServerId; file=$file; action="delete-permanent" } 400
    if (-not [bool]$deleteBlock.pass) {
        $trashAfterProbe = Get-Json ("/api/v4/backups/trash?id=" + [uri]::EscapeDataString($ServerId))
        if (@($trashAfterProbe.backups | Where-Object { [string]$_.file -eq $file }).Count -eq 0) {
            $unexpectedPermanentDelete = $true
            $finalLocation = "deleted"
        }
        throw "permanent-delete confirmation gate failed: HTTP $($deleteBlock.status)"
    }
    [void]$steps.Add([ordered]@{ step="permanent_delete_missing_confirm_block"; pass=$true; http_status=$deleteBlock.status })

    Write-Host "[7/10] Restoring from Trash..."
    $null = Post-Json "/api/v4/backup/action" @{ id=$ServerId; file=$file; action="restore-trash" }
    $finalLocation = "active"
    $restoredVerify = Post-Json "/api/v4/backup/verify" @{ id=$ServerId; file=$file } 600
    if (-not [bool]$restoredVerify.backup.verified) { throw "restored backup verification failed" }
    [void]$steps.Add([ordered]@{ step="restore_trash_and_verify"; pass=$true })

    Write-Host "[8/10] Running retention dry-run only..."
    $retention = Post-Json "/api/v4/backup/retention/dry-run" @{ id=$ServerId; keep_latest=2 }
    [void]$steps.Add([ordered]@{
        step="retention_dry_run"
        pass=$true
        candidates=@($retention.candidates).Count
        reclaim_bytes=[int64]$retention.reclaim_bytes
        blocked_reason=[string]$retention.blocked_reason
    })

    Write-Host "[9/10] Running restore PRE-FLIGHT only..."
    $preflight = Post-Json "/api/v4/restore/preflight" @{ id=$ServerId; file=$file }
    [void]$steps.Add([ordered]@{
        step="restore_preflight_only"
        pass=$true
        ready=[bool]$preflight.ready
        server_offline=[bool]$preflight.server_offline
        backup_verified=[bool]$preflight.backup_verified
        checkpoint_ready=[bool]$preflight.checkpoint_ready
        blocked_reason=[string]$preflight.blocked_reason
    })

    Write-Host "[10/10] Returning disposable backup to recoverable Trash..."
    $null = Post-Json "/api/v4/backup/action" @{ id=$ServerId; file=$file; action="trash" }
    $finalLocation = "trash"
    $finalTrash = Get-Json ("/api/v4/backups/trash?id=" + [uri]::EscapeDataString($ServerId))
    if (@($finalTrash.backups | Where-Object { [string]$_.file -eq $file }).Count -ne 1) { throw "final disposable backup not present in Trash" }
    [void]$steps.Add([ordered]@{ step="final_recoverable_trash"; pass=$true })

    $result = "PASS"
} catch {
    $result = "FAIL"
    [void]$steps.Add([ordered]@{ step="failure"; pass=$false; error=[string]$_.Exception.Message })
}

$report = [ordered]@{
    schema = 1
    phase = "11.7-disposable-backup-e2e"
    generated = (Get-Date).ToString("o")
    result = $result
    gsc_version = [string]$status.app_version
    server_id = $ServerId
    disposable_file = $file
    final_location = $finalLocation
    server_lifecycle_action_performed = $false
    minecraft_data_restore_performed = $false
    permanent_delete_requested_with_confirmation = $false
    unexpected_permanent_delete = $unexpectedPermanentDelete
    steps = @($steps)
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$path = Join-Path $OutDir ("Geumyi-Day11-Phase7-DISPOSABLE-" + $stamp + ".json")
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8

Write-Host ""
Write-Host ("RESULT        : " + $result)
Write-Host ("DISPOSABLE    : " + $file)
Write-Host ("FINAL LOCATION: " + $finalLocation)
Write-Host ("SERVER ACTION : false")
Write-Host ("DATA RESTORE  : false")
Write-Host ("PERM DELETE   : " + $unexpectedPermanentDelete)
Write-Host ("REPORT        : " + $path)

if ($result -ne "PASS") { exit 1 }
