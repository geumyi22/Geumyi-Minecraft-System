#requires -Version 5.1
[CmdletBinding()]
param(
 [ValidateSet('none','wild','playground-tcp','other-udp','unmatched','missing')]
 [string]$SyntheticScenario='none'
)
# WILD Java/Bedrock live topology only. Strictly READ ONLY.
# No raw paths, PIDs, command lines, usernames, secrets or task XML emitted.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function OwnerSet([object[]]$rows) {
 return [int[]]@($rows | Where-Object {$null -ne $_ -and $null -ne $_.OwningProcess -and [int]$_.OwningProcess -gt 0} |
   ForEach-Object {[int]$_.OwningProcess} | Sort-Object -Unique)
}
function ClassCount([int[]]$pids) {
 if($null -eq $pids -or $pids.Count -eq 0){return 'ZERO'}
 if($pids.Count -eq 1){return 'ONE'}
 return 'MULTIPLE'
}
function SharedOwner([int[]]$target,[int[]]$other) {
 if($target.Count -ne 1 -or $other.Count -ne 1){return $false}
 return ($target[0] -eq $other[0])
}
function CrossClass([int[]]$bedrock,[hashtable]$ports,[bool]$queryOK) {
 if(-not $queryOK){return 'OWNER_QUERY_INCOMPLETE'}
 if($bedrock.Count -ne 1){return 'UDP19132_NOT_UNIQUE'}
 if(SharedOwner $bedrock $ports['tcp25565']){return 'MATCHES_WILD_TCP25565'}
 if(SharedOwner $bedrock $ports['tcp25566']){return 'MATCHES_PLAYGROUND_TCP25566'}
 if(SharedOwner $bedrock $ports['tcp25567']){return 'MATCHES_OTHER_TCP25567'}
 if(SharedOwner $bedrock $ports['udp19133']){return 'MATCHES_PLAYGROUND_UDP19133'}
 if(SharedOwner $bedrock $ports['udp19134']){return 'MATCHES_OTHER_UDP19134'}
 return 'NO_MATCH_WITH_KNOWN_PROXY_PORTS'
}
function ExecutableClass([int]$pidValue,[string]$taskJava) {
 try {
  $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$pidValue) -ErrorAction Stop
  if($null -eq $p -or [string]::IsNullOrWhiteSpace([string]$p.ExecutablePath)){return 'METADATA_UNAVAILABLE'}
  $name=[IO.Path]::GetFileName([string]$p.ExecutablePath)
  if($name -ieq 'java.exe') {
   if([IO.Path]::GetFullPath([string]$p.ExecutablePath) -ieq [IO.Path]::GetFullPath($taskJava)){return 'TASK_JAVA_EXACT'}
   return 'OTHER_JAVA_INSTALLATION'
  }
  if($name -ieq 'javaw.exe'){return 'JAVA_WINDOWLESS'}
  return 'NON_JAVA_EXECUTABLE'
 }catch{return 'QUERY_FAILED'}
}
function SafeReport($r) {
 $r.read_only=$true
 $r.task_or_service_mutations=0
 $r.java_operations=0
 $r.safe_to_stop=$false
 $r.safe_to_cutover=$false
 $r.live_control_authorized=$false
 $r.task_to_jvm_identity_proven=$false
 $r.legacy_stdin_available=$false
 $r | ConvertTo-Json -Compress -Depth 5
}
$r=[ordered]@{
 schema=4
 check='GSC452_WILD_PROXY_TOPOLOGY_READ_ONLY'
 target='wild'
 synthetic=($SyntheticScenario -ne 'none')
 wild_task_state='UNKNOWN'
 wild_task_java_shape='UNVERIFIED'
 task_auto_restart='UNKNOWN'
 wild_velocity_config_bind_port='UNVERIFIED'
 tcp25565='UNVERIFIED'
 tcp25566='UNVERIFIED'
 tcp25567='UNVERIFIED'
 udp19132='UNVERIFIED'
 udp19133='UNVERIFIED'
 udp19134='UNVERIFIED'
 udp19132_owner_executable='UNVERIFIED'
 udp19132_relation_to_proxy_ports='UNVERIFIED'
 tcp25565_owner_executable='UNVERIFIED'
 wild_task_config_and_port_agree='UNVERIFIED'
 result='PARTIAL_OR_UNVERIFIED_DO_NOT_CUTOVER'
}
if($SyntheticScenario -ne 'none') {
 $ports=@{tcp25565=[int[]]@(10);tcp25566=[int[]]@(20);tcp25567=[int[]]@(30);
  udp19133=[int[]]@(20);udp19134=[int[]]@(30)}
 $udp=[int[]]@(10)
 switch($SyntheticScenario) {
  'playground-tcp'{$udp=[int[]]@(20)}
  'other-udp'{$udp=[int[]]@(30);$ports.tcp25567=[int[]]@()}
  'unmatched'{$udp=[int[]]@(99)}
  'missing'{$udp=[int[]]@()}
 }
 $r.wild_task_state='Running'
 $r.wild_task_java_shape='MATCH'
 $r.task_auto_restart='PRESENT'
 $r.wild_velocity_config_bind_port=25565
 $r.tcp25565='ONE'
 $r.tcp25566='ONE'
 $r.tcp25567=ClassCount $ports.tcp25567
 $r.udp19132=ClassCount $udp
 $r.udp19133='ONE'
 $r.udp19134='ONE'
 $r.udp19132_owner_executable='SYNTHETIC_NOT_REAL'
 $r.udp19132_relation_to_proxy_ports=CrossClass $udp $ports $true
 $r.result='SYNTHETIC_NO_ACTION'
 SafeReport $r;return
}
try {
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
 $task=Get-ScheduledTask -TaskPath '\' -TaskName 'Geumyi Day10 Velocity wild' -ErrorAction Stop
 $r.wild_task_state=[string]$task.State
 $r.task_auto_restart=if([int]$task.Settings.RestartCount -gt 0){'PRESENT'}else{'NOT_OBSERVED'}
 $action=@($task.Actions|Where-Object {$null -ne $_})
 if($action.Count -ne 1){throw 'TASK_ACTION_COUNT'}
 $exe=[string]$action[0].Execute
 $work=[string]$action[0].WorkingDirectory
 $approved=Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer\wild'
 $shape=([IO.Path]::IsPathRooted($exe) -and [IO.Path]::IsPathRooted($work) -and
  [IO.Path]::GetFileName($exe) -ieq 'java.exe' -and
  [IO.Path]::GetFullPath($work) -ieq [IO.Path]::GetFullPath($approved) -and
  [string]$action[0].Arguments -match '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)' -and
  (Test-Path -LiteralPath $exe -PathType Leaf))
 $r.wild_task_java_shape=if($shape){'MATCH'}else{'DIFFERENT_OR_UNVERIFIED'}
 # Only read the configured listening port; no forwarding secret is emitted.
 $config=Join-Path $work 'velocity.toml'
 if($shape -and (Test-Path -LiteralPath $config -PathType Leaf)) {
  $lines=@(Get-Content -LiteralPath $config -ErrorAction Stop)
  $bind=@($lines|Where-Object {$_ -match '^\s*bind\s*=\s*"([^"]+)"'} )
  if($bind.Count -eq 1) {
   $m=[regex]::Match([string]$bind[0],'^\s*bind\s*=\s*"[^"]*:(\d{1,5})"')
   if($m.Success) {
    $port=[int]$m.Groups[1].Value
    if($port -gt 0 -and $port -le 65535){$r.wild_velocity_config_bind_port=$port}
   }
  }
 }
 $tcp=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
 $udp=@(Get-NetUDPEndpoint -ErrorAction Stop)
 $owners=@{}
 foreach($port in @(25565,25566,25567)){
  $key='tcp'+$port
  $subset=@($tcp | Where-Object {[int]$_.LocalPort -eq $port})
  $owners[$key]=[int[]]@(OwnerSet $subset)
  $r[$key]=ClassCount $owners[$key]
 }
 foreach($port in @(19132,19133,19134)){
  $key='udp'+$port
  $subset=@($udp | Where-Object {[int]$_.LocalPort -eq $port})
  $owners[$key]=[int[]]@(OwnerSet $subset)
  $r[$key]=ClassCount $owners[$key]
 }
 $r.wild_task_config_and_port_agree=if($r.wild_velocity_config_bind_port -is [int]) {
  if([int]$r.wild_velocity_config_bind_port -eq 25565){'YES'}else{'NO'}
 }else{'UNVERIFIED'}
 if($owners['udp19132'].Count -eq 1){
  $r.udp19132_owner_executable=ExecutableClass $owners['udp19132'][0] $exe
 }
 if($owners['tcp25565'].Count -eq 1){
  $r.tcp25565_owner_executable=ExecutableClass $owners['tcp25565'][0] $exe
 }
 $r.udp19132_relation_to_proxy_ports=CrossClass $owners['udp19132'] $owners $true
 $again=Get-ScheduledTask -TaskPath '\' -TaskName 'Geumyi Day10 Velocity wild' -ErrorAction Stop
 if([string]$again.State -ne $r.wild_task_state){throw 'TASK_STATE_DRIFT'}
 $r.result='PROXY_PORT_TOPOLOGY_CAPTURED_NO_ACTION'
}catch{
 # No raw exception data. Even partial results always mean NO GO.
 $r.result='PARTIAL_OR_UNVERIFIED_DO_NOT_CUTOVER'
}
SafeReport $r
