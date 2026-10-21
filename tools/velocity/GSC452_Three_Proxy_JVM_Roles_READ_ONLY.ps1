#requires -Version 5.1
[CmdletBinding()]
param([switch]$Synthetic)
# PRIVATE PROCESS METADATA IS NEVER PRINTED. READ ONLY; NO STOP/START/DISABLE.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$targets=@('wild','playground','other')
$ports=@{wild=@(25565,19132);playground=@(25566,19133);other=@(25567,19134)}
function Bucket([int]$n){
 if($n -lt 0){return 'UNVERIFIED'}
 if($n -eq 0){return 'ZERO'}
 if($n -eq 1){return 'ONE'}
 return 'MULTIPLE'
}
function JarClass([string]$cmd) {
 if([string]::IsNullOrWhiteSpace($cmd)){return 'COMMANDLINE_UNAVAILABLE'}
 $m=[regex]::Match($cmd,'(?i)(?:^|\s)-jar\s+(?:"([^"]+)"|([^\s"]+))')
 if(-not $m.Success){return 'NO_RECOGNIZED_JAR'}
 $arg=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
 $file=[IO.Path]::GetFileName($arg)
 if($file -ieq 'velocity.jar'){return 'VELOCITY_JAR'}
 if($file -match '(?i)^geyser.*\.jar$'){return 'GEYSER_STANDALONE_JAR'}
 if($file -match '(?i)^(?:paper|purpur|spigot|minecraft_server|server)\b.*\.jar$'){return 'MINECRAFT_SERVER_JAR'}
 return 'OTHER_JAR'
}
function ExactJava([string]$value,[string]$exe) {
 if([string]::IsNullOrWhiteSpace($value) -or [string]::IsNullOrWhiteSpace($exe)){return $false}
 try{return ([IO.Path]::GetFullPath($value) -ieq [IO.Path]::GetFullPath($exe))}catch{return $false}
}
function EventIndex(){
 try{return [pscustomobject]@{
  status='AVAILABLE'
  rows=@(Get-WinEvent -FilterHashtable @{
   LogName='Microsoft-Windows-TaskScheduler/Operational'
   Id=129
   StartTime=(Get-Date).AddDays(-14)
  } -MaxEvents 2048 -ErrorAction Stop)
 }}catch{return [pscustomobject]@{status='UNAVAILABLE_OR_NO_EVENTS';rows=@()}}
}
function EventAttestation([int]$pidValue,[string]$task,[string]$exe,[datetime]$born,$history){
 if($history.status -ne 'AVAILABLE'){return 'HISTORY_UNAVAILABLE'}
 foreach($event in $history.rows) {
  try{
   [xml]$xml=$event.ToXml()
   $taskField=$xml.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='TaskName']")
   $pidField=$xml.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='ProcessID']")
   $pathField=$xml.SelectSingleNode("//*[local-name()='EventData']/*[local-name()='Data' and @Name='Path']")
   if($null -eq $taskField -or $null -eq $pidField -or $null -eq $pathField){continue}
   $eventPid=0
   if(-not [int]::TryParse([string]$pidField.InnerText,[ref]$eventPid)){continue}
   if([string]$taskField.InnerText -ine ('\Geumyi Day10 Velocity '+$task) -or
      $eventPid -ne $pidValue -or
      -not(ExactJava ([string]$pathField.InnerText) $exe) -or
      [math]::Abs(($born-([datetime]$event.TimeCreated).ToUniversalTime()).TotalSeconds) -gt 30){continue}
   return 'MATCHED_TASK_AND_LIVE_PROCESS'
  }catch{continue}
 }
 return 'NOT_ATTESTED'
}
function Emit($data) {
 $data.read_only=$true
 $data.service_mutations=0
 $data.task_mutations=0
 $data.java_operations=0
 $data.task_to_jvm_ownership_proven=$false
 $data.legacy_stdin_access_proven=$false
 $data.safe_to_stop=$false
 $data.safe_to_cutover=$false
 $data.live_control_authorized=$false
 $data|ConvertTo-Json -Depth 6 -Compress
}
$r=[ordered]@{
 schema=5;check='GSC452_THREE_PROXY_JVM_ROLE_INVENTORY_READ_ONLY'
 synthetic=[bool]$Synthetic
 all_target_tcp_ports='UNVERIFIED'
 all_target_udp_ports='UNVERIFIED'
 scheduler_history='UNVERIFIED'
 scheduled_tasks=@()
 udp_owners=@()
 status='INCOMPLETE_NO_ACTION'
}
if($Synthetic){
 $r.all_target_tcp_ports='ZERO_LISTENERS'
 $r.all_target_udp_ports='THREE_UNIQUE'
 $r.scheduler_history='SYNTHETIC'
 foreach($id in $targets){
  $r.scheduled_tasks+=@([ordered]@{
   target=$id;task_state='Running';task_launcher='MATCH'
   last_run_result='RUNNING_OR_SUCCESS'
   matching_velocity_java_candidates='ONE'
   matching_candidate_tcp_listener_count='ZERO'
   scheduler_event_129='SYNTHETIC_UNATTESTED'
  })
  $r.udp_owners+=@([ordered]@{
   target=$id;port=($ports[$id][1]);owner_count='ONE'
   executable_class='OTHER_JAVA_INSTALLATION'
   jar_class='MINECRAFT_SERVER_JAR'
  })
 }
 $r.status='SYNTHETIC_NO_ACTION'
 Emit $r;return
}
try{
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
 # Metadata is held only in memory, never included in the report.
 $processes=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
 $byPid=@{}
 foreach($p in $processes){$byPid[[int]$p.ProcessId]=$p}
 $tcp=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
 $udp=@(Get-NetUDPEndpoint -ErrorAction Stop)
 $history=EventIndex
 $r.scheduler_history=$history.status
 $tcpTotals=0
 $udpOwnerPid=@()
 foreach($id in $targets){
  $taskName='Geumyi Day10 Velocity '+$id
  $state='UNKNOWN';$shape='UNVERIFIED';$taskJava=''
  $lastResult='UNVERIFIED';$candidates=@()
  $eventStatus='NOT_CHECKED';$listenCount='UNVERIFIED'
  $task=Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction Stop
  $state=[string]$task.State
  $acts=@($task.Actions|Where-Object {$null -ne $_})
  if($acts.Count -eq 1){
   $work=[string]$acts[0].WorkingDirectory
   $taskJava=[string]$acts[0].Execute
   $expected=Join-Path $env:ProgramData ('GeumyiServerCenter\Network\FourServer\'+$id)
   $shape=if([IO.Path]::IsPathRooted($work) -and
    [IO.Path]::IsPathRooted($taskJava) -and
    [IO.Path]::GetFullPath($work) -ieq [IO.Path]::GetFullPath($expected) -and
    [IO.Path]::GetFileName($taskJava) -ieq 'java.exe' -and
    [string]$acts[0].Arguments -match '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)'){'MATCH'}else{'UNVERIFIED_OR_DIFFERENT'}
  }else{$shape='UNVERIFIED_OR_DIFFERENT'}
  try{
   $info=Get-ScheduledTaskInfo -TaskPath '\' -TaskName $taskName -ErrorAction Stop
   $code=[int64]$info.LastTaskResult
   $lastResult=if($code -in @(0,267009)){'RUNNING_OR_SUCCESS'}elseif($code -eq 267011){'NOT_YET_RUN'}else{'OTHER_OR_FAILURE'}
  }catch{$lastResult='UNVERIFIED'}
  if($shape -eq 'MATCH'){
   $candidates=@($processes|Where-Object {
     (ExactJava ([string]$_.ExecutablePath) $taskJava) -and
     (JarClass ([string]$_.CommandLine)) -eq 'VELOCITY_JAR'
   })
  }
  if($candidates.Count -eq 1){
   $only=$candidates[0]
   $listenCount=Bucket @($tcp|Where-Object {$_.OwningProcess -eq $only.ProcessId}).Count
   $eventStatus=if($null -ne $only.CreationDate){
    EventAttestation ([int]$only.ProcessId) $id $taskJava ([datetime]$only.CreationDate).ToUniversalTime() $history
   }else{'PROCESS_START_UNKNOWN'}
  }elseif($candidates.Count -gt 1){$listenCount='AMBIGUOUS_MULTIPLE_JVMS';$eventStatus='AMBIGUOUS_CANDIDATES'}
  else{$listenCount='NO_CANDIDATE';$eventStatus='NO_CANDIDATE'}
  $r.scheduled_tasks+=@([ordered]@{
   target=$id;task_state=$state;task_launcher=$shape
   last_run_result=$lastResult
   matching_velocity_java_candidates=Bucket $candidates.Count
   matching_candidate_tcp_listener_count=$listenCount
   scheduler_event_129=$eventStatus
  })
  $javaPort=[int]$ports[$id][0]
  $tcpTotals+=@($tcp|Where-Object {$_.LocalPort -eq $javaPort}).Count
  $bedrockPort=[int]$ports[$id][1]
  $owners=[int[]]@($udp|Where-Object {$_.LocalPort -eq $bedrockPort -and $_.OwningProcess -gt 0}|
    Select-Object -ExpandProperty OwningProcess -Unique)
  foreach($owner in $owners){$udpOwnerPid+=@($owner)}
  $image='UNVERIFIED';$jar='UNVERIFIED'
  if($owners.Count -eq 1){
   $one=$byPid[[int]$owners[0]]
   if($null -eq $one){
    try{$one=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$owners[0]) -ErrorAction Stop}catch{}
   }
   if($null -ne $one){
    $image=if($one.ExecutablePath -and (ExactJava ([string]$one.ExecutablePath) $taskJava)){'TASK_JAVA_EXACT'}elseif([IO.Path]::GetFileName([string]$one.ExecutablePath) -ieq 'java.exe'){'OTHER_JAVA_INSTALLATION'}elseif([IO.Path]::GetFileName([string]$one.ExecutablePath) -ieq 'javaw.exe'){'JAVA_WINDOWLESS'}else{'NON_JAVA_OR_UNKNOWN'}
    $jar=JarClass ([string]$one.CommandLine)
   }else{$image='PROCESS_METADATA_UNAVAILABLE';$jar='PROCESS_METADATA_UNAVAILABLE'}
  }
  $r.udp_owners+=@([ordered]@{
   target=$id;port=$bedrockPort;owner_count=Bucket $owners.Count
   executable_class=$image;jar_class=$jar
  })
 }
 $r.all_target_tcp_ports=if($tcpTotals -eq 0){'ZERO_LISTENERS'}else{'SOME_LISTENERS'}
 $r.all_target_udp_ports=if($udpOwnerPid.Count -eq 3){
  if(@($udpOwnerPid|Sort-Object -Unique).Count -eq 3){'THREE_DISTINCT_OWNERS'}else{'SOME_SHARED_OWNERS'}
 }else{'NOT_THREE_UNIQUE_ENDPOINT_OWNERS'}
 $r.status='PROCESS_ROLE_EVIDENCE_CAPTURED_NO_ACTION'
}catch{$r.status='PARTIAL_EVIDENCE_NO_ACTION'}
Emit $r
