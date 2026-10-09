[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# USER-ACTION ONLY, SUB PC ONLY. Never auto-run from update pipeline.
# Requires verified Ed25519 client-only manifest, pinned files, official
# GSC 4.3.8 Client hash, no Host role and typed approval before UAC.
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$expectedOld="05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61"
$expectedNew="c3057d6dfc2e88232a857932e960866c12fd6c8b65c40d2252ed71d6000fe111"
$report=[ordered]@{
 schema=1;phase="day12-gsc-rc2-subpc-client-only-real-update"
 generated_at=(Get-Date).ToString("o");result="STOPPED_NOT_APPLIED"
 baseline_sha_verified=$false;client_only_role_verified=$false
 manifest_signature_and_package_verified=$false;operator_approved=$false
 helper_report_success=$false;client_binary_updated=$false
 verified_old_client_backup=$false;client_relaunch_reported=$false
 host_service_modified=$false;game_server_modified=$false
 backend_ports_private="UNCHANGED_FAIL";notes="Client-only sub-PC test. Does NOT close Day12.10 bind gate."
}
$outDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-SubPC-GSC"
New-Item -ItemType Directory -Force -Path $outDir|Out-Null
$out=Join-Path $outDir ("Day12-SubPC-GSC-RC2-Apply-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
function PinHash([string]$p,[string]$want){
 if(-not (Test-Path -LiteralPath $p -PathType Leaf)){return $false}
 try{return ((Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -eq $want)}catch{return $false}
}
try {
 $verifier=Join-Path $root "Geumyi-GSC-Client-Canary-Verify.exe"
 if(-not (Test-Path -LiteralPath $verifier -PathType Leaf)){throw "SIGNATURE_VERIFIER_MISSING"}
 $v=& $verifier $root 2>&1
 if($LASTEXITCODE -ne 0 -or ([string]($v|Out-String)).Trim() -ne "GSC_CLIENT_OFFLINE_SIGNATURE_AND_FILE_HASH_PASS"){
   throw "OFFLINE_SIGNATURE_OR_PACKAGE_INVALID"
 }
 $report.manifest_signature_and_package_verified=$true

 $reg="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter"
 $item=Get-ItemProperty -LiteralPath $reg -ErrorAction Stop
 $install=[string]$item.InstallLocation
 if([string]::IsNullOrWhiteSpace($install) -or -not (Test-Path -LiteralPath $install -PathType Container)){
   throw "GSC_INSTALL_LOCATION_UNVERIFIED"
 }
 $client=Join-Path $install "GeumyiServerCenter.exe"
 if(-not (PinHash $client $expectedOld)){throw "SUBPC_BASELINE_CLIENT_NOT_OFFICIAL_438"}
 $report.baseline_sha_verified=$true
 if(Test-Path -LiteralPath (Join-Path $install "GeumyiServerHost.exe") -PathType Leaf){throw "HOST_BINARY_DETECTED"}
 if($null -ne (Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){throw "HOST_SERVICE_DETECTED"}
 if($null -ne (Get-ScheduledTask -TaskName "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){throw "HOST_AUTOSTART_TASK_DETECTED"}
 if(Test-Path -LiteralPath (Join-Path $env:ProgramData "GeumyiServerCenter\server.json") -PathType Leaf){throw "SERVER_CONFIG_DETECTED"}
 $clientCfgPresent=$false
 foreach($base in @($env:APPDATA,$env:LOCALAPPDATA)){
   if($base -and (Test-Path -LiteralPath (Join-Path $base "GeumyiServerCenter\client.json") -PathType Leaf)){$clientCfgPresent=$true}
 }
 if(-not $clientCfgPresent){throw "CLIENT_CONFIG_MISSING"}
 $pids=@(Get-Process -Name "GeumyiServerCenter" -ErrorAction SilentlyContinue)
 if($pids.Count -gt 1){throw "MULTIPLE_GSC_CLIENT_PROCESSES_UNSAFE"}
 foreach($proc in $pids){
   $processPath=""
   try{$processPath=[string]$proc.Path}catch{throw "CLIENT_PROCESS_PATH_UNREADABLE"}
   if(-not [string]::Equals($processPath,$client,[StringComparison]::OrdinalIgnoreCase)){
     throw "UNRELATED_GSC_CLIENT_PROCESS_UNSAFE"
   }
 }
 $report.client_only_role_verified=$true
 Write-Host ""
 Write-Host "GSC Client 4.3.8 -> 4.3.9-rc.2 Canary SUB PC ONLY"
 Write-Host "Only the GSC Client on THIS PC will temporarily close and update."
 Write-Host "No Minecraft server or Host is present; no update channel change."
 Write-Host "Windows executable is not Authenticode-signed; the separate signed"
 Write-Host "client-only manifest and pinned SHA256 files have passed verification."
 $consent=Read-Host "To START client-only update, enter UPDATE CLIENT ONLY"
 if($consent -cne "UPDATE CLIENT ONLY"){throw "OPERATOR_CANCELLED"}
 $report.operator_approved=$true
 $setup=Join-Path $root "GeumyiServerCenter-v4.3.9-rc.2-Setup.exe"
 $p=Start-Process -FilePath $setup -ArgumentList "--client-self-update" -Verb RunAs -PassThru -Wait
 $last=Join-Path $env:ProgramData "GeumyiServerCenter\Updates\gsc-client-self-update-last.json"
 if(-not (Test-Path -LiteralPath $last -PathType Leaf)){throw "UPDATE_HELPER_REPORT_MISSING"}
 $log=Get-Content -LiteralPath $last -Raw -Encoding UTF8|ConvertFrom-Json
 if([string]$log.status -ne "success" -or [string]$log.target_version -ne "4.3.9-rc.2"){
   throw "UPDATE_HELPER_NOT_SUCCESSFUL"
 }
 $report.helper_report_success=$true
 $report.client_binary_updated=PinHash $client $expectedNew
 if(-not $report.client_binary_updated){throw "UPDATED_CLIENT_SHA256_MISMATCH"}
 $bdir=[string]$log.backup_dir
 if($bdir -and (PinHash (Join-Path $bdir "GeumyiServerCenter.exe") $expectedOld)){
   $report.verified_old_client_backup=$true
 } else {throw "OLD_CLIENT_BACKUP_HASH_MISSING"}
 $report.client_relaunch_reported=[bool]$log.client_relaunched
 $report.result="SUBPC_CLIENT_RC2_APPLY_VERIFIED"
 Write-Host "GSC Client Canary updated and old 4.3.8 backup verified."
} catch {
 $msg=[string]$_.Exception.Message
 $allowed=@("SIGNATURE_VERIFIER_MISSING","OFFLINE_SIGNATURE_OR_PACKAGE_INVALID","GSC_INSTALL_LOCATION_UNVERIFIED",
 "SUBPC_BASELINE_CLIENT_NOT_OFFICIAL_438","HOST_BINARY_DETECTED","HOST_SERVICE_DETECTED",
 "HOST_AUTOSTART_TASK_DETECTED","SERVER_CONFIG_DETECTED","CLIENT_CONFIG_MISSING",
 "MULTIPLE_GSC_CLIENT_PROCESSES_UNSAFE","CLIENT_PROCESS_PATH_UNREADABLE",
 "UNRELATED_GSC_CLIENT_PROCESS_UNSAFE","OPERATOR_CANCELLED","UPDATE_HELPER_REPORT_MISSING",
 "UPDATE_HELPER_NOT_SUCCESSFUL","UPDATED_CLIENT_SHA256_MISMATCH","OLD_CLIENT_BACKUP_HASH_MISSING")
 $report.issue_code=if($allowed -contains $msg){$msg}else{"CHECK_REQUIRED_UNCLASSIFIED"}
 Write-Host ("Stopped: "+$report.issue_code)
} finally {
 $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding UTF8
 Write-Host "Report on Desktop: Geumyi-Day12-SubPC-GSC"
}
