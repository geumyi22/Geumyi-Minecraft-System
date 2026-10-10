[CmdletBinding()]
param([string]$ServerTailnetIPv4="",[string]$ServerTailnetIPv6="",[string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# SubPC-only Tailscale overlay vantage. Zero write/mutation to networking,
# GSC, Minecraft, firewall, operating services, or Golden backups.
# Do not print or export target IPs, hostnames, tokens, paths or peer identities.
$privatePorts=@(25570,25571,25572,25573,25575,25576,25577,25579)
$publicPorts=@(25565,25566,25567)
$apiControl=8787

function Test-TailnetIPv4([Net.IPAddress]$IP) {
  if($null -eq $IP -or $IP.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return $false}
  $bytes=$IP.GetAddressBytes()
  return ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127)
}
function Test-TailnetIPv6([Net.IPAddress]$IP) {
  if($null -eq $IP -or $IP.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6 -or
     $IP.IsIPv6LinkLocal -or $IP.IsIPv4MappedToIPv6 -or
     [Net.IPAddress]::IsLoopback($IP)){return $false}
  $b=$IP.GetAddressBytes()
  return ($b[0] -eq 0xfd -and $b[1] -eq 0x7a -and $b[2] -eq 0x11 -and
    $b[3] -eq 0x5c -and $b[4] -eq 0xa1 -and $b[5] -eq 0xe0)
}
function Probe-TCP([Net.IPAddress]$Ip,[int]$Port,[int]$TimeoutMs=1200) {
  $tcp=$null;$task=$null
  try {
    $tcp=[Net.Sockets.TcpClient]::new($Ip.AddressFamily)
    $task=$tcp.ConnectAsync($Ip,$Port)
    if(-not $task.Wait($TimeoutMs)){return "TIMEOUT"}
    if($tcp.Connected){return "CONNECTED"}
    return "NOT_CONNECTED"
  }catch{
    return "REFUSED_OR_NETWORK_ERROR"
  }finally{
    if($null -ne $tcp){$tcp.Dispose()}
  }
}
function Classify-Family([object[]]$Rows,[string]$Family) {
  $rs=@($Rows|Where-Object{$_.family -eq $Family})
  if($rs.Count -ne 12){
    return [ordered]@{family=$Family;status="NOT_TESTED";public_control_connected=0;private_connected=0}
  }
  $control=@($rs|Where-Object{$_.role -eq "POSITIVE_CONTROL" -and $_.outcome -eq "CONNECTED"}).Count
  $private=@($rs|Where-Object{$_.role -eq "PRIVATE_BACKEND" -and $_.outcome -eq "CONNECTED"}).Count
  $status=if($private -gt 0){"TAILNET_PRIVATE_BACKEND_REACHABLE_REVIEW"}
    elseif($control -eq 0){"TAILNET_PATH_INCONCLUSIVE_NO_TCP_CONTROL"}
    else{"TAILNET_PRIVATE_BACKEND_UNREACHABLE_TESTED_PATH_ONLY"}
  return [ordered]@{family=$Family;status=$status;public_control_connected=$control;private_connected=$private}
}
function Synthetic-Checks {
  if(-not (Test-TailnetIPv4 ([Net.IPAddress]::Parse("100.84.252.113"))) -or
    (Test-TailnetIPv4 ([Net.IPAddress]::Parse("100.128.1.2"))) -or
    (Test-TailnetIPv4 ([Net.IPAddress]::Parse("192.168.0.2"))) -or
    -not (Test-TailnetIPv6 ([Net.IPAddress]::Parse("fd7a:115c:a1e0::3401:fcbb"))) -or
    (Test-TailnetIPv6 ([Net.IPAddress]::Parse("fd12::1"))) -or
    (Test-TailnetIPv6 ([Net.IPAddress]::Parse("fe80::5")))){
    throw "TAILNET_ADDRESS_SCOPE_REGRESSION"
  }
  $rs=@()
  foreach($p in $privatePorts){$rs+= [pscustomobject]@{family="IPv4";port=$p;role="PRIVATE_BACKEND";outcome="TIMEOUT"}}
  foreach($p in ($publicPorts+@($apiControl))){$rs+= [pscustomobject]@{family="IPv4";port=$p;role="POSITIVE_CONTROL";outcome="TIMEOUT"}}
  $ok=Classify-Family @($rs|ForEach-Object{
    [pscustomobject]@{family=$_.family;port=$_.port;role=$_.role;outcome=$(if($_.port -eq 8787){"CONNECTED"}else{$_.outcome})}
  }) "IPv4"
  $no=Classify-Family $rs "IPv4"
  $exposed=Classify-Family @($rs|ForEach-Object{
    [pscustomobject]@{family=$_.family;port=$_.port;role=$_.role;outcome=$(if($_.port -eq 25575){"CONNECTED"}else{$_.outcome})}
  }) "IPv4"
  if($ok.status -ne "TAILNET_PRIVATE_BACKEND_UNREACHABLE_TESTED_PATH_ONLY" -or
     $no.status -ne "TAILNET_PATH_INCONCLUSIVE_NO_TCP_CONTROL" -or
     $exposed.status -ne "TAILNET_PRIVATE_BACKEND_REACHABLE_REVIEW" -or
     (Classify-Family @($rs|Select-Object -First 11) "IPv4").status -ne "NOT_TESTED"){
    throw "TAILNET_BOUNDED_CLASSIFIER_REGRESSION"
  }
}
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Tailnet-Proof"}
if($Synthetic){
  Synthetic-Checks
  New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
  [ordered]@{schema=1;phase="12.10-tailnet-vantage";synthetic=$true;read_only=$true
    result="SYNTHETIC_PASS";private_ports_probed=$false;mutation_performed=$false
    canonical_backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $OutputDir "Day12-Tailnet-Synthetic.json") -Encoding UTF8
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "SUBPC_WINDOWS_ONLY"}
$svc=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
if($null -ne $svc){throw "REFUSE_SERVER_PC_HOST_SERVICE_PRESENT"}
$adapter=@(Get-NetAdapter -ErrorAction Stop | Where-Object {
  $_.Name -like "*Tailscale*" -and [string]$_.Status -eq "Up"
})
if($adapter.Count -ne 1){throw "SUBPC_TAILSCALE_ADAPTER_NOT_EXACTLY_ONE_UP"}
$ownAddresses=@(Get-NetIPAddress -InterfaceIndex ([int]$adapter[0].ifIndex) -ErrorAction Stop)
$ownIPv4=@($ownAddresses|Where-Object{
  $v=$null
  [Net.IPAddress]::TryParse([string]$_.IPAddress,[ref]$v) -and (Test-TailnetIPv4 $v)
})
if($ownIPv4.Count -lt 1){throw "SUBPC_TAILNET_IPV4_UNAVAILABLE"}
if(-not $ServerTailnetIPv4){
  Write-Host "Tailscale OVERLAY (not Wi-Fi LAN). IPv4+IPv6 physical LAN tests are already complete."
  Write-Host "Enter the SERVER PC Tailscale IPv4 100.x.y.z (not local 192.168 address)."
  $ServerTailnetIPv4=(Read-Host "Server PC Tailscale IPv4").Trim()
}
$ipv4=$null;$ipv6=$null
if(-not [Net.IPAddress]::TryParse($ServerTailnetIPv4,[ref]$ipv4) -or
   -not (Test-TailnetIPv4 $ipv4)){throw "INVALID_SERVER_TAILNET_IPV4"}
if(-not $ServerTailnetIPv6){
  Write-Host "Optional server PC Tailscale IPv6 (fd7a:115c:a1e0::...), blank = IPv6 OVERLAY UNVERIFIED."
  $ServerTailnetIPv6=(Read-Host "Server PC Tailscale IPv6").Trim()
}
if($ServerTailnetIPv6){
  if(-not [Net.IPAddress]::TryParse($ServerTailnetIPv6,[ref]$ipv6) -or
     -not (Test-TailnetIPv6 $ipv6)){throw "INVALID_SERVER_TAILNET_IPV6"}
}
foreach($target in @($ipv4,$ipv6)|Where-Object{$null -ne $_}){
  $targetBytes=[Convert]::ToBase64String($target.GetAddressBytes())
  foreach($own in $ownAddresses){
    $local=$null
    if([Net.IPAddress]::TryParse([string]$own.IPAddress,[ref]$local) -and
       [Convert]::ToBase64String($local.GetAddressBytes()) -eq $targetBytes){
      throw "REFUSE_SUBPC_SELF_TAILNET_TARGET"
    }
  }
}
$rows=@()
foreach($dest in @(
  [pscustomobject]@{family="IPv4";ip=$ipv4},
  [pscustomobject]@{family="IPv6";ip=$ipv6}
)){
  if($null -eq $dest.ip){continue}
  foreach($p in ($publicPorts+@($apiControl)+$privatePorts)){
    $role=if($privatePorts -contains $p){"PRIVATE_BACKEND"}else{"POSITIVE_CONTROL"}
    $outcome=Probe-TCP $dest.ip $p
    $rows+=[ordered]@{family=$dest.family;port=$p;role=$role;outcome=$outcome}
    Write-Host ("Tailnet {0} {1} {2}: {3}" -f $dest.family,$role,$p,$outcome)
  }
}
$v4=Classify-Family $rows "IPv4"
$v6=Classify-Family $rows "IPv6"
$overall=if($v4.private_connected -gt 0 -or $v6.private_connected -gt 0){"OVERLAY_PRIVATE_ACCESS_SIGNAL_REVIEW"}
  elseif($v4.status -eq "TAILNET_PRIVATE_BACKEND_UNREACHABLE_TESTED_PATH_ONLY" -and
         $v6.status -eq "TAILNET_PRIVATE_BACKEND_UNREACHABLE_TESTED_PATH_ONLY"){"OVERLAY_BOTH_FAMILIES_BOUNDED_NEGATIVE"}
  else{"OVERLAY_INCOMPLETE_OR_BOUNDED_NEGATIVE"}
$report=[ordered]@{
  schema=1;phase="12.10-tailnet-vantage";generated_at=(Get-Date).ToString("o")
  synthetic=$false;read_only=$true;mutation_performed=$false;secrets_exported=$false
  result=$overall;target_scope="TAILNET_CGNAT_V4_AND_OPTIONAL_FD7A_IPV6"
  ipv4=$v4;ipv6=$v6;tcp_connect_results=$rows
  public_positive_controls=@(25565,25566,25567,8787)
  canonical_backend_ports_private="UNCHANGED_FAIL"
  notes=@(
    "Requires separate Windows SubPC with one connected Tailscale adapter; refuses local self-address.",
    "A positive control confirms only TCP reachability to that tailnet IP and port, not host/app identity.",
    "Tailscale TCP negative results prove only this tailnet peer's tested vantage/policy, not global tailnet ACL.",
    "Direct Windows socket PID/bind and Internet/multiple overlay paths remain unresolved.",
    "No authentication/API request, no Java login, no RCON/HTTP commands, no data or firewall modification."
  )
}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-Tailnet-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Tailnet report: "+$out)
Write-Host ("Result: "+$overall+"; real strict backend_ports_private remains UNCHANGED FAIL.")
exit 0
