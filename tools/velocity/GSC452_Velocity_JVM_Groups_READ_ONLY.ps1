#requires -Version 5.1
[CmdletBinding()]
param(
 [ValidateSet('none','disjoint','overlap','partial-overlap','shared-owner','missing-udp','tcp-active','metadata-missing','no-candidates')]
 [string]$Fixture='none'
)
# V6.2 permission-hardened (schema 7 compatible). READ ONLY.
# This diagnostic NEVER provides task->JVM attribution or stop authority.
# Raw task XML, private paths, PIDs, process command lines, secrets and logs
# are NEVER serialized. Fixtures exercise the SAME analysis as live snapshots.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$script:phase='PREFLIGHT'
$script:resultCode=0

function CountLabel([int]$value) {
 if($value -lt 0){return 'UNVERIFIED'}
 if($value -eq 0){return 'ZERO'}
 if($value -eq 1){return 'ONE'}
 if($value -eq 2){return 'TWO'}
 if($value -eq 3){return 'THREE'}
 return 'MORE_THAN_THREE'
}
function PathEquals([string]$a,[string]$b) {
 if([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)){return $false}
 try{return [IO.Path]::GetFullPath($a) -ieq [IO.Path]::GetFullPath($b)}
 catch{return $false}
}
function VelocityJarCommand([string]$cmd) {
 if([string]::IsNullOrWhiteSpace($cmd)){return $false}
 $m=[regex]::Match($cmd,'(?i)(?:^|\s)-jar\s+(?:"([^"]+)"|([^\s"]+))')
 if(-not $m.Success){return $false}
 $jar=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
 return [IO.Path]::GetFileName($jar) -ieq 'velocity.jar'
}
function ProcessImageClass($p,[string]$expectedJava) {
 if($null -eq $p){return 'METADATA_UNAVAILABLE'}
 $exe=[string]$p.ExecutablePath
 if([string]::IsNullOrWhiteSpace($exe)){return 'METADATA_UNAVAILABLE'}
 if(PathEquals $exe $expectedJava){return 'TASK_JAVA_EXACT'}
 $leaf=[IO.Path]::GetFileName($exe)
 if($leaf -ieq 'java.exe'){return 'JAVA_OTHER_LOCATION'}
 if($leaf -ieq 'javaw.exe'){return 'JAVA_WINDOWLESS'}
 return 'OTHER_EXECUTABLE'
}
function Owners($rows,[int]$port) {
 return ,([int[]]@($rows|Where-Object {
  [int]$_.LocalPort -eq $port -and [int]$_.OwningProcess -gt 0
 }|ForEach-Object {[int]$_.OwningProcess}|Sort-Object -Unique))
}
function Emit($r) {
 $r.read_only=$true
 $r.task_mutations=0
 $r.service_mutations=0
 $r.java_operations=0
 $r.task_to_jvm_ownership_proven=$false
 $r.legacy_stdin_access_proven=$false
 $r.safe_to_stop=$false
 $r.safe_to_cutover=$false
 $r.live_control_authorized=$false
 $r|ConvertTo-Json -Compress -Depth 7
}
function EmptyResult([bool]$synthetic) {
 return [ordered]@{
  schema=7
  diagnostic_revision='6.2-permissions'
  check='GSC452_VELOCITY_JVM_GROUP_SEPARATION_VERIFIED_READ_ONLY'
  synthetic=$synthetic
  execution_elevated='NOT_CHECKED'
  programdata_path_check='NOT_CHECKED'
  process_metadata_completeness='NOT_CHECKED'
  failure_phase='NONE'
  failure_class='NONE'
  task_states=@()
  scheduled_java_profiles_shared='UNVERIFIED'
  candidate_velocity_java_unique='UNVERIFIED'
  candidate_jvms_with_tcp_listeners='UNVERIFIED'
  candidate_jvms_with_known_udp='UNVERIFIED'
  known_tcp_listeners=@()
  udp_three_distinct_owner_pids='UNVERIFIED'
  udp_owner_overlap_with_launcher_candidates='UNVERIFIED'
  udp_owners=@()
  snapshot_task_states_unchanged='UNVERIFIED'
  status='INCOMPLETE_NO_ACTION'
 }
}
function Analyze($snap,$report) {
 $targets=@('wild','playground','other')
 $udpPorts=@(19132,19133,19134)
 $tcpPorts=@(25565,25566,25567)
 $tasksByTarget=@{}
 $profiles=@()
 foreach($id in $targets) {
  $hits=@($snap.tasks|Where-Object {$_.target -ceq $id})
  if($hits.Count -ne 1){throw 'TASK_COUNT_INVALID'}
  $t=$hits[0]
  $expected=Join-Path $snap.programData ('GeumyiServerCenter\Network\FourServer\'+$id)
  $valid=([IO.Path]::IsPathRooted([string]$t.executable) -and
    [IO.Path]::IsPathRooted([string]$t.workdir) -and
    [IO.Path]::GetFileName([string]$t.executable) -ieq 'java.exe' -and
    (PathEquals ([string]$t.workdir) $expected) -and
    [string]$t.arguments -match '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)' -and
    $t.executable_exists -eq $true)
  $report.task_states+=@([ordered]@{
   target=$id;state=[string]$t.state
   launch_shape=if($valid){'MATCH'}else{'NOT_VERIFIED'}
   scheduler_auto_restart=if([int]$t.restartCount -gt 0){'PRESENT'}else{'NOT_OBSERVED'}
  })
  if(-not $valid){throw 'SCHEDULER_LAUNCH_PROFILE_UNVERIFIED'}
  $profiles+=@([string]$t.executable)
  $tasksByTarget[$id]=$t
 }
 $report.scheduled_java_profiles_shared=if(
  (PathEquals $profiles[0] $profiles[1]) -and
  (PathEquals $profiles[0] $profiles[2])
 ){'YES'}else{'NO'}
 $procs=@{}
 foreach($p in @($snap.processes)){
  if($null -eq $p.ProcessId){continue}
  $id=[int]$p.ProcessId
  if($id -gt 0 -and -not $procs.ContainsKey($id)){$procs[$id]=$p}
 }
 $candidate=@{}
 foreach($p in @($snap.processes)){
  if($null -eq $p.ProcessId){continue}
  $pidValue=[int]$p.ProcessId
  if($pidValue -le 0 -or [string]$p.Name -ine 'java.exe' -or
     -not (VelocityJarCommand ([string]$p.CommandLine))){continue}
  $sameJava=$false
  foreach($j in $profiles){
   if(PathEquals ([string]$p.ExecutablePath) $j){$sameJava=$true;break}
  }
  if($sameJava){$candidate[$pidValue]=$true}
 }
 $report.candidate_velocity_java_unique=CountLabel $candidate.Count
 $candidateWithTcp=0;$candidateWithUdp=0
 foreach($candidatePid in @($candidate.Keys)){
  $p=[int]$candidatePid
  if(@($snap.tcp|Where-Object {[int]$_.OwningProcess -eq $p}).Count -gt 0){$candidateWithTcp++}
  if(@($snap.udp|Where-Object {
   [int]$_.OwningProcess -eq $p -and
   [int]$_.LocalPort -in $udpPorts
  }).Count -gt 0){$candidateWithUdp++}
 }
 $report.candidate_jvms_with_tcp_listeners=CountLabel $candidateWithTcp
 $report.candidate_jvms_with_known_udp=CountLabel $candidateWithUdp
 foreach($port in $tcpPorts){
  $pidSet=Owners $snap.tcp $port
  $report.known_tcp_listeners+=@([ordered]@{
   port=$port;unique_owner_count=CountLabel $pidSet.Count
  })
 }
 $udpIds=@();$complete=$true;$verifiedMetadata=$true;$overlapCount=0
 for($i=0;$i -lt 3;$i++){
  $id=$targets[$i];$port=$udpPorts[$i]
  $pidSet=Owners $snap.udp $port
  $row=[ordered]@{
   target=$id;port=$port;unique_owner_count=CountLabel $pidSet.Count
   jar_class='UNVERIFIED';image_class='UNVERIFIED'
   owns_any_tcp_listener='UNVERIFIED'
  }
  if($pidSet.Count -ne 1){$complete=$false}
  else {
   $pidValue=[int]$pidSet[0]
   $udpIds+=@($pidValue)
   $p=$procs[$pidValue]
   if($null -eq $p){$verifiedMetadata=$false}
   else {
    $row.jar_class=if(VelocityJarCommand ([string]$p.CommandLine)){'VELOCITY_JAR'}else{'OTHER_OR_UNAVAILABLE'}
    $row.image_class=ProcessImageClass $p ([string]$tasksByTarget[$id].executable)
    $row.owns_any_tcp_listener=if(@($snap.tcp|Where-Object {
      [int]$_.OwningProcess -eq $pidValue
    }).Count -gt 0){'YES'}else{'NO'}
   }
   if($candidate.ContainsKey($pidValue)){$overlapCount++}
  }
  $report.udp_owners+=@($row)
 }
 if($complete -and $udpIds.Count -eq 3){
  $report.udp_three_distinct_owner_pids=if(@($udpIds|Sort-Object -Unique).Count -eq 3){'YES'}else{'NO'}
  if($verifiedMetadata -and $report.udp_three_distinct_owner_pids -eq 'YES'){
   $report.udp_owner_overlap_with_launcher_candidates=if($overlapCount -eq 0){'NONE'}elseif($overlapCount -eq 3){'ALL_THREE'}else{'SOME'}
  }
 }
 $report.snapshot_task_states_unchanged=[string]$snap.tasksStable
 $report.status=if([string]$snap.tasksStable -ceq 'YES'){'JVM_GROUPS_READ_ONLY_ANALYZED_NO_ACTION'}else{'INCONSISTENT_TASK_STATE_NO_ACTION'}
 $incomplete=@($snap.processes|Where-Object {($_.Name -ieq 'java.exe' -or $_.Name -ieq 'javaw.exe') -and ([string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -or [string]::IsNullOrWhiteSpace([string]$_.CommandLine))}).Count
 $report.process_metadata_completeness=if($incomplete -gt 0){'PARTIAL_JAVA_PROCESS_METADATA'}else{'NO_NULL_FIELDS_IN_VISIBLE_JAVA_PROCESSES'}
 if(-not $report.synthetic -and $incomplete -gt 0){$report.status='PARTIAL_JAVA_METADATA_NO_ACTION';$script:resultCode=2}
 if(-not $report.synthetic -and $report.snapshot_task_states_unchanged -cne 'YES'){$script:resultCode=2}
}
function FixtureSnapshot([string]$scenario) {
 $base='C:\ProgramData'
 $java='C:\RuntimeA\bin\java.exe'
 $tasks=@()
 $targets=@('wild','playground','other')
 foreach($id in $targets){
  $tasks+=@([pscustomobject]@{
   target=$id;state='Running';executable=$java
   executable_exists=$true
   workdir=('C:\ProgramData\GeumyiServerCenter\Network\FourServer\'+$id)
   arguments='-Xmx2G -jar velocity.jar'
   restartCount=999
  })
 }
 $processes=@()
 foreach($pidValue in @(101,102,103)){
  $processes+=@([pscustomobject]@{
   ProcessId=$pidValue;Name='java.exe';ExecutablePath=$java
   CommandLine='"C:\RuntimeA\bin\java.exe" -jar velocity.jar'
  })
 }
 $udpIds=[int[]]@(201,202,203)
 if($scenario -eq 'overlap'){$udpIds=[int[]]@(101,102,103)}
 if($scenario -eq 'partial-overlap'){$udpIds=[int[]]@(101,202,203)}
 if($scenario -eq 'shared-owner'){$udpIds=[int[]]@(201,201,203)}
 if($scenario -eq 'no-candidates'){
  $processes=@()
 }
 foreach($pidValue in @(201,202,203)){
  if($scenario -eq 'metadata-missing' -and $pidValue -eq 202){continue}
  $processes+=@([pscustomobject]@{
   ProcessId=$pidValue;Name='java.exe'
   ExecutablePath='C:\RuntimeB\bin\java.exe'
   CommandLine='"C:\RuntimeB\bin\java.exe" -jar velocity.jar'
  })
 }
 $tcp=@()
 if($scenario -eq 'tcp-active'){
  $tcp+=@([pscustomobject]@{LocalPort=25565;OwningProcess=101})
 }
 $udp=@()
 for($i=0;$i -lt 3;$i++){
  if($scenario -eq 'missing-udp' -and $i -eq 0){continue}
  $udp+=@([pscustomobject]@{LocalPort=(19132+$i);OwningProcess=$udpIds[$i]})
 }
 return [pscustomobject]@{
  programData=$base;tasks=@($tasks);processes=@($processes)
  tcp=@($tcp);udp=@($udp);tasksStable='YES'
 }
}
function RealSnapshot {
 $script:phase='PLATFORM_CHECK'
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
 $script:phase='TOKEN_CHECK'
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=[Security.Principal.WindowsPrincipal]::new($identity)
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
   $report.execution_elevated='NO';throw 'ELEVATION_REQUIRED'
 }
 $report.execution_elevated='YES'
 $script:phase='PROGRAMDATA_PATH_CHECK'
 $canonical=[Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)
 if([string]::IsNullOrWhiteSpace($env:ProgramData) -or [string]::IsNullOrWhiteSpace($canonical) -or -not (PathEquals $env:ProgramData $canonical)){
   $report.programdata_path_check='ENVIRONMENT_MISMATCH';throw 'PROGRAMDATA_MISMATCH'
 }
 $report.programdata_path_check='CANONICAL_MATCH'
 $taskFacts=@()
 foreach($id in @('wild','playground','other')){
  $name='Geumyi Day10 Velocity '+$id
  $script:phase='SCHEDULED_TASK_READ'
  $t=Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop
  $act=@($t.Actions|Where-Object {$null -ne $_})
  if($act.Count -ne 1){throw 'TASK_ACTION_AMBIGUOUS'}
  $exe=[string]$act[0].Execute
  $script:phase='WORKDIR_METADATA_READ'
  $workdir=Join-Path $env:ProgramData ('GeumyiServerCenter\Network\FourServer\'+$id)
  if(-not (Test-Path -LiteralPath $workdir -PathType Container -ErrorAction Stop)){throw 'WORKDIR_NOT_ACCESSIBLE'}
  $script:phase='SCHEDULED_TASK_READ'
  $taskFacts+=@([pscustomobject]@{
   target=$id;state=[string]$t.State;executable=$exe
   executable_exists=(Test-Path -LiteralPath $exe -PathType Leaf)
   workdir=[string]$act[0].WorkingDirectory
   arguments=[string]$act[0].Arguments
   restartCount=[int]$t.Settings.RestartCount
  })
 }
 $script:phase='JAVA_CIM_QUERY'
 $java=@(Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe'" -ErrorAction Stop)
 $script:phase='TCP_LISTENER_QUERY'
 $tcp=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
 $script:phase='UDP_ENDPOINT_QUERY'
 $udp=@(Get-NetUDPEndpoint -ErrorAction Stop)
 $stable='YES'
 $script:phase='SCHEDULED_TASK_STABILITY_CHECK'
 foreach($t in $taskFacts){
  $again=Get-ScheduledTask -TaskPath '\' -TaskName ('Geumyi Day10 Velocity '+$t.target) -ErrorAction Stop
  if([string]$again.State -cne [string]$t.state){$stable='NO'}
 }
 return [pscustomobject]@{
  programData=$env:ProgramData;tasks=@($taskFacts)
  processes=@($java);tcp=@($tcp);udp=@($udp);tasksStable=$stable
 }
}
$report=EmptyResult ($Fixture -ne 'none')
try {
 $snapshot=if($Fixture -ne 'none'){FixtureSnapshot $Fixture}else{RealSnapshot}
 $script:phase='ANALYSIS'
 Analyze $snapshot $report
}catch {
 # Never print exception message, paths, PIDs, command lines, task XML or stack.
 $report.status='INCOMPLETE_NO_ACTION'
 $report.failure_phase=$script:phase
 $ex=$_.Exception
 $code=[int64]$ex.HResult
 if($ex.Message -ceq 'ELEVATION_REQUIRED'){
   $report.failure_class='ELEVATION_REQUIRED';$script:resultCode=3
 }elseif($ex.Message -ceq 'PROGRAMDATA_MISMATCH'){
   $report.failure_class='PROGRAMDATA_ENVIRONMENT_MISMATCH';$script:resultCode=4
 }elseif($ex.Message -ceq 'WINDOWS_REQUIRED'){
   $report.failure_class='WINDOWS_REQUIRED';$script:resultCode=4
 }elseif($ex.Message -ceq 'WORKDIR_NOT_ACCESSIBLE'){
   $report.failure_class='WORKDIR_ACCESS_OR_MISSING';$script:resultCode=2
 }elseif($ex -is [System.UnauthorizedAccessException] -or $code -eq -2147024891 -or [string]$_.FullyQualifiedErrorId -match 'AccessDenied|UnauthorizedAccess'){
   $report.failure_class='ACCESS_DENIED';$script:resultCode=2
 }elseif($ex -is [System.Management.Automation.ItemNotFoundException]){
   $report.failure_class='EXPECTED_OBJECT_NOT_FOUND';$script:resultCode=2
 }else{
   $report.failure_class='QUERY_OR_ENVIRONMENT_FAILURE';$script:resultCode=2
 }
}
Emit $report
# Return nonzero errorlevel on incomplete evidence; do not auto-elevate or change ACLs.
exit $script:resultCode
