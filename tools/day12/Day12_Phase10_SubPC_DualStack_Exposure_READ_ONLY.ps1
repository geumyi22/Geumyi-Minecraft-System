[CmdletBinding()]
param(
  [string]$TargetIPv4="",
  [string]$TargetIPv6="",
  [string]$OutputDir="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Read-only, fixed 11-port TCP probe from a SECOND Windows computer only.
# No firewall, service, RCON, Java, Velocity, GSC or backend mutations.
# No raw IP, MAC, name, PID, interface alias, command line or secrets exported.
$privatePorts=@(25570,25571,25572,25573,25575,25576,25577,25579)
$publicControls=@(25565,25566,25567)

function Test-IPv4PrivateAddress([Net.IPAddress]$IP){
  if($null -eq $IP -or $IP.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return $false}
  $b=$IP.GetAddressBytes()
  return ($b[0] -eq 10 -or
    ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
    ($b[0] -eq 192 -and $b[1] -eq 168))
}
function Test-IPv6RemoteCandidate([Net.IPAddress]$IP){
  if($null -eq $IP -or $IP.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6){return $false}
  if([Net.IPAddress]::IsLoopback($IP) -or $IP.IsIPv6Multicast -or $IP.IsIPv6SiteLocal -or
     $IP.Equals([Net.IPAddress]::IPv6Any) -or $IP.IsIPv4MappedToIPv6){return $false}
  $b=$IP.GetAddressBytes()
  if(($b[0] -eq 0 -and $b[1] -eq 0) -or
     ($b[0] -eq 0xff)){return $false}
  return $true
}
function Get-AddressClass([Net.IPAddress]$IP){
  if($IP.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){return "RFC1918_LAN_IPV4"}
  $b=$IP.GetAddressBytes()
  if(($b[0] -band 0xfe) -eq 0xfc){return "IPV6_ULA"}
  if($b[0] -eq 0xfe -and ($b[1] -band 0xc0) -eq 0x80){return "IPV6_LINK_LOCAL"}
  return "IPV6_GLOBAL_OR_OTHER"
}
function Probe-Tcp([Net.IPAddress]$IP,[int]$Port,[int]$TimeoutMs=1000){
  $client=$null;$task=$null
  try{
    $client=[Net.Sockets.TcpClient]::new($IP.AddressFamily)
    $task=$client.ConnectAsync($IP,$Port)
    if(-not $task.Wait($TimeoutMs)){return "TIMEOUT"}
    if($client.Connected){return "CONNECTED"}
    return "REJECTED"
  }catch{
    # Intentional: never export raw exception (may contain target IP / paths).
    return "REJECTED_OR_NETWORK_ERROR"
  }finally{
    if($null -ne $client){$client.Dispose()}
  }
}
function Test-LocalTarget([Net.IPAddress]$IP){
  try{
    $all=@(Get-NetIPAddress -ErrorAction Stop)
  }catch{return "UNAVAILABLE"}
  foreach($item in $all){
    $p=$null
    if([Net.IPAddress]::TryParse([string]$item.IPAddress,[ref]$p)){
      if($IP.Equals($p)){return "LOCAL_SELF"}
    }
  }
  return "REMOTE_CANDIDATE"
}
function Summarize-Family([object[]]$Rows,[string]$Family){
  $part=@($Rows|Where-Object{$_.family -eq $Family})
  if($part.Count -ne 11){return [ordered]@{family=$Family;status="NOT_TESTED";private_connected=0;public_connected=0}}
  $exposure=@($part|Where-Object{$_.role -eq "private" -and $_.outcome -eq "CONNECTED"}).Count
  $controls=@($part|Where-Object{$_.role -eq "public-control" -and $_.outcome -eq "CONNECTED"}).Count
  $status=if($exposure -gt 0){"PRIVATE_BACKEND_REACHABLE_INVESTIGATE"}
    elseif($controls -eq 0){"INCONCLUSIVE_NO_PUBLIC_CONTROL"}
    else{"REMOTE_PRIVATE_UNREACHABLE_AT_TESTED_VANTAGE"}
  return [ordered]@{family=$Family;status=$status;private_connected=$exposure;public_connected=$controls}
}
function Assert-Synthetic {
  $v4=[Net.IPAddress]::Parse("192.168.10.1")
  $v6=[Net.IPAddress]::Parse("fd12::5")
  if(-not(Test-IPv4PrivateAddress $v4) -or -not(Test-IPv6RemoteCandidate $v6) -or
     -not(Test-IPv6RemoteCandidate ([Net.IPAddress]::Parse("2001:db8::4"))) -or
     (Test-IPv4PrivateAddress ([Net.IPAddress]::Parse("127.0.0.1"))) -or
     (Test-IPv4PrivateAddress ([Net.IPAddress]::Parse("198.51.100.1"))) -or
     (Test-IPv6RemoteCandidate ([Net.IPAddress]::Parse("::1"))) -or
     (Test-IPv6RemoteCandidate ([Net.IPAddress]::Parse("::"))) -or
     (Test-IPv6RemoteCandidate ([Net.IPAddress]::Parse("ff02::1"))) -or
     (Get-AddressClass $v6) -ne "IPV6_ULA"){throw "ADDRESS_GUARD_REGRESSION"}
  $positive=@()
  foreach($p in $privatePorts){$positive+= [pscustomobject]@{family="IPv4";port=$p;role="private";outcome="TIMEOUT"}}
  foreach($p in $publicControls){$positive+= [pscustomobject]@{family="IPv4";port=$p;role="public-control";outcome="CONNECTED"}}
  $ok=Summarize-Family $positive "IPv4"
  $noCtrl=Summarize-Family @($positive|ForEach-Object{
    [pscustomobject]@{family=$_.family;port=$_.port;role=$_.role;outcome=$(if($_.role -eq "public-control"){"TIMEOUT"}else{$_.outcome})}
  }) "IPv4"
  $hit=Summarize-Family @($positive|ForEach-Object{
    [pscustomobject]@{family=$_.family;port=$_.port;role=$_.role;outcome=$(if($_.port -eq 25575){"CONNECTED"}else{$_.outcome})}
  }) "IPv4"
  $missing=Summarize-Family @($positive | Select-Object -First 10) "IPv4"
  if($ok.status -ne "REMOTE_PRIVATE_UNREACHABLE_AT_TESTED_VANTAGE" -or
     $noCtrl.status -ne "INCONCLUSIVE_NO_PUBLIC_CONTROL" -or
     $hit.status -ne "PRIVATE_BACKEND_REACHABLE_INVESTIGATE" -or
     $missing.status -ne "NOT_TESTED"){throw "DUAL_STACK_CLASSIFIER_REGRESSION"}
}

if(-not $OutputDir){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-DualStack-Proof"
}
if($Synthetic){
  Assert-Synthetic
  New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
  $f=Join-Path $OutputDir "Day12-SubPC-DualStack-Synthetic.json"
  [ordered]@{schema=1;phase="12.10-subpc-dualstack";synthetic=$true
    read_only=$true;result="SYNTHETIC_PASS";mutation_performed=$false
    private_ports_probed=$false;canonical_backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $f -Encoding UTF8
  Write-Host "SYNTHETIC_PASS: dual-stack parser/classifier only, no network connections."
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "WINDOWS_SECOND_PC_ONLY"}
# Fail closed: the local management/server PC must never run the remote-vantage tool.
try{
  $svc=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
  if($null -ne $svc){throw "REFUSE_SERVER_PC_HOST_SERVICE_PRESENT"}
}catch{
  if($_.Exception.Message -eq "REFUSE_SERVER_PC_HOST_SERVICE_PRESENT"){throw}
  throw "SERVER_PC_GUARD_UNAVAILABLE"
}
if(-not $TargetIPv4){$TargetIPv4=(Read-Host "Minecraft server PC LAN IPv4 (RFC1918)").Trim()}
$v4=$null;$v6=$null
if(-not [Net.IPAddress]::TryParse($TargetIPv4,[ref]$v4) -or -not(Test-IPv4PrivateAddress $v4)){
  throw "INVALID_PRIVATE_SERVER_IPV4"
}
if(-not $TargetIPv6){
  Write-Host "IPv6 is optional, but without a real server IPv6 target the IPv6 claim remains UNVERIFIED."
  $TargetIPv6=(Read-Host "Server PC IPv6 (blank = UNVERIFIED)").Trim()
}
if($TargetIPv6){
  if(-not[Net.IPAddress]::TryParse($TargetIPv6,[ref]$v6) -or -not(Test-IPv6RemoteCandidate $v6)){
    throw "INVALID_SERVER_IPV6"
  }
}
if((Test-LocalTarget $v4) -ne "REMOTE_CANDIDATE"){throw "IPV4_IS_LOCAL_OR_INTERFACE_INVENTORY_FAILED"}
if($null -ne $v6 -and (Test-LocalTarget $v6) -ne "REMOTE_CANDIDATE"){throw "IPV6_IS_LOCAL_OR_INTERFACE_INVENTORY_FAILED"}
$rows=@();$targets=@()
$targets+= [pscustomobject]@{family="IPv4";ip=$v4;class=(Get-AddressClass $v4)}
if($null -ne $v6){$targets+= [pscustomobject]@{family="IPv6";ip=$v6;class=(Get-AddressClass $v6)}}
foreach($target in $targets){
  foreach($port in (@($publicControls)+@($privatePorts))){
    $role=if($publicControls -contains $port){"public-control"}else{"private"}
    $outcome=Probe-Tcp $target.ip $port
    $rows+= [ordered]@{family=$target.family;port=$port;role=$role;outcome=$outcome}
    Write-Host ("{0} {1} {2}: {3}" -f $target.family,$role,$port,$outcome)
  }
}
$st4=Summarize-Family $rows "IPv4"
$st6=Summarize-Family $rows "IPv6"
$overall=if($st4.status -eq "PRIVATE_BACKEND_REACHABLE_INVESTIGATE" -or
            $st6.status -eq "PRIVATE_BACKEND_REACHABLE_INVESTIGATE"){"EXPOSURE_SIGNAL_REVIEW"}
  elseif($st4.status -eq "REMOTE_PRIVATE_UNREACHABLE_AT_TESTED_VANTAGE" -and
         $st6.status -eq "REMOTE_PRIVATE_UNREACHABLE_AT_TESTED_VANTAGE"){"DUAL_STACK_LAN_REACHABILITY_REVIEW_ONLY"}
  else{"INCOMPLETE_OR_SINGLE_FAMILY_REVIEW_ONLY"}
$report=[ordered]@{
  schema=1;phase="12.10-subpc-dualstack";generated_at=(Get-Date).ToString("o")
  synthetic=$false;read_only=$true;result=$overall
  execution_scope="SEPARATE_WINDOWS_PC_OPERATOR_ATTESTED"
  target_scopes=@($targets|ForEach-Object{$_.class})
  tcp_connect_results=$rows
  ipv4=$st4;ipv6=$st6
  public_tcp_controls="VELOCITY_JAVA_ONLY"
  bedrock_udp_controls="NOT_TESTED"
  overlay_vpn_external_routes="NOT_TESTED"
  canonical_backend_ports_private="UNCHANGED_FAIL"
  limitations=@(
    "Remote TCP connection tests do not prove exclusive local listener binding, PID ownership or all firewall paths.",
    "A successful Velocity TCP public control supports only this IP family and vantage; no Minecraft login/Bedrock UDP is claimed.",
    "No raw IP/PID/hostname/credentials/paths exported. Server PC should not run this script.",
    "IPv6 missing/no positive control means unverified, never PASS. Overlay/VPN requires separate approved evidence.",
    "No firewall, Java, GSC, RCON, proxy or backup settings changed."
  )
  mutation_performed=$false;secrets_exported=$false
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-SubPC-DualStack-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Report: "+$out)
Write-Host ("Scope verdict: "+$overall+"; canonical private bind+owner gate is still FAIL.")
exit 0
