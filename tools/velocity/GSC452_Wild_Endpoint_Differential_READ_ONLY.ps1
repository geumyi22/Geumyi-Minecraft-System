#requires -Version 5.1
[CmdletBinding()]
param(
 [ValidateSet('none','same','different','udp-missing','udp-multiple','tcp-missing','query-failed')]
 [string]$SyntheticScenario='none'
)
# GSC 4.5.2 CANARY / WILD ONLY. STRICT READ ONLY. No raw PID, path,
# address, task XML or Event XML is printed. No OS mutation is performed.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function CountClass([int]$n){
 if($n -eq 0){return 'ZERO'}
 if($n -eq 1){return 'ONE'}
 return 'MULTIPLE'
}
function Relation([int[]]$tcp,[int[]]$udp,[bool]$queryOK){
 if(-not $queryOK){return 'UNVERIFIED_QUERY'}
 if($tcp.Count -ne 1 -or $udp.Count -ne 1){return 'INSUFFICIENT_UNIQUE_OWNERS'}
 if($tcp[0] -eq $udp[0]){return 'SAME_PID'}
 return 'DIFFERENT_PID'
}
function Output($d){
 $d.safe_to_stop=$false
 $d.safe_to_cutover=$false
 $d.live_control_authorized=$false
 $d.task_to_jvm_identity_proven=$false
 $d.legacy_console_stdin_control_proven=$false
 $d.scheduled_task_modified=$false
 $d.java_operations=0
 $d | ConvertTo-Json -Compress -Depth 4
}
$d=[ordered]@{
 schema=2
 check='GSC452_WILD_ENDPOINT_DIFFERENTIAL_READ_ONLY'
 target='wild'
 read_only=$true
 synthetic=($SyntheticScenario -ne 'none')
 task_state='UNKNOWN'
 task_java_action_verified=$false
 owner_generation_marker_absent=$false
 scheduler_restart_risk='UNKNOWN'
 tcp_25565_inventory='NOT_CHECKED'
 tcp_unique_owner_count='UNVERIFIED'
 udp_19132_inventory='NOT_CHECKED'
 udp_unique_owner_count='UNVERIFIED'
 tcp_udp_owner_relation='UNVERIFIED_QUERY'
 tcp_owner_image_matches_task='NOT_CHECKED'
 udp_owner_image_matches_task='NOT_CHECKED'
 scheduler_event_129_tcp_owner='NOT_CHECKED'
 probe_status='INCOMPLETE_NO_ACTION'
}
if($SyntheticScenario -ne 'none'){
 $t=@(101);$u=@(101)
 switch($SyntheticScenario){
  'different'{$u=@(202)}
  'udp-missing'{$u=@()}
  'udp-multiple'{$u=@(101,202)}
  'tcp-missing'{$t=@()}
  'query-failed'{$u=@()}
 }
 $q=$SyntheticScenario -ne 'query-failed'
 $d.task_state='Running'
 $d.task_java_action_verified=$true
 $d.owner_generation_marker_absent=$true
 $d.scheduler_restart_risk='PRESENT'
 $d.tcp_25565_inventory=if($t.Count){'OBSERVED'}else{'NO_ENDPOINT'}
 $d.udp_19132_inventory=if(-not $q){'QUERY_FAILED'}elseif($u.Count){'OBSERVED'}else{'NO_ENDPOINT'}
 $d.tcp_unique_owner_count=CountClass $t.Count
 $d.udp_unique_owner_count=if($q){CountClass $u.Count}else{'UNVERIFIED'}
 $d.tcp_udp_owner_relation=Relation $t $u $q
 $d.tcp_owner_image_matches_task=if($t.Count){'MATCH'}else{'NOT_CHECKED'}
 $d.udp_owner_image_matches_task=if($u.Count -eq 1 -and $q){'MATCH'}else{'NOT_CHECKED'}
 $d.scheduler_event_129_tcp_owner='SYNTHETIC_NOT_REAL'
 $d.probe_status='SYNTHETIC_DIAGNOSTIC_NO_ACTION'
 Output $d
 return
}
# Return only unique numeric PIDs to local memory. Never serialize them.
function Inventory([string]$protocol,[int]$port){
 try {
  if($protocol -ceq 'tcp') {
   $rows=@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop)
  }else{
   $rows=@(Get-NetUDPEndpoint -LocalPort $port -ErrorAction Stop)
  }
  $pids=@($rows|Where-Object { $_.OwningProcess -gt 0 } |
    Select-Object -ExpandProperty OwningProcess -Unique |
    ForEach-Object {[int]$_})
  return [pscustomobject]@{status=if($rows.Count){'OBSERVED'}else{'NO_ENDPOINT'};pids=[int[]]$pids}
 }catch{
  return [pscustomobject]@{status='QUERY_FAILED';pids=[int[]]@()}
 }
}
function ProcessEvidence([int]$processId,[string]$expectedExe) {
 try{
  $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$processId) -ErrorAction Stop
  if($null -eq $p -or -not $p.ExecutablePath -or -not $p.CreationDate){
   return [pscustomobject]@{status='PROCESS_METADATA_MISSING';creation=$null}
  }
  if([IO.Path]::GetFullPath([string]$p.ExecutablePath) -ine
      [IO.Path]::GetFullPath($expectedExe)){
   return [pscustomobject]@{status='DIFFERENT_EXECUTABLE';creation=$null}
  }
  return [pscustomobject]@{status='MATCH';creation=([datetime]$p.CreationDate).ToUniversalTime()}
 }catch{
  return [pscustomobject]@{status='PROCESS_QUERY_FAILED';creation=$null}
 }
}
function Event129Evidence([int]$processId,[string]$taskName,[string]$exe,[datetime]$born){
 # Absent/rotated/disabled TaskScheduler history is not a proxy outage.
 $events=@()
 try{
  $events=@(Get-WinEvent -FilterHashtable @{
   LogName='Microsoft-Windows-TaskScheduler/Operational'
   Id=129
   StartTime=$born.ToLocalTime().AddSeconds(-30)
  } -MaxEvents 4096 -ErrorAction Stop)
 }catch{return 'HISTORY_UNAVAILABLE_OR_NO_EVENTS'}
 $recognized=$false
 foreach($e in $events){
  try{
   [xml]$x=$e.ToXml()
   $tn=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='TaskName']")
   $image=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='Path']")
   $id=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='ProcessID']")
   if($null -eq $tn -or $null -eq $image -or $null -eq $id){continue}
   $recognized=$true
   $reported=0
   if(-not [int]::TryParse([string]$id.InnerText,[ref]$reported)){continue}
   $time=([datetime]$e.TimeCreated).ToUniversalTime()
   if([string]$tn.InnerText -ine ('\'+$taskName) -or $reported -ne $processId -or
      [IO.Path]::GetFullPath([string]$image.InnerText) -ine [IO.Path]::GetFullPath($exe) -or
      [math]::Abs(($time-$born).TotalSeconds) -gt 20){continue}
   return 'MATCHED_TCP_PROCESS'
  }catch{continue}
 }
 if(-not $recognized){return 'EVENT_FIELDS_UNAVAILABLE'}
 return 'NO_MATCHING_TASK_PID_IMAGE_TIME'
}
try{
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'OS_UNSUPPORTED'}
 $taskName='Geumyi Day10 Velocity wild'
 $task=Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction Stop
 $d.task_state=[string]$task.State
 $actions=@($task.Actions|Where-Object {$null -ne $_})
 if($actions.Count -ne 1){throw 'ACTION_COUNT'}
 $a=$actions[0]
 $exe=[string]$a.Execute
 $work=[string]$a.WorkingDirectory
 $arg=[string]$a.Arguments
 $dir=Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer\wild'
 $d.task_java_action_verified=([IO.Path]::IsPathRooted($exe) -and
   [IO.Path]::IsPathRooted($work) -and
   [IO.Path]::GetFileName($exe) -ieq 'java.exe' -and
   [IO.Path]::GetFullPath($work) -ieq [IO.Path]::GetFullPath($dir) -and
   $arg -match '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)' -and
   (Test-Path -LiteralPath $exe -PathType Leaf))
 $d.scheduler_restart_risk=if([int]$task.Settings.RestartCount -gt 0){'PRESENT'}else{'NOT_OBSERVED'}
 $ownerMarker=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged\Recovery\wild.active.json'
 $d.owner_generation_marker_absent=-not(Test-Path -LiteralPath $ownerMarker)
 if(-not $d.task_java_action_verified){throw 'BAD_TASK_SHAPE'}
 # Query the port families INDEPENDENTLY. Do not short-circuit when different.
 $tcp=Inventory 'tcp' 25565
 $udp=Inventory 'udp' 19132
 $d.tcp_25565_inventory=$tcp.status
 $d.udp_19132_inventory=$udp.status
 $d.tcp_unique_owner_count=if($tcp.status -eq 'QUERY_FAILED'){'UNVERIFIED'}else{CountClass $tcp.pids.Count}
 $d.udp_unique_owner_count=if($udp.status -eq 'QUERY_FAILED'){'UNVERIFIED'}else{CountClass $udp.pids.Count}
 $d.tcp_udp_owner_relation=Relation $tcp.pids $udp.pids (($tcp.status -ne 'QUERY_FAILED') -and ($udp.status -ne 'QUERY_FAILED'))
 if($tcp.status -eq 'OBSERVED' -and $tcp.pids.Count -eq 1){
  $p=ProcessEvidence $tcp.pids[0] $exe
  $d.tcp_owner_image_matches_task=$p.status
  if($p.status -ceq 'MATCH' -and $null -ne $p.creation){
   $d.scheduler_event_129_tcp_owner=Event129Evidence $tcp.pids[0] $taskName $exe $p.creation
  }
 }
 if($udp.status -eq 'OBSERVED' -and $udp.pids.Count -eq 1){
  $p=ProcessEvidence $udp.pids[0] $exe
  $d.udp_owner_image_matches_task=$p.status
 }
 $again=Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction Stop
 if([string]$again.State -ne [string]$d.task_state){throw 'TASK_STATE_CHANGED'}
 $d.probe_status='READ_ONLY_ENDPOINT_DIAGNOSTICS_CAPTURED'
}catch{
 $d.probe_status='READ_ONLY_PARTIAL_OR_ERROR_NO_ACTION'
}
Output $d
