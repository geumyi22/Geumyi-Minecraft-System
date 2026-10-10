[CmdletBinding()]
param(
  [string]$OutputDir="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# ONLY a preflight for later one-server, disposable offline-start E2E.
# No network adapter, firewall, DNS, API POST, service, backups, worlds,
# cached artifacts, plugins, or GSC policy may be changed by this script.
$phase="12.7-offline-start-readiness"
$target="playground"
$base="http://127.0.0.1:8790"
$now=(Get-Date).ToString("o")
if(-not $OutputDir){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) (
    "Geumyi-Day12-Offline-Readiness-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
}
function Value([object]$Object,[string]$Field,[object]$Fallback=$null){
  if($null -eq $Object){return $Fallback}
  $fieldProp=$Object.PSObject.Properties[$Field]
  if($null -eq $fieldProp -or $null -eq $fieldProp.Value){return $Fallback}
  return $fieldProp.Value
}
function Is-ProtectedFullBackup([object]$b) {
  return (([bool](Value $b "protected" $false)) -and
    ([bool](Value $b "verified" $false)) -and
    ([string](Value $b "scope" "") -eq "full") -and
    (-not [bool](Value $b "trashed" $true)))
}
function Evaluate([object]$Snapshot,[object]$Fleet,[object]$Players,[object]$Backups,[bool]$HostRunning){
  $issues=New-Object System.Collections.ArrayList
  if(-not $HostRunning){[void]$issues.Add("HOST_SERVICE_NOT_RUNNING")}
  if($null -eq $Snapshot -or
     [string](Value $Snapshot "gsc_version" "") -ne "4.3.8"){
    [void]$issues.Add("HOST_VERSION_NOT_CONFIRMED_4_3_8")
  }
  $jobs=Value $Snapshot "active_jobs" $null
  if($null -eq $jobs -or [int]$jobs -ne 0){[void]$issues.Add("ACTIVE_JOBS_PRESENT_OR_UNKNOWN")}
  $profiles=if($null -ne $Fleet){@((Value $Fleet "servers" @()))}else{@()}
  $targetProfiles=@($profiles|Where-Object{[string](Value $_ "server_id" "") -eq $target})
  if($targetProfiles.Count -ne 1){
    [void]$issues.Add("TARGET_PROFILE_MISSING_OR_AMBIGUOUS")
    $profile=$null
  }else{$profile=$targetProfiles[0]}
  $online=[bool](Value $profile "online" $false)
  if(-not $online){[void]$issues.Add("TARGET_NOT_ONLINE")}
  $update=Value $profile "status" $null
  if($null -eq $update){[void]$issues.Add("UPDATE_STATUS_MISSING")}
  if([bool](Value $update "block_start" $false)){
    [void]$issues.Add("EXPLICIT_BLOCK_START")
  }
  $updatePhase=[string](Value $update "phase" "UNKNOWN")
  if($updatePhase -notin @("current","idle","disabled","held","manual","completed","none","up_to_date")){
    [void]$issues.Add("UPDATE_TRANSACTION_OR_UNKNOWN_PHASE")
  }
  $policy=[string](Value $update "policy" "UNKNOWN")
  # A managed policy might fetch and apply a DIFFERENT release on startup,
  # even if it is currently "current". Do not treat it as no-risk.
  if($policy -notin @("hold","manual")){
    [void]$issues.Add("AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED")
  }
  $playersOnline=[bool](Value $Players "online" $false)
  $playerCount=[int](Value $Players "count" -1)
  if(-not $playersOnline -or $playerCount -ne 0){
    [void]$issues.Add("PLAYERS_PRESENT_OR_UNVERIFIED")
  }
  $backupsArray=if($null -ne $Backups){@((Value $Backups "backups" @()))}else{@()}
  $safeBackups=@($backupsArray|Where-Object{Is-ProtectedFullBackup $_})
  if($safeBackups.Count -lt 1){[void]$issues.Add("TARGET_PROTECTED_VERIFIED_FULL_BACKUP_NOT_CONFIRMED")}
  $noIssues=($issues.Count -eq 0)
  return [ordered]@{
    result=$(if($noIssues){"PRECHECK_GUARDS_MET_NO_TEST_PERFORMED"}else{"BLOCKED_NEEDS_SAFETY_REVIEW"})
    reasons=@($issues)
    host_service_running=$HostRunning
    expected_host_version_confirmed=([string](Value $Snapshot "gsc_version" "") -eq "4.3.8")
    active_jobs_zero=($null -ne $jobs -and [int]$jobs -eq 0)
    target_profile_unique=($targetProfiles.Count -eq 1)
    target_online=$online
    target_player_count_confirmed_zero=($playersOnline -and $playerCount -eq 0)
    protected_verified_full_backup_present=($safeBackups.Count -ge 1)
    update_policy_nonmanaged=($policy -in @("hold","manual"))
    update_phase_safe=($updatePhase -in @("current","idle","disabled","held","manual","completed","none","up_to_date"))
    explicit_block_start=([bool](Value $update "block_start" $false))
    # NEVER prove offline boot from GET API results alone.
    actually_disconnected_update_source=$false
    actual_offline_restart_performed=$false
    real_game_client_test_performed=$false
    stable_release_allowed=$false
  }
}
function Save-Report([object]$Review,[bool]$SyntheticFlag){
  $report=[ordered]@{
    schema=1;phase=$phase;generated_at=$now
    synthetic=$SyntheticFlag
    read_only=$true;production_config_mutated=$false
    firewall_acl_or_adapter_modified=$false;backup_world_cache_modified=$false
    service_restart_performed=$false;network_outage_initiated=$false
    target_server=$target
    result=$Review.result
    checks=$Review
    offline_start_e2e_proven=$false
    canonical_backend_ports_private="UNCHANGED_FAIL"
    stable_release_allowed=$false
    remarks=@(
      "A readiness result is not evidence of real offline startup or Geyser/Paper behavior.",
      "GSC snapshot, update fleet, target online player count and full backup are queried using local authenticated policy GET only.",
      "No API credentials or response bodies, hostnames, IP addresses, backup filenames, player identities or PIDs are exported.",
      "A managed updater may change plugins on a future startup even when current update status is current.",
      "Never disable network adapters or alter firewall/ACL to force an outage as part of this preflight.",
      "Later disruption requires a disposable staging design or explicit reviewed network-scope and rollback plan."
    )
  }
  New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
  $out=Join-Path $OutputDir "Day12-Offline-Readiness-READ-ONLY.json"
  if(Test-Path -LiteralPath $out -PathType Leaf){throw "REFUSE_OVERWRITE_EXISTING_REPORT"}
  $report|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host ("Day12.7 OFFLINE START precheck: "+$Review.result)
  if(@($Review.reasons).Count){Write-Host ("Safety holds: "+(@($Review.reasons) -join ", "))}
  Write-Host ("Operator-safe JSON: "+$out)
}
if($Synthetic){
  $snap=[pscustomobject]@{gsc_version="4.3.8";active_jobs=0}
  $fleet=[pscustomobject]@{servers=@([pscustomobject]@{
    server_id=$target;online=$true;status=[pscustomobject]@{
      phase="manual";policy="manual";block_start=$false}})}
  $players=[pscustomobject]@{online=$true;count=0}
  $backup=[pscustomobject]@{backups=@([pscustomobject]@{
    protected=$true;verified=$true;scope="full";trashed=$false})}
  $pass=Evaluate $snap $fleet $players $backup $true
  if($pass.result -ne "PRECHECK_GUARDS_MET_NO_TEST_PERFORMED" -or
    $pass.offline_start_e2e_proven -or $pass.actual_offline_restart_performed){
    throw "SYNTHETIC_SAFE_PREFLIGHT_REGRESSION"
  }
  $unsafeFleet=[pscustomobject]@{servers=@([pscustomobject]@{
    server_id=$target;online=$true;status=[pscustomobject]@{phase="current";policy="managed"}})}
  if((Evaluate $snap $unsafeFleet $players $backup $true).result -ne "BLOCKED_NEEDS_SAFETY_REVIEW"){
    throw "SYNTHETIC_MANAGED_UPDATER_FALSE_READY"
  }
  if((Evaluate $snap $fleet ([pscustomobject]@{online=$true;count=1}) $backup $true).result -ne "BLOCKED_NEEDS_SAFETY_REVIEW"){
    throw "SYNTHETIC_PLAYER_FALSE_READY"
  }
  if((Evaluate $snap $fleet $players ([pscustomobject]@{backups=@()}) $true).result -ne "BLOCKED_NEEDS_SAFETY_REVIEW"){
    throw "SYNTHETIC_BACKUP_FALSE_READY"
  }
  if((Evaluate ([pscustomobject]@{gsc_version="4.3.8";active_jobs=1}) $fleet $players $backup $true).result -ne "BLOCKED_NEEDS_SAFETY_REVIEW"){
    throw "SYNTHETIC_ACTIVE_JOB_FALSE_READY"
  }
  if((Evaluate $snap $fleet $players $backup $false).result -ne "BLOCKED_NEEDS_SAFETY_REVIEW"){
    throw "SYNTHETIC_HOST_SERVICE_FALSE_READY"
  }
  $report=Evaluate $snap $fleet $players $backup $true
  Save-Report $report $true
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "SERVER_PC_WINDOWS_ONLY"}
$svc=Get-Service "Geumyi Server Center Host" -ErrorAction SilentlyContinue
if($null -eq $svc){throw "REFUSE_NON_HOST_PC"}
$serviceRunning=([string]$svc.Status -eq "Running")
function Get-SafeAPI([string]$uriPath){
  try{
    return Invoke-RestMethod -Uri ($base+$uriPath) -Method GET -TimeoutSec 8 -ErrorAction Stop
  }catch{return $null}
}
# These are all GET routes; no game-state-altering command is sent.
$snapshot=Get-SafeAPI "/api/v1/snapshot"
$fleet=Get-SafeAPI "/api/v4/update/fleet"
$players=Get-SafeAPI "/api/v1/servers/playground/players"
$backups=Get-SafeAPI "/api/v4/backups?id=playground"
$review=Evaluate $snapshot $fleet $players $backups $serviceRunning
Save-Report $review $false
# Exit zero indicates a valid classified report; not that it is safe to boot.
exit 0
