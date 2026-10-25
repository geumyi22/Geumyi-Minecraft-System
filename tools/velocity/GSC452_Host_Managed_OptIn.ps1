#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
 [ValidateSet('Plan','Apply','Restore')][string]$Mode='Plan',
 [switch]$Approved
)
# GSC Host service ONLY. No existing Minecraft tasks, worlds, JVMs or
# global Machine environment variables are modified by this script.
# Plan is read-only; Apply/Restore require explicit attended approval.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$service='Geumyi Server Center Host'
$variable='GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN'
$approval='DIRECT_OWNERSHIP_APPROVED'
$registry='HKLM:\SYSTEM\CurrentControlSet\Services\'+$service
$root=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged'
$recovery=Join-Path $root 'Recovery'
$journal=Join-Path $recovery 'host-optin-original-service-env.json'
$staging=Join-Path $root 'CanaryStaging'
function Deny([string]$code){throw ('HOST_OPTIN_NO_GO_'+$code)}
function Result([string]$message,[bool]$ok){
 [ordered]@{schema=1;check='GSC452_HOST_ONLY_MANAGED_OPTIN';mode=$Mode
  success=$ok;status=$message;read_only=($Mode -eq 'Plan')
  proxy_task_operations=0;java_operations=0;paper_operations_direct=0
  world_operations=0;host_service_restart_required=($Mode -ne 'Plan')
  host_restart_may_affect_autostart_backends=$true
  live_cutover_completed=$false}|ConvertTo-Json -Compress
}
function TrustedService(){
 $svc=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
 if($null -eq $svc -or $svc.StartName -notin @('LocalSystem','NT AUTHORITY\SYSTEM')){
  Deny 'TRUSTED_HOST_SERVICE_NOT_FOUND'
 }
 return $svc
}
function ServiceEnvironment(){
 $key=Get-Item -LiteralPath $registry -ErrorAction Stop
 if(@($key.GetValueNames()) -notcontains 'Environment'){
  return [pscustomobject]@{present=$false;values=@()}
 }
 if($key.GetValueKind('Environment') -ne [Microsoft.Win32.RegistryValueKind]::MultiString){
  Deny 'UNEXPECTED_SERVICE_ENV_TYPE'
 }
 $items=@($key.GetValue('Environment',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))
 return [pscustomobject]@{present=$true;values=$items}
}
function SetServiceEnvironment([bool]$has,[string[]]$values){
 if($has){
  New-ItemProperty -LiteralPath $registry -Name Environment -PropertyType MultiString -Value $values -Force -ErrorAction Stop|Out-Null
 }else{
  if(@((Get-Item -LiteralPath $registry -ErrorAction Stop).GetValueNames()) -contains 'Environment'){
   Remove-ItemProperty -LiteralPath $registry -Name Environment -ErrorAction Stop
  }
 }
}
function ProtectedFolder(){
 foreach($path in @($root,$recovery)){
  $f=Get-Item -LiteralPath $path -Force -ErrorAction Stop
  if(-not $f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   Deny 'RECOVERY_FOLDER_NOT_REGULAR'
  }
  $acl=Get-Acl -LiteralPath $path -ErrorAction Stop
  if(-not $acl.AreAccessRulesProtected){Deny 'RECOVERY_ACL_INHERITS'}
  foreach($ace in $acl.Access){
   if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow){
    $sid=$ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    if($sid -notin @('S-1-5-18','S-1-5-32-544')){Deny 'RECOVERY_ACL_NOT_PRIVATE'}
   }
  }
 }
}
function FleetNotMigrated(){
 foreach($name in @('wild','playground','other')){
  $task=Get-ScheduledTask -TaskName ('Geumyi Day10 Velocity '+$name) -TaskPath '\' -ErrorAction Stop
  if([string]$task.State -ne 'Running' -or $task.Settings.Enabled -ne $true){
   Deny 'LEGACY_PROXY_TASKS_NOT_RUNNING'
  }
  if(Test-Path -LiteralPath (Join-Path $recovery ($name+'.active.json'))){
   Deny 'EXISTING_GSC_PROXY_OWNER_OR_ORPHAN'
  }
  $file=Join-Path $recovery ($name+'.receipt.json')
  if(-not(Test-Path -LiteralPath $file -PathType Leaf)){Deny 'ORIGINAL_PROTECTED_RECEIPT_MISSING'}
  $receipt=Get-Content -LiteralPath $file -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
  if($receipt.schema -ne 1 -or $receipt.target -cne $name -or $receipt.cutover_committed -ne $false){
   Deny 'PROXY_ALREADY_MIGRATED_OR_RECEIPT_INVALID'
  }
 }
}
function VerifiedCanary([bool]$allowStopped=$false){
 $svc=TrustedService
 if($svc.State -ne 'Running' -and (-not $allowStopped -or $svc.State -ne 'Stopped')){Deny 'CANARY_HOST_SERVICE_NOT_RUNNING'}
 if($svc.State -eq 'Running' -and [int]$svc.ProcessId -le 4){Deny 'CANARY_HOST_SERVICE_PID_UNKNOWN'}
 $m=[regex]::Match([string]$svc.PathName,'(?i)^\s*"([^"]+\\GeumyiServerHost-v4\.5\.2-Velocity-CANARY\.exe)"\s+--service\s+--config\s+"([^"]+)"\s*$')
 if(-not $m.Success){Deny 'HOST_SERVICE_NOT_CANARY'}
 $exe=$m.Groups[1].Value
 $config=$m.Groups[2].Value
 if($svc.State -eq 'Running'){
  $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$svc.ProcessId) -ErrorAction Stop
  if($null -eq $proc -or [string]::IsNullOrWhiteSpace([string]$proc.ExecutablePath) -or
     [IO.Path]::GetFullPath([string]$proc.ExecutablePath) -ine [IO.Path]::GetFullPath($exe)){
   Deny 'HOST_SERVICE_BINARY_IDENTITY_MISMATCH'
  }
 }
 $stagingRecord=Get-Content -LiteralPath (Join-Path $staging 'STAGING-RECEIPT.json') -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 $exeInfo=Get-Item -LiteralPath $exe -Force -ErrorAction Stop
 if($exeInfo.PSIsContainer -or ($exeInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
    (Get-FileHash -LiteralPath $exe -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne [string]$stagingRecord.canary_sha256){
  Deny 'HOST_CANARY_EXE_HASH_DRIFT'
 }
 $cfg=Get-Content -LiteralPath $config -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 foreach($s in @($cfg.servers)){
  if($s.auto_start -eq $true){
   $port=[int]$s.java_port
   if($port -lt 1 -or $port -gt 65535){Deny 'BACKEND_PORT_UNVERIFIED'}
   $client=New-Object Net.Sockets.TcpClient
   try{
    $async=$client.BeginConnect('127.0.0.1',$port,$null,$null)
    if(-not $async.AsyncWaitHandle.WaitOne(900)){Deny 'AUTOSTART_BACKEND_OFFLINE'}
    $client.EndConnect($async)
   }catch{Deny 'AUTOSTART_BACKEND_OFFLINE'}finally{$client.Close()}
  }
 }
 return $svc
}
function Health([bool]$expect,[int]$seconds=6){
 $limit=[DateTime]::UtcNow.AddSeconds($seconds)
 do{
  try{
   $h=Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/health' -Method Get -TimeoutSec 2 -ErrorAction Stop
   $v=Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/v1/velocity/managed/status' -Method Get -TimeoutSec 2 -ErrorAction Stop
   if($h.ok -eq $true -and $h.service -eq $true -and [string]$h.version -ceq '4.5.2-canary' -and
      $v.read_only -eq $true -and $v.canary_enabled -eq $expect -and @($v.tasks).Count -eq 3){return $true}
  }catch{}
  Start-Sleep -Milliseconds 450
 }while([DateTime]::UtcNow -lt $limit)
 return $false
}
function RestartHost(){
 $svc=TrustedService
 if($svc.State -notin @('Running','Stopped')){Deny 'SERVICE_IN_UNKNOWN_STATE'}
 if($svc.State -eq 'Running'){
  $oldPID=[int]$svc.ProcessId
  Stop-Service -Name $service -ErrorAction Stop
  $controller=Get-Service -Name $service -ErrorAction Stop
  $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(25))
  $limit=[DateTime]::UtcNow.AddSeconds(25)
  do{
   $oldProc=Get-CimInstance Win32_Process -Filter ('ProcessId='+$oldPID) -ErrorAction Stop
   if($null -eq $oldProc){break}
   Start-Sleep -Milliseconds 300
  }while([DateTime]::UtcNow -lt $limit)
  if($null -ne $oldProc){Deny 'OLD_HOST_PROCESS_STILL_ALIVE'}
 }
 FleetNotMigrated
 Start-Service -Name $service -ErrorAction Stop
 $controller=Get-Service -Name $service -ErrorAction Stop
 $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(25))
}
try{
 Import-Module ScheduledTasks -ErrorAction Stop
 ProtectedFolder
 FleetNotMigrated
 $current=ServiceEnvironment
 $matches=@($current.values|Where-Object {$_ -match ('(?i)^'+$variable+'=')})
 if($matches.Count -gt 1){Deny 'DUPLICATE_SERVICE_FLAG'}
 if([Environment]::GetEnvironmentVariable($variable,'Machine') -ne $null){
  Deny 'UNEXPECTED_GLOBAL_MACHINE_OPTIN'
 }
 if($Mode -eq 'Plan'){
  if($matches.Count -gt 0 -or (Test-Path -LiteralPath $journal)){Deny 'OPTIN_ALREADY_STAGED'}
  $null=VerifiedCanary
  if(-not (Health $false 5)){Deny 'CANARY_STATUS_NOT_LOCKED_OR_UNAVAILABLE'}
  Result 'HOST_MANAGED_OPTIN_PLAN_PASS_NO_CHANGES' $true
  return
 }
 if(-not $Approved){Deny 'EXPLICIT_APPROVAL_REQUIRED'}
 if($Mode -eq 'Apply'){
  if($matches.Count -gt 0 -or (Test-Path -LiteralPath $journal)){Deny 'OPTIN_ALREADY_STAGED'}
  $null=VerifiedCanary
  if(-not (Health $false 5)){Deny 'CANARY_NOT_DEFAULT_LOCKED'}
  $typed=Read-Host 'Type RESTART GSC HOST ONLY (does not stop Velocity tasks)'
  if($typed -cne 'RESTART GSC HOST ONLY'){Deny 'HOST_RESTART_NOT_APPROVED'}
  $record=[ordered]@{schema=1;service=$service;original_present=[bool]$current.present
   original_values=@($current.values);created_utc=[DateTimeOffset]::UtcNow.ToString('o')}
  # Journal is PRIVATE and may contain earlier unrelated environment secrets.
  $out=[IO.File]::Open($journal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
   $bytes=[Text.Encoding]::UTF8.GetBytes(($record|ConvertTo-Json -Depth 5))
   $out.Write($bytes,0,$bytes.Length);$out.Flush($true)
  }finally{$out.Dispose()}
  SetServiceEnvironment $true ([string[]](@($current.values)+@($variable+'='+$approval)))
  RestartHost
  if(-not (Health $true 25)){Deny 'MANAGED_FLAG_NOT_ACTIVE_AFTER_HOST_RESTART'}
  Result 'HOST_MANAGED_OPTIN_ACTIVE_NO_VELOCITY_MIGRATION' $true
  return
 }
 if($Mode -eq 'Restore'){
  if(-not (Test-Path -LiteralPath $journal -PathType Leaf)){Deny 'PRIVATE_JOURNAL_MISSING'}
  $record=Get-Content -LiteralPath $journal -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
  if($record.schema -ne 1 -or $record.service -cne $service -or $null -eq $record.original_present){
   Deny 'JOURNAL_INVALID'
  }
  if($matches.Count -ne 1 -or $matches[0] -cne ($variable+'='+$approval)){
   Deny 'OPTIN_REGISTRY_DRIFTED'
  }
  $null=VerifiedCanary $true
  $typed=Read-Host 'Type RESTORE HOST MANAGED LOCK to revert service-specific flag'
  if($typed -cne 'RESTORE HOST MANAGED LOCK'){Deny 'HOST_RESTORE_NOT_APPROVED'}
  SetServiceEnvironment ([bool]$record.original_present) ([string[]]@($record.original_values))
  RestartHost
  if(-not (Health $false 25)){Deny 'RESTORED_HOST_LOCK_NOT_VERIFIED'}
  Result 'HOST_MANAGED_OPTIN_RESTORED_NO_VELOCITY_MIGRATION' $true
  return
 }
}catch{
 # No raw exceptions or registry values are ever printed in chat.
 # If an Apply fails after a registry write, the private journal remains.
 Result 'HOST_MANAGED_OPTIN_BLOCKED_OR_UNCONFIRMED_MANUAL_RECOVERY' $false
 exit 2
}
