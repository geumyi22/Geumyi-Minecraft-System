[CmdletBinding()]
param([string]$BaseUrl="http://127.0.0.1:8790",[string]$PolicyPath="",[string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase4"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase4-LifecycleDryRun-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){[ordered]@{schema=1;phase="12.4";synthetic=$true;result="SYNTHETIC_PASS";mutation_performed=$false}|ConvertTo-Json|Set-Content $out -Encoding UTF8;exit 0}
if([string]::IsNullOrWhiteSpace($PolicyPath)){throw "PolicyPath required"}
$p=Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8|ConvertFrom-Json
function G([string]$path){Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$path) -Method GET -TimeoutSec 20}
function P([string]$path,[object]$body){Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$path) -Method POST -ContentType "application/json" -Body ($body|ConvertTo-Json -Compress) -TimeoutSec 60}
$f=G "/api/v4/update/fleet";$servers=@($f.servers|ForEach-Object{[string]$_.server_id})
$backup=@()
foreach($id in $servers){
  $active=G ("/api/v4/backups?id="+[uri]::EscapeDataString($id));$dry=P "/api/v4/backup/retention/dry-run" @{id=$id;keep_latest=[int]$p.backup.recent}
  $backup += [ordered]@{server_id=$id;active_count=@($active.backups).Count;protected=@($active.backups|Where-Object{[bool]$_.protected}).Count;existing_api_candidates=@($dry.candidates);reclaim_bytes=[int64]$dry.reclaim_bytes;blocked_reason=[string]$dry.blocked_reason}
}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"};$root=Join-Path $pd "GeumyiServerCenter"
$logRoots=@((Join-Path $root "logs"));$cfgPath=Join-Path $root "server.json"
if(Test-Path $cfgPath){$cfg=Get-Content $cfgPath -Raw -Encoding UTF8|ConvertFrom-Json;foreach($s in @($cfg.servers)){if([string]$s.path){$logRoots+=@(Join-Path ([string]$s.path) "logs";Join-Path ([string]$s.path) "crash-reports")}}}
$now=Get-Date;$logRows=@()
foreach($lr in $logRoots|Select-Object -Unique){
  if(-not(Test-Path $lr)){continue}
  foreach($x in Get-ChildItem $lr -File -Recurse -ErrorAction SilentlyContinue){
    $isCrash=$lr -like "*crash-reports*";$days=if($isCrash){[int]$p.logs.crash_retention_days}else{[int]$p.logs.normal_retention_days}
    $age=($now-$x.LastWriteTime).TotalDays;$preserve=($now-$x.LastWriteTime).TotalHours -lt [int]$p.logs.preserve_recent_incident_hours
    if($age -gt $days -and -not$preserve){$logRows += [ordered]@{name=$x.Name;size=[int64]$x.Length;age_days=[math]::Round($age,1);kind=$(if($isCrash){"crash"}else{"log"})}}
  }
}
$free=0;try{$free=[int64](Get-Item $root).PSDrive.Free}catch{}
$r=[ordered]@{schema=1;phase="12.4";mode="DRY_RUN";generated_at=(Get-Date).ToString("o");policy=$p;backup=$backup;log_delete_candidates=$logRows;log_reclaim_bytes=[int64](($logRows|Measure-Object size -Sum).Sum);disk_free_gib=[math]::Round($free/1GB,2);disk_status=$(if($free/1GB -lt [int]$p.disk.minimum_free_gib){"FAIL"}elseif($free/1GB -lt [int]$p.disk.warning_free_gib){"WARN"}else{"PASS"});mutation_performed=$false;note="No file was moved or deleted. Advanced daily/weekly selection is policy-defined but not applied until live review."}
$r|ConvertTo-Json -Depth 14|Set-Content $out -Encoding UTF8
Write-Host "DAY 12 PHASE 4 DRY-RUN COMPLETE";Write-Host ("Report: "+$out)
