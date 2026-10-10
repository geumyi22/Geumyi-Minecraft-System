[CmdletBinding()]
param(
  [string]$ServerTailnetIPv4="",
  [string]$ServerTailnetIPv6="",
  [string]$OutputDir="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
Add-Type -AssemblyName System.Net.Http
# The selected GETs may create routine rejected-request audit entries on GSC.
# No configuration, file, firewall, job, service or Minecraft world changes.
# Never export IPs, bodies, headers, tokens, hostnames or identifiers.
$paths=@("/api/v1/info","/api/v1/snapshot","/api/v1/devices","/api/settings")
function Is-TailnetV4([Net.IPAddress]$IP){
  if($null -eq $IP -or $IP.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return $false}
  $b=$IP.GetAddressBytes()
  return ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127)
}
function Is-TailnetV6([Net.IPAddress]$IP){
  if($null -eq $IP -or $IP.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6 -or
     $IP.IsIPv4MappedToIPv6 -or $IP.IsIPv6LinkLocal){return $false}
  $b=$IP.GetAddressBytes()
  return ($b[0] -eq 0xfd -and $b[1] -eq 0x7a -and $b[2] -eq 0x11 -and
    $b[3] -eq 0x5c -and $b[4] -eq 0xa1 -and $b[5] -eq 0xe0)
}
function Classify-Family([object[]]$Rows,[string]$Family,[bool]$HealthIdentity){
  $r=@($Rows|Where-Object{$_.family -eq $Family})
  $unexpected=@($r|Where-Object{$_.status_code -ge 200 -and $_.status_code -lt 400}).Count
  $deny=@($r|Where-Object{$_.status_code -eq 401}).Count
  $other=@($r|Where-Object{$_.status_code -eq 403}).Count
  $result=if($unexpected -gt 0){"POTENTIAL_UNAUTHENTICATED_API_EXPOSURE"}
    elseif($r.Count -ne 4 -or -not $HealthIdentity){"INCONCLUSIVE_OR_SERVICE_ID_UNVERIFIED"}
    elseif($deny -eq 4){"GSC_REMOTE_API_REQUIRES_AUTH_TESTED_PATH"}
    elseif($deny+$other -eq 4){"DENIED_BUT_AUTH_VS_NETWORK_GATE_NOT_FULLY_PROVEN"}
    else{"INCONCLUSIVE_HTTP_RESPONSE"}
  return [ordered]@{family=$Family;result=$result;protected_401_count=$deny
    protected_403_count=$other;unexpected_success_count=$unexpected;gsc_service_identity=$HealthIdentity}
}
function Synthetic-Checks {
  $v4=[Net.IPAddress]::Parse("100.64.0.10")
  $v6=[Net.IPAddress]::Parse("fd7a:115c:a1e0::1234")
  if(-not(Is-TailnetV4 $v4) -or -not(Is-TailnetV6 $v6) -or
     (Is-TailnetV4 ([Net.IPAddress]::Parse("192.168.0.2"))) -or
     (Is-TailnetV4 ([Net.IPAddress]::Parse("100.128.0.1"))) -or
     (Is-TailnetV6 ([Net.IPAddress]::Parse("fd12::1")))){throw "ADDRESS_GUARD_SYNTHETIC_FAILURE"}
  $rs=@($paths|ForEach-Object{[pscustomobject]@{family="IPv4";path_key=$_;status_code=401}})
  $good=Classify-Family $rs "IPv4" $true
  $idMissing=Classify-Family $rs "IPv4" $false
  $bad=Classify-Family @($rs|ForEach-Object{
    [pscustomobject]@{family=$_.family;path_key=$_.path_key
      status_code=$(if($_.path_key -eq "/api/settings"){200}else{401})}
  }) "IPv4" $true
  $gate=Classify-Family @($rs|ForEach-Object{
    [pscustomobject]@{family=$_.family;path_key=$_.path_key;status_code=403}
  }) "IPv4" $true
  if($good.result -ne "GSC_REMOTE_API_REQUIRES_AUTH_TESTED_PATH" -or
     $idMissing.result -ne "INCONCLUSIVE_OR_SERVICE_ID_UNVERIFIED" -or
     $bad.result -ne "POTENTIAL_UNAUTHENTICATED_API_EXPOSURE" -or
     $gate.result -ne "DENIED_BUT_AUTH_VS_NETWORK_GATE_NOT_FULLY_PROVEN"){
    throw "AUTH_DENIAL_CLASSIFIER_SYNTHETIC_FAILURE"
  }
}
function Remote-Request([Net.Http.HttpClient]$Client,[string]$URI,[bool]$IsHealth) {
  $request=$null;$response=$null
  try {
    $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$URI)
    $response=$Client.SendAsync($request).GetAwaiter().GetResult()
    $status=[int]$response.StatusCode
    $service=$false
    if($IsHealth -and $status -eq 200){
      $content=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      try{
        $health=$content|ConvertFrom-Json
        $service=([bool]$health.ok -and [int]$health.generation -eq 4 -and
          [bool]$health.service -and [string]$health.version -match '^4\.3\.')
      }catch{}
    }
    return [pscustomobject]@{status_code=$status;service_identity=$service}
  }catch{
    return [pscustomobject]@{status_code=0;service_identity=$false}
  }finally{
    if($null -ne $response){$response.Dispose()}
    if($null -ne $request){$request.Dispose()}
  }
}
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Tailnet-Auth"}
if($Synthetic){
  Synthetic-Checks
  New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
  [ordered]@{schema=1;phase="12.10-tailnet-api-auth";synthetic=$true
    result="SYNTHETIC_PASS";read_only_client=$true;production_config_changes=$false
    unauthorized_audit_entries_produced=$false;network_requests=0
    backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 4|Set-Content (Join-Path $OutputDir "Day12-Tailnet-Auth-Synthetic.json") -Encoding UTF8
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "SUBPC_WINDOWS_ONLY"}
if($null -ne (Get-Service "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){
  throw "REFUSE_SERVER_PC_HOST_SERVICE_PRESENT"
}
$adapters=@(Get-NetAdapter -ErrorAction Stop|Where-Object{
  $_.Name -like '*Tailscale*' -and [string]$_.Status -eq 'Up'
})
if($adapters.Count -ne 1){throw "SUBPC_TAILSCALE_NOT_UP"}
$own=@(Get-NetIPAddress -InterfaceIndex ([int]$adapters[0].ifIndex) -ErrorAction Stop)
if(-not $ServerTailnetIPv4){
  Write-Host "SubPC-only authenticated API safety check, not a TCP port scan."
  Write-Host "No tokens or passwords requested. A few denied GET requests may be logged by GSC."
  $ServerTailnetIPv4=(Read-Host "Server PC Tailscale IPv4 (100.x.x.x)").Trim()
}
$ipv4=$null;$ipv6=$null
if(-not [Net.IPAddress]::TryParse($ServerTailnetIPv4,[ref]$ipv4) -or -not (Is-TailnetV4 $ipv4)){
  throw "INVALID_TAILNET_TARGET_IPV4"
}
if(-not $ServerTailnetIPv6){
  $ServerTailnetIPv6=(Read-Host "Server PC Tailscale IPv6 (blank = NOT_TESTED)").Trim()
}
if($ServerTailnetIPv6){
  if(-not [Net.IPAddress]::TryParse($ServerTailnetIPv6,[ref]$ipv6) -or -not (Is-TailnetV6 $ipv6)){
    throw "INVALID_TAILNET_TARGET_IPV6"
  }
}
foreach($addr in (@($ipv4,$ipv6)|Where-Object{$null -ne $_})){
  $bytes=[Convert]::ToBase64String($addr.GetAddressBytes())
  foreach($candidate in $own){
    $self=$null
    if([Net.IPAddress]::TryParse([string]$candidate.IPAddress,[ref]$self) -and
       [Convert]::ToBase64String($self.GetAddressBytes()) -eq $bytes){
      throw "REFUSE_SELF_TARGET"
    }
  }
}
$handler=[Net.Http.HttpClientHandler]::new()
$handler.UseProxy=$false
$handler.AllowAutoRedirect=$false
$client=[Net.Http.HttpClient]::new($handler)
$client.Timeout=[TimeSpan]::FromSeconds(4)
$results=@();$families=@()
try{
  foreach($target in @([pscustomobject]@{family="IPv4";ip=$ipv4},
                      [pscustomobject]@{family="IPv6";ip=$ipv6})){
    if($null -eq $target.ip){continue}
    $origin=if($target.family -eq "IPv6"){"http://["+$target.ip.ToString()+"]:8787"}else{"http://"+$target.ip.ToString()+":8787"}
    $health=Remote-Request $client ($origin+"/api/health") $true
    $rows=@()
    foreach($path in $paths){
      $status=Remote-Request $client ($origin+$path) $false
      $rows+= [ordered]@{family=$target.family;endpoint=$path;status_code=$status.status_code}
      Write-Host ("Remote GSC {0} endpoint {1}: HTTP {2}" -f $target.family,$path,$status.status_code)
    }
    $results+= $rows
    $families+= Classify-Family $rows $target.family ([bool]$health.service_identity)
  }
}finally{$client.Dispose()}
$bad=@($families|Where-Object{$_.result -eq "POTENTIAL_UNAUTHENTICATED_API_EXPOSURE"}).Count
$pass=@($families|Where-Object{$_.result -eq "GSC_REMOTE_API_REQUIRES_AUTH_TESTED_PATH"}).Count
$overall=if($bad -gt 0){"UNAUTHENTICATED_API_EXPOSURE_REVIEW"}
  elseif($pass -eq 2){"TAILNET_BOTH_FAMILIES_AUTH_DENIED"}
  else{"AUTH_PROOF_INCOMPLETE"}
$report=[ordered]@{
  schema=1;phase="12.10-tailnet-api-auth";generated_at=(Get-Date).ToString("o")
  synthetic=$false;result=$overall
  execution_scope="SUBPC_TAILSCALE_NO_CREDENTIALS"
  read_only_client=$true;production_config_changes=$false
  host_unauthorized_audit_entries_possible=$true
  families=$families;endpoint_http_status_only=$results
  raw_ip_or_headers_exported=$false;backend_ports_private="UNCHANGED_FAIL"
  limitations=@(
    "GET to protected routes may create routine GSC denied-request audit log entries.",
    "Responses are status codes only; no credential, response body or server address written.",
    "HTTP 401 over the tested Tailscale paths demonstrates unauthorized denial only at this time.",
    "This does not prove kernel socket bind, other peers' Tailscale access or Internet firewall isolation.",
    "No Minecraft worlds, services, settings, updates or firewall rules were changed."
  )
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-Tailnet-Auth-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("GSC API authorization evidence: "+$out)
Write-Host ("Result: "+$overall)
exit 0
