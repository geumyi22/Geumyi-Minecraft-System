[CmdletBinding()]
param([ValidateSet("Start","End")][string]$Mode="Start",[string]$SessionDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($SessionDir)){
  $SessionDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Soak"
}
New-Item -ItemType Directory -Force -Path $SessionDir|Out-Null
$base=Join-Path $SessionDir "soak-start.json"
$end=Join-Path $SessionDir "soak-end.json"
$report=Join-Path $SessionDir "FINAL-SOAK-REPORT.json"
function ProcKey([object]$p){
  $name=[string]$p.name
  $pid=[int]$p.pid
  $stamp=[string]$p.started_at
  if($stamp -eq ""){$stamp="START_TIME_UNAVAILABLE"}
  return "$name|$pid|$stamp"
}
function Compare-Procs([object[]]$Old,[object[]]$New){
  $start=@{};foreach($p in @($Old)){if($null -ne $p){$start[(ProcKey $p)]=$p}}
  $seen=@{};$rows=@()
  foreach($p in @($New)){
    if($null -eq $p){continue}
    $key=ProcKey $p
    $seen[$key]=$true
    $old=$null
    if($start.ContainsKey($key)){$old=$start[$key]}
    $same=($null -ne $old)
    $rows+= [ordered]@{
      name=[string]$p.name
      pid=[int]$p.pid
      start_time_available=([string]$p.started_at -ne "")
      same_identity_at_start=$same
      working_set=[int64]$p.working_set
      working_set_delta=$(if($same){[int64]$p.working_set-[int64]$old.working_set}else{$null})
      handles=[int]$p.handles
      handle_delta=$(if($same){[int]$p.handles-[int]$old.handles}else{$null})
    }
  }
  $lost=@($start.Keys|Where-Object{-not $seen.ContainsKey($_)}).Count
  $added=@($rows|Where-Object{-not $_.same_identity_at_start}).Count
  $unverified=@($rows|Where-Object{$_.same_identity_at_start -and -not $_.start_time_available}).Count
  return [ordered]@{rows=@($rows);missing_process_identity_count=$lost
    new_process_identity_count=$added;matched_without_start_time=$unverified
    continuous_process_identity_verified=($lost -eq 0 -and $new -eq 0 -and $unverified -eq 0)}
}
function Snapshot(){
  $pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
  $root=Join-Path $pd "GeumyiServerCenter"
  $procs=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{
    $_.ProcessName -match '(?i)java|GeumyiServerHost|GeumyiServerCenter'
  }|ForEach-Object{
    $startTime=""
    try{$startTime=$_.StartTime.ToUniversalTime().ToString("o")}catch{}
    [ordered]@{name=$_.ProcessName;pid=$_.Id;started_at=$startTime
      working_set=[int64]$_.WorkingSet64;private=[int64]$_.PrivateMemorySize64
      handles=[int]$_.HandleCount
      cpu=$(if($null -ne $_.CPU){[double]$_.CPU}else{0})}
  })
  $logs=0
  try{
    $m=Get-ChildItem (Join-Path $root "logs") -File -Recurse -ErrorAction SilentlyContinue|Measure-Object Length -Sum
    $logs=[int64]$m.Sum
  }catch{}
  $free=0
  try{$free=[int64](Get-Item $root).PSDrive.Free}catch{}
  return [ordered]@{
    captured_at=(Get-Date).ToString("o")
    processes=@($procs)
    gsc_log_bytes=$logs
    disk_free_bytes=$free
  }
}
if($Synthetic){
  $a=@(
    [pscustomobject]@{name="java";pid=101;started_at="2026-10-10T00:00:00Z";working_set=100;handles=10},
    [pscustomobject]@{name="java";pid=102;started_at="2026-10-10T00:00:00Z";working_set=200;handles=20}
  )
  $b=@(
    [pscustomobject]@{name="java";pid=101;started_at="2026-10-10T00:00:00Z";working_set=150;handles=11},
    [pscustomobject]@{name="java";pid=103;started_at="2026-10-10T01:00:00Z";working_set=180;handles=14}
  )
  $d=Compare-Procs $a $b
  $match=@($d.rows|Where-Object{$_.pid -eq 101})
  $restarted=@($d.rows|Where-Object{$_.pid -eq 103})
  if($d.missing_process_identity_count -ne 1 -or $d.new_process_identity_count -ne 1 -or
     $d.continuous_process_identity_verified -or $match.Count -ne 1 -or
     $match[0].working_set_delta -ne 50 -or $restarted.Count -ne 1 -or
     $null -ne $restarted[0].working_set_delta){
    throw "SOAK_PROCESS_IDENTITY_COMPARISON_REGRESSION"
  }
  [ordered]@{schema=2;phase="12.12";synthetic=$true;read_only=$true
    result="SYNTHETIC_PASS";process_identity_tested=$true
    no_cross_process_delta=$true;mutation_performed=$false
  }|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $SessionDir "soak-synthetic.json") -Encoding UTF8
  exit 0
}
if($Mode -eq "Start"){
  if((Test-Path -LiteralPath $base) -or (Test-Path -LiteralPath $end) -or
     (Test-Path -LiteralPath $report)){
    throw "Soak session already exists. Never overwrite evidence. Use a NEW -SessionDir for a new run."
  }
  (Snapshot)|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $base -Encoding UTF8
  Write-Host ("SOAK START captured: "+$base)
  exit 0
}
if(-not(Test-Path -LiteralPath $base -PathType Leaf)){throw "Start snapshot missing"}
if((Test-Path -LiteralPath $end) -or (Test-Path -LiteralPath $report)){
  throw "Soak end already exists. Never overwrite previous evidence."
}
$start=Get-Content -LiteralPath $base -Raw -Encoding UTF8|ConvertFrom-Json
$finish=Snapshot
$beginTime=[datetimeoffset]::Parse([string]$start.captured_at)
$finishTime=[datetimeoffset]::Parse([string]$finish.captured_at)
$hours=($finishTime-$beginTime).TotalHours
if($hours -lt 0){throw "Soak clock moved backward; review before writing END evidence"}
$compare=Compare-Procs @($start.processes) @($finish.processes)
$duration=if($hours -ge 8){"DURATION_MET_REVIEW_REQUIRED"}else{"SHORT_REVIEW_REQUIRED"}
$r=[ordered]@{
  schema=2;phase="12.12";mode="SOAK";start=$start.captured_at;end=$finish.captured_at
  duration_hours=[math]::Round($hours,2);target_hours="8-12 where practical"
  duration_gate=$duration
  start_process_count=@($start.processes).Count;end_process_count=@($finish.processes).Count
  process_identity_continuity=$compare.continuous_process_identity_verified
  started_or_changed_processes=$compare.new_process_identity_count
  exited_or_changed_processes=$compare.missing_process_identity_count
  matched_without_start_time=$compare.matched_without_start_time
  processes=$compare.rows
  gsc_log_growth=[int64]$finish.gsc_log_bytes-[int64]$start.gsc_log_bytes
  disk_free_delta=[int64]$finish.disk_free_bytes-[int64]$start.disk_free_bytes
  result="REVIEW_REQUIRED"
  notes=@(
    "Delta is computed only for the same name, PID and process start time, never the first Java process with a matching name.",
    "If process start time cannot be read, identity continuity is unverified even when PID matches.",
    "Start and End snapshots are immutable within the chosen directory; choose a new SessionDir for a later test.",
    "Eight-hour duration alone never marks stability PASS; review process continuity, errors, game operation and memory trends.",
    "No server restart, configuration, world, backup, firewall or ACL changes by this tool."
  )
}
$finish|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $end -Encoding UTF8
$r|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8
Write-Host ("SOAK END captured: "+$report)
