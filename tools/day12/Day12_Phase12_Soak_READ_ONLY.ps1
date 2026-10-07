[CmdletBinding()]
param([ValidateSet("Start","End")][string]$Mode,[string]$SessionDir="")
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($SessionDir)){$SessionDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Soak"}
New-Item -ItemType Directory -Force -Path $SessionDir|Out-Null
$base=Join-Path $SessionDir "soak-start.json";$end=Join-Path $SessionDir "soak-end.json";$report=Join-Path $SessionDir "FINAL-SOAK-REPORT.json"
function Snapshot(){
  $pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"};$root=Join-Path $pd "GeumyiServerCenter"
  $procs=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -match '(?i)java|GeumyiServerHost|GeumyiServerCenter'}|ForEach-Object{[ordered]@{name=$_.ProcessName;pid=$_.Id;working_set=[int64]$_.WorkingSet64;private=[int64]$_.PrivateMemorySize64;handles=$_.HandleCount;cpu=$(if($null-ne$_.CPU){[double]$_.CPU}else{0})}})
  $logs=0;try{$logs=[int64]((Get-ChildItem (Join-Path $root "logs") -File -Recurse -ErrorAction SilentlyContinue|Measure-Object Length -Sum).Sum)}catch{}
  $free=0;try{$free=[int64](Get-Item $root).PSDrive.Free}catch{}
  [ordered]@{captured_at=(Get-Date).ToString("o");processes=$procs;gsc_log_bytes=$logs;disk_free_bytes=$free}
}
if($Mode -eq "Start"){(Snapshot)|ConvertTo-Json -Depth 8|Set-Content $base -Encoding UTF8;Write-Host ("SOAK START captured: "+$base);exit 0}
if(-not(Test-Path $base)){throw "Start snapshot missing"}
$s=Get-Content $base -Raw|ConvertFrom-Json;$e=Snapshot;$e|ConvertTo-Json -Depth 8|Set-Content $end -Encoding UTF8
$hours=((Get-Date $e.captured_at)-(Get-Date $s.captured_at)).TotalHours
$rows=@();foreach($p in @($e.processes)){ $old=@($s.processes|Where-Object{[string]$_.name -eq [string]$p.name}|Select-Object -First 1);$rows += [ordered]@{name=[string]$p.name;pid=[int]$p.pid;working_set=[int64]$p.working_set;working_set_delta=$(if($old.Count){[int64]$p.working_set-[int64]$old[0].working_set}else{$null});handles=[int]$p.handles;handle_delta=$(if($old.Count){[int]$p.handles-[int]$old[0].handles}else{$null})}}
$r=[ordered]@{schema=1;phase="12.12";mode="SOAK";start=$s.captured_at;end=$e.captured_at;duration_hours=[math]::Round($hours,2);target_hours="8-12 where practical";duration_gate=$(if($hours -ge 8){"PASS"}else{"PENDING/SHORT"});processes=$rows;gsc_log_growth=[int64]$e.gsc_log_bytes-[int64]$s.gsc_log_bytes;disk_free_delta=[int64]$e.disk_free_bytes-[int64]$s.disk_free_bytes;result="REVIEW_REQUIRED";note="Memory/handle growth requires review; this script does not auto-declare leak-free operation."}
$r|ConvertTo-Json -Depth 10|Set-Content $report -Encoding UTF8;Write-Host ("SOAK END captured: "+$report)
