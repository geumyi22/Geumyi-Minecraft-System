[CmdletBinding()]
param(
  [string]$BaseUrl="http://127.0.0.1:8790",
  [Parameter(Mandatory=$true)][string]$PolicyPath,
  [string]$OutputDir="",
  [string]$Confirm="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase4"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$stamp=Get-Date -Format "yyyyMMdd-HHmmss"
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase4-LifecycleApply-"+$stamp+".json")

function Get-Json([string]$Path){
  Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$Path) -Method GET -TimeoutSec 30
}
function Post-Json([string]$Path,[object]$Body,[int]$Timeout=120){
  Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$Path) -Method POST -ContentType "application/json" -Body ($Body|ConvertTo-Json -Depth 10 -Compress) -TimeoutSec $Timeout
}
function Get-LogCandidates([object]$Policy,[string]$Root,[object]$Config){
  $now=Get-Date
  $rows=New-Object System.Collections.ArrayList
  $roots=@()
  $gscLogs=Join-Path $Root "logs"
  $roots += [pscustomobject]@{kind="gsc-log";path=$gscLogs;days=[int]$Policy.logs.normal_retention_days}
  foreach($s in @($Config.servers)){
    $dir=[string]$s.path
    if([string]::IsNullOrWhiteSpace($dir)){continue}
    $roots += [pscustomobject]@{kind=("server-log:"+[string]$s.id);path=(Join-Path $dir "logs");days=[int]$Policy.logs.normal_retention_days}
    $roots += [pscustomobject]@{kind=("server-crash:"+[string]$s.id);path=(Join-Path $dir "crash-reports");days=[int]$Policy.logs.crash_retention_days}
  }
  foreach($r in $roots){
    if(-not(Test-Path -LiteralPath $r.path -PathType Container)){continue}
    foreach($x in Get-ChildItem -LiteralPath $r.path -File -Recurse -ErrorAction SilentlyContinue){
      $ageDays=($now-$x.LastWriteTime).TotalDays
      $ageHours=($now-$x.LastWriteTime).TotalHours
      if($ageDays -le [int]$r.days){continue}
      if($ageHours -lt [int]$Policy.logs.preserve_recent_incident_hours){continue}
      [void]$rows.Add([pscustomobject]@{
        kind=[string]$r.kind
        path=$x.FullName
        name=$x.Name
        size=[int64]$x.Length
        modified=$x.LastWriteTime.ToString("o")
      })
    }
  }
  return @($rows)
}

