[CmdletBinding()]
param([switch]$Synthetic,[switch]$DisposableRunner,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# STRICTLY disposable GitHub-hosted Windows runner only. Never execute on
# Minecraft server PC. Only one ephemeral port; owned test rule removed in finally.
function Test-Target([int]$Port,[string]$Address){
  if($Port -lt 49152 -or $Port -gt 65535){return "DENY"}
  $ip=$null
  if(-not [Net.IPAddress]::TryParse($Address,[ref]$ip)){return "DENY"}
  if($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return "DENY"}
  $bytes=$ip.GetAddressBytes()
  if([Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or
     $bytes[0] -eq 0 -or $bytes[0] -ge 224 -or
     ($bytes[0] -eq 169 -and $bytes[1] -eq 254)){return "DENY"}
  return "ALLOW"
}
function Test-LocalTcp([int]$Port){
  $client=New-Object Net.Sockets.TcpClient
  $async=$null
  try{
    $async=$client.BeginConnect("127.0.0.1",$Port,$null,$null)
    if(-not $async.AsyncWaitHandle.WaitOne(1500,$false)){return $false}
    $client.EndConnect($async)
    return [bool]$client.Connected
  }catch{return $false}
  finally{
    if($null -ne $async){$async.AsyncWaitHandle.Dispose()}
    $client.Dispose()
  }
}
if(-not $OutputDir){$OutputDir=Join-Path ([IO.Path]::GetTempPath()) "Geumyi-Day12-Disposable-Stage"}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$out=Join-Path $OutputDir ("stage-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  if((Test-Target 25570 "192.0.2.4") -ne "DENY" -or
     (Test-Target 25575 "192.0.2.4") -ne "DENY" -or
     (Test-Target 53001 "127.0.0.1") -ne "DENY" -or
     (Test-Target 53001 "0.0.0.0") -ne "DENY" -or
     (Test-Target 53001 "::1") -ne "DENY" -or
     (Test-Target 53001 "169.254.1.1") -ne "DENY" -or
     (Test-Target 53001 "192.0.2.4") -ne "ALLOW"){
    throw "FAIL_CLOSED_TARGET_GUARD_REGRESSION"
  }
  [ordered]@{
    schema=1;synthetic=$true;result="SYNTHETIC_PASS"
    firewall_mutation_performed=$false
    private_ports_modified=$false
    canonical_backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "Disposable-rule safety fixture PASS"
  exit 0
}
# Refuse to create a firewall rule outside the specially named CI workflow.
if(-not $DisposableRunner -or $env:GITHUB_ACTIONS -ne "true" -or
   $env:GITHUB_REPOSITORY -ne "geumyi22/Geumyi-Minecraft-System" -or
   $env:GEUMYI_DISPOSABLE_STAGE -ne "approved_workflow_only" -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   [Environment]::OSVersion.Platform.ToString() -ne "Win32NT"){
  throw "REFUSED_OUTSIDE_DISPOSABLE_CI"
}
$listener=$null
$created=$false;$removed=$false;$before=$false;$after=$false
$metadata=$false;$state="INCONCLUSIVE";$port=0
$ruleName="Geumyi-Day12-Stage-"+[guid]::NewGuid().ToString("N")
try{
  # This ephemeral loopback listener exists only in a GitHub runner.
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $listener.Start()
  $port=[int]([Net.IPEndPoint]$listener.LocalEndpoint).Port
  if($port -lt 49152){throw "WINDOWS_EPHEMERAL_PORT_NOT_SUITABLE"}
  $local=@(Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred -ErrorAction Stop |
    Where-Object {(Test-Target $port $_.IPAddress) -eq "ALLOW"} |
    Select-Object -ExpandProperty IPAddress -Unique)
  if($local.Count -eq 0){throw "CI_HAS_NO_NONLOOPBACK_IPV4"}
  $ip=[string]$local[0]
  $before=Test-LocalTcp $port
  if(-not $before){throw "PRE_RULE_LOOPBACK_FAILURE"}
  if($null -ne (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)){throw "NAME_COLLISION"}
  $params=@{
    Name=$ruleName;DisplayName=$ruleName;Direction="Inbound";Action="Block"
    Enabled="True";Profile="Any";Protocol="TCP";LocalPort=[string]$port
    LocalAddress=$ip;RemoteAddress="Any";PolicyStore="PersistentStore"
    Description="Temporary GitHub-hosted CI ephemeral test; rollback required"
    ErrorAction="Stop"
  }
  New-NetFirewallRule @params | Out-Null
  $created=$true
  $r=Get-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore -ErrorAction Stop
  $pf=Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
  $af=Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
  $metadata=([string]$r.Action -eq "Block" -and [string]$pf.Protocol -in @("6","TCP") -and
     [string]$pf.LocalPort -eq [string]$port -and [string]$af.LocalAddress -eq $ip)
  if(-not $metadata){throw "RULE_SCOPE_READBACK_MISMATCH"}
  $after=Test-LocalTcp $port
  if(-not $after){throw "LOOPBACK_REGRESSED"}
  $state="CI_LOOPBACK_SURVIVED_TEMPORARY_RULE"
}catch{
  # Avoid exporting raw OS errors/IPs/paths from CI runner.
  $state="STAGE_INCONCLUSIVE"
}finally{
  if($created){
    try{
      Remove-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore -Confirm:$false -ErrorAction Stop
    }catch{}
  }
  $removed=($null -eq (Get-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore -ErrorAction SilentlyContinue))
  if($null -ne $listener){$listener.Stop()}
}
if(-not $removed){$state="STAGED_RULE_CLEANUP_FAILED"}
[ordered]@{
  schema=1;synthetic=$false;disposable_ci_runner_only=$true
  result=$state;rule_created=$created;owned_rule_removed=$removed
  metadata_matched=$metadata;loopback_before=$before;loopback_after=$after
  private_ports_modified=$false;production_host_touched=$false
  remote_host_tested=$false;ipv6_tested=$false
  canonical_backend_ports_private="UNCHANGED_FAIL"
  notes=@(
    "This confirms only a temporary local-address scoped block rule can coexist with local loopback on one disposable CI Windows runner.",
    "Does not prove remote packet enforcement, IPv6/VPN, Paper/RCON service health or current socket binding.",
    "No Minecraft ports or services were changed. Owned ephemeral test rule must be removed."
  )
}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Disposable stage: "+$state+"; owned rule removed: "+$removed)
if($state -ne "CI_LOOPBACK_SURVIVED_TEMPORARY_RULE"){exit 2}
exit 0
