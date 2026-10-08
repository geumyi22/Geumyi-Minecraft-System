[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "Day12_Native_TCP_Provider_READ_ONLY.ps1")
$ports=@(25565,25566,25567,25570,25571,25572,25573,25575,25576,25577,25579,8787)
$private=@(25570,25571,25572,25573,25575,25576,25577,25579)
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Native-TCP"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-Native-TCP-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
function AddressScope([string]$A){
  if([string]::IsNullOrWhiteSpace($A)){return "UNKNOWN"}
  $trimmed=$A.Trim('[',']').ToLowerInvariant()
  if($trimmed -in @("0.0.0.0","::","*")){return "WILDCARD"}
  $ip=$null
  if([System.Net.IPAddress]::TryParse($trimmed,[ref]$ip)){
    if([System.Net.IPAddress]::IsLoopback($ip)){return "LOOPBACK"}
  }
  if($trimmed -eq "::ffff:127.0.0.1" -or $trimmed -match '^127\.'){return "LOOPBACK"}
  return "NON_LOOPBACK_REDACTED"
}
function SafeRows([object[]]$Rows){
  $safe=@()
  foreach($r in @($Rows)){
    $scope=AddressScope ([string]$r.address)
    $safe+= [ordered]@{
      port=[int]$r.port
      address_scope=$scope
      loopback_or_wildcard_address=$(if($scope -in @("LOOPBACK","WILDCARD")){[string]$r.address}else{"REDACTED"})
      source=[string]$r.source
      pid_type=$(if([int]$r.pid -gt 0){"PID_RECORDED"}else{"PID_NOT_AVAILABLE"})
    }
  }
  return $safe
}
function Fleet(){
  try{
    $r=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/v4/update/fleet" -Method Get -TimeoutSec 5 -ErrorAction Stop
    $rows=@()
    foreach($sv in @($r.servers)){
      if($null -eq $sv){continue}
      $id=[string]$sv.server_id
      if($id -notin @("wild","playground","other","lobby")){continue}
      $online=$false
      $f=$sv.PSObject.Properties["online"]
      if($null -ne $f){$online=([bool]$f.Value)}
      $rows+= [ordered]@{id=$id;online=$online}
    }
    return [ordered]@{status="CAPTURED";servers=$rows}
  }catch{return [ordered]@{status="UNAVAILABLE";servers=@()}}
}
if($Synthetic){
  $listener=$null
  try {
    $listener=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $listener.Start()
    $port=[int]([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $native=Get-Day12NativeTcpInventory -WantedPorts @($port)
    $basic=@($native.rows|Where-Object{$_.source -eq "GetExtendedTcpTable_BASIC_LISTENER_IPv4" -and $_.port -eq $port -and (AddressScope $_.address) -eq "LOOPBACK"})
    $owner=@($native.rows|Where-Object{$_.source -eq "GetExtendedTcpTable_OWNER_PID_IPv4" -and $_.port -eq $port -and (AddressScope $_.address) -eq "LOOPBACK"})
    if($native.status -eq "ERROR" -or $basic.Count -eq 0 -or $owner.Count -eq 0){
      throw "Controlled localhost native listener was not observed from both IPv4 table classes"
    }
    $result=[ordered]@{
      schema=1;phase="12.10-native-crosscheck";read_only=$true;synthetic=$true
      result="SYNTHETIC_PASS";provider_status=$native.status
      controlled_listener_observed_basic=($basic.Count -gt 0)
      controlled_listener_observed_owner=($owner.Count -gt 0)
      mutation_performed=$false;secrets_exported=$false
    }
    $result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "Day12 native TCP basic+owner controlled listener PASS"
    exit 0
  }finally{if($null -ne $listener){$listener.Stop()}}
}
$fleetBefore=Fleet
$captures=@()
for($round=1;$round -le 2;$round++){
  $native=Get-Day12NativeTcpInventory -WantedPorts $ports
  $captures+= [ordered]@{
    round=$round;status=$native.status;providers=$native.providers
    listener_rows=@(SafeRows $native.rows)
    error_categories=$native.error_categories
  }
  if($round -eq 1){Start-Sleep -Milliseconds 600}
}
$fleetAfter=Fleet
$found=@($captures|ForEach-Object{$_.listener_rows}|Where-Object{$null -ne $_})
$exposed=@($found|Where-Object{($_.port -in $private) -and $_.address_scope -ne "LOOPBACK"})
$missing=@()
foreach($port in $private){
  if(@($found|Where-Object{$_.port -eq $port}).Count -eq 0){$missing+=$port}
}
$state=if(@($captures|Where-Object{$_.status -eq "ERROR"}).Count -gt 0){"CHECK_REQUIRED"}else{"CAPTURED_REVIEW_REQUIRED"}
$report=[ordered]@{
  schema=1;phase="12.10-native-crosscheck";read_only=$true;synthetic=$false
  generated_at=(Get-Date).ToString("o");result=$state
  fleet_before=$fleetBefore;fleet_after=$fleetAfter
  provider_rounds=$captures
  observed_nonloopback_or_wildcard_private_rows=$exposed.Count
  ports_without_native_listener_rows=$missing
  notes=@(
    "Compares GetExtendedTcpTable OWNER_PID_LISTENER IPv4 and IPv6 with BASIC_LISTENER IPv4; BASIC is an independent table class, not a new OS stack.",
    "Listener evidence is redacted: no nonloopback private IP, hostname, username, command line, credential or executable path is emitted.",
    "No listener row for an online backend is NOT proof of loopback-only bind.",
    "Loopback connection or a remote firewall block alone cannot prove private socket binding.",
    "This targeted evidence is not a final 12.10 PASS. Canonical verifier and live E2E remain mandatory."
  )
  mutation_performed=$false;secrets_exported=$false
}
$report|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Day12 native class crosscheck: "+$state)
Write-Host ("Native rows not found for private ports: "+$missing.Count)
Write-Host ("Nonloopback private listener rows: "+$exposed.Count)
Write-Host ("Report: "+$out)
if($state -ne "CAPTURED_REVIEW_REQUIRED"){exit 2}
exit 0
