[CmdletBinding()]
param([string]$TargetIPv6="",[string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# IPv6-only independent remote vantage. Never repeats the already established
# IPv4 3/3 public + 0/8 private result. Never changes services/firewall/config.
$public=@(25565,25566,25567)
$private=@(25570,25571,25572,25573,25575,25576,25577,25579)

function Test-RemoteIPv6([Net.IPAddress]$Ip) {
  if($null -eq $Ip -or $Ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6){return $false}
  if([Net.IPAddress]::IsLoopback($Ip) -or $Ip.IsIPv6Multicast -or $Ip.IsIPv4MappedToIPv6 -or
     $Ip.Equals([Net.IPAddress]::IPv6Any)){return $false}
  $b=$Ip.GetAddressBytes()
  return ($b[0] -ne 0 -or $b[1] -ne 0)
}
function Get-V6Class([Net.IPAddress]$Ip) {
  if($Ip.IsIPv6LinkLocal){return "LINK_LOCAL"}
  $b=$Ip.GetAddressBytes()
  if(($b[0] -band 0xfe) -eq 0xfc){return "ULA"}
  return "GLOBAL_OR_OTHER"
}
function Classify-IPv6Scope([Net.IPAddress]$Ip) {
  if(-not (Test-RemoteIPv6 $Ip)){return "INVALID_ADDRESS"}
  if($Ip.IsIPv6LinkLocal -and $Ip.ScopeId -eq 0){return "LINK_LOCAL_SCOPE_MISSING"}
  return "SCOPE_FORMAT_VALID"
}
function Get-IPv6LinkInterfaces {
  $up=@(Get-NetIPInterface -AddressFamily IPv6 -ErrorAction Stop |
    Where-Object { [string]$_.ConnectionState -eq "Connected" } |
    ForEach-Object { [int]$_.InterfaceIndex })
  $addresses=@(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop |
    Where-Object { ([string]$_.IPAddress).StartsWith("fe80:",[StringComparison]::OrdinalIgnoreCase) -and
      $up -contains [int]$_.InterfaceIndex } |
    ForEach-Object { [int]$_.InterfaceIndex } | Sort-Object -Unique)
  return @($addresses)
}
# The user may paste a server-side fe80::...%N address. The %N is local
# to the originating computer and MUST NOT be trusted as a SubPC zone even
# when the same numeric index happens to exist on both machines.
# This pure resolver is covered by synthetic tests without any OS/network IO.
function Resolve-SubPCLinkLocalScope([Net.IPAddress]$Target,[int[]]$LocalIndices,[int]$ChosenIndex=0) {
  if(-not (Test-RemoteIPv6 $Target)){return [pscustomobject]@{status="INVALID_ADDRESS";scope=0}}
  if(-not $Target.IsIPv6LinkLocal){return [pscustomobject]@{status="NOT_LINK_LOCAL";scope=0}}
  $valid=@($LocalIndices|Where-Object{$_ -gt 0}|Sort-Object -Unique)
  if($valid.Count -eq 0){return [pscustomobject]@{status="NO_LOCAL_INTERFACE";scope=0}}
  if($valid.Count -eq 1){
    return [pscustomobject]@{status="AUTO_LOCAL_INTERFACE";scope=[int]$valid[0]}
  }
  if($ChosenIndex -gt 0 -and $valid -contains $ChosenIndex){
    return [pscustomobject]@{status="SELECTED_LOCAL_INTERFACE";scope=$ChosenIndex}
  }
  return [pscustomobject]@{status="MULTIPLE_LOCAL_INTERFACES";scope=0}
}
function Tcp-Probe([Net.IPAddress]$IP,[int]$Port) {
  $c=$null;$task=$null
  try {
    $c=[Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetworkV6)
    $task=$c.ConnectAsync($IP,$Port)
    if(-not $task.Wait(1400)){return "TIMEOUT"}
    if($c.Connected){return "CONNECTED"}
    return "NOT_CONNECTED"
  } catch {
    $e=$_.Exception
    if($e -is [AggregateException]){$e=$e.GetBaseException()}
    if($e -is [Net.Sockets.SocketException]){
      switch([string]$e.SocketErrorCode) {
        "ConnectionRefused" {return "REFUSED"}
        "NetworkUnreachable" {return "NETWORK_UNREACHABLE"}
        "HostUnreachable" {return "HOST_UNREACHABLE"}
        "AddressNotAvailable" {return "ADDRESS_NOT_AVAILABLE"}
        "TimedOut" {return "TIMEOUT"}
      }
    }
    return "OTHER_NETWORK_ERROR"
  } finally {
    if($null -ne $c){$c.Dispose()}
  }
}
function Icmp-RouteSignal([Net.IPAddress]$IP) {
  $ping=$null
  try{
    $ping=[Net.NetworkInformation.Ping]::new()
    $r=$ping.Send($IP,1250)
    if($r.Status -eq [Net.NetworkInformation.IPStatus]::Success){return "ICMP_REACHABLE"}
    return "NO_ICMP_REPLY_OR_BLOCKED"
  }catch{return "NO_ICMP_REPLY_OR_BLOCKED"}
  finally{if($null -ne $ping){$ping.Dispose()}}
}
function Synthetic-Checks {
  $normal=[Net.IPAddress]::Parse("fd12::4")
  $linkNoScope=[Net.IPAddress]::Parse("fe80::55")
  $linkScoped=[Net.IPAddress]::Parse("fe80::55%4")
  if((Classify-IPv6Scope $normal) -ne "SCOPE_FORMAT_VALID" -or
     (Classify-IPv6Scope $linkNoScope) -ne "LINK_LOCAL_SCOPE_MISSING" -or
     (Classify-IPv6Scope $linkScoped) -ne "SCOPE_FORMAT_VALID" -or
     (Classify-IPv6Scope ([Net.IPAddress]::Parse("::1"))) -ne "INVALID_ADDRESS" -or
     (Classify-IPv6Scope ([Net.IPAddress]::Parse("ff02::1"))) -ne "INVALID_ADDRESS" -or
     (Get-V6Class $linkScoped) -ne "LINK_LOCAL"){
    throw "IPv6_ADDRESS_SCOPE_SYNTHETIC_REGRESSION"
  }
  # The server PC's explicit %15 must be ignored. For the same destination,
  # the single active local SubPC interface %7 must be chosen.
  $serverScoped=[Net.IPAddress]::Parse("fe80::55%15")
  $one=Resolve-SubPCLinkLocalScope $serverScoped @(7)
  $coincident=Resolve-SubPCLinkLocalScope $serverScoped @(15,7)
  $multiple=Resolve-SubPCLinkLocalScope $serverScoped @(7,9)
  $selected=Resolve-SubPCLinkLocalScope $serverScoped @(7,9) 9
  $invalidChoice=Resolve-SubPCLinkLocalScope $serverScoped @(7,9) 15
  $noInterface=Resolve-SubPCLinkLocalScope $serverScoped @()
  $nonlink=Resolve-SubPCLinkLocalScope $normal @(7)
  if($one.status -ne "AUTO_LOCAL_INTERFACE" -or $one.scope -ne 7 -or
     $coincident.status -ne "MULTIPLE_LOCAL_INTERFACES" -or
     $multiple.status -ne "MULTIPLE_LOCAL_INTERFACES" -or
     $selected.status -ne "SELECTED_LOCAL_INTERFACE" -or $selected.scope -ne 9 -or
     $invalidChoice.status -ne "MULTIPLE_LOCAL_INTERFACES" -or
     $noInterface.status -ne "NO_LOCAL_INTERFACE" -or
     $nonlink.status -ne "NOT_LINK_LOCAL"){
    throw "SERVER_VS_SUBPC_SCOPE_CORRECTION_REGRESSION"
  }
}
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-IPv6-Scope"}
if($Synthetic) {
  Synthetic-Checks
  New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
  [ordered]@{schema=1;phase="12.10-subpc-ipv6-scope-only";synthetic=$true;result="SYNTHETIC_PASS"
    ipv4_probes=0;ipv6_probes=0;read_only=$true;mutation_performed=$false
    canonical_backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $OutputDir "Day12-IPv6-Scope-Synthetic.json") -Encoding UTF8
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "WINDOWS_SUBPC_ONLY"}
$hostService=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
if($null -ne $hostService){throw "REFUSED_SERVER_PC_HOST_SERVICE_PRESENT"}
if(-not $TargetIPv6){
  Write-Host "SUBPC IPv6-only. The prior IPv4 result is preserved and NOT retested."
  Write-Host "Enter the SERVER PC IPv6 address (fe80:... link-local or other valid IPv6)."
  $TargetIPv6=(Read-Host "Server PC IPv6").Trim()
}
$ip=$null
if(-not [Net.IPAddress]::TryParse($TargetIPv6,[ref]$ip) -or -not (Test-RemoteIPv6 $ip)){
  throw "INVALID_SERVER_IPV6_ADDRESS"
}
$scopeResolution="NOT_APPLICABLE"
if($ip.IsIPv6LinkLocal) {
  $inputHadScope=($ip.ScopeId -gt 0)
  # The supplied %index may be the server PC index. Discard unconditionally
  # and resolve solely from the SubPC's current attached IPv6 adapters.
  $choices=@(Get-IPv6LinkInterfaces)
  $resolved=Resolve-SubPCLinkLocalScope $ip $choices
  if($resolved.status -eq "NO_LOCAL_INTERFACE"){
    throw "NO_ACTIVE_SUBPC_LINK_LOCAL_IPV6_INTERFACE"
  }
  if($resolved.status -eq "MULTIPLE_LOCAL_INTERFACES"){
    Write-Host "Multiple SUBPC IPv6 LAN interfaces found; the server's %index must not be reused."
    foreach($idx in $choices){
      $name="UNKNOWN"
      try{
        $adapter=Get-NetAdapter -InterfaceIndex ([int]$idx) -ErrorAction Stop
        $name=[string]$adapter.Name
      }catch{}
      Write-Host ("  SUBPC interface {0} : {1}" -f $idx,$name)
    }
    $chosen=0
    $raw=(Read-Host "Choose the SUBPC's active Ethernet/Wi-Fi LAN interface number").Trim()
    if(-not [int]::TryParse($raw,[ref]$chosen)){
      throw "SUBPC_IPV6_SCOPE_SELECTION_INVALID"
    }
    $resolved=Resolve-SubPCLinkLocalScope $ip $choices $chosen
    if($resolved.status -ne "SELECTED_LOCAL_INTERFACE"){
      throw "SUBPC_IPV6_SCOPE_SELECTION_INVALID"
    }
  }
  if($resolved.scope -le 0){throw "SUBPC_IPV6_SCOPE_UNRESOLVED"}
  $ip.ScopeId=[long]$resolved.scope
  $scopeResolution=if($inputHadScope){
    "INPUT_SERVER_SCOPE_REPLACED_WITH_SUBPC_SCOPE"
  }elseif($resolved.status -eq "AUTO_LOCAL_INTERFACE"){
    "AUTOMATIC_SINGLE_SUBPC_INTERFACE"
  }else{
    "OPERATOR_SELECTED_SUBPC_INTERFACE"
  }
  Write-Host "IPv6 link-local interface scope resolved using SUBPC network adapter."
}
if((Classify-IPv6Scope $ip) -ne "SCOPE_FORMAT_VALID"){throw "TARGET_IPV6_SCOPE_INVALID"}
# Refuse a target which equals a local SubPC address, ignoring %zone.
$locals=@(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop)
foreach($local in $locals){
  $x=$null
  if([Net.IPAddress]::TryParse([string]$local.IPAddress,[ref]$x)){
    if(([Convert]::ToBase64String($x.GetAddressBytes())) -eq
       ([Convert]::ToBase64String($ip.GetAddressBytes()))){throw "REFUSED_SUBPC_LOCAL_ADDRESS"}
  }
}
# ICMP is only a route/path signal. It must NEVER count as a positive TCP control.
$icmp=Icmp-RouteSignal $ip
$rows=@()
foreach($p in (@($public)+@($private))) {
  $role=if($public -contains $p){"VELOCITY_TCP_CONTROL"}else{"PRIVATE_JAVA_RCON"}
  $outcome=Tcp-Probe $ip $p
  $rows+= [ordered]@{port=$p;role=$role;outcome=$outcome}
  Write-Host ("IPv6 {0,-23} {1}: {2}" -f $role,$p,$outcome)
}
$exposed=@($rows|Where-Object{$_.role -eq "PRIVATE_JAVA_RCON" -and $_.outcome -eq "CONNECTED"}).Count
$controls=@($rows|Where-Object{$_.role -eq "VELOCITY_TCP_CONTROL" -and $_.outcome -eq "CONNECTED"}).Count
$result=if($exposed -gt 0){"REMOTE_IPV6_PRIVATE_PORT_REACHABLE_REVIEW"}
  elseif($controls -gt 0){"REMOTE_IPV6_PRIVATE_UNREACHABLE_TESTED_PATH_ONLY"}
  elseif($icmp -eq "ICMP_REACHABLE"){"IPV6_PATH_REACHABLE_BUT_NO_TCP_CONTROL"}
  else{"IPV6_PATH_OR_PUBLIC_TCP_UNVERIFIED"}
$report=[ordered]@{
  schema=1;phase="12.10-subpc-ipv6-scope-only";generated_at=(Get-Date).ToString("o")
  read_only=$true;synthetic=$false;mutation_performed=$false;secrets_exported=$false
  result=$result;target_family="IPv6";target_scope=(Get-V6Class $ip)
  local_interface_scope_resolution=$scopeResolution;scope_validated=$true
  icmp_route_signal=$icmp
  ipv4_probes=0;ipv6_tcp_probes=$rows
  private_connected=$exposed;public_control_connected=$controls
  canonical_backend_ports_private="UNCHANGED_FAIL"
  warnings=@(
    "IPv6 link-local zone is the SubPC interface index, not the server interface index.",
    "Successful IPv6 ping is NOT a TCP positive control. A failed ping may reflect ICMP filtering.",
    "A positive public TCP control proves only the tested IPv6 host/path, not all IPv6 exposure.",
    "A negative remote probe never proves exclusive kernel bind or Java/RCON socket ownership.",
    "No IPv4 retest, no server process/firewall/world/backup mutation."
  )
}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-IPv6-Scope-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Report: "+$out)
Write-Host ("IPv6-only result: "+$result)
exit 0
