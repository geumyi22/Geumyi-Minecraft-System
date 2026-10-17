# Status-only inventory of the three known Day 10 Velocity scheduled tasks.
# This script MUST NOT modify a task, process, port, service, configuration, or world.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expectedRoot = Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer'
$items = @(
  @{ id='wild'; tcp=25565; udp=19132 }
  @{ id='playground'; tcp=25566; udp=19133 }
  @{ id='other'; tcp=25567; udp=19134 }
)
$out = @()
foreach ($item in $items) {
  $id = [string]$item.id
  $taskName = 'Geumyi Day10 Velocity ' + $id
  $expectedDir = Join-Path $expectedRoot $id
  $tasks = @(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
  $taskFound = $tasks.Count -eq 1
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
      $args = [string]$act.Arguments
      $taskMatches = ($exe -ieq 'java.exe' -and $working -ieq $expected -and
          $args -match '(?i)(?:^|\s)-jar\s+(?:"velocity\.jar"|velocity\.jar)(?:\s|$)')
    }
  }
  $tcp = @(Get-NetTCPConnection -LocalPort ([int]$item.tcp) -State Listen -ErrorAction SilentlyContinue |
      Where-Object { [int]$_.OwningProcess -gt 0 } |
      Select-Object -ExpandProperty OwningProcess -Unique)
  $udp = @(Get-NetUDPEndpoint -LocalPort ([int]$item.udp) -ErrorAction SilentlyContinue |
      Where-Object { [int]$_.OwningProcess -gt 0 } |
      Select-Object -ExpandProperty OwningProcess -Unique)
  $ownersMatch = ($tcp.Count -eq 1 -and $udp.Count -eq 1 -and [int]$tcp[0] -eq [int]$udp[0])
  # Do not claim authenticated process identity on the basis of sockets alone.
  $state = 'unverified'
  if (-not $taskFound) { $state = 'task_missing_or_duplicate' }
  elseif (-not $taskMatches) { $state = 'task_config_drift' }
  elseif ($tcp.Count -eq 0 -and $udp.Count -eq 0) { $state = 'offline_or_starting' }
  elseif ($ownersMatch) { $state = 'ports_ready_owner_unverified' }
  else { $state = 'ports_partial_or_conflicting' }
  $out += [ordered]@{
    id=$id; task_present=$taskFound; task_matches_baseline=$taskMatches
    task_state=$taskState; java_port=[int]$item.tcp; bedrock_port=[int]$item.udp
    java_listening=($tcp.Count -gt 0); bedrock_listening=($udp.Count -gt 0)
    port_owner_consistent=$ownersMatch; status=$state
  }
}
[ordered]@{ schema=1; read_only=$true; proxies=$out } | ConvertTo-Json -Compress -Depth 6
