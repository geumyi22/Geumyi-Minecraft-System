[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# EXPLICIT operator-triggered SUB PC CLIENT-ONLY restore, not an automatic
# rollback on real systems. No Host, Java, worlds, firewall, credentials.
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$oldHash="05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61"
$newHash="c3057d6dfc2e88232a857932e960866c12fd6c8b65c40d2252ed71d6000fe111"
$report=[ordered]@{
 schema=1;phase="day12-gsc-rc2-subpc-restore-official-438"
 generated_at=(Get-Date).ToString("o");result="STOPPED_NOT_RESTORED"
 manifest_valid=$false;client_only_verified=$false
 operator_approved=$false;restore_completed=$false;client_restart_attempted=$false
 real_server_modified=$false;host_modified=$false;backend_ports_private="UNCHANGED_FAIL"
}
$outDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-SubPC-GSC"
New-Item -ItemType Directory -Path $outDir -Force|Out-Null
$out=Join-Path $outDir ("Day12-SubPC-GSC-RC2-Restore-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
function HashMatches([string]$p,[string]$want){
 if(-not (Test-Path -LiteralPath $p -PathType Leaf)){return $false}
 try{return ((Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -eq $want)}catch{return $false}
}
try{
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "ADMIN_REQUIRED_FOR_CONTROLLED_RESTORE"}
 $verifier=Join-Path $root "Geumyi-GSC-Client-Canary-Verify.exe"
 if(-not (Test-Path -LiteralPath $verifier -PathType Leaf)){throw "SIGNATURE_VERIFIER_MISSING"}
 $v=& $verifier $root 2>&1
 if($LASTEXITCODE -ne 0 -or ([string]($v|Out-String)).Trim() -ne "GSC_CLIENT_OFFLINE_SIGNATURE_AND_FILE_HASH_PASS"){
  throw "SIGNED_RECOVERY_PACKAGE_INVALID"
 }
 $report.manifest_valid=$true
 $reg="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter"
 $install=[string](Get-ItemProperty -LiteralPath $reg -ErrorAction Stop).InstallLocation
 if(-not $install -or -not (Test-Path -LiteralPath $install -PathType Container)){throw "GSC_INSTALL_DIR_UNAVAILABLE"}
 $client=Join-Path $install "GeumyiServerCenter.exe"
 if(Test-Path -LiteralPath (Join-Path $install "GeumyiServerHost.exe") -PathType Leaf){throw "HOST_BINARY_PRESENT"}
 if($null -ne (Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){throw "HOST_SERVICE_PRESENT"}
 if($null -ne (Get-ScheduledTask -TaskName "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){throw "HOST_TASK_PRESENT"}
 if(Test-Path -LiteralPath (Join-Path $env:ProgramData "GeumyiServerCenter\server.json") -PathType Leaf){throw "SERVER_CONFIG_PRESENT"}
 $report.client_only_verified=$true
 if(HashMatches $client $oldHash){
   $report.result="OFFICIAL_438_ALREADY_PRESENT";return
 }
 if(-not (HashMatches $client $newHash)){throw "INSTALLED_CLIENT_NOT_APPROVED_RC2"}
 $restore=Join-Path $root "GeumyiServerCenter-v4.3.8-Recovery.exe"
 if(-not (HashMatches $restore $oldHash)){throw "OFFICIAL_438_RECOVERY_SHA_MISMATCH"}
 $running=@(Get-Process -Name "GeumyiServerCenter" -ErrorAction SilentlyContinue)
 if($running.Count -gt 1){throw "MULTIPLE_GSC_CLIENT_PROCESSES_UNSAFE"}
 foreach($p in $running){
  $processPath=""
  try{$processPath=[string]$p.Path}catch{throw "PROCESS_PATH_UNREADABLE"}
  if(-not [string]::Equals($processPath,$client,[StringComparison]::OrdinalIgnoreCase)){
   throw "UNRELATED_GSC_CLIENT_PROCESS_UNSAFE"
  }
 }
 Write-Host "Restore ONLY the GSC Client on this SUB PC from 4.3.9-rc.2 to 4.3.8."
 Write-Host "GSC Client will close briefly. Host/server/worlds are not changed."
 $consent=Read-Host "Type RESTORE 4.3.8 to proceed"
 if($consent -cne "RESTORE 4.3.8"){throw "OPERATOR_CANCELLED"}
 $report.operator_approved=$true
 foreach($p in $running){
  Stop-Process -Id $p.Id -ErrorAction Stop
  $p.WaitForExit(5000)|Out-Null
 }
 $tempTarget=$client+".gsc-rollback-new"
 if(Test-Path -LiteralPath $tempTarget){throw "TEMP_RESTORE_TARGET_EXISTS"}
 Copy-Item -LiteralPath $restore -Destination $tempTarget -ErrorAction Stop
 if(-not (HashMatches $tempTarget $oldHash)){throw "RESTORE_STAGED_SHA_MISMATCH"}
 $preimage=$client+".gsc-rc2-before-restore"
 if(Test-Path -LiteralPath $preimage){throw "PREIMAGE_BACKUP_ALREADY_EXISTS"}
 [IO.File]::Replace($tempTarget,$client,$preimage,$true)
 if(-not (HashMatches $client $oldHash)){throw "RESTORED_CLIENT_SHA_MISMATCH"}
 $report.restore_completed=$true
 $report.result="RESTORE_438_VERIFIED"
 if($running.Count -gt 0){
  try{Start-Process -FilePath $client -ArgumentList "--background" -ErrorAction Stop; $report.client_restart_attempted=$true}catch{}
 }
 Write-Host "Official GSC 4.3.8 Client restored and SHA256 verified."
}catch{
 $msg=[string]$_.Exception.Message
 $allowed=@("ADMIN_REQUIRED_FOR_CONTROLLED_RESTORE","SIGNATURE_VERIFIER_MISSING",
 "SIGNED_RECOVERY_PACKAGE_INVALID","GSC_INSTALL_DIR_UNAVAILABLE","HOST_BINARY_PRESENT",
 "HOST_SERVICE_PRESENT","HOST_TASK_PRESENT","SERVER_CONFIG_PRESENT",
 "INSTALLED_CLIENT_NOT_APPROVED_RC2","OFFICIAL_438_RECOVERY_SHA_MISMATCH",
 "MULTIPLE_GSC_CLIENT_PROCESSES_UNSAFE","PROCESS_PATH_UNREADABLE",
 "UNRELATED_GSC_CLIENT_PROCESS_UNSAFE","OPERATOR_CANCELLED","TEMP_RESTORE_TARGET_EXISTS",
 "RESTORE_STAGED_SHA_MISMATCH","PREIMAGE_BACKUP_ALREADY_EXISTS","RESTORED_CLIENT_SHA_MISMATCH")
 $report.issue_code=if($allowed -contains $msg){$msg}else{"CHECK_REQUIRED_UNCLASSIFIED"}
 Write-Host ("Restore stopped: "+$report.issue_code)
}finally{
 $report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $out -Encoding UTF8
 Write-Host "Restore report: Desktop\Geumyi-Day12-SubPC-GSC"
}
