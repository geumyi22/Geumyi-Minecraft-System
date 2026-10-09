[CmdletBinding()]
param([switch]$Synthetic,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# No network except GET requests to the verified *local* GSC Client proxy
# at 127.0.0.1:8790. The Client itself forwards /api/ to its configured
# Host with its existing encrypted-client credential: this script NEVER
# reads client.json, tokens, passwords, Host URLs or the API status body
# into the generated report. No operations, POST, update endpoints, restart.
$knownLocalURL="http://127.0.0.1:8790"
$expectedClientSHA="c3057d6dfc2e88232a857932e960866c12fd6c8b65c40d2252ed71d6000fe111"

function Decide([bool]$LocalClientIdentity,[bool]$Health200,[bool]$HealthIsGSC,
                [bool]$Status200,[bool]$StatusIsGSC,[bool]$VersionMatch,[bool]$HostRoleAbsent) {
  $flags=[System.Collections.Generic.List[string]]::new()
  if(-not $LocalClientIdentity){$flags.Add("LOCAL_GSC_RC2_CLIENT_IDENTITY_UNVERIFIED")}
  if(-not $Health200){$flags.Add("HOST_HEALTH_NOT_HTTP_200")}
  if(-not $HealthIsGSC){$flags.Add("HOST_HEALTH_SCHEMA_UNEXPECTED")}
  if(-not $Status200){$flags.Add("AUTHENTICATED_HOST_STATUS_NOT_HTTP_200")}
  if(-not $StatusIsGSC){$flags.Add("HOST_STATUS_SCHEMA_UNEXPECTED")}
  if(-not $VersionMatch){$flags.Add("HOST_VERSION_MISMATCH_OR_UNAVAILABLE")}
  if(-not $HostRoleAbsent){$flags.Add("SECONDARY_PC_HOST_ROLE_DETECTED_OR_UNKNOWN")}
  $issues=@($flags.ToArray())
  return [ordered]@{
    result=$(if($issues.Count -eq 0){"SUBPC_RC2_AUTHENTICATED_HOST_STATUS_PASS"}else{"CHECK_REQUIRED"})
    issue_codes=$issues
    backend_ports_private="UNCHANGED_FAIL"
  }
}

function SafeGet([string]$Relative,[int]$TimeoutMs,[int]$MaxChars) {
  $status=0
  $body=""
  try {
    # Both URLs are literal known GET-only read endpoints of local GSC.
    if(@("/api/health","/api/status") -cnotcontains $Relative){throw "ENDPOINT_NOT_ALLOWLISTED"}
    $u=$knownLocalURL+$Relative
    $req=[System.Net.HttpWebRequest]::Create($u)
    $req.Method="GET";$req.Proxy=$null;$req.Timeout=$TimeoutMs
    $req.ReadWriteTimeout=$TimeoutMs;$req.AllowAutoRedirect=$false
    $req.KeepAlive=$false;$req.Headers["Cache-Control"]="no-cache"
    $resp=[System.Net.HttpWebResponse]$req.GetResponse()
    try {
      $status=[int]$resp.StatusCode
      if($status -eq 200){
        $stream=$resp.GetResponseStream()
        $reader=New-Object System.IO.StreamReader($stream,[Text.Encoding]::UTF8)
        try {
          $buffer=New-Object char[] ($MaxChars+1)
          $count=$reader.ReadBlock($buffer,0,$buffer.Length)
          if($count -gt $MaxChars){throw "STATUS_BODY_LIMIT_EXCEEDED"}
          $body=New-Object string ($buffer,0,$count)
        }finally{$reader.Dispose()}
      }
    }finally{$resp.Close()}
  } catch [System.Net.WebException] {
    if($_.Exception.Response -is [System.Net.HttpWebResponse]){
      $status=[int]$_.Exception.Response.StatusCode
      try{$_.Exception.Response.Close()}catch{}
    }
  } catch {
    $body=""
  }
  return [ordered]@{code=$status;body=$body}
}

if(-not $OutputDir) {
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-SubPC-GSC"
}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$output=Join-Path $OutputDir ("Day12-SubPC-GSC-RC2-HostProxy-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  $valid=Decide $true $true $true $true $true $true $true
  $notPaired=Decide $true $true $true $false $false $true $true
  $wrongHost=Decide $true $true $false $true $false $false $true
  $hostPresent=Decide $true $true $true $true $true $true $false
  if($valid.result -ne "SUBPC_RC2_AUTHENTICATED_HOST_STATUS_PASS" -or
     $notPaired.result -ne "CHECK_REQUIRED" -or
     $notPaired.issue_codes -notcontains "AUTHENTICATED_HOST_STATUS_NOT_HTTP_200" -or
     $wrongHost.result -ne "CHECK_REQUIRED" -or
     $hostPresent.result -ne "CHECK_REQUIRED"){
    throw "HOST_PROXY_SYNTHETIC_FAILED"
  }
  [ordered]@{schema=1;phase="day12-rc2-subpc-authenticated-host-proxy"
    synthetic=$true;read_only=$true;result="SYNTHETIC_PASS"
    mutation_performed=$false;backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $output -Encoding UTF8
  Write-Host "GSC SubPC Host proxy synthetic PASS"
  exit 0
}

$localVerified=$false;$hostRoleAbsent=$true;$roleReadable=$true
# Verify RC2 executable and ONE expected running client PID before sending
# requests; fail closed rather than talking to an unrelated local proxy.
try{
  $reg="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter"
  $install=[string](Get-ItemProperty -LiteralPath $reg -ErrorAction Stop).InstallLocation
  $client=Join-Path $install "GeumyiServerCenter.exe"
  $hash=(Get-FileHash -LiteralPath $client -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
  $procs=@(Get-Process -Name "GeumyiServerCenter" -ErrorAction Stop)
  $localVerified=($hash -eq $expectedClientSHA -and $procs.Count -eq 1 -and
    [string]::Equals([string]$procs[0].Path,$client,[StringComparison]::OrdinalIgnoreCase))
}catch{$localVerified=$false}
try{
  if($install -and (Test-Path -LiteralPath (Join-Path $install "GeumyiServerHost.exe") -PathType Leaf)){$hostRoleAbsent=$false}
  if($null -ne (Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){$hostRoleAbsent=$false}
  if($null -ne (Get-ScheduledTask -TaskName "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){$hostRoleAbsent=$false}
  if(Test-Path -LiteralPath (Join-Path $env:ProgramData "GeumyiServerCenter\server.json") -PathType Leaf){$hostRoleAbsent=$false}
}catch{$roleReadable=$false}

$healthCode=0;$statusCode=0;$healthGSC=$false;$statusGSC=$false
$hostVersion="UNVERIFIED";$statusVersion="UNVERIFIED";$versionMatch=$false
$serverListPresent=$false
if($localVerified -and $hostRoleAbsent -and $roleReadable){
  $h=SafeGet "/api/health" 6500 6000
  $healthCode=[int]$h.code
  if($healthCode -eq 200){
    try{
      $parsed=$h.body|ConvertFrom-Json -ErrorAction Stop
      $healthGSC=($parsed.ok -eq $true -and [int]$parsed.generation -eq 4 -and
        [string]$parsed.version -match '^4\.3\.[0-9]+')
      if($healthGSC){$hostVersion=[string]$parsed.version}
    }catch{$healthGSC=$false}
  }
  # /api/status is authenticated on GSC Host; the local Client proxy adds
  # the already-paired Bearer token. We never read/export that token.
  $st=SafeGet "/api/status" 18000 350000
  $statusCode=[int]$st.code
  if($statusCode -eq 200){
    try {
      $json=$st.body|ConvertFrom-Json -ErrorAction Stop
      $serverListPresent=($null -ne $json.servers -and @($json.servers).Count -ge 1)
      $statusGSC=($null -ne $json.host -and $serverListPresent -and
        [string]$json.app_version -match '^4\.3\.[0-9]+')
      if($statusGSC){$statusVersion=[string]$json.app_version}
    }catch{$statusGSC=$false}
  }
  $versionMatch=($healthGSC -and $statusGSC -and $hostVersion -eq $statusVersion)
}
$dec=Decide $localVerified ($healthCode -eq 200) $healthGSC ($statusCode -eq 200) $statusGSC $versionMatch ($hostRoleAbsent -and $roleReadable)
$report=[ordered]@{
  schema=1;phase="day12-rc2-subpc-authenticated-host-proxy"
  generated_at=(Get-Date).ToString("o")
  synthetic=$false;read_only=$true
  result=$dec.result;issue_codes=$dec.issue_codes
  local_rc2_client_identity_verified=$localVerified
  local_no_host_role_verified=($hostRoleAbsent -and $roleReadable)
  host_health_http_status=$healthCode
  host_health_schema_verified=$healthGSC
  authenticated_status_http_status=$statusCode
  authenticated_status_schema_verified=$statusGSC
  server_list_structure_present=$serverListPresent
  remote_host_version=$(if($versionMatch){$hostVersion}else{"UNVERIFIED"})
  health_status_version_agree=$versionMatch
  mutation_performed=$false;client_or_service_restarted=$false
  client_token_read_or_exported=$false;remote_host_url_exported=$false
  http_body_exported=$false;game_server_actions_triggered=$false
  backend_ports_private="UNCHANGED_FAIL"
  notes=@(
    "Local GSC Client proxy GET-only /api/health and authenticated /api/status checked.",
    "No commands, pairing changes, update stage/apply calls, backup restore or config writes.",
    "PASS means paired GSC Host read-only status reachable through existing Client auth; does not prove server health/port isolation.",
    "HTTP status codes are sanitized; no credentials, host address or server details in report."
  )
}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $output -Encoding UTF8
Write-Host ("GSC authenticated Host proxy check: "+$report.result)
Write-Host ("JSON: "+$output)
if($report.result -ne "SUBPC_RC2_AUTHENTICATED_HOST_STATUS_PASS"){exit 2}
exit 0
