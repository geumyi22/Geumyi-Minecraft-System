[CmdletBinding()]
param([switch]$Synthetic,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Day12.7 targeted follow-up ONLY after known dual holds:
# AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED
# TARGET_PROTECTED_VERIFIED_FULL_BACKUP_NOT_CONFIRMED.
# Two GET calls. Never writes GSC config, backup, world, network/firewall,
# launch/stop/update policy, credentials or any response bodies to disk.
$target="playground"
$base="http://127.0.0.1:8790"

function Prop([object]$Object,[string]$Name,[object]$Default=$null){
  if($null -eq $Object){return $Default}
  $property=$Object.PSObject.Properties[$Name]
  if($null -eq $property -or $null -eq $property.Value){return $Default}
  return $property.Value
}
function Get-LocalReadOnly([string]$Path){
  try{
    return [pscustomobject]@{
      status="OK"
      data=(Invoke-RestMethod -Method GET -Uri ($base+$Path) -TimeoutSec 8 -ErrorAction Stop)
    }
  }catch{
    $errorType="UNAVAILABLE"
    try {
      $code=[int]$_.Exception.Response.StatusCode.value__
      if($code -in @(401,403)){$errorType="ACCESS_DENIED"}
      elseif($code -eq 404){$errorType="API_ROUTE_NOT_FOUND"}
      elseif($code -ge 400){$errorType="HTTP_ERROR"}
    }catch{}
    return [pscustomobject]@{status=$errorType;data=$null}
  }
}
function Analyze([object]$FleetReply,[object]$BackupsReply){
  $reasons=New-Object System.Collections.ArrayList
  $fleetOK=([string](Prop $FleetReply "status" "") -eq "OK")
  $backupsOK=([string](Prop $BackupsReply "status" "") -eq "OK")
  if(-not $fleetOK){[void]$reasons.Add("FLEET_STATUS_UNAVAILABLE")}
  if(-not $backupsOK){[void]$reasons.Add("BACKUP_LIST_UNAVAILABLE")}
  $policy="UNAVAILABLE"
  $phase="UNAVAILABLE"
  $profileCount=0
  $roles=@()
  if($fleetOK){
    $roles=@((Prop (Prop $FleetReply "data") "servers" @())|
      Where-Object {[string](Prop $_ "server_id" "") -eq $target})
    $profileCount=$roles.Count
    if($profileCount -ne 1){[void]$reasons.Add("FLEET_PLAYGROUND_PROFILE_UNCONFIRMED")}
    else{
      $details=Prop $roles[0] "status"
      $policy=[string](Prop $details "policy" "UNAVAILABLE")
      $phase=[string](Prop $details "phase" "UNAVAILABLE")
    }
  }
  $recognizedPolicy=$policy -in @("hold","manual","managed","disabled")
  $policyClass=if($policy -in @("hold","manual")){"SAFE_NONMANAGED"}
    elseif($policy -eq "managed"){"MANAGED_AUTO"}
    elseif($policy -eq "disabled"){"DISABLED_REVIEW_REQUIRED"}
    else{"UNKNOWN_REVIEW_REQUIRED"}
  if($policyClass -ne "SAFE_NONMANAGED"){[void]$reasons.Add("UPDATER_POLICY_NOT_PROVEN_HELD")}
  $backupTotal=0;$full=0;$protectedFull=0;$verifiedProtectedFull=0;$trashedFull=0
  $anyProtected=0;$anyVerified=0
  if($backupsOK){
    $items=@(Prop (Prop $BackupsReply "data") "backups" @())
    $backupTotal=$items.Count
    foreach($item in $items){
      $scope=[string](Prop $item "scope" "")
      $protected=[bool](Prop $item "protected" $false)
      $verified=[bool](Prop $item "verified" $false)
      $trashed=[bool](Prop $item "trashed" $false)
      if($protected){$anyProtected++}
      if($verified){$anyVerified++}
      if($scope -ne "full"){continue}
      $full++
      if($trashed){$trashedFull++}
      if($protected -and -not $trashed){
        $protectedFull++
        if($verified){$verifiedProtectedFull++}
      }
    }
    if($verifiedProtectedFull -eq 0){[void]$reasons.Add("PROTECTED_VERIFIED_FULL_NOT_PRESENT_IN_API")}
  }else{[void]$reasons.Add("PROTECTED_VERIFIED_FULL_NOT_CONFIRMED")}
  $reasonCodes=@($reasons|Select-Object -Unique)
  return [ordered]@{
    result=$(if($reasonCodes.Count -eq 0){"TWO_PRIOR_HOLDS_RESOLVED_PREFLIGHT_ONLY"}else{"TWO_PRIOR_HOLDS_STILL_BLOCKED"})
    reason_codes=$reasonCodes
    fleet_api_status=[string](Prop $FleetReply "status" "UNAVAILABLE")
    backups_api_status=[string](Prop $BackupsReply "status" "UNAVAILABLE")
    playground_profile_count=$profileCount
    playground_update_policy_class=$policyClass
    playground_update_phase_class=$(if($phase -in @("current","idle","disabled","held","manual","completed","none","up_to_date")){"SAFE_REVIEWABLE"}else{"UNKNOWN_OR_TRANSITIONAL"})
    backup_inventory_entry_count=$backupTotal
    backup_full_count=$full
    backup_protected_full_count=$protectedFull
    backup_verified_protected_full_count=$verifiedProtectedFull
    backup_trashed_full_count=$trashedFull
    backup_any_scope_protected_count=$anyProtected
    backup_any_scope_verified_count=$anyVerified
    historic_golden_4_of_4_proves_current_playground_full_backup=$false
    actual_offline_boot_performed=$false
    canary_apply_rollback_performed=$false
    strict_stable_release_allowed=$false
  }
}
function SafeOutput([object]$Decision,[bool]$IsSynthetic){
  $report=[ordered]@{
    schema=1;phase="12.7-offline-start-dual-hold-rootcause"
    captured_at=(Get-Date).ToUniversalTime().ToString("o")
    target_server="playground";synthetic=$IsSynthetic
    read_only=$true;result=$Decision.result;checks=$Decision
    api_credentials_or_raw_responses_exported=$false
    backup_names_paths_sha256_exported=$false
    service_network_firewall_acl_world_backup_config_changed=$false
    read_only_get_calls=@("/api/v4/update/fleet","/api/v4/backups?id=playground")
    notes=@(
      "A false backup protected/verified/full count does not prove older Golden archives were deleted.",
      "Backup endpoint may return only entries listed for this server by GSC, not every disk-held recovery artifact.",
      "No update policy has been switched; no backup, restart, outage, Canary apply/rollback or offline startup has occurred.",
      "Do not rerun original broad readiness unless a material prerequisite has changed.",
      "Even BOTH holds resolved means only targeted PRECHECK, not any Stable PASS."
    )
  }
  $json=$report|ConvertTo-Json -Depth 9
  if($IsSynthetic){Write-Output $json;return}
  if(-not $OutputDir){
    $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) ("Geumyi-Day12-Two-Hold-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
  }
  if(Test-Path -LiteralPath $OutputDir){throw "REFUSE_EXISTING_REPORT_OUTPUT"}
  [void](New-Item -Path $OutputDir -ItemType Directory -ErrorAction Stop)
  $out=Join-Path $OutputDir "DAY12-OFFLINE-TWO-HOLD-SHARE-ONLY-THIS.json"
  [IO.File]::WriteAllText($out,$json,(New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("12.7 targeted hold result: "+[string]$Decision.result)
  Write-Host ("Send ONLY: "+$out)
}
if($Synthetic){
  $fleet=[pscustomobject]@{status="OK";data=[pscustomobject]@{servers=@(
    [pscustomobject]@{server_id="playground";status=[pscustomobject]@{policy="manual";phase="idle"}}
  )}}
  $backups=[pscustomobject]@{status="OK";data=[pscustomobject]@{backups=@(
    [pscustomobject]@{scope="full";verified=$true;protected=$true;trashed=$false}
  )}}
  $positive=Analyze $fleet $backups
  $managed=[pscustomobject]@{status="OK";data=[pscustomobject]@{servers=@(
    [pscustomobject]@{server_id="playground";status=[pscustomobject]@{policy="managed";phase="current"}}
  )}}
  $unprotected=[pscustomobject]@{status="OK";data=[pscustomobject]@{backups=@(
    [pscustomobject]@{scope="full";verified=$true;protected=$false}
  )}}
  $errorReply=[pscustomobject]@{status="ACCESS_DENIED";data=$null}
  $pManaged=Analyze $managed $backups
  $pBackup=Analyze $fleet $unprotected
  $pDenied=Analyze $fleet $errorReply
  $pEmpty=Analyze $fleet ([pscustomobject]@{status="OK";data=[pscustomobject]@{backups=@()}})
  if($positive.result -ne "TWO_PRIOR_HOLDS_RESOLVED_PREFLIGHT_ONLY" -or
     $positive.backup_verified_protected_full_count -ne 1 -or
     $positive.actual_offline_boot_performed -or $positive.strict_stable_release_allowed -or
     $pManaged.result -ne "TWO_PRIOR_HOLDS_STILL_BLOCKED" -or
     $pBackup.result -ne "TWO_PRIOR_HOLDS_STILL_BLOCKED" -or
     $pDenied.backups_api_status -ne "ACCESS_DENIED" -or
     $pEmpty.backup_inventory_entry_count -ne 0 -or
     $pEmpty.result -ne "TWO_PRIOR_HOLDS_STILL_BLOCKED"){
    throw "PHASE7_TWO_HOLD_SAFE_SYNTHETIC_FAIL"
  }
  Write-Host "PHASE7_TWO_HOLD_SAFE_SYNTHETIC_PASS"
  SafeOutput $positive $true
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "SERVER_PC_WINDOWS_ONLY"}
$service=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
if($null -eq $service -or $service.Status -ne "Running"){throw "REFUSE_NON_RUNNING_GSC_HOST"}
$decision=Analyze (Get-LocalReadOnly "/api/v4/update/fleet") (Get-LocalReadOnly "/api/v4/backups?id=playground")
SafeOutput $decision $false
exit 0