if($Synthetic){
  $tmp=Join-Path $env:TEMP ("Geumyi-Day12-LifeApply-"+[guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp|Out-Null
  try{
    $src=Join-Path $tmp "old.log"
    $trash=Join-Path $tmp "trash"
    New-Item -ItemType Directory -Force -Path $trash|Out-Null
    Set-Content -LiteralPath $src -Value "synthetic-old-log"
    $dst=Join-Path $trash "0001-old.log"
    Move-Item -LiteralPath $src -Destination $dst
    $pass=(-not(Test-Path $src)) -and (Test-Path $dst)
    $r=[ordered]@{schema=1;phase="12.4-apply";synthetic=$true;result=$(if($pass){"SYNTHETIC_PASS"}else{"FAIL"});production_files_touched=$false}
    $r|ConvertTo-Json|Set-Content $out -Encoding UTF8
    if(-not$pass){exit 2}
  }finally{
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
  exit 0
}

if($Confirm -ne "APPLY_DAY12_LIFECYCLE_TO_TRASH"){
  Write-Host "[BLOCKED] This operation moves eligible backup/log files to recoverable Trash areas."
  Write-Host 'Use -Confirm "APPLY_DAY12_LIFECYCLE_TO_TRASH" only after reviewing the Phase 12.4 dry-run report.'
  exit 23
}

$policy=Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8|ConvertFrom-Json
if([int]$policy.schema -ne 1){throw "Unsupported policy schema"}

$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root=Join-Path $pd "GeumyiServerCenter"
$configPath=Join-Path $root "server.json"
if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw "server.json missing"}
$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json

$fleet=Get-Json "/api/v4/update/fleet"
$unsafe=@($fleet.servers|Where-Object{
  [bool]$_.status.block_start -or [string]$_.status.phase -in @("blocked","rollback_failed","rolling_back","pending_health","downloading")
})
if($unsafe.Count -gt 0){throw "Unsafe update transaction exists; lifecycle apply blocked"}

# Disk guard before creating any local log archive/trash material.
$free=[int64]0
try{$free=[int64](Get-Item -LiteralPath $root).PSDrive.Free}catch{}
if($free -lt ([int64]$policy.disk.minimum_free_gib*1GB)){
  throw ("Free disk below required minimum: "+[math]::Round($free/1GB,2)+" GiB")
}

$backupSteps=New-Object System.Collections.ArrayList
foreach($id in @($fleet.servers|ForEach-Object{[string]$_.server_id})){
  $dry=Post-Json "/api/v4/backup/retention/dry-run" @{id=$id;keep_latest=[int]$policy.backup.recent}
  if(-not [string]::IsNullOrWhiteSpace([string]$dry.blocked_reason)){
    throw ("Retention blocked for "+$id+": "+[string]$dry.blocked_reason)
  }
  $candidates=@($dry.candidates)
  if($candidates.Count -eq 0){
    [void]$backupSteps.Add([ordered]@{server_id=$id;candidates=0;moved=0;result="NOOP"})
    continue
  }
  $applyResult=Post-Json "/api/v4/backup/retention/apply" @{id=$id;keep_latest=[int]$policy.backup.recent;confirm="MOVE_TO_TRASH"}
  [void]$backupSteps.Add([ordered]@{
    server_id=$id
    candidates=$candidates.Count
    moved=@($applyResult.moved).Count
    result="MOVED_TO_GSC_TRASH"
  })
}

$logCandidates=Get-LogCandidates $policy $root $config
$logTrash=Join-Path $root ("LogTrash\"+$stamp)
$logArchiveRoot=Join-Path $root "LogArchive"
New-Item -ItemType Directory -Force -Path $logTrash,$logArchiveRoot|Out-Null
$stage=Join-Path $env:TEMP ("Geumyi-Day12-LogArchive-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage|Out-Null
$manifestRows=New-Object System.Collections.ArrayList
$movedRows=New-Object System.Collections.ArrayList
try{
  $i=0
  foreach($x in $logCandidates){
    $i++
    $safeName=("{0:D5}-{1}" -f $i,([IO.Path]::GetFileName([string]$x.name)))
    $stageFile=Join-Path $stage $safeName
    Copy-Item -LiteralPath ([string]$x.path) -Destination $stageFile -Force
    [void]$manifestRows.Add([ordered]@{
      archive_name=$safeName
      kind=[string]$x.kind
      original_name=[string]$x.name
      size=[int64]$x.size
      modified=[string]$x.modified
    })
  }
  $manifest=[ordered]@{schema=1;created_at=(Get-Date).ToString("o");files=@($manifestRows)}
  $manifest|ConvertTo-Json -Depth 8|Set-Content (Join-Path $stage "manifest.json") -Encoding UTF8

  $archive=Join-Path $logArchiveRoot ("day12-logs-"+$stamp+".zip")
  Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $archive -Force
  if(-not(Test-Path $archive -PathType Leaf) -or (Get-Item $archive).Length -le 0){throw "Log archive creation failed"}

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($archive)
  try{
    if(@($zip.Entries|Where-Object{$_.FullName -eq "manifest.json"}).Count -ne 1){throw "Log archive manifest missing"}
    if(@($zip.Entries).Count -lt ($logCandidates.Count+1)){throw "Log archive entry count mismatch"}
  }finally{$zip.Dispose()}

  $i=0
  foreach($x in $logCandidates){
    $i++
    $safeName=("{0:D5}-{1}" -f $i,([IO.Path]::GetFileName([string]$x.name)))
    $dst=Join-Path $logTrash $safeName
    Move-Item -LiteralPath ([string]$x.path) -Destination $dst
    [void]$movedRows.Add([ordered]@{kind=[string]$x.kind;name=[string]$x.name;size=[int64]$x.size;trash_name=$safeName})
  }
}finally{
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

$result=[ordered]@{
  schema=1
  phase="12.4-apply"
  generated_at=(Get-Date).ToString("o")
  result="APPLIED_TO_RECOVERABLE_TRASH"
  backup_retention=$backupSteps
  logs=[ordered]@{
    candidates=$logCandidates.Count
    moved_to_log_trash=$movedRows.Count
    moved=@($movedRows)
    archive_created=($logCandidates.Count -gt 0)
    permanent_delete_performed=$false
  }
  server_lifecycle_action_performed=$false
  permanent_backup_delete_performed=$false
  note="Backups use GSC Trash. Old logs are archived then moved to LogTrash; no permanent delete is performed."
}
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "DAY 12 LIFECYCLE APPLY COMPLETE"
Write-Host ("Backups: "+@($backupSteps).Count+" servers")
Write-Host ("Logs moved to LogTrash: "+$movedRows.Count)
Write-Host ("Report: "+$out)
exit 0
