[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Loopback"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$out=Join-Path $OutputDir ("Day12-Loopback-Compare-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$targets=@(
  [pscustomobject]@{id="wild";java=25570;rcon=25575},
  [pscustomobject]@{id="playground";java=25571;rcon=25576},
  [pscustomobject]@{id="other";java=25572;rcon=25577},
  [pscustomobject]@{id="lobby";java=25573;rcon=25579}
)
function Test-LocalTcp([int]$Port,[string]$HostAddress="127.0.0.1"){
  $client=New-Object System.Net.Sockets.TcpClient
  $waiter=$null
  try{
    $ar=$client.BeginConnect($HostAddress,$Port,$null,$null)
    $waiter=$ar.AsyncWaitHandle
    if(-not $waiter.WaitOne(700,$false)){return $false}
    $client.EndConnect($ar)
    return [bool]$client.Connected
  }catch{return $false}finally{
    if($null -ne $waiter){$waiter.Close()}
    $client.Dispose()
  }
}
function Get-Fleet {
  try{
    $r=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/v4/update/fleet" -Method GET -TimeoutSec 5 -ErrorAction Stop
    if($null -eq $r -or $null -eq $r.servers){throw "NO_FLEET_ROWS"}
    $found=@()
    foreach($sv in @($r.servers)){
      if($null -eq $sv){continue}
      $id=[string]$sv.server_id
      if($id -notin @("wild","playground","other","lobby")){continue}
      $prop=$sv.PSObject.Properties["online"]
      $online=($null -ne $prop -and [bool]$prop.Value)
      $found+= [ordered]@{id=$id;online=$online}
    }
    if($found.Count -ne 4){return [ordered]@{status="INCOMPLETE";servers=$found}}
    return [ordered]@{status="CAPTURED";servers=$found}
  }catch{return [ordered]@{status="UNAVAILABLE";servers=@()}}
}
function OnlineFor([object]$Fleet,[string]$Id){
  foreach($entry in @($Fleet.servers)){
    if([string]$entry.id -eq $Id){return [bool]$entry.online}
  }
  return $false
}
if($Synthetic){
  $l=$null
  try{
    $l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $l.Start()
    $p=[int]([System.Net.IPEndPoint]$l.LocalEndpoint).Port
    if(-not (Test-LocalTcp $p)){throw "SYNTHETIC_LOCAL_LISTENER_UNREACHABLE"}
    $l.Stop();$l=$null
    $afterStop=Test-LocalTcp $p
    if($afterStop){throw "SYNTHETIC_CLOSED_LOCAL_LISTENER_REACHED"}
    [ordered]@{schema=1;phase="12.10-loopback-compare";synthetic=$true;read_only=$true
      result="SYNTHETIC_PASS";control_open_works=$true;control_closed_denied=$true;mutation_performed=$false
    }|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "Day12 Loopback read-only probe SYNTHETIC_PASS"
    exit 0
  }finally{if($null -ne $l){$l.Stop()}}
}
$before=Get-Fleet
$rows=@()
foreach($target in $targets){
  if(-not (OnlineFor $before $target.id)){continue}
  $j=Test-LocalTcp ([int]$target.java)
  $r=Test-LocalTcp ([int]$target.rcon)
  $rows+= [ordered]@{id=$target.id;gsc_online_at_start=$true
    java_port=[int]$target.java;java_loopback_tcp_connected=[bool]$j
    rcon_port=[int]$target.rcon;rcon_loopback_tcp_connected=[bool]$r}
}
$after=Get-Fleet
$consistent=($before.status -eq "CAPTURED" -and $after.status -eq "CAPTURED")
if($consistent){
  foreach($t in $targets){
    if((OnlineFor $before $t.id) -ne (OnlineFor $after $t.id)){$consistent=$false}
  }
}
$state=if($consistent){"CAPTURED_REVIEW_REQUIRED"}else{"CHECK_REQUIRED"}
$missing=@($rows|Where-Object{-not $_.java_loopback_tcp_connected -or -not $_.rcon_loopback_tcp_connected})
$report=[ordered]@{
  schema=1;phase="12.10-loopback-compare";synthetic=$false;read_only=$true
  generated_at=(Get-Date).ToString("o");result=$state
  fleet_before=$before;fleet_after=$after;stable_fleet=$consistent
  observed_online_server_count=$rows.Count;online_port_connectivity=$rows
  online_servers_with_unreachable_port=$missing.Count
  notes=@(
    "At most one TCP connect per online Java and RCON port to explicit 127.0.0.1; no Minecraft/RCON protocol message or credentials sent.",
    "A successful TCP connect does NOT prove a loopback-only listener. It only distinguishes an unobserved listener from an unreachable local endpoint.",
    "A failed connection may mean service not listening, a transient timeout, or local access restriction. Reconcile with fleet status before action.",
    "This tool does not change firewall, GSC configuration, servers, worlds, backups or ACLs. Brief TCP handshakes can appear in server logs.",
    "Do not change the backend_ports_private canonical FAIL/PASS state from this targeted report alone."
  );mutation_performed=$false;secrets_exported=$false
}
$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Day12 loopback comparison: "+$state)
Write-Host ("Online servers with unreachable Java or RCON port: "+$missing.Count)
Write-Host ("Report: "+$out)
if($state -ne "CAPTURED_REVIEW_REQUIRED"){exit 2}
exit 0
