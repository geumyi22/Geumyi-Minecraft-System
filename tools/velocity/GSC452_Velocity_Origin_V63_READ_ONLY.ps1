#requires -Version 5.1
[CmdletBinding()]
param(
  [ValidateSet('none','disjoint','overlap','missing-udp','missing-tcp','bind-failure','missing-metadata','task-drift','missing-task','query-denied')]
  [string]$Fixture='none'
)
# GSC 4.5.2 V6.3: sanitized read-only diagnostic. NO live control.
# An exact Task Scheduler -> Java process link CANNOT be proven from parent PID alone.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$script:phase='PREFLIGHT'
$script:exitCode=0
$script:now=[DateTime]::UtcNow
$script:targets=@('wild','playground','other')
$script:tcpPorts=@(25565,25566,25567)
$script:udpPorts=@(19132,19133,19134)

function SamePath([string]$a,[string]$b) {
  if([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)){return $false}
  try {return [IO.Path]::GetFullPath($a).TrimEnd('\') -ieq [IO.Path]::GetFullPath($b).TrimEnd('\')} catch {return $false}
}
function CountClass([int]$n) {
  if($n -eq 0){return 'ZERO'};if($n -eq 1){return 'ONE'};if($n -eq 2){return 'TWO'}
  if($n -eq 3){return 'THREE'};return 'MORE_THAN_THREE'
}
function VelocityJar([string]$cmd) {
  if([string]::IsNullOrWhiteSpace($cmd)){return $false}
  $m=[regex]::Match($cmd,'(?i)(?:^|\s)-jar\s+(?:"([^"]+)"|([^\s"]+))')
  if(-not $m.Success){return $false}
  $arg=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
  return [IO.Path]::GetFileName($arg) -ieq 'velocity.jar'
}
function JarArgumentClass([string]$cmd,[string]$expectedWorkdir) {
  if(-not (VelocityJar $cmd)){return 'NOT_VELOCITY_JAR'}
  $m=[regex]::Match($cmd,'(?i)(?:^|\s)-jar\s+(?:"([^"]+)"|([^\s"]+))')
  $v=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
  if(-not [IO.Path]::IsPathRooted($v)){return 'RELATIVE_JAR_CWD_NOT_PROVEN'}
  if(SamePath ([IO.Path]::GetDirectoryName($v)) $expectedWorkdir){return 'ABSOLUTE_APPROVED_WORKDIR'}
  return 'ABSOLUTE_OTHER_WORKDIR'
}
function ImageClass($p,[string]$expected) {
  if($null -eq $p -or [string]::IsNullOrWhiteSpace([string]$p.ExecutablePath)){return 'METADATA_UNAVAILABLE'}
  if(SamePath ([string]$p.ExecutablePath) $expected){return 'TASK_JAVA_EXACT'}
  $leaf=[IO.Path]::GetFileName([string]$p.ExecutablePath)
  if($leaf -ieq 'java.exe'){return 'JAVA_OTHER_LOCATION'}
  if($leaf -ieq 'javaw.exe'){return 'JAVA_WINDOWLESS'}
  return 'OTHER_EXECUTABLE'
}
function ParentClass($child,$byId) {
  if($null -eq $child){return 'UNVERIFIED'}
  $parentId=[int]$child.ParentProcessId
  if($parentId -le 0 -or -not $byId.ContainsKey($parentId)){return 'PARENT_NOT_OBSERVABLE'}
  $parent=$byId[$parentId]
  try {
    if([DateTime]$parent.CreationDate -gt [DateTime]$child.CreationDate){return 'PARENT_PID_REUSED_OR_INVALID'}
  }catch{return 'PARENT_TIME_UNVERIFIED'}
  $leaf=[string]$parent.Name
  if($leaf -match '^(?i:svchost|taskhostw|taskeng)\.exe$'){return 'WINDOWS_SERVICE_OR_TASK_HOST_HINT'}
  if($leaf -match '^(?i:cmd|powershell|pwsh|conhost)\.exe$'){return 'SHELL_PARENT_HINT'}
  if($leaf -match '^(?i:java|javaw)\.exe$'){return 'JAVA_PARENT_HINT'}
  return 'OTHER_PARENT_HINT'
}
function AgeRelativeToTask($proc,$info) {
  if($null -eq $proc -or $null -eq $info){return 'UNVERIFIED'}
  try {
    $start=[DateTime]$proc.CreationDate
    $run=[DateTime]$info.LastRunTime
    if($run.Year -lt 2000 -or $start.Year -lt 2000){return 'UNVERIFIED'}
    $seconds=($start.ToUniversalTime()-$run.ToUniversalTime()).TotalSeconds
    if([Math]::Abs($seconds) -le 120){return 'NEAR_LAST_RUN_HINT_ONLY'}
    if($seconds -lt -120){return 'STARTED_BEFORE_LAST_RUN'}
    return 'STARTED_AFTER_LAST_RUN'
  } catch {return 'UNVERIFIED'}
}
function OwnerIds($rows,[int]$port) {
  return ,([int[]]@($rows|Where-Object {[int]$_.LocalPort -eq $port -and [int]$_.OwningProcess -gt 0}|ForEach-Object {[int]$_.OwningProcess}|Sort-Object -Unique))
}
function ClassifyBind([string[]]$lines,[int]$expectedPort) {
  $value=@($lines|Where-Object {$_ -match '^\s*bind\s*=' -and $_ -notmatch '^\s*#'})
  if($value.Count -eq 0){return 'BIND_NOT_FOUND'}
  if($value.Count -gt 1){return 'MULTIPLE_BIND_LINES'}
  if($value[0] -notmatch '^\s*bind\s*=\s*["''](?:[^"'']*:)?(\d{1,5})["'']\s*(?:#.*)?$'){return 'BIND_SYNTAX_UNVERIFIED'}
  $port=[int]$Matches[1]
  if($port -eq $expectedPort){return 'EXPECTED_PORT'}
  return 'OTHER_PORT'
}
function ClassifyLog([string[]]$lines) {
  # Pattern matches only. NEVER serialize message content.
  if(@($lines|Where-Object {$_ -match '(?i)Address already in use|BindException|Failed to bind|Could not bind|Cannot bind'}).Count -gt 0){return 'BIND_FAILURE_EVIDENCE'}
  if(@($lines|Where-Object {$_ -match '(?i)(invalid|error).{0,35}(config|velocity\.toml)|failed to load config'}).Count -gt 0){return 'CONFIG_ERROR_EVIDENCE'}
  if(@($lines|Where-Object {$_ -match '(?i)Listening on|bound to|Proxy listening|Velocity.*started'}).Count -gt 0){return 'STARTUP_OR_BIND_SUCCESS_HINT'}
  return 'NO_RECOGNIZED_SIGNAL'
}
function NewResult([bool]$synthetic) {
  return [ordered]@{
    schema=8; diagnostic_revision='6.3-origin-read-only'
    check='GSC452_VELOCITY_PROCESS_ORIGIN_AND_BIND_CAUSE_READ_ONLY'
    synthetic=$synthetic;read_only=$true
    elevated='UNVERIFIED';programdata='UNVERIFIED';failure_phase='NONE';failure_class='NONE'
    tasks=@();java_groups=[ordered]@{task_java_candidates='UNVERIFIED';udp_velocity_owners='UNVERIFIED';overlap='UNVERIFIED'}
    ports=@();status='INCOMPLETE_NO_ACTION'
    task_mutations=0;java_operations=0;service_mutations=0;acl_mutations=0;world_operations=0
    task_to_jvm_ownership_proven=$false;legacy_stdin_access_proven=$false
    safe_to_stop=$false;safe_to_cutover=$false;live_control_authorized=$false
  }
}
function ReadTargetConfig([string]$dir,[int]$port) {
  $file=Join-Path $dir 'velocity.toml'
  try {
    if(-not (Test-Path -LiteralPath $file -PathType Leaf -ErrorAction Stop)){return 'CONFIG_NOT_FOUND'}
    $lines=@(Get-Content -LiteralPath $file -TotalCount 160 -ErrorAction Stop)
    return ClassifyBind $lines $port
  } catch [System.UnauthorizedAccessException]{return 'CONFIG_ACCESS_DENIED'}
    catch {return 'CONFIG_READ_FAILED'}
}
function ReadTargetLog([string]$dir) {
  try {
    $names=@('latest.log','velocity.log')
    $matches=@()
    foreach($name in $names){
      $p=Join-Path (Join-Path $dir 'logs') $name
      if(Test-Path -LiteralPath $p -PathType Leaf -ErrorAction Stop){
        $matches+=@(Get-Item -LiteralPath $p -ErrorAction Stop)
      }
    }
    if($matches.Count -eq 0){return [ordered]@{signal='NO_KNOWN_LOG_FILE';freshness='UNVERIFIED'}}
    $chosen=@($matches|Sort-Object LastWriteTimeUtc -Descending)[0]
    $fresh=if(($script:now-$chosen.LastWriteTimeUtc).TotalMinutes -ge 0 -and ($script:now-$chosen.LastWriteTimeUtc).TotalMinutes -le 30){'MODIFIED_WITHIN_30_MIN'}else{'STALE_OR_CLOCK_UNVERIFIED'}
    $lines=@(Get-Content -LiteralPath $chosen.FullName -Tail 300 -ErrorAction Stop)
    return [ordered]@{signal=(ClassifyLog $lines);freshness=$fresh}
  } catch [System.UnauthorizedAccessException]{return [ordered]@{signal='LOG_ACCESS_DENIED';freshness='UNVERIFIED'}}
    catch{return [ordered]@{signal='LOG_READ_FAILED';freshness='UNVERIFIED'}}
}
function CollectSnapshot($report) {
  $script:phase='PLATFORM'
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
  $script:phase='ELEVATION'
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=[Security.Principal.WindowsPrincipal]::new($id)
  if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){$report.elevated='NO';throw 'ELEVATION_REQUIRED'}
  $report.elevated='YES'
  $script:phase='PROGRAMDATA'
  $known=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
  if(-not (SamePath $known $env:ProgramData)){$report.programdata='MISMATCH';throw 'PROGRAMDATA_MISMATCH'}
  $report.programdata='CANONICAL_MATCH'
  $tasks=@()
  foreach($i in 0..2){
    $target=$script:targets[$i]
    $script:phase='TASK_METADATA'
    $name='Geumyi Day10 Velocity '+$target
    $t=Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop
    $actions=@($t.Actions|Where-Object {$null -ne $_})
    if($actions.Count -ne 1){throw 'UNEXPECTED_TASK_ACTIONS'}
    $workdir=Join-Path $env:ProgramData ('GeumyiServerCenter\Network\FourServer\'+$target)
    $expected=(SamePath ([string]$actions[0].WorkingDirectory) $workdir) -and ([IO.Path]::GetFileName([string]$actions[0].Execute) -ieq 'java.exe') -and (VelocityJar ([string]$actions[0].Arguments))
    if(-not $expected){throw 'TASK_LAUNCH_PROFILE_MISMATCH'}
    $script:phase='TASK_LAST_RUN'
    $info=$null
    try{$info=Get-ScheduledTaskInfo -TaskPath '\' -TaskName $name -ErrorAction Stop}catch{}
    $script:phase='TARGET_FILES'
    $config=ReadTargetConfig $workdir $script:tcpPorts[$i]
    $log=ReadTargetLog $workdir
    $tasks+=@([pscustomobject]@{id=$target;state=[string]$t.State;java=[string]$actions[0].Execute;workdir=$workdir;restart=[int]$t.Settings.RestartCount;info=$info;config=$config;log=$log})
  }
  $script:phase='JAVA_PROCESS_QUERY'
  $processes=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
  # Only query parents of Velocity candidates; not all users' process command lines.
  $parentIds=@($processes|Where-Object {VelocityJar ([string]$_.CommandLine)}|ForEach-Object {[int]$_.ParentProcessId}|Where-Object {$_ -gt 0}|Sort-Object -Unique)
  $byId=@{}
  foreach($p in $processes){if([int]$p.ProcessId -gt 0){$byId[[int]$p.ProcessId]=$p}}
  $script:phase='PARENT_PROCESS_QUERY'
  foreach($pidValue in $parentIds){
    if($byId.ContainsKey([int]$pidValue)){continue}
    try{$items=@(Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$pidValue) -ErrorAction Stop)
      if($items.Count -eq 1){$byId[[int]$pidValue]=$items[0]}
    }catch{} # parent is an optional hint; never an attribution proof
  }
  $script:phase='TCP_LISTEN_QUERY'
  $tcp=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
  $script:phase='UDP_ENDPOINT_QUERY'
  $udp=@(Get-NetUDPEndpoint -ErrorAction Stop)
  $script:phase='TASK_STATE_RECHECK'
  $unchanged=$true
  foreach($t in $tasks){$check=Get-ScheduledTask -TaskPath '\' -TaskName ('Geumyi Day10 Velocity '+$t.id) -ErrorAction Stop
    if([string]$check.State -cne [string]$t.state){$unchanged=$false}
  }
  return [pscustomobject]@{tasks=$tasks;processes=$processes;byId=$byId;tcp=$tcp;udp=$udp;unchanged=$unchanged}
}
function Analyze($snap,$report) {
  $taskJava=@{}
  $velocity=@{}
  $nullMetadata=0
  foreach($p in @($snap.processes)) {
    if([string]$p.Name -notmatch '^(?i:java|javaw)\.exe$'){continue}
    if([string]::IsNullOrWhiteSpace([string]$p.CommandLine) -or [string]::IsNullOrWhiteSpace([string]$p.ExecutablePath)){$nullMetadata++;continue}
    if(-not (VelocityJar ([string]$p.CommandLine))){continue}
    $pidValue=[int]$p.ProcessId
    if($pidValue -le 0){continue}
    $velocity[$pidValue]=$p
    foreach($t in @($snap.tasks)){if(SamePath ([string]$p.ExecutablePath) $t.java){$taskJava[$pidValue]=$p;break}}
  }
  $udpVelocity=@{};$overlap=0
  for($i=0;$i -lt 3;$i++){
    $t=$snap.tasks[$i];$port=$script:udpPorts[$i]
    $uids=OwnerIds $snap.udp $port
    $tcps=OwnerIds $snap.tcp $script:tcpPorts[$i]
    $javaOwner=$null;$parent='UNVERIFIED';$exeClass='UNVERIFIED';$jarClass='UNVERIFIED';$startClass='UNVERIFIED';$anyTcp='UNVERIFIED'
    if($uids.Count -eq 1 -and $snap.byId.ContainsKey([int]$uids[0])){
      $javaOwner=$snap.byId[[int]$uids[0]]
      $exeClass=ImageClass $javaOwner $t.java
      $jarClass=JarArgumentClass ([string]$javaOwner.CommandLine) $t.workdir
      $parent=ParentClass $javaOwner $snap.byId
      $startClass=AgeRelativeToTask $javaOwner $t.info
      $anyTcp=if(@($snap.tcp|Where-Object {[int]$_.OwningProcess -eq [int]$uids[0]}).Count -gt 0){'YES'}else{'NO'}
      if($velocity.ContainsKey([int]$uids[0])){$udpVelocity[[int]$uids[0]]=$true}
      if($taskJava.ContainsKey([int]$uids[0])){$overlap++}
    }
    $report.tasks+=@([ordered]@{
      target=$t.id;task_state=$t.state;restart_hazard=if($t.restart -gt 0){'PRESENT'}else{'NOT_OBSERVED'}
      task_launcher='MATCH';configured_tcp_port=$script:tcpPorts[$i]
      config_bind=$t.config;log_signal=$t.log.signal;log_freshness=$t.log.freshness
      udp_owner_image=$exeClass;udp_owner_jar_argument=$jarClass
      udp_owner_parent=$parent;udp_owner_start_vs_task=$startClass
      udp_owner_has_any_tcp=$anyTcp
    })
    $report.ports+=@([ordered]@{target=$t.id;tcp_port=$script:tcpPorts[$i];tcp_owner_count=(CountClass $tcps.Count);udp_port=$port;udp_owner_count=(CountClass $uids.Count)})
  }
  $report.java_groups.task_java_candidates=CountClass $taskJava.Count
  $report.java_groups.udp_velocity_owners=CountClass $udpVelocity.Count
  $report.java_groups.overlap=if($overlap -eq 0){'NONE'}elseif($overlap -eq 3){'ALL_THREE'}else{'SOME'}
  $report.status='PROCESS_ORIGIN_AND_BIND_EVIDENCE_COLLECTED_NO_ACTION'
  if(-not $snap.unchanged){$report.status='TASK_STATES_CHANGED_DURING_CHECK_NO_ACTION';$script:exitCode=2}
  if($nullMetadata -gt 0){$report.status='INCOMPLETE_JAVA_METADATA_NO_ACTION';$script:exitCode=2}
}
function FakeSnapshot([string]$case) {
  if($case -eq 'query-denied'){throw [System.UnauthorizedAccessException]::new('PRIVATE_FAKE_PATH')}
  if($case -eq 'missing-task'){throw 'TASK_NOT_FOUND_PRIVATE_DATA'}
  $taskJava='C:\JavaA\bin\java.exe';$otherJava='C:\JavaB\bin\java.exe'
  $tasks=@();$processes=@();$tcp=@();$udp=@()
  for($i=0;$i -lt 3;$i++){
    $name=$script:targets[$i]
    $log=[ordered]@{signal='NO_RECOGNIZED_SIGNAL';freshness='MODIFIED_WITHIN_30_MIN'}
    if($case -eq 'bind-failure'){$log.signal='BIND_FAILURE_EVIDENCE'}
    $tasks+=@([pscustomobject]@{id=$name;state='Running';java=$taskJava;workdir=('C:\ProgramData\GeumyiServerCenter\Network\FourServer\'+$name);restart=999;info=$null;config='EXPECTED_PORT';log=$log})
    $processes+=@([pscustomobject]@{Name='java.exe';ProcessId=(100+$i);ParentProcessId=8;CreationDate=$script:now;ExecutablePath=$taskJava;CommandLine='java.exe -jar velocity.jar'})
    $processes+=@([pscustomobject]@{Name='java.exe';ProcessId=(200+$i);ParentProcessId=8;CreationDate=$script:now;ExecutablePath=$otherJava;CommandLine='java.exe -jar velocity.jar'})
    $upId=if($case -eq 'overlap'){100+$i}else{200+$i}
    if(-not ($case -eq 'missing-udp' -and $i -eq 0)){$udp+=@([pscustomobject]@{LocalPort=(19132+$i);OwningProcess=$upId})}
    if($case -ne 'missing-tcp' -and $case -eq 'overlap'){$tcp+=@([pscustomobject]@{LocalPort=(25565+$i);OwningProcess=$upId})}
  }
  if($case -eq 'missing-metadata'){$processes[0].CommandLine=$null}
  $byId=@{};foreach($p in $processes){$byId[[int]$p.ProcessId]=$p}
  return [pscustomobject]@{tasks=$tasks;processes=$processes;byId=$byId;tcp=$tcp;udp=$udp;unchanged=($case -ne 'task-drift')}
}
$report=NewResult ($Fixture -ne 'none')
try {
  if($Fixture -eq 'none'){$snapshot=CollectSnapshot $report}
  else{$report.elevated='SYNTHETIC';$report.programdata='SYNTHETIC';$snapshot=FakeSnapshot $Fixture}
  $script:phase='ANALYZE';Analyze $snapshot $report
} catch {
  $report.status='INCOMPLETE_NO_ACTION';$report.failure_phase=$script:phase
  $e=$_.Exception
  if($e.Message -eq 'ELEVATION_REQUIRED'){$report.failure_class='ELEVATION_REQUIRED';$script:exitCode=3}
  elseif($e.Message -eq 'WINDOWS_REQUIRED' -or $e.Message -eq 'PROGRAMDATA_MISMATCH'){$report.failure_class='PLATFORM_OR_PATH_MISMATCH';$script:exitCode=4}
  elseif($e -is [System.UnauthorizedAccessException] -or $e.HResult -eq -2147024891){$report.failure_class='ACCESS_DENIED';$script:exitCode=2}
  elseif($script:phase -eq 'TASK_METADATA' -or $script:phase -eq 'TASK_LAST_RUN' -or $script:phase -eq 'TASK_STATE_RECHECK'){$report.failure_class='TASK_QUERY_OR_PROFILE_FAILURE';$script:exitCode=2}
  elseif($script:phase -eq 'JAVA_PROCESS_QUERY' -or $script:phase -eq 'PARENT_PROCESS_QUERY'){$report.failure_class='PROCESS_QUERY_FAILURE';$script:exitCode=2}
  elseif($script:phase -eq 'TCP_LISTEN_QUERY' -or $script:phase -eq 'UDP_ENDPOINT_QUERY'){$report.failure_class='SOCKET_QUERY_FAILURE';$script:exitCode=2}
  else{$report.failure_class='UNVERIFIED_ENVIRONMENT_FAILURE';$script:exitCode=2}
}
$report|ConvertTo-Json -Depth 7 -Compress
# Explicit exit codes for normal launch. Tests may dot-source this with injected mock cmdlets.
if($MyInvocation.InvocationName -eq '.'){$global:LASTEXITCODE=$script:exitCode}else{exit $script:exitCode}
