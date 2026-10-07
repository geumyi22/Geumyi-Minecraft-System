[CmdletBinding()]
param(
  [string]$BaseUrl="http://127.0.0.1:8790",
  [string]$OutputDir="",
  [string]$Confirm="",
  [string[]]$ServerIds=@("wild","playground","other","lobby"),
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase0"}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stamp=Get-Date -Format "yyyyMMdd-HHmmss"
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase0B-GoldenCheckpoint-"+$stamp+".json")

function GetJ([string]$p){Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$p) -Method GET -TimeoutSec 30}
function PostJ([string]$p,[object]$b,[int]$timeout=900){
  Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$p) -Method POST -ContentType "application/json" -Body ($b|ConvertTo-Json -Depth 10 -Compress) -TimeoutSec $timeout
}
function WriteReport([string]$result,[object[]]$steps,[bool]$mutation,[string[]]$failed){
  $r=[ordered]@{
    schema=1;phase="12.0B";generated_at=(Get-Date).ToString("o");result=$result
    servers=$ServerIds;steps=@($steps);failed=@($failed)
    mutation=[ordered]@{performed=$mutation;server_lifecycle=$false;world_restore=$false;backup_created=$mutation;backup_deleted=$false}
    safety="No server start/stop/restart, restore, Trash or permanent delete is performed."
  }
  $r|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host ("RESULT : "+$result);Write-Host ("REPORT : "+$out)
}
if($Synthetic){
  $steps=@(
    [ordered]@{step="preflight";pass=$true;all_servers_offline=$true},
    [ordered]@{step="create_verify_protect";pass=$true;server_id="synthetic";file="synthetic-full-backup.zip"},
    [ordered]@{step="retention_exemption";pass=$true}
  )
  WriteReport "SYNTHETIC_PASS" $steps $false @()
  exit 0
}
if($Confirm -ne "CREATE_PROTECTED_DAY12_GOLDEN"){
  Write-Host "[BLOCKED] Phase 12.0B creates one protected FULL backup per target server."
  Write-Host "It never stops a server automatically. All target servers must already be OFFLINE."
  Write-Host 'Re-run with -Confirm "CREATE_PROTECTED_DAY12_GOLDEN" only after Phase 12.0A is reviewed.'
  exit 23
}
$status=GetJ "/api/status"
if([string]$status.app_version -ne "4.3.8"){throw "GSC 4.3.8 required"}
$snapshot=GetJ "/api/v1/snapshot"
if([int]$snapshot.active_jobs -ne 0){throw "Active control jobs exist; Golden checkpoint blocked"}
$fleet=GetJ "/api/v4/update/fleet"
$known=@($fleet.servers|ForEach-Object{[string]$_.server_id})
foreach($id in $ServerIds){if($known -notcontains $id){throw "Unknown server id: $id"}}
$online=@($status.servers|Where-Object{$ServerIds -contains [string]$_.id -and [bool]$_.online})
if($online.Count -gt 0){throw ("All target servers must be OFFLINE. Online: "+(($online|ForEach-Object{$_.id}) -join ","))}
$unsafe=@($fleet.servers|Where-Object{$ServerIds -contains [string]$_.server_id -and ([bool]$_.status.block_start -or [string]$_.status.phase -in @("blocked","rollback_failed","rolling_back","pending_health","downloading"))})
if($unsafe.Count -gt 0){throw "Unsafe update transaction state exists; Golden checkpoint blocked"}

$steps=New-Object System.Collections.ArrayList
$failed=New-Object System.Collections.ArrayList
$reason="day12-golden-baseline"
foreach($id in $ServerIds){
  try{
    Write-Host ("["+ $id +"] Creating FULL Golden backup...")
    $c=PostJ "/api/v4/backup" @{id=$id;scope="full";reason=$reason} 3600
    $file=[string]$c.backup.file
    if([string]::IsNullOrWhiteSpace($file)){throw "backup filename missing"}
    $v=PostJ "/api/v4/backup/verify" @{id=$id;file=$file} 1800
    if(-not [bool]$v.backup.verified){throw "SHA/ZIP verification failed"}
    $null=PostJ "/api/v4/backup/action" @{id=$id;file=$file;action="protect"} 120
    $a=GetJ ("/api/v4/backups?id="+[uri]::EscapeDataString($id))
    $row=@($a.backups|Where-Object{[string]$_.file -eq $file}|Select-Object -First 1)
    if($row.Count -ne 1 -or -not [bool]$row[0].protected){throw "protected-state verification failed"}
    $dry=PostJ "/api/v4/backup/retention/dry-run" @{id=$id;keep_latest=2} 120
    $candidate=@($dry.candidates|Where-Object{[string]$_.file -eq $file})
    if($candidate.Count -ne 0){throw "Golden backup incorrectly appears in retention candidates"}
    [void]$steps.Add([ordered]@{server_id=$id;step="create_verify_protect";pass=$true;file=$file;sha256=[string]$v.backup.sha256;retention_exempt=$true})
  }catch{
    [void]$failed.Add($id)
    [void]$steps.Add([ordered]@{server_id=$id;step="create_verify_protect";pass=$false;error=[string]$_.Exception.Message})
    break
  }
}
$result=if($failed.Count -eq 0){"PASS"}else{"PARTIAL_REVIEW_REQUIRED"}
WriteReport $result @($steps) ($steps.Count -gt 0) @($failed)
if($failed.Count -gt 0){exit 2}
exit 0
