[CmdletBinding()]
param()
# Windows ServerPC diagnostic. READ ONLY on services/tasks/processes/firewall/worlds.
# The sole local mutation is creation of a sanitized report under Desktop.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$report=[ordered]@{
  schema=1
  purpose='Velocity three-task read-only inventory'
  collected_at_utc=[DateTimeOffset]::UtcNow.ToString('o')
  read_only_server_state=$true
  operation='STATUS_ONLY'
  task_or_process_changes=$false
  worlds_or_backups_changed=$false
  status='INSPECTION_NOT_COMPLETED'
  process_pair_census_consistent=$false
  udp_three_unique_child_owners=$false
  task_process_identity_verified=$false
  live_java_raknet_e2e_verified=$false
  proxies=@()
}
$probe=Join-Path $PSScriptRoot '..\..\GSC\ServerCenter\cmd\host\velocity_status.ps1'
try {
  $probe=(Resolve-Path -LiteralPath $probe -ErrorAction Stop).Path
  $raw=@(& $probe)
  if($raw.Count -ne 1){throw 'INVENTORY_OUTPUT_NOT_SINGLE_JSON'}
  $actual=[string]$raw[0] | ConvertFrom-Json -ErrorAction Stop
  if([int]$actual.schema -ne 1 -or -not [bool]$actual.read_only -or
      @($actual.proxies).Count -ne 3 -or
      [bool]$actual.task_process_identity_verified -or
      [bool]$actual.live_java_raknet_e2e_verified){
    throw 'INVALID_INVENTORY_SCHEMA'
  }
  $ids=@('wild','playground','other')
  $java=@(25565,25566,25567)
  $bedrock=@(19132,19133,19134)
  for($i=0;$i -lt 3;$i++){
    $p=$actual.proxies[$i]
    if([string]$p.id -cne $ids[$i] -or
       [int]$p.java_port -ne $java[$i] -or
       [int]$p.bedrock_port -ne $bedrock[$i]){
      throw 'UNEXPECTED_PROXY_TARGET'
    }
    $report.proxies+= [ordered]@{
      id=$ids[$i]
      task_present=[bool]$p.task_present
      task_matches_baseline=[bool]$p.task_matches_baseline
      task_state=[string]$p.task_state
      java_port=$java[$i]
      bedrock_port=$bedrock[$i]
      java_listening=[bool]$p.java_listening
      bedrock_listening=[bool]$p.bedrock_listening
      port_owner_consistent=[bool]$p.port_owner_consistent
      udp_owner_matches_velocity_child=[bool]$p.udp_owner_matches_velocity_child
      status=[string]$p.status
    }
  }
  $report.process_pair_census_consistent=[bool]$actual.process_pair_census_consistent
  $report.udp_three_unique_child_owners=[bool]$actual.udp_three_unique_child_owners
  $report.status='INVENTORY_CAPTURED_UNVERIFIED'
}catch{
  # Never export exception text; Windows process paths and account names may leak.
  $report.status='INVENTORY_NOT_VERIFIED'
  $report.proxies=@()
}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)){
  Write-Host 'Desktop folder unavailable. No report written.'
  exit 2
}
$folder=Join-Path $desktop 'Geumyi-Velocity-ReadOnly-Reports'
[void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop)
$dest=Join-Path $folder ('Geumyi-Velocity-READ-ONLY-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$json=$report | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($dest,$json,(New-Object Text.UTF8Encoding($false)))
Write-Host 'Velocity READ-ONLY inventory finished.'
Write-Host ('Result: '+[string]$report.status)
Write-Host ('Report: '+$dest)
Write-Host 'Share only this sanitized JSON; do not upload full process lists, logs, or secrets.'
if($report.status -ne 'INVENTORY_CAPTURED_UNVERIFIED'){exit 2}
exit 0
