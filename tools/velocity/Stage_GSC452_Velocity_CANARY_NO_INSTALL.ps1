#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param()
# Stage-only: copy and verify a CI-built GSC Canary and the original host
# executable into protected ProgramData. Never stop or restart services,
# disable Windows tasks, invoke Java, modify config/ACL/firewall or worlds.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Deny([string]$why){throw ('CANARY_STAGE_NO_GO: '+$why)}
$expectedFile='GeumyiServerHost-v4.5.2-Velocity-CANARY.exe'
$source=Join-Path $PSScriptRoot $expectedFile
$sums=Join-Path $PSScriptRoot 'SHA256SUMS.txt'
if(-not (Test-Path -LiteralPath $source -PathType Leaf) -or
   -not (Test-Path -LiteralPath $sums -PathType Leaf)){
 Deny 'CI_CANARY_AND_CHECKSUM_FILES_REQUIRED_IN_SAME_FOLDER'
}
$lines=@(Get-Content -LiteralPath $sums)
$line=@($lines|Where-Object {$_ -match ('(?i)^[a-f0-9]{64}\s\s'+[regex]::Escape($expectedFile)+'$')})
if($line.Count -ne 1){Deny 'MISSING_PINNED_CANARY_SHA256'}
$expected=$line[0].Substring(0,64).ToLowerInvariant()
$actual=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if($actual -cne $expected){Deny 'CANARY_SHA256_MISMATCH'}
$svc=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
if($null -eq $svc -or $svc.State -ne 'Running'){Deny 'EXISTING_GSC_HOST_SERVICE_NOT_RUNNING'}
$bin=[string]$svc.PathName
$match=[regex]::Match($bin,'(?i)^\s*"([^"]*\\GeumyiServerHost\.exe)"')
if(-not $match.Success){
 $match=[regex]::Match($bin,'(?i)^\s*([^\s"]*\\GeumyiServerHost\.exe)(?:\s|$)')
}
if(-not $match.Success){Deny 'GSC_SERVICE_EXECUTABLE_PATH_NOT_TRUSTED'}
$runningHost=$match.Groups[1].Value
$hostFile=Get-Item -LiteralPath $runningHost -ErrorAction Stop
if(-not $hostFile.Exists -or $hostFile.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){
 Deny 'GSC_HOST_BINARY_MISSING_OR_REPARSE'
}
$pd=$env:ProgramData
if([string]::IsNullOrWhiteSpace($pd) -or -not [IO.Path]::IsPathRooted($pd)){
 Deny 'PROGRAMDATA_MISSING'
}
$root=Join-Path $pd 'GeumyiServerCenter\VelocityManaged'
if(-not (Test-Path -LiteralPath $root -PathType Container)){
 Deny 'PROTECTED_SNAPSHOT_ROOT_NOT_CREATED'
}
$acl=Get-Acl -LiteralPath $root
if(-not $acl.AreAccessRulesProtected){Deny 'STAGING_PARENT_ACL_INHERITS'}
foreach($ace in $acl.Access){
 $id=$null
 try{$id=$ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value}
 catch{Deny 'UNKNOWN_PARENT_ACL_PRINCIPAL'}
 if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
    $id -notin @('S-1-5-18','S-1-5-32-544')){
  Deny 'STAGING_PARENT_ACL_BROAD_ALLOW'
 }
}
foreach($target in @('wild','playground','other')){
 $file=Join-Path (Join-Path $root 'Recovery') ($target+'.original.xml')
 if(-not(Test-Path -LiteralPath $file -PathType Leaf)){
  Deny ('PREVIOUS_ORIGINAL_TASK_SNAPSHOT_MISSING_'+$target)
 }
}
$dest=Join-Path $root 'CanaryStaging'
if(Test-Path -LiteralPath $dest){Deny 'STAGING_ALREADY_PRESENT_NEVER_OVERWRITE'}
# Stage only after all verification. Protect by inherited SYSTEM+Admins ACL.
[void](New-Item -ItemType Directory -Path $dest -ErrorAction Stop)
try{
 Copy-Item -LiteralPath $source -Destination (Join-Path $dest $expectedFile) -ErrorAction Stop
 Copy-Item -LiteralPath $runningHost -Destination (Join-Path $dest 'GeumyiServerHost-ORIGINAL.exe') -ErrorAction Stop
 $copy=(Get-FileHash -LiteralPath (Join-Path $dest $expectedFile) -Algorithm SHA256).Hash.ToLowerInvariant()
 if($copy -cne $expected){Deny 'STAGED_EXECUTABLE_INTEGRITY_FAILED'}
 $originalHash=(Get-FileHash -LiteralPath $runningHost -Algorithm SHA256).Hash.ToLowerInvariant()
 $copyOriginal=(Get-FileHash -LiteralPath (Join-Path $dest 'GeumyiServerHost-ORIGINAL.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
 if($originalHash -cne $copyOriginal){Deny 'ORIGINAL_HOST_BACKUP_INTEGRITY_FAILED'}
 $receipt=[ordered]@{
  schema=1;status='STAGED_NOT_INSTALLED';target='GSC_HOST_ONLY'
  canary_sha256=$copy;original_host_sha256=$copyOriginal
  original_host_service_running_before=$true
  tasks_untouched=$true;services_untouched=$true;worlds_untouched=$true
  created_utc=[DateTimeOffset]::UtcNow.ToString('o')
 }
 $json=$receipt|ConvertTo-Json -Compress
 [IO.File]::WriteAllText((Join-Path $dest 'STAGING-RECEIPT.json'),
   $json,(New-Object Text.UTF8Encoding($false)))
 [ordered]@{schema=1;status='CANARY_STAGED_NO_INSTALL'
   all_three_original_tasks_preserved=$true
   old_gsc_host_binary_backed_up=$true
   canary_binary_sha_verified=$true
   service_restarted=$false;scheduled_tasks_changed=$false;java_changed=$false
   next='HOST_SERVICE_AND_ORPHAN_RECOVERY_PLAN_REQUIRED_BEFORE_CUTOVER'
 }|ConvertTo-Json -Compress
}catch{
 # Retain partial staging for manual inspection instead of overwriting data.
 Deny 'STAGING_INCOMPLETE_SERVICES_UNTOUCHED'
}
