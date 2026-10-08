[CmdletBinding()]
param([string]$TargetIPv4="",[string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Is-PrivateLANIPv4([string]$AddressText){
  $parsed=$null
  if(-not [System.Net.IPAddress]::TryParse($AddressText,[ref]$parsed)){return $false}
  if($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork){return $false}
  $b=$parsed.GetAddressBytes()
  return ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168))
}

function Probe-Tcp([string]$AddressText,[int]$Port,[int]$TimeoutMs=1100){
  $client=New-Object System.Net.Sockets.TcpClient
  $async=$null
  try{
    $async=$client.BeginConnect($AddressText,$Port,$null,$null)
    if(-not $async.AsyncWaitHandle.WaitOne($TimeoutMs,$false)){return $false}
    $client.EndConnect($async)
    return [bool]$client.Connected
  }catch{return $false}finally{
    if($null -ne $async){$async.AsyncWaitHandle.Dispose()}
    $client.Dispose()
  }
}

if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-LAN-Proof"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-LAN-Proof-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  if(-not(Is-PrivateLANIPv4 "192.168.0.10") -or -not(Is-PrivateLANIPv4 "10.2.3.4") -or
    -not(Is-PrivateLANIPv4 "172.31.0.1") -or (Is-PrivateLANIPv4 "172.32.1.1") -or
    (Is-PrivateLANIPv4 "127.0.0.1") -or (Is-PrivateLANIPv4 "8.8.8.8") -or
    (Is-PrivateLANIPv4 "not-an-ip")){
    throw "LAN private IPv4 validation synthetic regression"
  }
  [ordered]@{schema=1;phase="12.10-LAN-proof";read_only=$true;synthetic=$true;result="SYNTHETIC_PASS";mutation_performed=$false} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "LAN proof synthetic PASS"
  exit 0
}

Write-Host "=========================================================="
Write-Host " DAY 12.10 - LAN REACHABILITY PROOF (SECOND PC ONLY)"
Write-Host "=========================================================="
Write-Host "Run this from a DIFFERENT Windows PC on the same LAN."
Write-Host "Use the server PC's local IPv4 (typically 192.168.x.x or 10.x.x.x)."
Write-Host "No server changes, credentials, or IP addresses are exported."
Write-Host ""
if([string]::IsNullOrWhiteSpace($TargetIPv4)){
  $TargetIPv4=(Read-Host "SERVER PC LAN IPv4").Trim()
}
if(-not(Is-PrivateLANIPv4 $TargetIPv4)){
  Write-Host "[ERROR] Enter a valid private LAN IPv4. Localhost or a public IP cannot be used."
  exit 2
}
$serviceRunning=$false
try{
  $svc=Get-Service "Geumyi Server Center Host" -ErrorAction Stop
  $serviceRunning=($svc.Status -eq "Running")
}catch{}
$targets=@(
  [ordered]@{port=25565;label="public-java-wild";role="positive-control"},
  [ordered]@{port=25566;label="public-java-playground";role="positive-control"},
  [ordered]@{port=25567;label="public-java-other";role="positive-control"},
  [ordered]@{port=25570;label="private-java-wild";role="private-check"},
  [ordered]@{port=25571;label="private-java-playground";role="private-check"},
  [ordered]@{port=25572;label="private-java-other";role="private-check"},
  [ordered]@{port=25573;label="private-java-lobby";role="private-check"},
  [ordered]@{port=25575;label="private-rcon-wild";role="private-check"},
  [ordered]@{port=25576;label="private-rcon-playground";role="private-check"},
  [ordered]@{port=25577;label="private-rcon-other";role="private-check"},
  [ordered]@{port=25579;label="private-rcon-lobby";role="private-check"}
)
$results=@()
foreach($t in $targets){
  $connected=Probe-Tcp $TargetIPv4 ([int]$t.port)
  $results+= [ordered]@{port=[int]$t.port;role=[string]$t.role;label=[string]$t.label;tcp_connect=$connected}
  Write-Host ("{0,-29} {1}" -f $t.label,$(if($connected){"CONNECTED"}else{"NO_CONNECTION"}))
}
$exposed=@($results|Where-Object{$_.role -eq "private-check" -and $_.tcp_connect})
$controls=@($results|Where-Object{$_.role -eq "positive-control" -and $_.tcp_connect})
$report=[ordered]@{
  schema=1;phase="12.10-LAN-proof";read_only=$true;synthetic=$false
  generated_at=(Get-Date).ToString("o");result="CAPTURED_REVIEW_REQUIRED"
  execution_context=[ordered]@{server_host_service_running_on_test_pc=$serviceRunning;target_scope="PRIVATE_IPV4_REDACTED"}
  probes=$results
  private_ports_reachable_count=$exposed.Count;public_controls_reachable_count=$controls.Count
  notes=@(
    "Must run on a separate Windows PC with the actual server PC LAN IPv4.",
    "A positive private-port TCP connection is an exposure signal requiring investigation.",
    "No connection may be caused by firewall/routing; negative results do not prove loopback binding.",
    "If all public controls fail, the remote host/path may be unreachable and the test is inconclusive.",
    "No credentials, LAN IP values or packet contents are included in the JSON."
  )
  mutation_performed=$false;secrets_exported=$false
}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ""
Write-Host ("Results: "+$out)
Write-Host "The existing 12.10 final bind verification remains separate and fail-closed."
exit 0
