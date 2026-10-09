[CmdletBinding()]
param([string]$CandidateDir="candidate-output")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# CI-only: creates/stops a Windows service, but NEVER on a real computer.
if($env:GITHUB_ACTIONS -ne "true" -or
   $env:GITHUB_REPOSITORY -ne "geumyi22/Geumyi-Minecraft-System" -or
   $env:GEUMYI_GSC_RC_STAGE -ne "isolated_ci_host_service" -or
   -not $env:GITHUB_RUN_ID -or -not $env:GITHUB_SHA -or -not $env:RUNNER_TEMP -or
   [Environment]::OSVersion.Platform.ToString() -ne "Win32NT"){
  throw "REFUSE_OUTSIDE_DISPOSABLE_GITHUB_WINDOWS"
}
$admin=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "CI_ADMIN_REQUIRED"}
$service="Geumyi Server Center Host"
$reg="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter"
if($null -ne (Get-Service -Name $service -ErrorAction SilentlyContinue) -or
   (Test-Path -LiteralPath $reg) -or
   @(Get-Process -Name GeumyiServerHost -ErrorAction SilentlyContinue).Count -gt 0 -or
   @(Get-Process -Name GeumyiServerCenter -ErrorAction SilentlyContinue).Count -gt 0){
  throw "REFUSE_PREEXISTING_GSC_STATE"
}
$tcp=New-Object Net.Sockets.TcpClient
try{$tcp.Connect("127.0.0.1",8787);throw "REFUSE_PORT_8787_OCCUPIED"}catch [Net.Sockets.SocketException]{}finally{$tcp.Dispose()}
$root=Join-Path $env:RUNNER_TEMP "Day12-Host-RC4-Rollback-CI"
if(Test-Path -LiteralPath $root){throw "REFUSE_REUSED_DISPOSABLE_ROOT"}
$candidate=(Resolve-Path -LiteralPath $CandidateDir).Path
$meta=Get-Content (Join-Path $candidate "RC-METADATA.json") -Raw -Encoding UTF8|ConvertFrom-Json
if($meta.candidate_version -ne "4.3.9-rc.4" -or
   $meta.source_commit -ne $env:GITHUB_SHA -or
   !$meta.unsigned -or !$meta.review_only -or
   $meta.operator_install_approved -or $meta.production_host_modified -or $meta.stable_published -or
   $meta.backend_ports_private -ne "UNCHANGED_FAIL"){throw "RC4_PREVIEW_METADATA_MISMATCH"}
