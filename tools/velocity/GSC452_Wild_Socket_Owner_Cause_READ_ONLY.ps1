#requires -Version 5.1
[CmdletBinding()]
param(
 [ValidateSet('none','tcp-no-listener','tcp-fallback','split-owners','other-java','non-java-udp','matching')]
 [string]$SyntheticScenario='none'
)
# READ-ONLY. No raw PID, paths, arguments, task XML, events or secrets leave host.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function CountClass([int[]]$values) {
 switch(@($values).Count){0{'ZERO'} 1{'ONE'} default{'MULTIPLE'}}
}
function PidSet([object[]]$values) {
 return [int[]]@($values | Where-Object { $null -ne $_ -and [int]$_ -gt 0 } |
   ForEach-Object {[int]$_} | Sort-Object -Unique)
}
function ClassifyExecutable([string]$image,[string]$expected) {
 if([string]::IsNullOrWhiteSpace($image)){return 'PROCESS_IMAGE_UNAVAILABLE'}
 $file=[IO.Path]::GetFileName($image)
 if($file -ieq 'java.exe') {
  if(-not [string]::IsNullOrWhiteSpace($expected) -and
    [IO.Path]::GetFullPath($image) -ieq [IO.Path]::GetFullPath($expected)) {
    return 'TASK_JAVA_EXACT'
  }
  return 'JAVA_OTHER_LOCATION'
 }
 if($file -ieq 'javaw.exe'){return 'JAVA_WINDOWLESS'}
 return 'NON_JAVA_EXECUTABLE'
}
function Output($row) {
 $row.read_only=$true
 $row.safe_to_stop=$false
 $row.safe_to_cutover=$false
 $row.live_control_authorized=$false
 $row.task_to_jvm_identity_proven=$false
 $row.legacy_console_stdin_control_proven=$false
 $row.scheduled_task_modified=$false
 $row.java_operations=0
 $row|ConvertTo-Json -Compress -Depth 4
}
$row=[ordered]@{
 schema=3
 check='GSC452_WILD_SOCKET_OWNER_CAUSE_READ_ONLY'
 target='wild'
 synthetic=($SyntheticScenario -ne 'none')
 task_state='UNKNOWN'
 task_java_action_verified=$false
 scheduler_restart_risk='UNKNOWN'
 owner_generation_marker_absent=$false
 tcp_powershell_inventory='NOT_CHECKED'
 tcp_netstat_inventory='NOT_CHECKED'
 tcp_owner_sources_agree='UNVERIFIED'
 tcp_25565_owner_count='UNVERIFIED'
 udp_19132_inventory='NOT_CHECKED'
 udp_19132_owner_count='UNVERIFIED'
 tcp_udp_owner_relation='UNVERIFIED'
 tcp_owner_executable_class='NOT_CHECKED'
 udp_owner_executable_class='NOT_CHECKED'
 scheduler_event_129_tcp_owner='NOT_CHECKED'
 status='READ_ONLY_INCOMPLETE_NO_ACTION'
}
if($SyntheticScenario -ne 'none'){
 $row.task_state='Running'
 $row.task_java_action_verified=$true
 $row.scheduler_restart_risk='PRESENT'
 $row.owner_generation_marker_absent=$true
 $row.tcp_powershell_inventory='OBSERVED'
 $row.tcp_netstat_inventory='OBSERVED'
 $row.tcp_owner_sources_agree='YES'
 $row.tcp_25565_owner_count='ONE'
 $row.udp_19132_inventory='OBSERVED'
 $row.udp_19132_owner_count='ONE'
 $row.tcp_udp_owner_relation='SAME_PID'
 $row.tcp_owner_executable_class='TASK_JAVA_EXACT'
 $row.udp_owner_executable_class='TASK_JAVA_EXACT'
 switch($SyntheticScenario){
  'tcp-no-listener'{
   $row.tcp_powershell_inventory='NO_LISTENER';$row.tcp_netstat_inventory='NO_LISTENER'
   $row.tcp_25565_owner_count='ZERO';$row.tcp_udp_owner_relation='TCP_NO_LOCAL_LISTENER'
   $row.tcp_owner_executable_class='NOT_CHECKED'
  }
  'tcp-fallback'{$row.tcp_powershell_inventory='QUERY_FAILED';$row.tcp_owner_sources_agree='UNVERIFIED'}
  'split-owners'{$row.tcp_udp_owner_relation='DIFFERENT_PID'}
  'other-java'{$row.udp_owner_executable_class=ClassifyExecutable 'C:\Other\jdk\bin\java.exe' 'C:\Expected\bin\java.exe'}
  'non-java-udp'{$row.udp_owner_executable_class=ClassifyExecutable 'C:\Windows\System32\svchost.exe' 'C:\Expected\bin\java.exe'}
 }
 $row.status='SYNTHETIC_NO_ACTION'
 Output $row;return
}
function TcpPowerShell {
 try {
  # Avoid -LocalPort with -ErrorAction Stop: no matching socket can itself
  # raise a CIM "not found" error, hiding a legitimate zero-listener result.
  $all=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
  $hits=@($all|Where-Object {[int]$_.LocalPort -eq 25565})
  return [pscustomobject]@{
   status=if($hits.Count){'OBSERVED'}else{'NO_LISTENER'}
   owners=(PidSet @($hits|Select-Object -ExpandProperty OwningProcess))
  }
 }catch{
  return [pscustomobject]@{status='QUERY_FAILED';owners=[int[]]@()}
 }
}
function TcpNetstat {
 try {
  $exe=Join-Path $env:SystemRoot 'System32\netstat.exe'
  $lines=@(& $exe -ano -p tcp 2>$null)
  if($LASTEXITCODE -ne 0){throw 'NETSTAT_UNAVAILABLE'}
  $found=New-Object 'System.Collections.Generic.List[int]'
  foreach($line in $lines){
   $m=[regex]::Match([string]$line,'(?i)^\s*TCP\s+(\S+)\s+\S+\s+LISTENING\s+(\d+)\s*$')
   if(-not $m.Success){continue}
   if(-not $m.Groups[1].Value.EndsWith(':25565')){continue}
   $id=0
   if([int]::TryParse($m.Groups[2].Value,[ref]$id) -and $id -gt 0){$found.Add($id)}
  }
  return [pscustomobject]@{
   status=if($found.Count){'OBSERVED'}else{'NO_LISTENER'}
   owners=(PidSet @($found.ToArray()))
  }
 }catch{
  return [pscustomobject]@{status='QUERY_FAILED';owners=[int[]]@()}
 }
}
function UdpPowerShell {
 try{
  $all=@(Get-NetUDPEndpoint -ErrorAction Stop)
  $hits=@($all|Where-Object {[int]$_.LocalPort -eq 19132})
  return [pscustomobject]@{
   status=if($hits.Count){'OBSERVED'}else{'NO_ENDPOINT'}
   owners=(PidSet @($hits|Select-Object -ExpandProperty OwningProcess))
  }
 }catch{
  return [pscustomobject]@{status='QUERY_FAILED';owners=[int[]]@()}
 }
}
function ImageEvidence([int]$id,[string]$taskExe) {
 try {
  $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$id) -ErrorAction Stop
  if($null -eq $p -or -not $p.ExecutablePath -or -not $p.CreationDate) {
   return [pscustomobject]@{status='PROCESS_METADATA_UNAVAILABLE';birth=$null}
  }
  return [pscustomobject]@{
   status=(ClassifyExecutable ([string]$p.ExecutablePath) $taskExe)
   birth=([datetime]$p.CreationDate).ToUniversalTime()
  }
 }catch {
  return [pscustomobject]@{status='PROCESS_QUERY_FAILED';birth=$null}
 }
}
function EventEvidence([int]$id,[string]$task,[string]$image,[datetime]$born) {
 try {
  $events=@(Get-WinEvent -FilterHashtable @{
   LogName='Microsoft-Windows-TaskScheduler/Operational'
   Id=129
   StartTime=$born.ToLocalTime().AddSeconds(-30)
  } -MaxEvents 4096 -ErrorAction Stop)
 }catch{return 'HISTORY_UNAVAILABLE'}
 $seen=$false
 foreach($e in $events){
  try{
   [xml]$x=$e.ToXml()
   $n=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='TaskName']")
   $p=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='ProcessID']")
   $path=$x.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='Path']")
   if($null -eq $n -or $null -eq $p -or $null -eq $path){continue}
   $seen=$true
   $parsed=0
   if(-not [int]::TryParse([string]$p.InnerText,[ref]$parsed)){continue}
   if([string]$n.InnerText -ine ('\'+$task) -or $parsed -ne $id -or
      [IO.Path]::GetFullPath([string]$path.InnerText) -ine [IO.Path]::GetFullPath($image) -or
      [math]::Abs(($born-([datetime]$e.TimeCreated).ToUniversalTime()).TotalSeconds) -gt 20){continue}
   return 'MATCHED_SCHEDULER_TASK_PROCESS'
  }catch{continue}
 }
 if($seen){return 'NO_MATCHING_TASK_EVENT'}
 return 'EVENT_FIELDS_OR_HISTORY_UNAVAILABLE'
}
try{
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
 $taskName='Geumyi Day10 Velocity wild'
 $task=Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction Stop
 $row.task_state=[string]$task.State
 $acts=@($task.Actions|Where-Object {$null -ne $_})
 if($acts.Count -ne 1){throw 'TASK_ACTION_COUNT'}
 $a=$acts[0]
 $exe=[string]$a.Execute;$work=[string]$a.WorkingDirectory
 $expected=Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer\wild'
 $row.task_java_action_verified=([IO.Path]::IsPathRooted($exe) -and
   [IO.Path]::IsPathRooted($work) -and
   [IO.Path]::GetFileName($exe) -ieq 'java.exe' -and
   [IO.Path]::GetFullPath($work) -ieq [IO.Path]::GetFullPath($expected) -and
   [string]$a.Arguments -match '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)' -and
   (Test-Path -LiteralPath $exe -PathType Leaf))
 $row.scheduler_restart_risk=if([int]$task.Settings.RestartCount -gt 0){'PRESENT'}else{'NOT_OBSERVED'}
 $mark=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged\Recovery\wild.active.json'
 $row.owner_generation_marker_absent=-not(Test-Path -LiteralPath $mark)
 if(-not $row.task_java_action_verified){throw 'UNTRUSTED_TASK_ACTION'}
 $first=TcpPowerShell
 $second=TcpNetstat
 $udp=UdpPowerShell
 $row.tcp_powershell_inventory=$first.status
 $row.tcp_netstat_inventory=$second.status
 $row.udp_19132_inventory=$udp.status
 $row.udp_19132_owner_count=if($udp.status -eq 'QUERY_FAILED'){'UNVERIFIED'}else{CountClass $udp.owners}
 $tcp=[int[]]@()
 if($first.status -ne 'QUERY_FAILED' -and $second.status -ne 'QUERY_FAILED'){
  $row.tcp_owner_sources_agree=if((@($first.owners)-join ',') -ceq (@($second.owners)-join ',')){'YES'}else{'NO'}
  if($row.tcp_owner_sources_agree -eq 'YES'){$tcp=$first.owners}
 }elseif($first.status -ne 'QUERY_FAILED'){$tcp=$first.owners}
 elseif($second.status -ne 'QUERY_FAILED'){$tcp=$second.owners}
 $row.tcp_25565_owner_count=if($first.status -eq 'QUERY_FAILED' -and $second.status -eq 'QUERY_FAILED'){'UNVERIFIED'}elseif($row.tcp_owner_sources_agree -eq 'NO'){'INCONSISTENT'}else{CountClass $tcp}
 if($row.tcp_25565_owner_count -eq 'ONE' -and $row.udp_19132_owner_count -eq 'ONE'){
  $row.tcp_udp_owner_relation=if($tcp[0] -eq $udp.owners[0]){'SAME_PID'}else{'DIFFERENT_PID'}
 }elseif($row.tcp_25565_owner_count -eq 'ZERO' -and $row.udp_19132_owner_count -eq 'ONE'){
  $row.tcp_udp_owner_relation='TCP_NO_LOCAL_LISTENER'
 }else{$row.tcp_udp_owner_relation='INSUFFICIENT_OR_UNVERIFIED_OWNERS'}
 if($row.tcp_25565_owner_count -eq 'ONE'){
  $p=ImageEvidence $tcp[0] $exe
  $row.tcp_owner_executable_class=$p.status
  if($p.status -eq 'TASK_JAVA_EXACT' -and $null -ne $p.birth){
   $row.scheduler_event_129_tcp_owner=EventEvidence $tcp[0] $taskName $exe $p.birth
  }
 }
 if($row.udp_19132_owner_count -eq 'ONE'){
  $row.udp_owner_executable_class=(ImageEvidence $udp.owners[0] $exe).status
 }
 $again=Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction Stop
 if([string]$again.State -ne [string]$row.task_state){throw 'TASK_STATE_CHANGED'}
 $row.status='READ_ONLY_SOCKET_CAUSE_CAPTURED_NO_ACTION'
}catch{
 $row.status='READ_ONLY_PARTIAL_OR_ERROR_NO_ACTION'
}
Output $row
