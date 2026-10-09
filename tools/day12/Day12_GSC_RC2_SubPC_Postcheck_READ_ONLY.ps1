[CmdletBinding()]
param([switch]$Synthetic,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Secondary-PC GSC Client post-Canary verification. NEVER launches/kills apps,
# calls update endpoints, changes config/registry/firewall, or reads client
# token/host URL. Source+runtime check is separate from backend bind gate.
$expectedRC2="c3057d6dfc2e88232a857932e960866c12fd6c8b65c40d2252ed71d6000fe111"
$expected438="05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61"

function FinalizeResult([bool]$ValidRC2,[bool]$ClientOnly,[bool]$RunningValid,
  [bool]$LocalIconOK,[bool]$BackupValid,[bool]$HelperSuccess,
  [bool]$RoleReadable,[bool]$IdentityReadable) {
  $flags=[System.Collections.Generic.List[string]]::new()
  if(-not $ValidRC2){$flags.Add("RC2_CLIENT_SHA_UNVERIFIED")}
  if(-not $ClientOnly){$flags.Add("HOST_ROLE_DETECTED")}
  if(-not $RunningValid){$flags.Add("RC2_CLIENT_NOT_RUNNING_OR_DIFFERENT_PROCESS")}
  if(-not $LocalIconOK){$flags.Add("CLIENT_LOCAL_HTTP_ICON_NOT_VERIFIED")}
  if(-not $BackupValid){$flags.Add("OFFICIAL_438_BACKUP_NOT_VERIFIED")}
  if(-not $HelperSuccess){$flags.Add("UPDATE_HELPER_RESULT_NOT_VERIFIED")}
  if(-not $RoleReadable){$flags.Add("HOST_ROLE_READ_UNCERTAIN")}
  if(-not $IdentityReadable){$flags.Add("CLIENT_PROCESS_IDENTITY_UNCERTAIN")}
  $issues=@($flags.ToArray())
  return [ordered]@{
    result=$(if($issues.Count -eq 0){"SUBPC_RC2_LOCAL_RUNTIME_PASS"}else{"CHECK_REQUIRED"})
    issue_codes=$issues
    backend_ports_private="UNCHANGED_FAIL"
  }
}
if(-not $OutputDir){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-SubPC-GSC"
}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$output=Join-Path $OutputDir ("Day12-SubPC-GSC-RC2-Postcheck-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  $ok=FinalizeResult $true $true $true $true $true $true $true $true
  $notRunning=FinalizeResult $true $true $false $false $true $true $true $true
  $wrongFile=FinalizeResult $false $true $true $true $true $true $true $true
  $hostDetected=FinalizeResult $true $false $true $true $true $true $true $true
  $noBackup=FinalizeResult $true $true $true $true $false $true $true $true
  $unknown=FinalizeResult $true $true $true $true $true $true $false $false
  if($ok.result -ne "SUBPC_RC2_LOCAL_RUNTIME_PASS" -or
     $notRunning.result -ne "CHECK_REQUIRED" -or
     $notRunning.issue_codes -notcontains "RC2_CLIENT_NOT_RUNNING_OR_DIFFERENT_PROCESS" -or
     $wrongFile.result -ne "CHECK_REQUIRED" -or
     $hostDetected.result -ne "CHECK_REQUIRED" -or
     $noBackup.result -ne "CHECK_REQUIRED" -or
     $unknown.result -ne "CHECK_REQUIRED"){
    throw "SUBPC_RC2_LOCAL_POSTCHECK_SYNTHETIC_FAILED"
  }
  [ordered]@{
    schema=1;phase="day12-gsc-rc2-subpc-client-runtime-postcheck"
    synthetic=$true;read_only=$true;result="SYNTHETIC_PASS"
    system_mutated=$false;backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $output -Encoding UTF8
  Write-Host "GSC RC2 SubPC postcheck synthetic PASS"
  exit 0
}

$issues=[System.Collections.Generic.List[string]]::new()
$clientPath=""
$clientHash=""
$helperSuccess=$false
$backupOK=$false
$runningValid=$false
$roleSafe=$true
$roleReadable=$true
$identityReadable=$true
$localIconOK=$false
$runningCount=0
$clientRelaunchedPreviously=$false
$ownerCorroborated=$false
$ownerObserved=$false

# Use existing registry; never create/edit it.
try {
  $reg="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter"
  $install=[string](Get-ItemProperty -LiteralPath $reg -ErrorAction Stop).InstallLocation
  if([string]::IsNullOrWhiteSpace($install) -or -not (Test-Path -LiteralPath $install -PathType Container)){
    throw "INSTALL_LOCATION_INVALID"
  }
  $clientPath=Join-Path $install "GeumyiServerCenter.exe"
  $clientHash=(Get-FileHash -LiteralPath $clientPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
} catch {
  $issues.Add("CLIENT_INSTALL_PATH_OR_SHA_UNAVAILABLE")
}
$validRC2=($clientHash -eq $expectedRC2)
# Fail closed on any Host indication or failure to read role.
try {
  if($clientPath -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $clientPath) "GeumyiServerHost.exe") -PathType Leaf)){$roleSafe=$false}
  if($null -ne (Get-Service -Name "Geumyi Server Center Host" -ErrorAction Stop)){$roleSafe=$false}
} catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
  # The absence of this service is expected on a client-only PC.
} catch {
  $roleReadable=$false
}
try {
  if($null -ne (Get-ScheduledTask -TaskName "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){$roleSafe=$false}
} catch {$roleReadable=$false}
try {
  if(Test-Path -LiteralPath (Join-Path $env:ProgramData "GeumyiServerCenter\server.json") -PathType Leaf){$roleSafe=$false}
} catch {$roleReadable=$false}

# Process identity only (no token, args, PID or executable path exported).
try {
  $running=@(Get-Process -Name "GeumyiServerCenter" -ErrorAction SilentlyContinue)
  $runningCount=$running.Count
  if($runningCount -eq 1 -and $clientPath){
    $procPath=[string]$running[0].Path
    if([string]::IsNullOrWhiteSpace($procPath)){$identityReadable=$false}
    $runningValid=[string]::Equals($procPath,$clientPath,[StringComparison]::OrdinalIgnoreCase)
  } elseif($runningCount -gt 1) {
    $issues.Add("MULTIPLE_GSC_CLIENT_PROCESSES")
  }
}catch{$identityReadable=$false}

# Only GET a static public icon from local client API. No admin/token URL
# requests or remote internet calls; no response body exported.
if($runningValid){
  try {
    $req=[Net.HttpWebRequest]::Create("http://127.0.0.1:8790/app.ico")
    $req.Method="GET";$req.Proxy=$null;$req.Timeout=2500
    $req.ReadWriteTimeout=2500;$req.AllowAutoRedirect=$false
    $resp=[Net.HttpWebResponse]$req.GetResponse()
    try {
      $stream=$resp.GetResponseStream()
      $head=New-Object byte[] 4
      $got=$stream.Read($head,0,4)
      $localIconOK=($resp.StatusCode -eq [Net.HttpStatusCode]::OK -and
        $got -eq 4 -and $head[0] -eq 0 -and $head[1] -eq 0 -and
        $head[2] -eq 1 -and $head[3] -eq 0)
    }finally{$resp.Close()}
  }catch{
    $issues.Add("LOCAL_CLIENT_HTTP_UNRESPONSIVE")
  }
  # Supplemental only; Windows provider may omit recent TCP entries.
  # This does not claim an authoritative dual-stack listener inventory.
  try {
    $listeners=@(Get-NetTCPConnection -LocalPort 8790 -State Listen -ErrorAction Stop)
    $ownerObserved=($listeners.Count -gt 0)
    foreach($l in $listeners){
      if([int]$l.OwningProcess -eq [int]$running[0].Id){$ownerCorroborated=$true;break}
    }
  }catch{}
}
# Load ONLY safe update report fields. Never serialize backup paths.
try {
  $reportPath=Join-Path $env:ProgramData "GeumyiServerCenter\Updates\gsc-client-self-update-last.json"
  $r=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  $helperSuccess=([string]$r.status -eq "success" -and [string]$r.target_version -eq "4.3.9-rc.2")
  $clientRelaunchedPreviously=[bool]$r.client_relaunched
  $bdir=[string]$r.backup_dir
  if($helperSuccess -and $bdir){
    $bpath=Join-Path $bdir "GeumyiServerCenter.exe"
    $backupOK=((Get-FileHash -LiteralPath $bpath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -eq $expected438)
  }
}catch{$issues.Add("CLIENT_UPDATE_REPORT_OR_BACKUP_READ_ERROR")}

$final=FinalizeResult $validRC2 $roleSafe $runningValid $localIconOK $backupOK $helperSuccess $roleReadable $identityReadable
$issues.AddRange([string[]]@($final.issue_codes))
$all=@($issues.ToArray()|Sort-Object -Unique)
$result=if($all.Count -eq 0){"SUBPC_RC2_LOCAL_RUNTIME_PASS"}else{"CHECK_REQUIRED"}
$report=[ordered]@{
  schema=1;phase="day12-gsc-rc2-subpc-client-runtime-postcheck"
  generated_at=(Get-Date).ToString("o")
  synthetic=$false;read_only=$true
  result=$result;issue_codes=$all
  installed_rc2_client_hash_match=$validRC2
  client_process_count=$runningCount
  correct_client_process_running=$runningValid
  client_http_icon_responsive=$localIconOK
  local_tcp_owner_observed=$ownerObserved
  local_tcp_owner_correlated=$ownerCorroborated
  gsc_host_role_absent=($roleSafe -and $roleReadable)
  updater_last_report_success=$helperSuccess
  original_438_backup_hash_match=$backupOK
  updater_reported_auto_relaunch=$clientRelaunchedPreviously
  config_read_or_modified=$false
  registry_modified=$false;software_launched=$false;service_modified=$false
  firewall_modified=$false;secrets_exported=$false
  backend_ports_private="UNCHANGED_FAIL"
  notes=@(
    "Only local client file hash, process identity, static localhost /app.ico and official 4.3.8 backup were checked.",
    "client_relaunched=false can mean client was not running when updater started; not automatically an update failure.",
    "Even a PASS does not prove dashboard-to-remote-Host API/GSCM connectivity; check the UI separately.",
    "No identity, token, remote address, backup file path, PID or client config contents are exported."
  )
}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $output -Encoding UTF8
Write-Host ("GSC RC2 SubPC postcheck: "+$result)
Write-Host ("JSON: "+$output)
if($result -ne "SUBPC_RC2_LOCAL_RUNTIME_PASS"){exit 2}
exit 0