$hashes=@(Get-Content (Join-Path $candidate "SHA256SUMS.txt") -Encoding ascii)
if($hashes.Count -ne 5){throw "RC4_PREVIEW_CHECKSUM_COUNT_INVALID"}
foreach($line in $hashes){
  if($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$'){throw "RC4_CHECKSUM_ROW_INVALID"}
  $want=$Matches[1];$name=$Matches[2]
  $file=Join-Path $candidate $name
  if(-not (Test-Path -LiteralPath $file -PathType Leaf) -or
     (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $want){
    throw "RC4_PREVIEW_CHECKSUM_MISMATCH"
  }
}
$oldPF=$env:ProgramFiles
$oldPD=$env:PROGRAMDATA
$serviceCreated=$false
$regCreated=$false
$report=[ordered]@{
  schema=1;disposable_ci_only=$true;synthetic=$false
  result="CHECK_REQUIRED";candidate_version="4.3.9-rc.4"
  official_host_sha_verified=$false
  service_health_438_before=$false;stale_health_caused_update_rejection=$false
  automatic_rollback_reported=$false;original_host_restored_sha=$false
  original_backup_verified_sha=$false;new_setup_removed=$false
  service_health_438_after=$false;no_update_lock_residue=$false
  service_removed=$false;registry_removed=$false
  production_host_modified=$false;production_network_modified=$false
  game_servers_started=$false;backend_ports_private="UNCHANGED_FAIL"
  error_category="NONE"
}
function Wait-Host([string]$Version,[int]$Seconds) {
  $deadline=(Get-Date).AddSeconds($Seconds)
  while((Get-Date) -lt $deadline){
    try {
      $h=Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/health" -TimeoutSec 2
      $state=(Get-Service -Name $service -ErrorAction Stop).Status
      if($state -eq "Running" -and $h.ok -eq $true -and
         [string]$h.version -eq $Version -and [int]$h.generation -eq 4 -and
         $h.service -eq $true){return $true}
    }catch{}
    Start-Sleep -Milliseconds 650
  }
  return $false
}
function Stop-CITestService {
  $svc=Get-Service -Name $service -ErrorAction SilentlyContinue
  if($null -ne $svc -and $svc.Status -ne "Stopped") {
    & sc.exe stop $service *> $null
    for($i=0;$i -lt 50;$i++){
      Start-Sleep -Milliseconds 400
      $cur=Get-Service -Name $service -ErrorAction SilentlyContinue
      if($null -eq $cur -or $cur.Status -eq "Stopped"){break}
    }
  }
}
try {
  $env:ProgramFiles=Join-Path $root "ProgramFiles"
  $env:PROGRAMDATA=Join-Path $root "ProgramData"
  $install=Join-Path $env:ProgramFiles "Geumyi Server Center"
  $oldDir=Join-Path $root "Official-4.3.8"
  New-Item -ItemType Directory -Path $install,$oldDir,$env:PROGRAMDATA -Force|Out-Null
  & gh release download "system-2026.10.07-day11-gsc438-beta" --repo $env:GITHUB_REPOSITORY --pattern "GeumyiServerHost.exe" --dir $oldDir --clobber
  if($LASTEXITCODE -ne 0){throw "OFFICIAL_HOST_DOWNLOAD_FAILED"}
  $original=Join-Path $oldDir "GeumyiServerHost.exe"
  $expectedOldSha="2fae64e09ba2e55639a6647e25eca41d2cbba8d751191b52e504a0f4b3232ad8"
  if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedOldSha){
    throw "OFFICIAL_HOST_SHA_MISMATCH"
  }
  $report.official_host_sha_verified=$true
  $installedHost=Join-Path $install "GeumyiServerHost.exe"
  Copy-Item -LiteralPath $original -Destination $installedHost -ErrorAction Stop
  # Intentionally register service to an IMMUTABLE separate official 4.3.8
  # executable. Setup can replace the installed Host, but SCM will keep
  # starting 4.3.8. Candidate exact-version check MUST reject this stale
  # service, then auto-restore the original installed Host and remove Setup.
  $frozenHost=Join-Path $oldDir "GeumyiServerHost.exe"
  $config=Join-Path $root "isolated-server.json"
  @{bind="127.0.0.1";port=8787;api_token="";servers=@();
    auto_start_agent=$false;mobile_enabled=$false;
    update=@{enabled=$false;repository="";channel="stable"}
  }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $config -Encoding UTF8
  $binPath='"'+$frozenHost+'" --service --config "'+$config+'"'
  New-Service -Name $service -DisplayName $service -BinaryPathName $binPath -StartupType Manual -ErrorAction Stop|Out-Null
  $serviceCreated=$true
  [void](New-Item -Path $reg -Force -ErrorAction Stop)
  $regCreated=$true
  [void](New-ItemProperty -LiteralPath $reg -Name "InstallLocation" -PropertyType String -Value $install -Force)
  & sc.exe start $service
  if($LASTEXITCODE -ne 0){throw "FROZEN_BASELINE_SERVICE_START_FAILED"}
  $report.service_health_438_before=Wait-Host "4.3.8" 45
  if(-not $report.service_health_438_before){throw "FROZEN_BASELINE_SERVICE_HEALTH_FAILED"}
  $setupPath=Join-Path $install "GeumyiServerCenter-Setup.exe"
  if(Test-Path -LiteralPath $setupPath){throw "SETUP_MUST_BE_ABSENT_BEFORE_TEST"}
  $previewSetup=Join-Path $candidate "GeumyiServerCenter-v4.3.9-rc.4-Setup.exe"
  # This is the actual RC4 self-update helper, not a mock. Its Host service
  # restart sees stale 4.3.8 and must automatically roll back after timeout.
  $p=Start-Process -FilePath $previewSetup -ArgumentList "--self-update" -PassThru -Wait -NoNewWindow
  $reportPath=Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Updates\gsc-self-update-last.json"
  if(-not (Test-Path -LiteralPath $reportPath)){throw "AUTO_ROLLBACK_REPORT_MISSING"}
  $r=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8|ConvertFrom-Json
  $report.stale_health_caused_update_rejection=([string]$r.status -eq "rolled_back" -and
    [string]$r.target_version -eq "4.3.9-rc.4" -and
    [string]$r.error -match "health gate timed out")
  $report.automatic_rollback_reported=([string]$r.status -eq "rolled_back" -and
    $r.rolled_back -eq $true -and $r.host_health -eq $true)
  $report.original_host_restored_sha=((Get-FileHash -LiteralPath $installedHost -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedOldSha)
  $backupDir=Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Backups"
  $backs=@(Get-ChildItem -LiteralPath $backupDir -Directory -ErrorAction Stop)
  foreach($b in $backs){
    $f=Join-Path $b.FullName "GeumyiServerHost.exe"
    if((Test-Path -LiteralPath $f -PathType Leaf) -and
       (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedOldSha){
      $report.original_backup_verified_sha=$true;break
    }
  }
  $report.new_setup_removed=(-not (Test-Path -LiteralPath $setupPath))
  $report.service_health_438_after=Wait-Host "4.3.8" 20
  $report.no_update_lock_residue=(-not (Test-Path -LiteralPath (Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Updates\gsc-self-update.lock")))
  if(-not $report.stale_health_caused_update_rejection -or
     -not $report.automatic_rollback_reported -or
     -not $report.original_host_restored_sha -or
     -not $report.original_backup_verified_sha -or
     -not $report.new_setup_removed -or
     -not $report.service_health_438_after -or
     -not $report.no_update_lock_residue){
    throw "AUTOMATIC_ROLLBACK_ASSERTION_FAILED"
  }
  $report.result="DISPOSABLE_RC4_HOST_AUTOMATIC_ROLLBACK_PASS"
}catch{
  $msg=[string]$_.Exception.Message
  $report.error_category=($msg -replace '[^A-Z0-9_]','')
  if($report.error_category.Length -gt 90){$report.error_category=$report.error_category.Substring(0,90)}
  $report.result="DISPOSABLE_RC4_ROLLBACK_CHECK_FAILED"
}finally {
  if($serviceCreated){
    try{
      Stop-CITestService
      & sc.exe delete $service *> $null
      if($LASTEXITCODE -ne 0){throw "DELETE_CI_SERVICE_FAILED"}
      Start-Sleep -Seconds 3
      $report.service_removed=($null -eq (Get-Service -Name $service -ErrorAction SilentlyContinue))
    }catch{$report.service_removed=$false}
  }else{$report.service_removed=$true}
  if($regCreated){
    try{
      Remove-Item -LiteralPath $reg -Recurse -Force -ErrorAction Stop
      $report.registry_removed=(-not (Test-Path -LiteralPath $reg))
    }catch{$report.registry_removed=$false}
  }else{$report.registry_removed=$true}
  $env:ProgramFiles=$oldPF;$env:PROGRAMDATA=$oldPD
  $report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $env:RUNNER_TEMP "Day12-GSC-Host-RC4-AutoRollback-Report.json") -Encoding UTF8
}
if($report.result -ne "DISPOSABLE_RC4_HOST_AUTOMATIC_ROLLBACK_PASS" -or
   -not $report.service_removed -or -not $report.registry_removed){
  throw "RC4_AUTO_ROLLBACK_NOT_VERIFIED; CHECK_SANITIZED_REPORT"
}
Write-Host "CI-ONLY GSC Host RC4 automatic rollback to official 4.3.8 PASS."
