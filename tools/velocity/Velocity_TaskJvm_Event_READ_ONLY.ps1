[CmdletBinding()]
param(
 [switch]$Synthetic,
 [ValidateSet('Normal','NoEvent')][string]$SyntheticCase='Normal'
)
if(-not $Synthetic -and $SyntheticCase -ne 'Normal'){
 throw 'SyntheticCase requires Synthetic; no OS inspection permitted for test cases'
}
# GSC 4.5.2 Canary: strictly read-only Task Scheduler process-generation
# correlation hints. Does NOT attest complete OS identity or authorize any
# start, stop, restart, plugin control or maintenance action.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$targets=@(
 [pscustomobject]@{id='wild';name='Geumyi Day10 Velocity wild';udp=19132},
 [pscustomobject]@{id='playground';name='Geumyi Day10 Velocity playground';udp=19133},
 [pscustomobject]@{id='other';name='Geumyi Day10 Velocity other';udp=19134}
)
$report=[ordered]@{
 schema=1
 kind='GEUMYI_GSC_452_VELOCITY_TASK_PROCESS_EVENT_READ_ONLY'
 collected_at_utc=[DateTimeOffset]::UtcNow.ToString('o')
 synthetic=[bool]$Synthetic
 server_state_changed=$false
 task_state_modified=$false
 audit_log_settings_changed=$false
 read_only=$true
 source_authenticated=$false
 live_control_authorized=$false
 event_log_state='UNAVAILABLE'
 event129_query_status='NOT_QUERIED'
 event129_window_hours=48
 event129_scan_capped=$false
 result='EVIDENCE_UNVERIFIED'
 instances=@()
}
function NewFinding([string]$id){
 return [ordered]@{
  id=$id
  task_running=$false
  task_event129_found=$false
  event_task_process_current=$false
  event_process_creation_time_correlated=$false
  task_started_java_directly=$false
  single_java_child_found=$false
  udp_owner_correlates_with_child=$false
  udp_java_pair_hint=$false # An independent process/UDP hint, NOT Task Scheduler identity
  reliable_task_to_jvm_identity_verified=$false
  live_control_authorized=$false
  result='NOT_ATTESTED'
 }
}
if($Synthetic){
 $report.event_log_state='ENABLED'
 $report.event129_query_status=if($SyntheticCase -eq 'NoEvent'){'NO_MATCHES_48H'}else{'HAS_EVENTS'}
 foreach($t in $targets){
  $x=NewFinding $t.id
  $x.task_running=$true
  $x.task_event129_found=$SyntheticCase -eq 'Normal'
  $x.udp_java_pair_hint=$SyntheticCase -eq 'NoEvent'
  $x.result=if($SyntheticCase -eq 'NoEvent'){
   'SYNTHETIC_NO_EVENT_JAVA_PAIR_NEVER_ATTESTED'
  }else{'SYNTHETIC_EVENT_CANNOT_PROVE_IDENTITY'}
  $report.instances+=$x
 }
 $report.result='SYNTHETIC_SHAPE_PASS_NEVER_LIVE'
 $report|ConvertTo-Json -Depth 7 -Compress
 exit 0
}
$eventList=@()
$logName='Microsoft-Windows-TaskScheduler/Operational'
# Check metadata only; NEVER enable or configure the channel.
try {
 $cfg=Get-WinEvent -ListLog $logName -ErrorAction Stop
 $report.event_log_state=if($cfg.IsEnabled){'ENABLED'}else{'DISABLED'}
} catch {
 $report.event_log_state='UNAVAILABLE'
}
if($report.event_log_state -eq 'DISABLED'){
 $report.event129_query_status='LOG_DISABLED'
}elseif($report.event_log_state -eq 'ENABLED'){
 try {
  # Only event 129 ("Created Task Process"), capped to the last 48 hours.
  # Older/overwritten events and cap-limited rows do not prove task absence.
  $eventList=@(Get-WinEvent -FilterHashtable @{
   LogName=$logName
   Id=129
   StartTime=(Get-Date).AddHours(-48)
  } -MaxEvents 1200 -ErrorAction Stop)
  $report.event129_query_status=if($eventList.Count -gt 0){'HAS_EVENTS'}else{'NO_MATCHES_48H'}
  $report.event129_scan_capped=$eventList.Count -ge 1200
 }catch{
  $eventList=@()
  if([string]$_.FullyQualifiedErrorId -match 'NoMatchingEventsFound'){
   $report.event129_query_status='NO_MATCHES_48H'
  }else{
   # No raw exception string is written (it might contain host metadata).
   $report.event129_query_status='QUERY_FAILED'
  }
 }
}
$processes=@()
try{$processes=@(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)}catch{$processes=@()}
$udpRows=@()
try{$udpRows=@(Get-NetUDPEndpoint -ErrorAction Stop)}catch{$udpRows=@()}
foreach($t in $targets){
 $x=NewFinding $t.id
 try{
  $task=@(Get-ScheduledTask -TaskName $t.name -ErrorAction Stop |
   Where-Object {[string]$_.TaskPath -eq '\'})
  $x.task_running=$task.Count -eq 1 -and [string]$task[0].State -eq 'Running'
 }catch{$x.task_running=$false}
 # Event-independent LIVENESS HINT ONLY: find one UDP owner Java child
 # with a Java parent. Never promote this to Task Scheduler PID attestation.
 try {
  $owners=@($udpRows|Where-Object {[int]$_.LocalPort -eq $t.udp})
  if($owners.Count -eq 1 -and [int]$owners[0].OwningProcess -gt 0){
   $childrenHint=@($processes|Where-Object {
    [int]$_.ProcessId -eq [int]$owners[0].OwningProcess -and
    [string]$_.Name -in @('java.exe','javaw.exe')
   })
   if($childrenHint.Count -eq 1 -and [int]$childrenHint[0].ParentProcessId -gt 0 -and
      [int]$childrenHint[0].ParentProcessId -ne [int]$childrenHint[0].ProcessId){
    $parentsHint=@($processes|Where-Object {
     [int]$_.ProcessId -eq [int]$childrenHint[0].ParentProcessId -and
     [string]$_.Name -in @('java.exe','javaw.exe')
    })
    if($parentsHint.Count -eq 1){
     $parentCreated=[datetime]$parentsHint[0].CreationDate
     $childCreated=[datetime]$childrenHint[0].CreationDate
     $x.udp_java_pair_hint=$parentCreated -le $childCreated
    }
   }
  }
 }catch{$x.udp_java_pair_hint=$false}
 $events=@()
 foreach($evt in $eventList){
  try{
   [xml]$node=[string]$evt.ToXml()
   $values=@{}
   foreach($data in @($node.Event.EventData.Data)){
    if($null -ne $data -and $null -ne $data.Name){
     $values[[string]$data.Name]=[string]$data.'#text'
    }
   }
   $n=''
   if($values.ContainsKey('TaskName')){$n=[string]$values.TaskName}
   $n=$n.TrimStart('\')
   if($n -cne $t.name){continue}
   $rawPid=''
   if($values.ContainsKey('ProcessID')){$rawPid=[string]$values.ProcessID}
   elseif($values.ContainsKey('ProcessId')){$rawPid=[string]$values.ProcessId}
   if($rawPid -notmatch '^\d{1,10}$'){continue}
   $pidValue=[int64]$rawPid
   if($pidValue -le 0 -or $pidValue -gt [int]::MaxValue){continue}
   $events+= [pscustomobject]@{Time=$evt.TimeCreated;PID=[int]$pidValue}
  }catch{continue}
 }
 $x.task_event129_found=$events.Count -gt 0
 if($events.Count -gt 0 -and $x.task_running){
  # A log event alone is not sufficient: require a live process with the
  # SAME PID and creation time within 10 seconds of the event record.
  $mostRecent=@($events|Sort-Object Time -Descending|Select-Object -First 1)
  $event=$mostRecent[0]
  $match=@($processes|Where-Object {[int]$_.ProcessId -eq $event.PID})
  if($match.Count -eq 1){
   $proc=$match[0]
   $x.event_task_process_current=$true
   try{
    $created=[datetime]$proc.CreationDate
    $when=[datetime]$event.Time
    $delta=[Math]::Abs(($created-$when).TotalSeconds)
    $x.event_process_creation_time_correlated=$delta -le 10
   }catch{$x.event_process_creation_time_correlated=$false}
   $x.task_started_java_directly=[string]$proc.Name -in @('java.exe','javaw.exe')
   if($x.event_process_creation_time_correlated -and $x.task_started_java_directly){
    $children=@($processes|Where-Object {
      [int]$_.ParentProcessId -eq $event.PID -and
      [string]$_.Name -in @('java.exe','javaw.exe')
    })
    $x.single_java_child_found=$children.Count -eq 1
    if($children.Count -eq 1){
     $owner=@($udpRows|Where-Object {
       [int]$_.LocalPort -eq $t.udp -and
       [int]$_.OwningProcess -eq [int]$children[0].ProcessId
     })
     $x.udp_owner_correlates_with_child=$owner.Count -eq 1
    }
   }
  }
 }
 # Fail-closed: even every derived boolean is only a read-only hint,
 # not an authenticated process token, real player gate, or stop permit.
 $x.result=if($x.task_running -and $x.event_process_creation_time_correlated -and
  $x.task_started_java_directly -and $x.single_java_child_found -and
  $x.udp_owner_correlates_with_child){
  'EVENT_PID_AND_CHILD_UDP_CORRELATED_AUTH_UNVERIFIED'
 }elseif($x.task_running -and -not $x.task_event129_found -and $x.udp_java_pair_hint){
  'EVENT129_MISSING_JAVA_PAIR_ONLY_NO_GO'
 }else{'PROCESS_OR_TASK_EVENT_EVIDENCE_INCOMPLETE'}
 $report.instances += $x
}
if(@($report.instances|Where-Object {$_.result -ne 'EVENT_PID_AND_CHILD_UDP_CORRELATED_AUTH_UNVERIFIED'}).Count -eq 0){
 $report.result='THREE_EVENT_CORRELATIONS_CAPTURED_STILL_NOT_AUTHENTICATED'
}else{
 $report.result='EVENT_OR_PROCESS_CORRELATION_INCOMPLETE'
}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)){
 Write-Host 'Desktop unavailable. No report written or task changed.'
 exit 2
}
$dir=Join-Path $desktop 'Geumyi-Velocity-ReadOnly-Reports'
[void](New-Item -ItemType Directory -Path $dir -Force)
$file=Join-Path $dir ('Velocity-TaskJvm-READ-ONLY-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
[IO.File]::WriteAllText($file,($report|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))
Write-Host ('READ ONLY result: '+$report.result)
Write-Host ('Sanitized report: '+$file)
Write-Host 'Share only this JSON: no PIDs, event XML, task commands, paths or secrets included.'
