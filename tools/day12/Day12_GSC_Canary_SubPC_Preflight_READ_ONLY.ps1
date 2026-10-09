[CmdletBinding()]
param([switch]$Synthetic,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# READ-ONLY. Does not install, download, update, restart, start, stop,
# execute GSC binaries, read client.json contents, or touch Windows Firewall.
# A matching version/hash is NOT proof of real update/rollback success.
$ExpectedClientSHA256="05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61"
$CandidateVersion="4.3.9-rc.1"
$LiveBaseline="4.3.8"

function Decide([bool]$RegistryKnown,[bool]$ClientPresent,[string]$ClientSHA,
  [bool]$HostBinaryPresent,[bool]$HostServicePresent,[bool]$HostTaskPresent,
  [bool]$ServerConfigPresent,[bool]$ClientConfigPresent,[bool]$ClientBinaryReadFailed) {
  $flags=[System.Collections.Generic.List[string]]::new()
  if(-not $RegistryKnown){$flags.Add("INSTALL_REGISTRY_UNCONFIRMED")}
  if(-not $ClientPresent){$flags.Add("CLIENT_BINARY_MISSING")}
  if($ClientBinaryReadFailed){$flags.Add("CLIENT_BINARY_HASH_UNAVAILABLE")}
  if($ClientPresent -and $ClientSHA -ne $ExpectedClientSHA256){$flags.Add("NOT_PINNED_GSC_438_CLIENT")}
  if($HostBinaryPresent){$flags.Add("HOST_BINARY_PRESENT")}
  if($HostServicePresent){$flags.Add("HOST_SERVICE_PRESENT")}
  if($HostTaskPresent){$flags.Add("HOST_AUTOSTART_TASK_PRESENT")}
  if($ServerConfigPresent){$flags.Add("SERVER_CONFIG_PRESENT")}
  if(-not $ClientConfigPresent){$flags.Add("CLIENT_CONFIG_NOT_OBSERVED")}
  $issues=@($flags.ToArray())
  return [ordered]@{
    result=$(if($issues.Count -eq 0){"CLIENT_ONLY_CANARY_TEST_CANDIDATE"}else{"CHECK_REQUIRED"})
    issue_codes=$issues
    client_matches_published_438_release=($ClientPresent -and $ClientSHA -eq $ExpectedClientSHA256)
    client_only_role_supported_by_evidence=(-not ($HostBinaryPresent -or $HostServicePresent -or
      $HostTaskPresent -or $ServerConfigPresent))
    signed_canary_install_allowed=$false
    production_host_tested=$false
    backend_ports_private="UNCHANGED_FAIL"
  }
}
if(-not $OutputDir){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-SubPC-GSC"
}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$output=Join-Path $OutputDir ("Day12-SubPC-GSC-Preflight-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  $valid=Decide $true $true $ExpectedClientSHA256 $false $false $false $false $true $false
  $server=Decide $true $true $ExpectedClientSHA256 $true $true $false $true $true $false
  $changed=Decide $true $true ("f"*64) $false $false $false $false $true $false
  $unknown=Decide $false $false "" $false $false $false $false $false $true
  if($valid.result -ne "CLIENT_ONLY_CANARY_TEST_CANDIDATE" -or
     $valid.signed_canary_install_allowed -or
     $server.result -ne "CHECK_REQUIRED" -or
     $server.issue_codes -notcontains "HOST_BINARY_PRESENT" -or
     $changed.issue_codes -notcontains "NOT_PINNED_GSC_438_CLIENT" -or
     $unknown.issue_codes -notcontains "CLIENT_BINARY_MISSING"){
      throw "CANARY_SUBPC_PREFLIGHT_SYNTHETIC_FAILED"
  }
  [ordered]@{
    schema=1;phase="day12-gsc-canary-subpc-preflight"
    synthetic=$true;read_only=$true;result="SYNTHETIC_PASS"
    mutation_performed=$false;client_only_ready=$false
    backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $output -Encoding UTF8
  Write-Host "GSC Canary SubPC preflight synthetic PASS"
  exit 0
}

$issues=[System.Collections.Generic.List[string]]::new()
$installationRegistryKnown=$false
$installDir=""
try {
  $regPath="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter"
  $key=Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
  $value=[string]$key.InstallLocation
  if(-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -LiteralPath $value -PathType Container)) {
    $installDir=$value
    $installationRegistryKnown=$true
  }
} catch {$issues.Add("INSTALL_REGISTRY_UNREADABLE_OR_MISSING")}
if(-not $installationRegistryKnown){
  # Fallback is READ-ONLY inspection of the canonical installation directory.
  $fallback=Join-Path $env:ProgramFiles "Geumyi Server Center"
  if(Test-Path -LiteralPath $fallback -PathType Container){$installDir=$fallback}
}
$clientPresent=$false
$clientHash=""
$clientHashFailed=$false
$hostPresent=$false
if($installDir){
  $client=Join-Path $installDir "GeumyiServerCenter.exe"
  $clientPresent=Test-Path -LiteralPath $client -PathType Leaf
  if($clientPresent){
    try{
      $clientHash=(Get-FileHash -LiteralPath $client -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    }catch{$clientHashFailed=$true}
  }
  $hostPresent=Test-Path -LiteralPath (Join-Path $installDir "GeumyiServerHost.exe") -PathType Leaf
}
$hostServicePresent=$false
$hostTaskPresent=$false
try{
  $hostServicePresent=($null -ne (Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue))
}catch{$issues.Add("HOST_SERVICE_STATUS_UNKNOWN")}
try{
  $hostTaskPresent=($null -ne (Get-ScheduledTask -TaskName "Geumyi Server Center Host" -ErrorAction SilentlyContinue))
}catch{$issues.Add("HOST_AUTOSTART_TASK_STATUS_UNKNOWN")}
$serverConfigPresent=$false
try{
  $serverConfigPresent=Test-Path -LiteralPath (Join-Path $env:ProgramData "GeumyiServerCenter\server.json") -PathType Leaf
}catch{$issues.Add("SERVER_CONFIG_STATE_UNKNOWN")}
$clientConfigPresent=$false
try{
  foreach($base in @($env:APPDATA,$env:LOCALAPPDATA)){
    if($base -and (Test-Path -LiteralPath (Join-Path $base "GeumyiServerCenter\client.json") -PathType Leaf)){
      $clientConfigPresent=$true;break
    }
  }
}catch{$issues.Add("CLIENT_CONFIG_STATE_UNKNOWN")}
$preflight=Decide $installationRegistryKnown $clientPresent $clientHash $hostPresent $hostServicePresent $hostTaskPresent $serverConfigPresent $clientConfigPresent $clientHashFailed
$issues.AddRange([string[]]@($preflight.issue_codes))
$uniq=@($issues.ToArray()|Sort-Object -Unique)
$result=if($uniq.Count -eq 0){"CLIENT_ONLY_CANARY_TEST_CANDIDATE"}else{"CHECK_REQUIRED"}
$report=[ordered]@{
  schema=1
  phase="day12-gsc-canary-subpc-preflight"
  generated_at=(Get-Date).ToString("o")
  synthetic=$false
  read_only=$true
  result=$result
  expected_baseline_version=$LiveBaseline
  candidate_version=$CandidateVersion
  installed_client_sha256=$(if($clientHash){"sha256:"+$clientHash}else{"UNREADABLE"})
  baseline_published_client_sha256="sha256:"+$ExpectedClientSHA256
  client_binary_present=$clientPresent
  host_binary_present=$hostPresent
  host_service_present=$hostServicePresent
  host_task_present=$hostTaskPresent
  server_config_present=$serverConfigPresent
  client_config_present=$clientConfigPresent
  issue_codes=$uniq
  mutation_performed=$false
  install_performed=$false
  update_channel_changed=$false
  service_restarted=$false
  secrets_exported=$false
  signed_canary_install_allowed=$false
  production_host_tested=$false
  backend_ports_private="UNCHANGED_FAIL"
  notes=@(
    "This only checks CLIENT-ONLY test-PC role and SHA256 against published GSC 4.3.8 client asset.",
    "No client.json content, device token, host URL, real paths, PID, IP address or credential is serialized.",
    "CLIENT_ONLY_CANARY_TEST_CANDIDATE is not approval to execute candidate Setup or self-update.",
    "The Canary release remains Draft, so normal update discovery cannot install it.",
    "A future approved test must separately verify rollback, signed asset origin, and operator window."
  )
}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $output -Encoding UTF8
Write-Host ("GSC Canary SubPC preflight: "+$result)
Write-Host ("Report: "+$output)
if($result -ne "CLIENT_ONLY_CANARY_TEST_CANDIDATE"){exit 2}
exit 0
