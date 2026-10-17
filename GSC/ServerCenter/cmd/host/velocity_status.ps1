# GSC read-only Velocity task/socket/process-pair inventory.
# Never creates, stops or starts any task, process, server or service.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expectedRoot = Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer'
$items = @(
  @{ id='wild'; tcp=25565; udp=19132 }
  @{ id='playground'; tcp=25566; udp=19133 }
  @{ id='other'; tcp=25567; udp=19134 }
)
# Process command lines are inspected in memory only. Never emit them.
function Get-VelocityJarRole([string]$command) {
  if ([string]::IsNullOrWhiteSpace($command)) { return $false }
  $jarMatches = [regex]::Matches($command, '(?i)(?:^|\s)-jar\s+(?:"([^"\r\n]+)"|([^\s"]+))(?=\s|$)')
  if ($jarMatches.Count -ne 1) { return $false }
  $jar = if ($jarMatches[0].Groups[1].Success) {
    $jarMatches[0].Groups[1].Value
  } else {
    $jarMatches[0].Groups[2].Value
  }
  return ([IO.Path]::GetFileName($jar) -ieq 'velocity.jar')
}
# The historical Day12 host run had three parent/child pairs (six JVMs).
# This is a topology sanity check, NOT a proof of Scheduled Task ownership.
$allJava = @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
$velocity = @($allJava | Where-Object { Get-VelocityJarRole ([string]$_.CommandLine) })
$pids = @($velocity | ForEach-Object { [int]$_.ProcessId })
$roots = @($velocity | Where-Object { [int]$_.ParentProcessId -notin $pids })
$children = @($velocity | Where-Object { [int]$_.ParentProcessId -in $pids })
$pairConsistent = ($velocity.Count -eq 6 -and $roots.Count -eq 3 -and $children.Count -eq 3 -and
  @($pids | Select-Object -Unique).Count -eq 6)
if ($pairConsistent) {
  foreach ($root in $roots) {
    if (@($children | Where-Object { [int]$_.ParentProcessId -eq [int]$root.ProcessId }).Count -ne 1) {
      $pairConsistent = $false
      break
    }
  }
}
$out = @()
$udpOwnersByID = @{}
foreach ($item in $items) {
  $id = [string]$item.id
  $taskName = 'Geumyi Day10 Velocity ' + $id
  $expectedDir = Join-Path $expectedRoot $id
  $tasks = @(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
  $taskFound = ($tasks.Count -eq 1)
  $taskMatches = $false
  $taskState = 'UNKNOWN'
  if ($taskFound) {
    $task = $tasks[0]
    $taskState = [string]$task.State
    $actions = @($task.Actions)
    if ($actions.Count -eq 1 -and [string]$task.TaskPath -eq '\' -and
        [string]$task.Principal.UserId -in @('SYSTEM','S-1-5-18','NT AUTHORITY\SYSTEM')) {
      $act = $actions[0]
      $exe = [IO.Path]::GetFileName([string]$act.Execute)
      $working = ([string]$act.WorkingDirectory).TrimEnd('\')
      $expected = $expectedDir.TrimEnd('\')
      $arguments = [string]$act.Arguments
      $taskMatches = ($exe -ieq 'java.exe' -and $working -ieq $expected -and
          $arguments -match '(?i)(?:^|\s)-jar\s+(?:"velocity\.jar"|velocity\.jar)(?:\s|$)')
    }
  }
  # Historical Windows telemetry sometimes returned no TCP listener rows for
  # healthy Java/Bedrock proxies. Missing sockets MUST NOT mean OFFLINE.
  $tcp = @(Get-NetTCPConnection -LocalPort ([int]$item.tcp) -State Listen -ErrorAction SilentlyContinue |
      Where-Object { [int]$_.OwningProcess -gt 0 } |
      Select-Object -ExpandProperty OwningProcess -Unique)
  $udp = @(Get-NetUDPEndpoint -LocalPort ([int]$item.udp) -ErrorAction SilentlyContinue |
      Where-Object { [int]$_.OwningProcess -gt 0 } |
      Select-Object -ExpandProperty OwningProcess -Unique)
  $udpOwnersByID[$id] = @($udp)
  $ownersMatch = ($tcp.Count -eq 1 -and $udp.Count -eq 1 -and [int]$tcp[0] -eq [int]$udp[0])
  $state = 'unverified'
  if (-not $taskFound) { $state = 'task_missing_or_duplicate' }
  elseif (-not $taskMatches) { $state = 'task_config_drift' }
  elseif ($taskState -ne 'Running') { $state = 'task_not_running_unverified' }
  elseif ($tcp.Count -eq 0 -and $udp.Count -eq 0) { $state = 'socket_inventory_missing' }
  elseif ($tcp.Count -eq 0 -and $udp.Count -gt 0) { $state = 'tcp_inventory_missing_udp_visible' }
  elseif ($ownersMatch) { $state = 'ports_ready_owner_unverified' }
  else { $state = 'ports_partial_or_conflicting' }
  $out += [ordered]@{
    id=$id; task_present=$taskFound; task_matches_baseline=$taskMatches
    task_state=$taskState; java_port=[int]$item.tcp; bedrock_port=[int]$item.udp
    java_listening=($tcp.Count -gt 0); bedrock_listening=($udp.Count -gt 0)
    port_owner_consistent=$ownersMatch
    udp_owner_matches_velocity_child=$false
    status=$state
  }
}
# A valid process family can be correlated to each unique UDP child owner, but
# task launch provenance and full Java/RakNet application health remain unknown.
$udpUnique = @()
$allLeafOwners = $pairConsistent
foreach ($item in $out) {
  $owners = @($udpOwnersByID[[string]$item.id])
  if ($owners.Count -ne 1 -or @($children | Where-Object { [int]$_.ProcessId -eq [int]$owners[0] }).Count -ne 1) {
    $allLeafOwners = $false
  } else {
    $udpUnique += [int]$owners[0]
  }
}
if (@($udpUnique | Select-Object -Unique).Count -ne 3) { $allLeafOwners = $false }
if ($allLeafOwners) {
  foreach ($item in $out) {
    $item['udp_owner_matches_velocity_child'] = $true
    # Historical actual-server report 2026-10-17: TCP provider returned no
    # rows, while all 3 running tasks and 3 unique UDP child JVM owners matched.
    # This is a *telemetry gap*, not a port collision or an OFFLINE diagnosis.
    if ($item['status'] -eq 'tcp_inventory_missing_udp_visible') {
      $item['status'] = 'tcp_inventory_missing_udp_child_verified'
    }
  }
}
[ordered]@{
  schema=1; read_only=$true; process_pair_census_consistent=[bool]$pairConsistent
  udp_three_unique_child_owners=[bool]$allLeafOwners
  task_process_identity_verified=$false
  live_java_raknet_e2e_verified=$false
  proxies=$out
} | ConvertTo-Json -Compress -Depth 6
