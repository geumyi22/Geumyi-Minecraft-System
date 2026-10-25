#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
 [ValidateSet('none','before-write','journal-only','flag-host-offline','flag-host-locked','flag-host-enabled')]
 [string]$SyntheticScenario='none'
)
# Diagnose the LAST attempted Host managed-control opt-in without any mutation.
# DO NOT print API tokens, raw service command lines, original Environment values,
# private journal, XML, PID, executable paths, secrets or stack traces.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Classify([string]$journal,[string]$flag,[string]$svc,[string]$api){
 if($journal -eq 'ABSENT' -and $flag -eq 'ABSENT'){return 'NO_HOST_OPTIN_WRITE_EVIDENT'}
 if($journal -eq 'VALID' -and $flag -eq 'ABSENT'){return 'PRIVATE_JOURNAL_CREATED_FLAG_NOT_SET'}
 if($journal -eq 'VALID' -and $flag -eq 'EXACT'){
  if($svc -eq 'Stopped'){return 'FLAG_SET_HOST_STOPPED_NEEDS_CONTROLLED_RECOVERY'}
  if($svc -eq 'Running' -and $api -eq 'ENABLED'){return 'FLAG_SET_HOST_RUNNING_API_ENABLED'}
  if($svc -eq 'Running' -and $api -eq 'LOCKED'){return 'FLAG_SET_HOST_RUNNING_API_STILL_LOCKED'}
  return 'FLAG_SET_RUNTIME_NOT_ATTESTED'
 }
 return 'AMBIGUOUS_OR_PARTIAL_APPLY_RECOVERY_REQUIRES_REVIEW'
}
if($SyntheticScenario -cne 'none'){
 if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:CI -cne 'true'){
  throw 'SYNTHETIC_ONLY_ON_ISOLATED_WINDOWS_GITHUB_ACTIONS'
 }
 $cases=@{
  'before-write'=@('ABSENT','ABSENT','Running','LOCKED');
  'journal-only'=@('VALID','ABSENT','Running','LOCKED');
  'flag-host-offline'=@('VALID','EXACT','Stopped','UNAVAILABLE');
  'flag-host-locked'=@('VALID','EXACT','Running','LOCKED');
  'flag-host-enabled'=@('VALID','EXACT','Running','ENABLED')
 }
 $a=$cases[$SyntheticScenario]
 [ordered]@{schema=1;check='GSC452_HOST_OPTIN_POSTFAIL_DIAGNOSTIC'
  synthetic=$true;read_only=$true;classification=(Classify $a[0] $a[1] $a[2] $a[3])
  service_mutations=0;task_mutations=0;jvm_mutations=0}|ConvertTo-Json -Compress
 return
}
$out=[ordered]@{
 schema=1;check='GSC452_HOST_OPTIN_POSTFAIL_DIAGNOSTIC'
 synthetic=$false;read_only=$true
 service_state='UNKNOWN';registered_host_kind='UNVERIFIED'
 service_runtime_process_identity='UNVERIFIED'
 service_environment_type='UNVERIFIED';optin_service_flag='UNVERIFIED'
 private_journal='UNVERIFIED';private_journal_acl='UNVERIFIED'
 canary_health='UNVERIFIED';canary_managed_api='UNVERIFIED'
 original_scheduler_running_count=0;original_scheduler_disabled_count=0
 original_scheduler_unknown_count=3
 classification='DIAGNOSTIC_INCOMPLETE'
 original_protected_files_written=0;service_mutations=0
 task_mutations=0;jvm_mutations=0;world_mutations=0
 safe_to_start_another_proxy=$false
}
try{
 $svc=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
 if($null -ne $svc){
  $out.service_state=[string]$svc.State
  $pattern='(?i)^\s*"([^"]+\\GeumyiServerHost-v4\.5\.2-Velocity-CANARY\.exe)"\s+--service\s+--config\s+"([^"]+)"\s*$'
  $m=[regex]::Match([string]$svc.PathName,$pattern)
  $out.registered_host_kind=if($m.Success){'EXPECTED_CANARY'}else{'OTHER_OR_UNVERIFIED'}
  if($m.Success -and $svc.State -eq 'Running' -and [int]$svc.ProcessId -gt 4){
   try{
    $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$svc.ProcessId) -ErrorAction Stop
    $out.service_runtime_process_identity=if($null -ne $p -and $p.ExecutablePath -and
        [IO.Path]::GetFullPath([string]$p.ExecutablePath) -ieq
        [IO.Path]::GetFullPath($m.Groups[1].Value)){'MATCH'}else{'MISMATCH_OR_UNVERIFIED'}
   }catch{$out.service_runtime_process_identity='UNAVAILABLE'}
  }
 }
}catch{}
try{
 $name='GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN'
 $serviceKey='HKLM:\SYSTEM\CurrentControlSet\Services\Geumyi Server Center Host'
 $key=Get-Item -LiteralPath $serviceKey -ErrorAction Stop
 if(@($key.GetValueNames()) -notcontains 'Environment'){
  $out.service_environment_type='ABSENT'
  $out.optin_service_flag='ABSENT'
 }elseif($key.GetValueKind('Environment') -ne [Microsoft.Win32.RegistryValueKind]::MultiString){
  $out.service_environment_type='OTHER_TYPE'
  $out.optin_service_flag='UNVERIFIED'
 }else{
  $out.service_environment_type='REG_MULTI_SZ'
  $entries=@($key.GetValue('Environment',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))
  $matched=@($entries|Where-Object {$_ -imatch ('^'+$name+'=')})
  if($matched.Count -eq 0){$out.optin_service_flag='ABSENT'}
  elseif($matched.Count -gt 1){$out.optin_service_flag='DUPLICATE'}
  elseif($matched[0] -ceq ($name+'=DIRECT_OWNERSHIP_APPROVED')){$out.optin_service_flag='EXACT'}
  else{$out.optin_service_flag='OTHER_VALUE'}
 }
}catch{}
try{
 $root=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged\Recovery'
 $journal=Join-Path $root 'host-optin-original-service-env.json'
 if(-not(Test-Path -LiteralPath $journal -PathType Leaf)){
  $out.private_journal='ABSENT'
 }else{
  $ji=Get-Item -LiteralPath $journal -Force -ErrorAction Stop
  $out.private_journal=if(($ji.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
     $ji.Length -lt 40 -or $ji.Length -gt 65536){'UNTRUSTED_TYPE_OR_SIZE'}else{'PRESENT_UNVERIFIED'}
  if($out.private_journal -eq 'PRESENT_UNVERIFIED'){
   $j=Get-Content -LiteralPath $journal -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
   if($j.schema -eq 1 -and $j.service -ceq 'Geumyi Server Center Host' -and
      $null -ne $j.original_present -and $null -ne $j.original_values){
    $out.private_journal='VALID'
   }else{$out.private_journal='INVALID_SCHEMA'}
  }
 }
 $dir=Get-Acl -LiteralPath $root -ErrorAction Stop
 $trusted=$dir.AreAccessRulesProtected
 foreach($ace in $dir.Access){
  if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow){
   $sid=$ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
   if($sid -notin @('S-1-5-18','S-1-5-32-544')){$trusted=$false}
  }
 }
 $out.private_journal_acl=if($trusted){'TRUSTED_RECOVERY_DIRECTORY'}else{'REVIEW_RECOVERY_DIRECTORY_ACL'}
}catch{
 if($out.private_journal -eq 'UNVERIFIED'){$out.private_journal='INACCESSIBLE_OR_UNVERIFIED'}
}
try{
 $h=Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:8787/api/health' -TimeoutSec 3 -ErrorAction Stop
 $out.canary_health=if($h.ok -eq $true -and $h.service -eq $true -and
   [string]$h.version -ceq '4.5.2-canary'){'HEALTHY_CANARY'}else{'OTHER_VERSION_OR_UNHEALTHY'}
}catch{$out.canary_health='UNAVAILABLE'}
try{
 # Enabled Canary probes ScheduledTasks with a 5-second host-side cap;
 $status=Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:8787/api/v1/velocity/managed/status' -TimeoutSec 15 -ErrorAction Stop
 $out.canary_managed_api=if($status.ok -eq $true -and $status.read_only -eq $true -and
   @($status.tasks).Count -eq 3){
    if($status.canary_enabled -eq $true){'ENABLED'}elseif($status.canary_enabled -eq $false){'LOCKED'}else{'UNVERIFIED'}
   }else{'UNVERIFIED'}
}catch{$out.canary_managed_api='UNAVAILABLE'}
try{
 Import-Module ScheduledTasks -ErrorAction Stop
 $states=@('wild','playground','other')|ForEach-Object {
  $t=Get-ScheduledTask -TaskPath '\' -TaskName ('Geumyi Day10 Velocity '+$_) -ErrorAction Stop
  [string]$t.State
 }
 $out.original_scheduler_running_count=@($states|Where-Object {$_ -eq 'Running'}).Count
 $out.original_scheduler_disabled_count=@($states|Where-Object {$_ -eq 'Disabled'}).Count
 $out.original_scheduler_unknown_count=3-$out.original_scheduler_running_count-$out.original_scheduler_disabled_count
}catch{}
$out.classification=Classify $out.private_journal $out.optin_service_flag $out.service_state $out.canary_managed_api
$out|ConvertTo-Json -Compress -Depth 4
