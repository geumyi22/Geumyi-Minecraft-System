[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic,[switch]$PreflightOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Explicitly scoped routine restart permission from operator, 2026-10-10.
# No force-stop, no config edits, no backup creation/restore/deletion.
# Uses GSC's graceful per-server job queue, exactly once.
$serverId="playground"
$expectedJava=25571
$expectedRcon=25576
$baseUrl="http://127.0.0.1:8790"
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Scoped-Restart"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-Scoped-Restart-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report=[ordered]@{
  schema=1;phase="12.10-scoped-maintenance-restart";server_id=$serverId
  generated_at=(Get-Date).ToString("o");synthetic=[bool]$Synthetic
  planned_action=if($PreflightOnly){"PREFLIGHT_ONLY"}else{"GSC_GRACEFUL_RESTART"}
  mutation_performed=$false;restart_accepted=$false
  golden_verified=$false;players_confirmed_zero=$false;no_active_jobs=$false
  old_state="UNAVAILABLE";job_status="NOT_SUBMITTED";new_state="UNAVAILABLE"
  observer=[ordered]@{native_status="NOT_RUN";java="UNKNOWN";rcon="UNKNOWN"}
  result="PRECHECK_NOT_RUN"
  notes=@(
    "Target ONLY playground: Java 25571 and RCON 25576. Other servers are untouched.",
    "Invokes GSC queue graceful restart ONCE only after verified protected FULL backup, zero players, zero global jobs and safe fleet status.",
    "GSC-managed prestart auto-updates may occur as part of the server's existing restart configuration; this script neither selects nor installs updates itself.",
    "No forced process kill, Windows restart, backup creation/deletion/restore, firewall or ACL writes. No automatic second restart if errors occur.",
    "The single post-restart native listener snapshot is contextual; never promotes canonical backend_ports_private or Day12.10.",
    "If preflight is inconclusive, fail closed without any restart."
  )
}
function SaveReport([string]$Result){
  $report.result=$Result
  $report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host ("Day12 12.10 scoped restart: "+$Result)
  Write-Host ("Report: "+$out)
}
function Prop([object]$Obj,[string]$Key,[object]$Fallback=$null){
  if($null -eq $Obj){return $Fallback}
  $p=$Obj.PSObject.Properties[$Key]
  if($null -eq $p -or $null -eq $p.Value){return $Fallback}
  return $p.Value
}
function PreflightCheck([object]$State,[object]$Fleet,[object]$Players,[object]$Backups){
  $globalJobs=Prop $State "active_jobs" -1
  if([int]$globalJobs -ne 0){return "ACTIVE_JOBS_OR_MISSING_STATUS"}
  if([string](Prop $State "gsc_version" "") -ne "4.3.8"){return "UNEXPECTED_GSC_VERSION"}
  $our=@($Fleet.servers|Where-Object{[string](Prop $_ "server_id" "") -eq $serverId})
  if($our.Count -ne 1){return "FLEET_PROFILE_NOT_UNIQUE"}
  if(-not [bool](Prop $our[0] "online" $false)){return "TARGET_NOT_ONLINE"}
  $update=Prop $our[0] "status" $null
  if([bool](Prop $update "block_start" $true)){return "UPDATE_BLOCK_START"}
  $phase=[string](Prop $update "phase" "UNKNOWN")
  if($phase -notin @("idle","ready","up_to_date","current","online","completed","none","")){return "UPDATE_STATE_UNKNOWN_OR_ACTIVE"}
  if(-not [bool](Prop $Players "online" $false)){return "PLAYER_COUNT_NOT_PROVEN_ONLINE"}
  if([int](Prop $Players "count" -1) -ne 0){return "PLAYERS_PRESENT_OR_UNKNOWN"}
  $safe=@($Backups.backups|Where-Object{
    [bool](Prop $_ "protected" $false) -and [bool](Prop $_ "verified" $false) -and
    [string](Prop $_ "scope" "") -eq "full" -and -not [bool](Prop $_ "trashed" $false)
  })
  if($safe.Count -lt 1){return "NO_PROTECTED_VERIFIED_FULL_BACKUP"}
  return "PASS"
}
if($Synthetic){
  $status=[pscustomobject]@{gsc_version="4.3.8";active_jobs=0}
  $fleet=[pscustomobject]@{servers=@([pscustomobject]@{
    server_id="playground";online=$true;status=[pscustomobject]@{block_start=$false;phase="idle"}})}
  $players=[pscustomobject]@{online=$true;count=0}
  $backups=[pscustomobject]@{backups=@([pscustomobject]@{
    protected=$true;verified=$true;scope="full";trashed=$false})}
  if((PreflightCheck $status $fleet $players $backups) -ne "PASS"){throw "SAFE_FIXTURE_FAILED"}
  if((PreflightCheck $status $fleet ([pscustomobject]@{online=$true;count=1}) $backups) -ne "PLAYERS_PRESENT_OR_UNKNOWN"){throw "PLAYER_SAFETY_REGRESSION"}
  if((PreflightCheck $status $fleet $players ([pscustomobject]@{backups=@()}) ) -ne "NO_PROTECTED_VERIFIED_FULL_BACKUP"){throw "GOLDEN_SAFETY_REGRESSION"}
  if((PreflightCheck ([pscustomobject]@{gsc_version="4.3.8";active_jobs=1}) $fleet $players $backups) -ne "ACTIVE_JOBS_OR_MISSING_STATUS"){throw "JOB_SAFETY_REGRESSION"}
  $report.notes=@("Synthetic preflight fixtures only; no HTTP request or server mutation.")
  SaveReport "SYNTHETIC_PASS"
  exit 0
}
function GetJ([string]$Path){Invoke-RestMethod -Uri ($baseUrl+$Path) -Method GET -TimeoutSec 20 -ErrorAction Stop}
function PostJ([string]$Path,[object]$Body){
  Invoke-RestMethod -Uri ($baseUrl+$Path) -Method POST -ContentType "application/json" -Body ($Body|ConvertTo-Json -Depth 5 -Compress) -TimeoutSec 20 -ErrorAction Stop
}
try{
  $snap=GetJ "/api/v1/snapshot"
  $fleet=GetJ "/api/v4/update/fleet"
  $players=GetJ "/api/v1/servers/playground/players"
  $backups=GetJ "/api/v4/backups?id=playground"
  $check=PreflightCheck $snap $fleet $players $backups
  $report.no_active_jobs=([int](Prop $snap "active_jobs" -1) -eq 0)
  $report.players_confirmed_zero=([bool](Prop $players "online" $false) -and [int](Prop $players "count" -1) -eq 0)
  $report.golden_verified=(@($backups.backups|Where-Object{
    [bool](Prop $_ "protected" $false) -and [bool](Prop $_ "verified" $false) -and
    [string](Prop $_ "scope" "") -eq "full" -and -not [bool](Prop $_ "trashed" $false)
  }).Count -gt 0)
  $report.old_state=if(@($fleet.servers|Where-Object{[string]$_.server_id -eq $serverId -and [bool]$_.online}).Count -eq 1){"ONLINE"}else{"NOT_ONLINE"}
  if($check -ne "PASS"){
    SaveReport ("BLOCKED_"+$check)
    exit 2
  }
  if($PreflightOnly){SaveReport "PREFLIGHT_PASS_NO_RESTART";exit 0}
  # Reconfirm immediately before sending the single mutation.
  $playersNow=GetJ "/api/v1/servers/playground/players"
  $snapNow=GetJ "/api/v1/snapshot"
  if(-not [bool](Prop $playersNow "online" $false) -or
     [int](Prop $playersNow "count" -1) -ne 0 -or
     [int](Prop $snapNow "active_jobs" -1) -ne 0){
    SaveReport "BLOCKED_CHANGED_DURING_PREFLIGHT"
    exit 2
  }
  # Approved graceful lifecycle job, exactly one request. A GSC job may
  # include a 15-second countdown before the server's ordinary save/stop/start.
  $resp=PostJ "/api/v1/servers/playground/actions" @{action="restart";countdown_seconds=15}
  if(-not [bool](Prop $resp "ok" $false)){
    SaveReport "REQUEST_NOT_ACCEPTED"
    exit 2
  }
  $id=[string](Prop (Prop $resp "job") "id" "")
  if(-not $id -or $id -notmatch '^job-[A-Za-z0-9-]+$'){
    $report.mutation_performed=$true
    SaveReport "ACCEPTED_BUT_JOB_ID_INVALID_REVIEW"
    exit 3
  }
  $report.mutation_performed=$true
  $report.restart_accepted=$true
  $report.job_status="ACCEPTED"
  $deadline=(Get-Date).AddMinutes(7)
  $done=$false
  while((Get-Date) -lt $deadline){
    Start-Sleep -Seconds 4
    $job=GetJ ("/api/v1/jobs/"+$id)
    $jobState=[string](Prop $job "status" "")
    $report.job_status=$jobState
    if($jobState -in @("failed","cancelled","interrupted")){
      SaveReport "RESTART_JOB_FAILED_OR_CANCELLED"
      exit 3
    }
    if($jobState -eq "completed"){$done=$true;break}
  }
  if(-not $done){SaveReport "RESTART_JOB_TIMEOUT_REVIEW";exit 3}
  $online=$false
  $waitUntil=(Get-Date).AddMinutes(2)
  while((Get-Date) -lt $waitUntil){
    $fleetNow=GetJ "/api/v4/update/fleet"
    if(@($fleetNow.servers|Where-Object{
      [string](Prop $_ "server_id" "") -eq $serverId -and [bool](Prop $_ "online" $false)
    }).Count -eq 1){$online=$true;break}
    Start-Sleep -Seconds 5
  }
  $report.new_state=if($online){"ONLINE"}else{"NOT_CONFIRMED"}
  # One short target-only native listener snapshot, no retries and no
  # security gate promotion. If its input is unavailable, continue reporting
  # the restart result without treating missing bind rows as safe.
  if($online){
    try{
      . (Join-Path $PSScriptRoot "Day12_Native_TCP_Provider_READ_ONLY.ps1")
      $native=Get-Day12NativeTcpInventory -WantedPorts @($expectedJava,$expectedRcon)
      $report.observer.native_status=[string]$native.status
      foreach($port in @($expectedJava,$expectedRcon)){
        $rows=@($native.rows|Where-Object{[int]$_.port -eq $port})
        $kind=if($rows.Count -eq 0){"NOT_OBSERVED"}
          elseif(@($rows|Where-Object{[string]$_.address -notin @("127.0.0.1","::1","::ffff:127.0.0.1")}).Count -gt 0){"NON_LOOPBACK_OR_UNKNOWN_REVIEW"}
          else{"LOOPBACK_OBSERVED"}
        if($port -eq $expectedJava){$report.observer.java=$kind}else{$report.observer.rcon=$kind}
      }
    }catch{$report.observer.native_status="QUERY_ERROR"}
  }
  if($online){SaveReport "GSC_RESTART_COMPLETED_ONLINE_BIND_REVIEW";exit 0}
  SaveReport "RESTART_JOB_COMPLETED_BUT_SERVER_OFFLINE_REVIEW"
  exit 3
}catch{
  # Do not include HTTP error response bodies, auth headers or file paths.
  SaveReport "HOST_QUERY_OR_RESTART_ERROR_REVIEW"
  exit 3
}
