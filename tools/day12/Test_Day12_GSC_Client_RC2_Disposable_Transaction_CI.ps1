[CmdletBinding()]
param([string]$CandidateDir="candidate-output")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# GitHub-hosted disposable Windows runner ONLY. Never execute on any real PC.
if($env:GITHUB_ACTIONS -ne "true" -or $env:GITHUB_REPOSITORY -ne "geumyi22/Geumyi-Minecraft-System" -or
  $env:GEUMYI_GSC_RC_STAGE -ne "isolated_ci_review_only" -or -not $env:RUNNER_TEMP -or
  [Environment]::OSVersion.Platform.ToString() -ne "Win32NT"){throw "REFUSE_OUTSIDE_DISPOSABLE_CI"}
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "CI_RUNNER_ELEVATION_REQUIRED"}
if(@(Get-Process -Name GeumyiServerCenter -ErrorAction SilentlyContinue).Count -gt 0 -or
   @(Get-Process -Name GeumyiServerHost -ErrorAction SilentlyContinue).Count -gt 0 -or
   $null -ne (Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){
  throw "REFUSE_EXISTING_CLIENT_OR_HOST_PROCESS"
}
$reg="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter"
if(Test-Path -LiteralPath $reg){throw "REFUSE_PREEXISTING_GSC_UNINSTALL_REGISTRY_KEY"}
$registryCreated=$false
$oldPF=$env:ProgramFiles;$oldPD=$env:PROGRAMDATA;$oldAD=$env:APPDATA
$temp=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path
$root=Join-Path $temp "Day12-GSC-RC2-Client-Transaction"
if(Test-Path -LiteralPath $root){throw "REFUSE_REUSING_CI_TEST_ROOT"}
$report=[ordered]@{
 schema=1;synthetic=$false;disposable_ci_only=$true
 result="CHECK_REQUIRED"
 baseline_sha_verified=$false
 failed_update_preserved_client=$false
 updated_client_hash_verified=$false
 old_client_backup_verified=$false
 manual_restore_verified=$false
 real_subpc_modified=$false
 production_server_modified=$false
 host_service_modified=$false
 backend_ports_private="UNCHANGED_FAIL"
}
try {
  $env:ProgramFiles=Join-Path $root "ProgramFiles"
  $env:PROGRAMDATA=Join-Path $root "ProgramData"
  $env:APPDATA=Join-Path $root "AppData"
  foreach($p in @($env:ProgramFiles,$env:PROGRAMDATA,$env:APPDATA)){
    New-Item -ItemType Directory -Path $p -Force|Out-Null
  }
  $installed=Join-Path $env:ProgramFiles "Geumyi Server Center"
  $baseline=Join-Path $root "official-438"
  New-Item -ItemType Directory -Path $installed,$baseline -Force | Out-Null
  # Real client-only installs advertise InstallLocation via this uninstall key.
  # Create it ONLY on a verified disposable GitHub Windows runner, never on a
  # user's machine, and remove exactly this owned test key in finally.
  [void](New-Item -Path $reg -ItemType RegistryKey -ErrorAction Stop)
  $registryCreated=$true
  [void](New-ItemProperty -LiteralPath $reg -Name "InstallLocation" -PropertyType String -Value $installed -Force -ErrorAction Stop)
  & gh release download "system-2026.10.07-day11-gsc438-beta" --repo $env:GITHUB_REPOSITORY --pattern "GeumyiServerCenter.exe" --dir $baseline --clobber
  if($LASTEXITCODE -ne 0){throw "OFFICIAL_438_CLIENT_DOWNLOAD_FAILED"}
  $original=Join-Path $baseline "GeumyiServerCenter.exe"
  $sha438="05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61"
  if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha438){
    throw "OFFICIAL_438_CLIENT_SHA_MISMATCH"
  }
  $report.baseline_sha_verified=$true
  $installedClient=Join-Path $installed "GeumyiServerCenter.exe"
  Copy-Item -LiteralPath $original -Destination $installedClient -ErrorAction Stop
  $candidateSetup=(Resolve-Path -LiteralPath (Join-Path $CandidateDir "GeumyiServerCenter-v4.3.9-rc.2-Setup.exe")).Path
  $candidateClient=(Resolve-Path -LiteralPath (Join-Path $CandidateDir "GeumyiServerCenter-v4.3.9-rc.2.exe")).Path
  $shaRC2=(Get-FileHash -LiteralPath $candidateClient -Algorithm SHA256).Hash.ToLowerInvariant()
  if($shaRC2 -eq $sha438){throw "CANDIDATE_CLIENT_SAME_SHA_AS_438"}
  # Inject a backup failure using a DIRECTORY at the Setup backup target,
  # inside the disposable CI installation only. No real processes are killed.
  $blockedTarget=Join-Path $installed "GeumyiServerCenter-Setup.exe"
  New-Item -ItemType Directory -Path $blockedTarget -Force|Out-Null
  $first=Start-Process -FilePath $candidateSetup -ArgumentList "--client-self-update" -Wait -PassThru -NoNewWindow
  $updateReport=Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Updates\gsc-client-self-update-last.json"
  if(-not (Test-Path -LiteralPath $updateReport)){throw "FIRST_REPORT_MISSING"}
  $r=Get-Content -LiteralPath $updateReport -Raw -Encoding UTF8|ConvertFrom-Json
  if($r.status -ne "failed" -or $r.target_version -ne "4.3.9-rc.2" -or
    (Get-FileHash -LiteralPath $installedClient -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha438){
    throw "FAILURE_INJECTION_CHANGED_BASELINE_CLIENT"
  }
  $report.failed_update_preserved_client=$true
  $report.first_failure_caused_by_directory=([string]$r.error -match "directory")
  $report.first_target_is_temporary=([string]$r.install_dir -eq [string]$installed)
  Remove-Item -LiteralPath $blockedTarget -Force -ErrorAction Stop
  $second=Start-Process -FilePath $candidateSetup -ArgumentList "--client-self-update" -Wait -PassThru -NoNewWindow
  $r=Get-Content -LiteralPath $updateReport -Raw -Encoding UTF8|ConvertFrom-Json
  $report.second_helper_status=if(@("success","failed","rolled_back") -contains [string]$r.status){[string]$r.status}else{"UNKNOWN"}
  $report.second_target_version_exact=([string]$r.target_version -eq "4.3.9-rc.2")
  $report.second_install_dir_is_temporary=([string]$r.install_dir -eq [string]$installed)
  $report.second_rolled_back=[bool]$r.rolled_back
  $failure=[string]$r.error
  $report.second_error_category=if(!$failure){"NONE"}elseif($failure -match "Host"){"HOST_UNEXPECTED"}elseif($failure -match "Client replacement"){"CLIENT_REPLACEMENT"}elseif($failure -match "Setup replacement"){"SETUP_REPLACEMENT"}elseif($failure -match "backup"){"BACKUP"}elseif($failure -match "embedded"){"EMBEDDED_EXTRACTION"}elseif($failure -match "not found"){"MISSING_CLIENT"}else{"OTHER"}
  if($r.status -ne "success" -or $r.target_version -ne "4.3.9-rc.2" -or $r.rolled_back){
    throw "CI_CLIENT_ONLY_UPDATE_NOT_SUCCESS"
  }
  if((Get-FileHash -LiteralPath $installedClient -Algorithm SHA256).Hash.ToLowerInvariant() -ne $shaRC2){
    throw "UPDATED_CLIENT_HASH_MISMATCH"
  }
  if(Test-Path -LiteralPath (Join-Path $installed "GeumyiServerHost.exe")){throw "UNEXPECTED_HOST_CREATED"}
  $report.updated_client_hash_verified=$true
  $backups=@(Get-ChildItem -LiteralPath (Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Backups") -Directory -ErrorAction Stop)
  foreach($b in $backups){
    $copy=Join-Path $b.FullName "GeumyiServerCenter.exe"
    if((Test-Path -LiteralPath $copy) -and
      (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sha438){
      $report.old_client_backup_verified=$true;break
    }
  }
  if(-not $report.old_client_backup_verified){throw "OLD_438_CLIENT_BACKUP_NOT_VERIFIED"}
  # Manual restoration exercise. This does NOT validate automatic rollback
  # triggered after an interrupted replacement.
  Copy-Item -LiteralPath $original -Destination $installedClient -Force
  $report.manual_restore_verified=((Get-FileHash -LiteralPath $installedClient -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sha438)
  if(-not $report.manual_restore_verified){throw "MANUAL_RESTORE_SHA_FAILED"}
  $report.result="DISPOSABLE_CLIENT_UPDATE_AND_MANUAL_RESTORE_PASS"
}finally{
  if($registryCreated) {
    try {
      Remove-Item -LiteralPath $reg -Recurse -Force -ErrorAction Stop
      $report.owned_disposable_registry_key_removed=(-not (Test-Path -LiteralPath $reg))
    } catch {
      $report.owned_disposable_registry_key_removed=$false
      $report.result="CI_REGISTRY_CLEANUP_FAILED"
    }
  }
  $env:ProgramFiles=$oldPF;$env:PROGRAMDATA=$oldPD;$env:APPDATA=$oldAD
  $report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $temp "Day12-RC2-Client-Transaction-Report.json") -Encoding UTF8
}
if($report.result -ne "DISPOSABLE_CLIENT_UPDATE_AND_MANUAL_RESTORE_PASS"){throw "DISPOSABLE_TRANSACTION_NOT_PASS"}
Write-Host "CI client-only helper and manual restoration PASS (disposable Windows runner only)"
