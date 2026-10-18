#requires -Version 5.1
[CmdletBinding()]
param(
 [switch]$Synthetic,
 [ValidateSet('MatchingHint','NoVisibility','Ambiguous')][string]$SyntheticCase='MatchingHint'
)
# GSC 4.5.2 Canary: Task Scheduler COM IRegisteredTask.GetInstances(0)
# plus IRunningTask.EnginePID. READ ONLY. Not a PID authentication oracle.
# EnginePID is the TASK ENGINE PID; it is not guaranteed to be the task
# action's process ID. Per Microsoft, instance visibility also depends
# on the caller's Windows security context.
# Never call IRunningTask.Stop(), Run(), SetInfo, Register, or shell commands.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$targets=@(
 [pscustomobject]@{id='wild';task='Geumyi Day10 Velocity wild';port=19132},
 [pscustomobject]@{id='playground';task='Geumyi Day10 Velocity playground';port=19133},
 [pscustomobject]@{id='other';task='Geumyi Day10 Velocity other';port=19134}
)
$report=[ordered]@{
 schema=1
 kind='GEUMYI_GSC_452_VELOCITY_TASK_INSTANCE_COM_READ_ONLY'
 collected_at_utc=[DateTimeOffset]::UtcNow.ToString('o')
 synthetic=[bool]$Synthetic
 server_state_changed=$false
 task_state_modified=$false
 audit_log_settings_changed=$false
 privilege_elevation_attempted=$false
 read_only=$true
 task_instance_source='WINDOWS_TASKSCHD_COM_READ_ONLY'
 source_authenticated=$false
 live_control_authorized=$false
 result='TASK_INSTANCE_HINTS_UNVERIFIED_NO_GO'
 instances=@()
}
function NewFinding([string]$id){
 return [ordered]@{
  id=$id
  task_running=$false
  instance_query_status='NOT_QUERIED'
  visible_instance_count=0
  engine_pid_present=$false
  engine_pid_visible_as_process=$false
  engine_pid_matches_java_parent=$false
  engine_pid_matches_udp_java_child=$false
  udp_java_pair_hint=$false
  instance_to_jvm_suggestive=$false
  reliable_task_to_jvm_identity_verified=$false
  live_control_authorized=$false
  safe_to_start=$false
  safe_to_stop=$false
  safe_to_restart=$false
  result='NOT_ATTESTED'
 }
}
if($Synthetic){
 foreach($t in $targets){
  $x=NewFinding $t.id
  $x.task_running=$true
  if($SyntheticCase -eq 'MatchingHint'){
   $x.instance_query_status='ONE_VISIBLE'
   $x.visible_instance_count=1
   $x.engine_pid_present=$true
   $x.engine_pid_visible_as_process=$true
   $x.engine_pid_matches_java_parent=$true
   $x.udp_java_pair_hint=$true
   $x.instance_to_jvm_suggestive=$true
   $x.result='SYNTHETIC_ENGINE_PARENT_HINT_NEVER_AUTHENTICATED'
  }elseif($SyntheticCase -eq 'Ambiguous'){
   $x.instance_query_status='MULTIPLE_VISIBLE'
   $x.visible_instance_count=2
   $x.udp_java_pair_hint=$true
   $x.result='SYNTHETIC_MULTIPLE_INSTANCES_NO_GO'
  }else{
   $x.instance_query_status='NO_VISIBLE_INSTANCE'
   $x.udp_java_pair_hint=$true
   $x.result='SYNTHETIC_SECURITY_CONTEXT_UNVERIFIED'
  }
  $report.instances+=$x
 }
 $report.result='SYNTHETIC_NO_GO_FIXTURE_PASS'
 $report|ConvertTo-Json -Compress -Depth 7
 exit 0
}
$svc=$null
$folder=$null
$comStatus='COM_UNAVAILABLE'
try{
 $svc=New-Object -ComObject 'Schedule.Service' -ErrorAction Stop
 $svc.Connect()
 $folder=$svc.GetFolder('\')
 if($null -eq $folder){throw 'Task Scheduler root not available'}
 $comStatus='CONNECTED'
}catch{$comStatus='COM_UNAVAILABLE'}
$processes=@()
try{$processes=@(Get-CimInstance Win32_Process -ErrorAction Stop)}catch{$processes=@()}
$udpRows=@()
try{$udpRows=@(Get-NetUDPEndpoint -ErrorAction Stop)}catch{$udpRows=@()}
foreach($t in $targets){
 $x=NewFinding $t.id
 try{
  $taskRows=@(Get-ScheduledTask -TaskName $t.task -TaskPath '\' -ErrorAction Stop)
  $x.task_running=$taskRows.Count -eq 1 -and [string]$taskRows[0].State -eq 'Running'
 }catch{$x.task_running=$false}
 $ownerPid=0
 $parentPid=0
 $childPid=0
 try{
  $owners=@($udpRows|Where-Object {[int]$_.LocalPort -eq $t.port})
  if($owners.Count -eq 1 -and [int]$owners[0].OwningProcess -gt 0){
   $candidate=[int]$owners[0].OwningProcess
   $children=@($processes|Where-Object {
    [int]$_.ProcessId -eq $candidate -and [string]$_.Name -in @('java.exe','javaw.exe')
   })
   if($children.Count -eq 1){
    $possibleParent=[int]$children[0].ParentProcessId
    if($possibleParent -gt 0 -and $possibleParent -ne $candidate){
     $parents=@($processes|Where-Object {
      [int]$_.ProcessId -eq $possibleParent -and [string]$_.Name -in @('java.exe','javaw.exe')
     })
     if($parents.Count -eq 1){
      if([datetime]$parents[0].CreationDate -le [datetime]$children[0].CreationDate){
       $ownerPid=$candidate
       $parentPid=$possibleParent
       $childPid=$candidate
       $x.udp_java_pair_hint=$true
      }
     }
    }
   }
  }
 }catch{$x.udp_java_pair_hint=$false}
 if($comStatus -ne 'CONNECTED'){
  $x.instance_query_status='COM_UNAVAILABLE'
 }else{
  try{
   # Only the three exact existing registered tasks; never enumerate
   # unrelated task definitions or call ANY mutation method.
   $registered=$folder.GetTask($t.task)
   $instances=$registered.GetInstances(0)
   if($null -eq $instances){throw 'GetInstances returned no collection'}
   $count=[int]$instances.Count
   if($count -eq 0){
    # Non-elevated callers might be unable to see SYSTEM instances.
    $x.instance_query_status='NO_VISIBLE_INSTANCE'
   }elseif($count -ne 1){
    $x.instance_query_status='MULTIPLE_VISIBLE'
    $x.visible_instance_count=[Math]::Min($count,2)
   }else{
    $x.visible_instance_count=1
    $x.instance_query_status='ONE_VISIBLE'
    $engine=[int]$instances.Item(1).EnginePID
    if($engine -gt 0){
     $x.engine_pid_present=$true
     $matching=@($processes|Where-Object {[int]$_.ProcessId -eq $engine})
     $x.engine_pid_visible_as_process=$matching.Count -eq 1
     if($x.engine_pid_visible_as_process -and $x.udp_java_pair_hint){
      $x.engine_pid_matches_java_parent=$engine -eq $parentPid
      $x.engine_pid_matches_udp_java_child=$engine -eq $childPid
      $x.instance_to_jvm_suggestive=$x.engine_pid_matches_java_parent -or $x.engine_pid_matches_udp_java_child
     }
    }
   }
  }catch{
   # Access denied and unknown COM/provider errors both mean no proof.
   # Never emit exception payloads, remote addresses or the task engine PID.
   $x.instance_query_status='COM_QUERY_FAILED_OR_ACCESS_DENIED'
  }
 }
 $x.result=if(-not $x.task_running){'TASK_STATE_NOT_CONFIRMED_NO_GO'}
 elseif($x.instance_to_jvm_suggestive){'ENGINE_PID_PAIR_HINT_NOT_AUTHENTICATED'}
 elseif($x.instance_query_status -eq 'NO_VISIBLE_INSTANCE'){'INSTANCE_NOT_VISIBLE_CONTEXT_UNVERIFIED'}
 else{'TASK_INSTANCE_OR_JAVA_CORRELATION_UNVERIFIED'}
 $report.instances += $x
}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)){
 Write-Host 'Desktop unavailable; no task was changed.'
 exit 2
}
$dir=Join-Path $desktop 'Geumyi-Velocity-ReadOnly-Reports'
[void](New-Item -ItemType Directory -Path $dir -Force)
$file=Join-Path $dir ('Velocity-TaskInstance-COM-READ-ONLY-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
[IO.File]::WriteAllText($file,($report|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))
Write-Host ('READ ONLY result: '+$report.result)
Write-Host ('Sanitized report: '+$file)
Write-Host 'Share only this JSON. No PIDs, instance GUIDs, task commands or secrets are included.'
