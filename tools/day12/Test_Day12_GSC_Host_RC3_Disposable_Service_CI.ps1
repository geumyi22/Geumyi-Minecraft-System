[CmdletBinding()]
param([string]$CandidateDir="candidate-output")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# DANGEROUS on a real host: this test creates/stops a Windows service.
# It is allowed ONLY on a fresh disposable GitHub-hosted Windows Actions runner.
if($env:GITHUB_ACTIONS -ne "true" -or
   $env:GITHUB_REPOSITORY -ne "geumyi22/Geumyi-Minecraft-System" -or
   $env:GEUMYI_GSC_RC_STAGE -ne "isolated_ci_host_service" -or
   -not $env:RUNNER_TEMP -or -not $env:GITHUB_RUN_ID -or
   [Environment]::OSVersion.Platform.ToString() -ne "Win32NT"){
  throw "REFUSE_OUTSIDE_DISPOSABLE_GITHUB_WINDOWS"
}
$admin=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "DISPOSABLE_ADMIN_REQUIRED"}
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
$root=Join-Path $env:RUNNER_TEMP "Day12-Host-RC3-Disposable"
if(Test-Path -LiteralPath $root){throw "REFUSE_EXISTING_CI_TEST_ROOT"}
$candidate=(Resolve-Path -LiteralPath $CandidateDir).Path
$meta=Get-Content (Join-Path $candidate "RC-METADATA.json") -Raw -Encoding UTF8|ConvertFrom-Json
if($meta.candidate_version -ne "4.3.9-rc.3" -or
   $meta.source_commit -ne "f45f1ba58171cd8018b6c74d2a0ca8bafe1b47e0" -or
   -not $meta.review_only -or -not $meta.unsigned -or
   $meta.operator_install_approved -or $meta.production_host_modified -or $meta.stable_published -or
   $meta.backend_ports_private -ne "UNCHANGED_FAIL"){throw "PINNED_PREVIEW_METADATA_MISMATCH"}
