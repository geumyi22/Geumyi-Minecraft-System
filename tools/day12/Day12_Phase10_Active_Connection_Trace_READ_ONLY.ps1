[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Active-Connections"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-Active-Connections-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

# Narrow follow-up to the four ONLINE ports missing from 01:12 native
# LISTEN snapshots yet confirmed loopback-reachable by 01:19 probes.
$targets=@(
  [pscustomobject]@{id="playground";kind="java";port=25571},
  [pscustomobject]@{id="lobby";kind="java";port=25573},
  [pscustomobject]@{id="wild";kind="rcon";port=25575},
  [pscustomobject]@{id="playground";kind="rcon";port=25576}
)
function SafeScope([string]$Text){
  $s=$Text.Trim('[',']').ToLowerInvariant()
  if($s -in @("0.0.0.0","::","*")){return "WILDCARD"}
  if($s -eq "127.0.0.1" -or $s -eq "::1" -or $s -eq "::ffff:127.0.0.1"){return "LOOPBACK"}
  if($s -match '^127\.'){return "LOOPBACK"}
  return "NON_LOOPBACK_REDACTED"
}
function Endpoint([string]$Addr){
  if($Addr -match '^\[(.+)\]:(\d+)$'){
    return [pscustomobject]@{ip=[string]$Matches[1];port=[int]$Matches[2]}
  }
  if($Addr -match '^(.+):(\d+)$'){
    return [pscustomobject]@{ip=[string]$Matches[1];port=[int]$Matches[2]}
  }
  return $null
}
function Get-ActiveRows([int]$Port,[int]$ClientEphemeralPort){
  $seen=New-Object System.Collections.ArrayList
  $providerStatus=@()
  try{
    $rows=@(Get-NetTCPConnection -State Established -LocalPort $Port -ErrorAction Stop)
    $matched=0
    foreach($r in $rows){
      if($null -eq $r -or [int]$r.RemotePort -ne $ClientEphemeralPort){continue}
      $matched++
      [void]$seen.Add([ordered]@{provider="Get-NetTCPConnection";local_scope=(SafeScope ([string]$r.LocalAddress));
        remote_scope=(SafeScope ([string]$r.RemoteAddress));server_pid_present=([int]$r.OwningProcess -gt 0)})
    }
    $providerStatus+= [ordered]@{provider="Get-NetTCPConnection";status="CAPTURED";matches=$matched}
  }catch{$providerStatus+= [ordered]@{provider="Get-NetTCPConnection";status="ERROR";matches=0}}
  try{
    $netstat=Join-Path $env:WINDIR "System32\netstat.exe"
    if(-not(Test-Path -LiteralPath $netstat -PathType Leaf)){throw "NETSTAT_MISSING"}
    $lines=@(& $netstat -ano -p TCP 2>$null)
    if($LASTEXITCODE -ne 0){throw "NETSTAT_FAILED"}
    $matched=0
    foreach($line in $lines){
      if([string]$line -notmatch '^\s*TCP\s+(\S+)\s+(\S+)\s+ESTABLISHED\s+(\d+)\s*$'){continue}
      $local=Endpoint ([string]$Matches[1])
      $remote=Endpoint ([string]$Matches[2])
      $pid=[int]$Matches[3]
      if($null -eq $local -or $null -eq $remote){continue}
      if($local.port -ne $Port -or $remote.port -ne $ClientEphemeralPort){continue}
      $matched++
      [void]$seen.Add([ordered]@{provider="netstat";local_scope=(SafeScope $local.ip);
        remote_scope=(SafeScope $remote.ip);server_pid_present=($pid -gt 0)})
    }
    $providerStatus+= [ordered]@{provider="netstat";status="CAPTURED";matches=$matched}
  }catch{$providerStatus+= [ordered]@{provider="netstat";status="ERROR";matches=0}}
  try{
    $rows=@([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpConnections())
    $matched=0
    foreach($r in $rows){
      if($null -eq $r -or $r.State -ne [System.Net.NetworkInformation.TcpState]::Established){continue}
      if($r.LocalEndPoint.Port -ne $Port -or $r.RemoteEndPoint.Port -ne $ClientEphemeralPort){continue}
      $matched++
      [void]$seen.Add([ordered]@{provider="IPGlobalProperties";local_scope=(SafeScope ([string]$r.LocalEndPoint.Address));
        remote_scope=(SafeScope ([string]$r.RemoteEndPoint.Address));server_pid_present=$false})
    }
    $providerStatus+= [ordered]@{provider="IPGlobalProperties";status="CAPTURED";matches=$matched}
  }catch{$providerStatus+= [ordered]@{provider="IPGlobalProperties";status="ERROR";matches=0}}
  return [pscustomobject]@{evidence=@($seen.ToArray());providers=$providerStatus}
}
function Trace([int]$Port){
  $client=New-Object System.Net.Sockets.TcpClient
  $waiter=$null
  try{
    $a=$client.BeginConnect("127.0.0.1",$Port,$null,$null)
    $waiter=$a.AsyncWaitHandle
    if(-not $waiter.WaitOne(900,$false)){return [ordered]@{connected=$false;evidence=@();providers=@();reason="TIMEOUT"}}
    $client.EndConnect($a)
    if(-not $client.Connected){return [ordered]@{connected=$false;evidence=@();providers=@();reason="NOT_CONNECTED"}}
    $clientPort=[int]([System.Net.IPEndPoint]$client.Client.LocalEndPoint).Port
    $snap=Get-ActiveRows $Port $clientPort
    return [ordered]@{connected=$true;evidence=@($snap.evidence);providers=@($snap.providers);reason="SNAPSHOT_COMPLETE"}
  }catch{
    return [ordered]@{connected=$false;evidence=@();providers=@();reason="CONNECT_FAILED"}
  }finally{
    if($null -ne $waiter){$waiter.Close()}
    $client.Dispose()
  }
}
function Fleet(){
  try{
    $r=Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8790/api/v4/update/fleet" -TimeoutSec 5 -ErrorAction Stop
    if($null -eq $r.servers){throw "NO_FLEET"}
    $rows=@()
    foreach($sv in @($r.servers)){
      if($null -eq $sv){continue}
      $id=[string]$sv.server_id
      if($id -notin @("wild","playground","other","lobby")){continue}
      $p=$sv.PSObject.Properties["online"]
      $rows+= [ordered]@{id=$id;online=($null -ne $p -and [bool]$p.Value)}
    }
    $state=if($rows.Count -eq 4){"CAPTURED"}else{"INCOMPLETE"}
    return [pscustomobject]@{status=$state;servers=$rows}
  }catch{return [pscustomobject]@{status="UNAVAILABLE";servers=@()}}
}
function IsOnline([object]$F,[string]$Id){
  foreach($sv in @($F.servers)){
    if($sv.id -eq $Id){return [bool]$sv.online}
  }
  return $false
}
if($Synthetic){
  $listener=$null;$serverClient=$null;$testClient=$null
  try{
    $listener=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $listener.Start()
    $port=[int]([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $async=$listener.BeginAcceptTcpClient($null,$null)
    $testClient=New-Object System.Net.Sockets.TcpClient
    $testClient.Connect("127.0.0.1",$port)
    $serverClient=$listener.EndAcceptTcpClient($async)
    $ephemeral=[int]([System.Net.IPEndPoint]$testClient.Client.LocalEndPoint).Port
    $probe=Get-ActiveRows $port $ephemeral
    $observations=@($probe.evidence)
    if($observations.Count -eq 0){throw "No established server endpoint observed in synthetic Windows fixture"}
    if(@($observations|Where-Object{$_.local_scope -ne "LOOPBACK"}).Count -gt 0){
      throw "Local-only fixture was not identified as loopback"
    }
    [ordered]@{schema=1;phase="12.10-active-connection-trace";synthetic=$true;read_only=$true
      result="SYNTHETIC_PASS";server_side_established_seen=$true
      providers=$probe.providers;mutation_performed=$false;secrets_exported=$false
    }|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "Day12 controlled established-connection fixture PASS"
    exit 0
  }finally{
    if($null -ne $serverClient){$serverClient.Dispose()}
    if($null -ne $testClient){$testClient.Dispose()}
    if($null -ne $listener){$listener.Stop()}
  }
}
$before=Fleet
$traces=@()
foreach($t in $targets){
  if(-not(IsOnline $before $t.id)){continue}
  $r=Trace ([int]$t.port)
  $traces+= [ordered]@{server_id=$t.id;kind=$t.kind;port=$t.port
    loopback_tcp_connected=$r.connected;server_side_established_rows=@($r.evidence)
    providers=@($r.providers);reason=$r.reason}
}
$after=Fleet
$stable=($before.status -eq "CAPTURED" -and $after.status -eq "CAPTURED")
if($stable){
  foreach($id in @("wild","playground","other","lobby")){
    if((IsOnline $before $id) -ne (IsOnline $after $id)){$stable=$false}
  }
}
$state=if($stable){"CAPTURED_REVIEW_REQUIRED"}else{"CHECK_REQUIRED"}
$report=[ordered]@{
  schema=1;phase="12.10-active-connection-trace";synthetic=$false;read_only=$true
  generated_at=(Get-Date).ToString("o");result=$state;fleet_before=$before;fleet_after=$after
  stable_fleet=$stable;traces=$traces
  observed_server_side_rows=@($traces|ForEach-Object{$_.server_side_established_rows}).Count
  notes=@(
    "Targeted four online ports previously missing from LISTEN inventory only; opens one temporary TCP client connection each to 127.0.0.1.",
    "During each held connection, reads Established server-side local/remote endpoint scope using Get-NetTCPConnection, netstat and IPGlobalProperties.",
    "No RCON password, commands, Minecraft application frames or process command lines are sent or recorded.",
    "Actual service may log a handshake. Target addresses other than explicit loopback are not attempted.",
    "Established local endpoint evidence is NOT evidence the listener binds exclusively to loopback.",
    "Do not promote backend_ports_private, Day12.10 or Stable from this diagnostic alone."
  );mutation_performed=$false;secrets_exported=$false
}
$report|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Day12 active connection trace: "+$state)
Write-Host ("Report: "+$out)
if($state -ne "CAPTURED_REVIEW_REQUIRED"){exit 2}
exit 0
