#requires -Version 5.1
[CmdletBinding()]
param(
 [ValidateSet('none','matched','missing-event','different-owner','stale-event')]
 [string]$SyntheticScenario='none'
)
# Strict read-only wild proxy evidence; this script NEVER authorizes lifecycle actions.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Emit([bool]$synthetic,[string]$state,[bool]$taskExact,[bool]$owners,[bool]$liveJava,[bool]$event,[bool]$noMarker,[bool]$risk,[string]$eventStatus){
 $match=(!$synthetic -and $state -ceq 'Running' -and $taskExact -and $owners -and $liveJava -and $event -and $noMarker)
 [ordered]@{
  schema=1;check='GSC452_WILD_TASK_JVM_IDENTITY_READ_ONLY';target='wild';read_only=$true
  synthetic=$synthetic;task_state=$state;task_java_action_verified=$taskExact
  java_tcp_bedrock_udp_same_owner=$owners;live_executable_matches_task=$liveJava
  scheduler_event_129_pid_image_time_matches=$event;scheduler_event_129_status=$eventStatus
  owner_generation_marker_absent=$noMarker;scheduler_restart_risk=$risk
  task_to_proxy_jvm_evidence_matched=$match
  legacy_console_stdin_control_proven=$false
  safe_to_stop=$false;safe_to_cutover=$false;live_control_authorized=$false
  scheduled_task_modified=$false;java_operations=0
  status=if($match){'IDENTITY_EVIDENCE_MATCHED_NO_ACTION_APPROVED'}else{'IDENTITY_EVIDENCE_INCOMPLETE_NO_ACTION_APPROVED'}
 }|ConvertTo-Json -Compress
}
if($SyntheticScenario -ne 'none'){
 $e=$SyntheticScenario -ceq 'matched'
 $owner=$SyntheticScenario -cne 'different-owner'
 $fresh=$SyntheticScenario -cne 'stale-event'
 Emit $true 'Running' $true $owner $fresh $e $true $true 'SYNTHETIC_ONLY'
 return
}
$state='UNKNOWN';$exact=$false;$owners=$false;$live=$false;$event=$false
$markerAbsent=$false;$restartRisk=$true;$evtStatus='NOT_REACHED'
try{
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
 $name='Geumyi Day10 Velocity wild'
 $task=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
 $state=[string]$task.State
 $actions=@($task.Actions|Where-Object {$null -ne $_})
 if($actions.Count -ne 1){throw 'ACTION_COUNT'}
 $action=$actions[0]
 $exe=[string]$action.Execute;$args=[string]$action.Arguments
 $dir=[string]$action.WorkingDirectory
 $expected=Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer\wild'
 $exact=([IO.Path]::IsPathRooted($exe) -and [IO.Path]::IsPathRooted($dir) -and
   [IO.Path]::GetFileName($exe) -ieq 'java.exe' -and
   [IO.Path]::GetFullPath($dir) -ieq [IO.Path]::GetFullPath($expected) -and
   $args -match '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)' -and
   (Test-Path -LiteralPath $exe -PathType Leaf))
 $restartRisk=([int]$task.Settings.RestartCount -gt 0)
 $marker=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged\Recovery\wild.active.json'
 $markerAbsent=-not(Test-Path -LiteralPath $marker)
 if($state -ne 'Running' -or -not $exact){throw 'TASK_NOT_RUNNING'}
 $tcp=@(Get-NetTCPConnection -LocalPort 25565 -State Listen -ErrorAction Stop | Where-Object {$_.OwningProcess -gt 0} | Select-Object -ExpandProperty OwningProcess -Unique)
 $udp=@(Get-NetUDPEndpoint -LocalPort 19132 -ErrorAction Stop | Where-Object {$_.OwningProcess -gt 0} | Select-Object -ExpandProperty OwningProcess -Unique)
 $owners=($tcp.Count -eq 1 -and $udp.Count -eq 1 -and [int]$tcp[0] -eq [int]$udp[0])
 if(-not $owners){throw 'PORT_OWNER_AMBIGUOUS'}
 $pidValue=[int]$tcp[0]
 $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+$pidValue) -ErrorAction Stop
 if($null -eq $proc -or -not $proc.ExecutablePath -or -not $proc.CreationDate){throw 'PROCESS_DETAILS_UNAVAILABLE'}
 $live=([IO.Path]::GetFullPath([string]$proc.ExecutablePath) -ieq [IO.Path]::GetFullPath($exe))
 if(-not $live){throw 'TASK_ACTION_AND_PROCESS_DIFFER'}
 # Event 129 gives task-to-created-process evidence; EnginePID alone does not.
 $born=([datetime]$proc.CreationDate).ToUniversalTime()
 $evtStatus='HISTORY_ABSENT_OR_NO_MATCH'
 $events=@()
 try{$events=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational';Id=129;StartTime=$born.ToLocalTime().AddSeconds(-30)} -MaxEvents 4096 -ErrorAction Stop)}
 catch{$evtStatus='HISTORY_UNAVAILABLE'}
 foreach($row in $events){
  try{
   [xml]$x=$row.ToXml()
   $tn=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='TaskName']")
   $pn=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='Path']")
   $idn=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='ProcessID']")
   if($null -eq $tn -or $null -eq $pn -or $null -eq $idn){continue}
   $parsedPid=0
   if(-not [int]::TryParse([string]$idn.InnerText,[ref]$parsedPid)){continue}
   $when=([datetime]$row.TimeCreated).ToUniversalTime()
   if([string]$tn.InnerText -cne ('\'+$name) -or $parsedPid -ne $pidValue -or
     [IO.Path]::GetFullPath([string]$pn.InnerText) -ine [IO.Path]::GetFullPath($exe) -or
     [math]::Abs(($born-$when).TotalSeconds) -gt 20){continue}
   $event=$true;$evtStatus='MATCHED_EVENT_129';break
  }catch{continue}
 }
 $later=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
 if([string]$later.State -ne 'Running'){throw 'TASK_STATE_DRIFT'}
}catch{
 # Fail closed; neither private paths nor raw process/event data leave host.
}
Emit $false $state $exact $owners $live $event $markerAbsent $restartRisk $evtStatus
