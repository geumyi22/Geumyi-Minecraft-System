# PowerShell 5.1 CI: disposable in-memory fixtures only. No operating-system queries.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$probe=Join-Path $PSScriptRoot '..\..\GSC\ServerCenter\cmd\host\velocity_status.ps1'
$probe=(Resolve-Path -LiteralPath $probe -ErrorAction Stop).Path
$tokens=$null; $errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($probe,[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){throw 'Velocity probe failed Windows PowerShell parser'}

$script:fixture = 'healthy'
$script:root = Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer'
function Get-CimInstance {
  [CmdletBinding()]
  param([string]$ClassName,[string]$Filter)
  if($ClassName -ne 'Win32_Process'){throw 'unexpected CIM class'}
  $rows=@()
  foreach($i in 0..2){
    $parent=4100+($i*10);$child=$parent+1
    $rows+= [pscustomobject]@{Name='java.exe';ProcessId=$parent;ParentProcessId=500;CommandLine='java.exe -Xmx512M -jar velocity.jar'}
    if($script:fixture -ne 'orphan' -or $i -ne 1){
      $rows+= [pscustomobject]@{Name='java.exe';ProcessId=$child;ParentProcessId=$parent;CommandLine='java.exe -Xmx512M -jar velocity.jar'}
    }
  }
  return @($rows)
}
function Get-ScheduledTask {
  [CmdletBinding()]
  param([string]$TaskName)
  if($script:fixture -eq 'missing_task' -and $TaskName -like '*wild'){return}
  $id=$TaskName -replace '^Geumyi Day10 Velocity ',''
  if($id -notin @('wild','playground','other')){throw 'unexpected fixture task'}
  $dir=Join-Path $script:root $id
  if($script:fixture -eq 'drift' -and $id -eq 'wild'){$dir=Join-Path $script:root 'WRONG'}
  return [pscustomobject]@{
    TaskPath='\';State='Running';Principal=[pscustomobject]@{UserId='SYSTEM'}
    Actions=@([pscustomobject]@{
      Execute='C:\Windows\System32\java.exe'
      WorkingDirectory=$dir
      Arguments='-Xms256M -Xmx512M -jar velocity.jar'
    })
  }
}
function Get-NetTCPConnection {
  [CmdletBinding()]
  param([int]$LocalPort,[string]$State)
  if($State -ne 'Listen' -or $LocalPort -notin @(25565,25566,25567)){throw 'unexpected TCP request'}
  if($script:fixture -in @('tcp_missing','all_sockets_missing')){return}
  $id=$LocalPort-25565
  return [pscustomobject]@{OwningProcess=(4101+$id*10)}
}
function Get-NetUDPEndpoint {
  [CmdletBinding()]
  param([int]$LocalPort)
  if($LocalPort -notin @(19132,19133,19134)){throw 'unexpected UDP request'}
  if($script:fixture -eq 'all_sockets_missing'){return}
  $id=$LocalPort-19132
  return [pscustomobject]@{OwningProcess=(4101+$id*10)}
}

function Probe([string]$mode){
  $script:fixture=$mode
  $raw=@(& $probe)
  if($raw.Count -ne 1){throw "Unexpected stdout count for $mode"}
  $json=([string]$raw[0] | ConvertFrom-Json -ErrorAction Stop)
  if(-not [bool]$json.read_only -or [int]$json.schema -ne 1 -or @($json.proxies).Count -ne 3){
    throw "Invalid schema for $mode"
  }
  if([bool]$json.task_process_identity_verified -or [bool]$json.live_java_raknet_e2e_verified){
    throw "False production process/E2E proof for $mode"
  }
  if([string]$raw[0] -match '(?i)CommandLine|WorkingDirectory|ProcessId|C:\\Windows|4101|4111|4121'){
    throw "Private process metadata leaked for $mode"
  }
  return $json
}

$good=Probe 'healthy'
if(-not [bool]$good.process_pair_census_consistent -or -not [bool]$good.udp_three_unique_child_owners){
  throw 'Healthy six-process topology was not detected'
}
if(@($good.proxies|Where-Object {$_.status -ne 'ports_ready_owner_unverified'}).Count -ne 0){
  throw 'Healthy fixture did not report bounded port status'
}
$tcpMissing=Probe 'tcp_missing'
if(@($tcpMissing.proxies|Where-Object {$_.status -ne 'ports_partial_or_conflicting'}).Count -ne 0){
  throw 'Missing TCP provider rows must not claim OFFLINE'
}
$socketsMissing=Probe 'all_sockets_missing'
if(@($socketsMissing.proxies|Where-Object {$_.status -ne 'socket_inventory_missing'}).Count -ne 0){
  throw 'Missing TCP and UDP provider rows must be UNVERIFIED, not OFFLINE'
}
$missing=Probe 'missing_task'
if([string]$missing.proxies[0].status -ne 'task_missing_or_duplicate'){throw 'Missing task was not detected'}
$drift=Probe 'drift'
if([string]$drift.proxies[0].status -ne 'task_config_drift'){throw 'Task action path drift was not detected'}
$orphan=Probe 'orphan'
if([bool]$orphan.process_pair_census_consistent -or [bool]$orphan.udp_three_unique_child_owners){
  throw 'Orphan process wrongly accepted'
}
Write-Host 'VELOCITY_READ_ONLY_WINDOWS_FIXTURE_PASS: 6 cases; no real processes, tasks, ports, or files changed.'
