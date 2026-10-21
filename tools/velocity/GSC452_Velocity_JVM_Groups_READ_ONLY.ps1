#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('none','disjoint','overlap','no-candidates','query-failed')][string]$Synthetic='none')
# Read-only immutable operator diagnostic. No secrets, executable paths,
# process IDs, raw command lines, original task XML or raw logs are exported.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function CountBucket([int]$n) {
 if($n -lt 0){return 'UNVERIFIED'}
 if($n -eq 0){return 'ZERO'}
 if($n -eq 1){return 'ONE'}
 if($n -eq 2){return 'TWO'}
 if($n -eq 3){return 'THREE'}
 return 'MORE_THAN_THREE'
}
function ExactPath([string]$a,[string]$b) {
 if([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)){return $false}
 try{return ([IO.Path]::GetFullPath($a) -ieq [IO.Path]::GetFullPath($b))}catch{return $false}
}
function VelocityJar([string]$cmd) {
 if([string]::IsNullOrWhiteSpace($cmd)){return $false}
 $m=[regex]::Match($cmd,'(?i)(?:^|\s)-jar\s+(?:"([^"]+)"|([^\s"]+))')
 if(-not $m.Success){return $false}
 $jar=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
 return [IO.Path]::GetFileName($jar) -ieq 'velocity.jar'
}
function ParentClass($child,[hashtable]$processIndex) {
 try{
  if($null -eq $child -or $null -eq $child.ParentProcessId){return 'UNKNOWN'}
  $parent=$processIndex[[int]$child.ParentProcessId]
  if($null -eq $parent -or $null -eq $parent.CreationDate -or
     $null -eq $child.CreationDate){return 'NOT_AVAILABLE_OR_EXITED'}
  $born=([datetime]$parent.CreationDate).ToUniversalTime()
  $childBorn=([datetime]$child.CreationDate).ToUniversalTime()
  if($born -gt $childBorn){return 'PID_REUSED_UNVERIFIED'}
  $name=([string]$parent.Name).ToLowerInvariant()
  if($name -in @('svchost.exe','taskeng.exe','taskhostw.exe')){return 'SCHEDULER_OR_SERVICE_POSSIBLE_NOT_ATTESTED'}
  if($name -in @('java.exe','javaw.exe')){return 'JAVA_PARENT'}
  if($name -in @('powershell.exe','pwsh.exe','cmd.exe')){return 'SHELL_PARENT'}
  return 'OTHER_PARENT'
 }catch{return 'UNVERIFIED'}
}
function Emit($r) {
 $r.read_only=$true
 $r.task_mutations=0
 $r.service_mutations=0
 $r.java_operations=0
 $r.safe_to_stop=$false
 $r.safe_to_cutover=$false
 $r.live_control_authorized=$false
 $r.task_to_jvm_ownership_proven=$false
 $r.legacy_console_stdin_control_proven=$false
 $r|ConvertTo-Json -Depth 6 -Compress
}
$r=[ordered]@{
 schema=6
 check='GSC452_VELOCITY_JVM_GROUP_SEPARATION_READ_ONLY'
 synthetic=($Synthetic -ne 'none')
 task_states=@()
 scheduled_launcher_profiles_shared='UNVERIFIED'
 task_java_velocity_candidates_distinct='UNVERIFIED'
 task_java_candidates_with_any_tcp_listen='UNVERIFIED'
 task_java_candidates_with_any_known_udp='UNVERIFIED'
 udp_three_distinct_owners='UNVERIFIED'
 udp_owners_overlap_task_java_candidates='UNVERIFIED'
 udp_owners=@()
 diagnostics_status='UNVERIFIED_NO_ACTION'
}
$targetNames=@('wild','playground','other')
$udpPorts=@(19132,19133,19134)
if($Synthetic -ne 'none') {
 foreach($id in $targetNames){$r.task_states+=@([ordered]@{target=$id;state='Running';action_shape='MATCH'})}
 $r.scheduled_launcher_profiles_shared='YES'
 $candidateIds=if($Synthetic -eq 'no-candidates'){[int[]]@()}else{[int[]]@(11,22,33)}
 $udpIds=if($Synthetic -eq 'overlap'){[int[]]@(11,22,33)}else{[int[]]@(44,55,66)}
 if($Synthetic -eq 'query-failed'){$udpIds=[int[]]@()}
 $r.task_java_velocity_candidates_distinct=CountBucket $candidateIds.Count
 $r.task_java_candidates_with_any_tcp_listen='ZERO'
 $r.task_java_candidates_with_any_known_udp=if($Synthetic -eq 'overlap'){'THREE'}else{'ZERO'}
 $r.udp_three_distinct_owners=if($Synthetic -eq 'query-failed'){'UNVERIFIED'}else{'YES'}
 $r.udp_owners_overlap_task_java_candidates=if($Synthetic -eq 'query-failed'){'UNVERIFIED'}elseif($Synthetic -eq 'overlap'){'ALL_THREE'}else{'NONE'}
 foreach($i in 0..2){
  $r.udp_owners+=@([ordered]@{
   target=$targetNames[$i];port=$udpPorts[$i]
   unique_owner=if($Synthetic -eq 'query-failed'){'UNVERIFIED'}else{'YES'}
   velocity_jar=if($Synthetic -eq 'query-failed'){'UNVERIFIED'}else{'YES'}
   task_java_exact=if($Synthetic -eq 'overlap'){'YES'}else{'NO'}
   owner_any_tcp_listener='ZERO'
   owner_other_known_udp_listener='ZERO'
   immediate_parent_class='SYNTHETIC_NOT_PROOF'
  })
 }
 $r.diagnostics_status='SYNTHETIC_NO_ACTION'
 Emit $r;return
}
try{
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
 $actions=@{}
 $stateOK=$true
 foreach($id in $targetNames){
  $task=Get-ScheduledTask -TaskPath '\' -TaskName ('Geumyi Day10 Velocity '+$id) -ErrorAction Stop
  $acts=@($task.Actions|Where-Object {$null -ne $_})
  $shape='UNVERIFIED'
  if($acts.Count -eq 1){
   $exe=[string]$acts[0].Execute
   $work=[string]$acts[0].WorkingDirectory
   $expected=Join-Path $env:ProgramData ('GeumyiServerCenter\Network\FourServer\'+$id)
   if([IO.Path]::IsPathRooted($exe) -and [IO.Path]::IsPathRooted($work) -and
      [IO.Path]::GetFileName($exe) -ieq 'java.exe' -and
      (ExactPath $work $expected) -and
      [string]$acts[0].Arguments -match '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)'){
     $shape='MATCH'
     $actions[$id]=$exe
   }
  }
  $r.task_states+=@([ordered]@{target=$id;state=[string]$task.State;action_shape=$shape})
  if($shape -ne 'MATCH'){$stateOK=$false}
 }
 if(-not $stateOK){throw 'TASK_SHAPE_NOT_CONFIRMED'}
 $r.scheduled_launcher_profiles_shared=if(
  (ExactPath $actions['wild'] $actions['playground']) -and
  (ExactPath $actions['wild'] $actions['other'])
 ){'YES'}else{'NO'}
 $all=@(Get-CimInstance Win32_Process -ErrorAction Stop)
 $idx=@{}
 foreach($p in $all){$idx[[int]$p.ProcessId]=$p}
 $jvms=@($all|Where-Object {([string]$_.Name -ieq 'java.exe') -and (VelocityJar ([string]$_.CommandLine))})
 $candidates=@($jvms|Where-Object {
    (ExactPath ([string]$_.ExecutablePath) $actions['wild']) -or
    (ExactPath ([string]$_.ExecutablePath) $actions['playground']) -or
    (ExactPath ([string]$_.ExecutablePath) $actions['other'])
 })
 $r.task_java_velocity_candidates_distinct=CountBucket $candidates.Count
 $candidateIds=[int[]]@($candidates|ForEach-Object {[int]$_.ProcessId})
 $tcp=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
 $udp=@(Get-NetUDPEndpoint -ErrorAction Stop)
 $candidateTcp=0;$candidateUdp=0
 foreach($p in $candidates){
  if(@($tcp|Where-Object {[int]$_.OwningProcess -eq [int]$p.ProcessId}).Count -gt 0){$candidateTcp++}
  if(@($udp|Where-Object {[int]$_.OwningProcess -eq [int]$p.ProcessId -and [int]$_.LocalPort -in $udpPorts}).Count -gt 0){$candidateUdp++}
 }
 $r.task_java_candidates_with_any_tcp_listen=CountBucket $candidateTcp
 $r.task_java_candidates_with_any_known_udp=CountBucket $candidateUdp
 $owners=@();$overlap=0;$complete=$true
 for($i=0;$i -lt 3;$i++){
  $port=$udpPorts[$i];$id=$targetNames[$i]
  $list=[int[]]@($udp|Where-Object {[int]$_.LocalPort -eq $port -and [int]$_.OwningProcess -gt 0}|
   Select-Object -ExpandProperty OwningProcess -Unique)
  $row=[ordered]@{
   target=$id;port=$port;unique_owner='NO'
   velocity_jar='UNVERIFIED';task_java_exact='UNVERIFIED'
   owner_any_tcp_listener='UNVERIFIED'
   owner_other_known_udp_listener='UNVERIFIED'
   immediate_parent_class='UNVERIFIED'
  }
  if($list.Count -ne 1){$complete=$false}
  else{
   $pidValue=[int]$list[0];$owners+=@($pidValue)
   $p=$idx[$pidValue]
   if($null -ne $p){
    $row.unique_owner='YES'
    $row.velocity_jar=if(VelocityJar ([string]$p.CommandLine)){'YES'}else{'NO_OR_UNAVAILABLE'}
    $row.task_java_exact=if(ExactPath ([string]$p.ExecutablePath) $actions[$id]){'YES'}else{'NO'}
    $row.owner_any_tcp_listener=CountBucket @($tcp|Where-Object {[int]$_.OwningProcess -eq $pidValue}).Count
    $row.owner_other_known_udp_listener=CountBucket @($udp|Where-Object {
      [int]$_.OwningProcess -eq $pidValue -and
      [int]$_.LocalPort -in $udpPorts -and
      [int]$_.LocalPort -ne $port
    }).Count
    $row.immediate_parent_class=ParentClass $p $idx
   }else{$complete=$false}
   if($pidValue -in $candidateIds){$overlap++}
  }
  $r.udp_owners+=@($row)
 }
 $r.udp_three_distinct_owners=if($complete -and $owners.Count -eq 3){
  if(@($owners|Sort-Object -Unique).Count -eq 3){'YES'}else{'NO'}
 }else{'UNVERIFIED'}
 $r.udp_owners_overlap_task_java_candidates=if($complete){
  if($overlap -eq 0){'NONE'}elseif($overlap -eq 3){'ALL_THREE'}else{'SOME'}
 }else{'UNVERIFIED'}
 $r.diagnostics_status='JVM_GROUPS_CLASSIFIED_NO_ACTION'
}catch{
 $r.diagnostics_status='PARTIAL_OR_UNVERIFIED_NO_ACTION'
}
Emit $r