$lines=@(Get-Content (Join-Path $candidate "SHA256SUMS.txt") -Encoding ascii)
if($lines.Count -ne 5){throw "PREVIEW_HASH_COUNT_INVALID"}
foreach($row in $lines){
  if($row -notmatch '^([a-f0-9]{64})  ([A-Za-z0-9._-]+)$'){throw "PREVIEW_HASH_ROW_INVALID"}
  $want=$Matches[1];$filename=$Matches[2]
  $p=Join-Path $candidate $filename
  if(-not (Test-Path -LiteralPath $p -PathType Leaf) -or
     (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $want){
    throw "PREVIEW_HASH_MISMATCH"
  }
}
$oldPF=$env:ProgramFiles;$oldPD=$env:PROGRAMDATA
$serviceCreated=$false;$regCreated=$false
$report=[ordered]@{
  schema=1;disposable_github_windows_only=$true;synthetic=$false
  result="CHECK_REQUIRED";baseline_host_sha_verified=$false
  baseline_service_health_verified=$false;real_service_update_verified=$false
  installed_candidate_sha_verified=$false;official_backup_sha_verified=$false
  manual_service_restore_verified=$false;service_removed=$false;registry_removed=$false
  production_host_modified=$false;minecraft_server_started=$false
  backend_ports_private="UNCHANGED_FAIL";error_category="NONE"
}
function Wait-Host([string]$Version,[int]$Seconds){
  $deadline=(Get-Date).AddSeconds($Seconds)
  while((Get-Date) -lt $deadline){
    try {
      $h=Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/health" -TimeoutSec 2
      $state=(Get-Service -Name $service -ErrorAction Stop).Status
      if($state -eq "Running" -and $h.ok -eq $true -and
         [string]$h.version -eq $Version -and [int]$h.generation -eq 4 -and
         $h.service -eq $true){return $true}
    }catch{}
    Start-Sleep -Milliseconds 600
  }
  return $false
}
function Stop-CITestService {
  $svc=Get-Service -Name $service -ErrorAction SilentlyContinue
  if($null -ne $svc -and $svc.Status -ne 'Stopped') {
    & sc.exe stop $service *> $null
    for($i=0;$i -lt 40;$i++){
      Start-Sleep -Milliseconds 500
      if((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -eq 'Stopped'){break}
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
  $sha438="2fae64e09ba2e55639a6647e25eca41d2cbba8d751191b52e504a0f4b3232ad8"
  if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha438){
    throw "OFFICIAL_438_HOST_SHA_MISMATCH"
  }
  $report.baseline_host_sha_verified=$true
  $installedHost=Join-Path $install "GeumyiServerHost.exe"
  Copy-Item -LiteralPath $original -Destination $installedHost -ErrorAction Stop
  # No Minecraft directories or Java servers: only a blank backend list, no Agent,
  # no mobile API and no update-enabled environment on a disposable Windows VM.
  $config=Join-Path $root "isolated-server.json"
  @{bind="127.0.0.1";port=8787;api_token="";servers=@();
    auto_start_agent=$false;mobile_enabled=$false;
    update=@{enabled=$false;repository="";channel="stable"}
   }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $config -Encoding UTF8
  $binPath='"'+$installedHost+'" --service --config "'+$config+'"'
  New-Service -Name $service -DisplayName $service -BinaryPathName $binPath -StartupType Manual -ErrorAction Stop | Out-Null
  $serviceCreated=$true
  [void](New-Item -Path $reg -Force -ErrorAction Stop)
  $regCreated=$true
  [void](New-ItemProperty -LiteralPath $reg -Name "InstallLocation" -PropertyType String -Value $install -Force)
  & sc.exe start $service
  if($LASTEXITCODE -ne 0){throw "OFFICIAL_SERVICE_START_FAILED"}
  if(-not (Wait-Host "4.3.8" 45)){throw "OFFICIAL_SERVICE_HEALTH_FAILED"}
  $report.baseline_service_health_verified=$true
  $setup=Join-Path $candidate "GeumyiServerCenter-v4.3.9-rc.3-Setup.exe"
  $hostCandidate=Join-Path $candidate "GeumyiServerHost-v4.3.9-rc.3.exe"
  $candidateHash=(Get-FileHash -LiteralPath $hostCandidate -Algorithm SHA256).Hash.ToLowerInvariant()
  # Actual Setup self-update: service stop -> backup -> binary replacement ->
  # service start -> exact-version health. It must not launch any Minecraft backend.
  $p=Start-Process -FilePath $setup -ArgumentList "--self-update" -Wait -PassThru -NoNewWindow
  $reportPath=Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Updates\gsc-self-update-last.json"
  if(-not (Test-Path -LiteralPath $reportPath)){throw "CI_HELPER_REPORT_MISSING"}
  $r=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8|ConvertFrom-Json
  if($r.status -ne "success" -or $r.target_version -ne "4.3.9-rc.3" -or
     $r.rolled_back -or -not $r.host_health -or
     [string]$r.install_dir -ne [string]$install -or
     -not (Wait-Host "4.3.9-rc.3" 15)){throw "CI_REAL_HOST_SERVICE_UPDATE_FAILED"}
  $report.real_service_update_verified=$true
  $report.installed_candidate_sha_verified=((Get-FileHash -LiteralPath $installedHost -Algorithm SHA256).Hash.ToLowerInvariant() -eq $candidateHash)
  $backups=@(Get-ChildItem -LiteralPath (Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Backups") -Directory -ErrorAction Stop)
  foreach($b in $backups){
    $f=Join-Path $b.FullName "GeumyiServerHost.exe"
    if(Test-Path -LiteralPath $f -PathType Leaf){
      if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sha438){
        $report.official_backup_sha_verified=$true;break
      }
    }
  }
  if(-not $report.installed_candidate_sha_verified -or -not $report.official_backup_sha_verified){
    throw "CI_HOST_CANDIDATE_OR_BACKUP_SHA_MISMATCH"
  }
  # Explicit restoration exercise; automatic rollback-on-failure is separately unverified.
  Stop-CITestService
  if((Get-Service -Name $service -ErrorAction Stop).Status -ne "Stopped"){
    throw "CI_SERVICE_STOP_FOR_RESTORE_FAILED"
  }
  Copy-Item -LiteralPath $original -Destination $installedHost -Force -ErrorAction Stop
  & sc.exe start $service
  if($LASTEXITCODE -ne 0){throw "CI_BASELINE_RESTORE_START_FAILED"}
  $report.manual_service_restore_verified=((Get-FileHash -LiteralPath $installedHost -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sha438 -and
    (Wait-Host "4.3.8" 45))
  if(-not $report.manual_service_restore_verified){throw "CI_BASELINE_RESTORE_HEALTH_FAILED"}
  $report.result="DISPOSABLE_HOST_SERVICE_UPDATE_AND_MANUAL_RESTORE_PASS"
}catch{
  $report.error_category=([string]$_.Exception.Message -replace '[^A-Z0-9_]', '')
  if($report.error_category.Length -gt 90){$report.error_category=$report.error_category.Substring(0,90)}
  $report.result="DISPOSABLE_HOST_SERVICE_CHECK_FAILED"
}finally{
  if($serviceCreated){
    try{
      Stop-CITestService
      & sc.exe delete $service *> $null
      if($LASTEXITCODE -ne 0){throw "SC_DELETE_FAILED"}
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
  $out=Join-Path $env:RUNNER_TEMP "Day12-GSC-Host-RC3-Service-Report.json"
  $report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
}
if($report.result -ne "DISPOSABLE_HOST_SERVICE_UPDATE_AND_MANUAL_RESTORE_PASS" -or
   -not $report.service_removed -or -not $report.registry_removed){
  throw "HOST_DISPOSABLE_E2E_NOT_VERIFIED; SEE SANITIZED_ARTIFACT"
}
Write-Host "Disposable Windows Host service update and manual restore PASS; production unchanged."
