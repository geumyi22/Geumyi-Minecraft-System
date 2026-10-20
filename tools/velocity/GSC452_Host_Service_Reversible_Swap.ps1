#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
 [ValidateSet('Plan','Apply','Rollback','Synthetic')]
 [string]$Mode='Plan',
 [switch]$OperatorConfirmed,
 [ValidateSet('healthy','canary-start-fails','rollback-start-fails')]
 [string]$SyntheticCase='healthy'
)
# GSC Host service ONLY. Never replace the original executable, kill tasks,
# run arbitrary Java, modify worlds/firewall or write configuration files.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$serviceName='Geumyi Server Center Host'
$expectedOriginalVersion='4.5.1'
$expectedCanaryVersion='4.5.2-canary'
$canaryName='GeumyiServerHost-v4.5.2-Velocity-CANARY.exe'
$journalName='HOST-SWAP-PRIVATE-JOURNAL.json'
function Output([string]$status,[bool]$success,[string]$detail){
 [ordered]@{schema=1;operation='HOST_SERVICE_REVERSIBLE_SWAP';mode=$Mode
  success=$success;status=$status;detail=$detail
  minecraft_task_operations=0;paper_operations_direct=0;paper_indirect_restart_effects_not_proven=$true;configuration_writes=0
  service_mutation_authorized=($Mode -in @('Apply','Rollback') -and $OperatorConfirmed.IsPresent)
 }|ConvertTo-Json -Compress -Depth 4
}
function Deny([string]$code){throw ('SWAP_NO_GO_'+$code)}
function Sha([string]$path){
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Deny 'MISSING_VERIFIED_FILE'}
 $f=Get-Item -LiteralPath $path -ErrorAction Stop
 if($f.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){Deny 'REPARSE_FILE'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function PrivateDir([string]$path){
 $item=Get-Item -LiteralPath $path -ErrorAction Stop
 if(-not $item.PSIsContainer -or $item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){Deny 'STAGING_DIRECTORY_TYPE'}
 $acl=Get-Acl -LiteralPath $path
 if(-not $acl.AreAccessRulesProtected){Deny 'STAGING_INHERITED_ACL'}
 foreach($ace in $acl.Access){
  $sid=$ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
  if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
    $sid -notin @('S-1-5-18','S-1-5-32-544')){Deny 'STAGING_UNTRUSTED_ALLOW_ACE'}
 }
}
function Service(){
 $item=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
 if($null -eq $item){Deny 'SERVICE_MISSING'}
 if($item.StartName -notin @('LocalSystem','NT AUTHORITY\SYSTEM')){Deny 'SERVICE_PRINCIPAL_MISMATCH'}
 return $item
}
function ParseService([string]$line){
 $m=[regex]::Match($line,'(?i)^\s*"([^"]+\\GeumyiServerHost(?:-v4\.5\.2-Velocity-CANARY)?\.exe)"\s+--service\s+--config\s+"([^"]+)"\s*$')
 if(-not $m.Success){Deny 'SCM_LAUNCH_FORMAT'}
 $binary=$m.Groups[1].Value
 $cfg=$m.Groups[2].Value
 if(-not [IO.Path]::IsPathRooted($binary) -or -not [IO.Path]::IsPathRooted($cfg)){Deny 'SERVICE_PATH_NOT_ABSOLUTE'}
 return [pscustomobject]@{binary=$binary;config=$cfg}
}
function Health([int]$port,[string]$expected,[int]$waitSec=4){
 $limit=[DateTime]::UtcNow.AddSeconds($waitSec)
 while([DateTime]::UtcNow -lt $limit){
  try{
   $uri='http://127.0.0.1:'+$port+'/api/health'
   $r=Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 2 -ErrorAction Stop
   if($r.ok -eq $true -and $r.service -eq $true -and [string]$r.version -ceq $expected){return $true}
  }catch{}
  Start-Sleep -Milliseconds 400
 }
 return $false
}
function VerifyServiceBinary([string]$expected){
 $svc=Service
 if($svc.State -ne 'Running' -or [int]$svc.ProcessId -le 0){Deny 'SERVICE_PROCESS_NOT_RUNNING'}
 $registered=ParseService ([string]$svc.PathName)
 if($registered.binary -ine $expected){Deny 'SERVICE_TARGET_NOT_EXPECTED'}
 $process=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$svc.ProcessId) -ErrorAction Stop
 if($null -eq $process -or -not $process.ExecutablePath){Deny 'SERVICE_PID_EXECUTABLE_MISSING'}
 if([IO.Path]::GetFullPath([string]$process.ExecutablePath) -ine [IO.Path]::GetFullPath($expected)){
  Deny 'SERVICE_PID_EXE_MISMATCH'
 }
}
function VerifyCanaryLocked([string]$configPath,[int]$port){
 $cfg=Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 $token=[string]$cfg.api_token
 if([string]::IsNullOrWhiteSpace($token)){Deny 'HOST_API_TOKEN_MISSING'}
 try{
  $headers=@{'X-GSC-Token'=$token}
  $data=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$port+'/api/v1/velocity/managed/status') -Headers $headers -Method Get -TimeoutSec 3 -ErrorAction Stop
  if($data.canary_enabled -ne $false -or $data.read_only -ne $true -or @($data.tasks).Count -ne 3){Deny 'CANARY_MANAGED_GATE_NOT_LOCKED'}
  foreach($row in @($data.tasks)){
   if($row.can_start -ne $false -or $row.can_stop -ne $false -or $row.can_restart -ne $false){Deny 'VELOCITY_ACTION_UNEXPECTEDLY_ENABLED'}
  }
 }catch{Deny 'CANARY_CONTROL_STATUS_UNVERIFIED'}
}
function SvcWait([string]$state,[int]$seconds){
 $s=Get-Service -Name $serviceName -ErrorAction Stop
 if([string]$s.Status -ne $state){
  $s.WaitForStatus([ServiceProcess.ServiceControllerStatus]::$state,[TimeSpan]::FromSeconds($seconds))
 }
 $s.Refresh()
 return ([string]$s.Status -eq $state)
}
function SvcStop(){
 $s=Get-Service -Name $serviceName -ErrorAction Stop
 if([string]$s.Status -eq 'Stopped'){return}
 if([string]$s.Status -ne 'Running'){Deny 'SERVICE_NOT_STABLE_BEFORE_STOP'}
 Stop-Service -Name $serviceName -ErrorAction Stop
 if(-not(SvcWait 'Stopped' 25)){Deny 'SERVICE_DID_NOT_STOP'}
}
function SvcStart(){
 $s=Get-Service -Name $serviceName -ErrorAction Stop
 if([string]$s.Status -ne 'Stopped'){Deny 'SERVICE_NOT_STOPPED_BEFORE_START'}
 Start-Service -Name $serviceName -ErrorAction Stop
 if(-not(SvcWait 'Running' 25)){Deny 'SERVICE_DID_NOT_REACH_RUNNING'}
}
function ScSetBinary([string]$exe,[string]$cfg){
 if(-not [IO.Path]::IsPathRooted($exe)){Deny 'BINARY_NOT_ABSOLUTE'}
 $arg='"'+$exe+'" --service --config "'+$cfg+'"'
 $result=Invoke-CimMethod -InputObject (Service) -MethodName Change -Arguments @{PathName=$arg} -ErrorAction Stop
 if($null -eq $result -or [int]$result.ReturnValue -ne 0){Deny 'SCM_BINPATH_CONFIG_FAILED'}
 $after=ParseService ([string](Service).PathName)
 if($after.binary -ine $exe -or $after.config -ine $cfg){Deny 'SCM_BINPATH_VERIFY_FAILED'}
}
function VerifyProxyBaseline(){
 foreach($id in @('wild','playground','other')){
  $state=(Get-ScheduledTask -TaskName ('Geumyi Day10 Velocity '+$id) -TaskPath '\' -ErrorAction Stop).State
  if([string]$state -ne 'Running'){Deny ('LEGACY_PROXY_TASK_STATE_'+$id)}
 }
}
function OwnersAbsent([string]$folder){
 foreach($id in @('wild','playground','other')){
  if(Test-Path -LiteralPath (Join-Path $folder ($id+'.active.json'))){Deny 'ORPHANED_VELOCITY_GENERATION_PRESENT'}
 }
}
function ConfigPorts([string]$path){
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Deny 'CONFIG_NOT_FOUND'}
 $cfg=Get-Content -LiteralPath $path -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 $port=[int]$cfg.port
 if($port -lt 1024 -or $port -gt 65535){Deny 'INVALID_GSC_PORT'}
 # A Host restart runs startupSupervisor. To avoid unexpectedly launching
 # or updating Paper, all currently auto-start backends MUST already be up.
 foreach($entry in @($cfg.servers)){
  if($entry.auto_start -eq $true){
   $p=[int]$entry.java_port
   if($p -lt 1 -or $p -gt 65535){Deny 'INVALID_BACKEND_PORT'}
   $client=New-Object System.Net.Sockets.TcpClient
   try{
    $a=$client.BeginConnect('127.0.0.1',$p,$null,$null)
    if(-not $a.AsyncWaitHandle.WaitOne(900)){Deny 'AUTOSTART_BACKEND_OFFLINE'}
    $client.EndConnect($a)
   }catch{Deny 'AUTOSTART_BACKEND_OFFLINE'}finally{$client.Close()}
  }
 }
 return $port
}
function Preflight(){
 if($env:GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN -ceq 'DIRECT_OWNERSHIP_APPROVED'){Deny 'MANAGED_OPTIN_ENV_ENABLED'}
 try{
  $machineOpt=[Environment]::GetEnvironmentVariable('GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN','Machine')
  if($machineOpt -ceq 'DIRECT_OWNERSHIP_APPROVED'){Deny 'MANAGED_MACHINE_OPTIN_ENABLED'}
 }catch{Deny 'MACHINE_ENV_CHECK_FAILED'}
 if($Mode -ne 'Rollback'){
  # Repeat the already successful read-only evidence *internally*, not as
  # another operator step; reject drift in private task snapshots, local Host
  # process identity, current binary and frozen Canary digest.
  $readOnly=Join-Path $PSScriptRoot 'GSC452_Host_Swap_Recovery_PREFLIGHT_READ_ONLY.ps1'
  if(-not(Test-Path -LiteralPath $readOnly -PathType Leaf)){Deny 'READONLY_PREFLIGHT_SCRIPT_MISSING'}
  $recordText=(& powershell.exe -NoProfile -NonInteractive -File $readOnly |Out-String)
  if($LASTEXITCODE -ne 0){Deny 'READONLY_PREFLIGHT_EXECUTION_FAILED'}
  $record=$recordText|ConvertFrom-Json -ErrorAction Stop
  if($record.schema -ne 1 -or $record.preflight_passed -ne $true -or
    $record.check -cne 'HOST_SWAP_AND_ROLLBACK_PREFLIGHT' -or
    $record.checks.host_version -cne '4.5.1' -or
    $record.host_cutover_authorized -ne $false -or
    $record.task_mutations -ne 0 -or $record.java_operations -ne 0){
    Deny 'READONLY_PREFLIGHT_FAILED_OR_DRIFTED'
  }
 }
 $pd=$env:ProgramData
 if([string]::IsNullOrWhiteSpace($pd) -or -not [IO.Path]::IsPathRooted($pd)){Deny 'PROGRAMDATA'}
 $base=Join-Path $pd 'GeumyiServerCenter\VelocityManaged'
 $recover=Join-Path $base 'Recovery'
 $stage=Join-Path $base 'CanaryStaging'
 PrivateDir $base
 PrivateDir $recover
 PrivateDir $stage
 OwnersAbsent $recover
 VerifyProxyBaseline
 $receipt=Get-Content -LiteralPath (Join-Path $stage 'STAGING-RECEIPT.json') -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 if($receipt.schema -ne 1 -or $receipt.status -cne 'STAGED_NOT_INSTALLED'){Deny 'STAGING_RECEIPT_INVALID'}
 $candidate=Join-Path $stage $canaryName
 $backup=Join-Path $stage 'GeumyiServerHost-ORIGINAL.exe'
 if((Sha $candidate) -cne $receipt.canary_sha256 -or (Sha $backup) -cne $receipt.original_host_sha256){Deny 'STAGING_HASH_MISMATCH'}
 $svc=Service
 $launch=ParseService ([string]$svc.PathName)
 $config=$launch.config
 $port=ConfigPorts $config
 $originalVersion=$expectedOriginalVersion
 return [pscustomobject]@{stage=$stage;recover=$recover;candidate=$candidate
  backup=$backup;receipt=$receipt;service=$svc;launch=$launch
  config=$config;port=$port;originalVersion=$originalVersion
  journal=Join-Path $stage $journalName}
}
function SaveJournal($pre){
 if(Test-Path -LiteralPath $pre.journal){Deny 'JOURNAL_EXISTS'}
 $journal=[ordered]@{schema=1;original_command=[string]$pre.service.PathName
  original_binary=[string]$pre.launch.binary;config=[string]$pre.config
  original_sha256=[string]$pre.receipt.original_host_sha256
  canary_binary=[string]$pre.candidate
  canary_sha256=[string]$pre.receipt.canary_sha256
  created_utc=[DateTimeOffset]::UtcNow.ToString('o')}
 $file=[IO.File]::Open($pre.journal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{
  $bytes=New-Object Text.UTF8Encoding($false)
  $value=($journal|ConvertTo-Json -Compress -Depth 4)
  $data=$bytes.GetBytes($value)
  $file.Write($data,0,$data.Length)
  $file.Flush($true)
 }finally{$file.Dispose()}
 return $journal
}
function ReadJournal($pre){
 $j=Get-Content -LiteralPath $pre.journal -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 if($j.schema -ne 1 -or $j.canary_binary -cne $pre.candidate -or
    $j.canary_sha256 -cne $pre.receipt.canary_sha256 -or
    $j.original_sha256 -cne $pre.receipt.original_host_sha256 -or
    $j.config -cne $pre.config -or
    (Sha $pre.backup) -cne $j.original_sha256 -or
    (Sha $j.canary_binary) -cne $j.canary_sha256){Deny 'JOURNAL_INTEGRITY'}
 $parsed=ParseService ([string]$j.original_command)
 if($parsed.binary -cne [string]$j.original_binary -or
    $parsed.config -cne [string]$j.config -or
    (Sha ([string]$j.original_binary)) -cne $j.original_sha256){Deny 'ORIGINAL_SERVICE_FILE_CHANGED'}
 return $j
}
function Restore($pre,$j){
 OwnersAbsent $pre.recover
 $svc=Service
 if($svc.State -eq 'Running'){SvcStop}
 elseif($svc.State -ne 'Stopped'){Deny 'SERVICE_UNEXPECTED_STATE_ON_ROLLBACK'}
 ScSetBinary ([string]$j.original_binary) ([string]$j.config)
 SvcStart
 if(-not(Health $pre.port $expectedOriginalVersion 25)){Deny 'RESTORED_HOST_HEALTH_FAILED'}
 VerifyServiceBinary ([string]$j.original_binary)
 VerifyProxyBaseline
 OwnersAbsent $pre.recover
}
if($Mode -eq 'Synthetic'){
 $out=switch($SyntheticCase){
  'healthy' {'SYNTHETIC_CANARY_HEALTHY_NO_WINDOWS_SERVICE_TOUCHED'}
  'canary-start-fails' {'SYNTHETIC_AUTOROLLBACK_REQUIRED_NO_WINDOWS_SERVICE_TOUCHED'}
  'rollback-start-fails' {'SYNTHETIC_MANUAL_RECOVERY_REQUIRED_NO_WINDOWS_SERVICE_TOUCHED'}
 }
 Output $out $true 'A state-machine classification fixture only, not a real SCM test.'
 return
}
try{
 $pre=Preflight
 if($Mode -eq 'Plan'){
  if((Service).State -ne 'Running'){Deny 'SERVICE_NOT_RUNNING'}
  $live=Sha $pre.launch.binary
  if($live -cne $pre.receipt.original_host_sha256){Deny 'ORIGINAL_HASH_MISMATCH'}
  if(-not(Health $pre.port $expectedOriginalVersion 5)){Deny 'ORIGINAL_HOST_HEALTH_FAILED'}
  if(Test-Path -LiteralPath $pre.journal){Deny 'JOURNAL_ALREADY_PRESENT'}
  Output 'HOST_SWAP_PLAN_VERIFIED_NO_CHANGE' $true 'Canary, old Host, 3 legacy tasks and current service verified. No Windows service was modified.'
  return
 }
 if(-not $OperatorConfirmed){Deny 'EXPLICIT_CONFIRMATION_REQUIRED'}
 if($Mode -eq 'Apply'){
  if((Service).State -ne 'Running'){Deny 'SERVICE_NOT_RUNNING'}
  if([IO.Path]::GetFileName($pre.launch.binary) -ine 'GeumyiServerHost.exe'){Deny 'ALREADY_NOT_ORIGINAL_SERVICE_BINARY'}
  $live=Sha $pre.launch.binary
  if($live -cne $pre.receipt.original_host_sha256){Deny 'ORIGINAL_HASH_MISMATCH'}
  if(-not(Health $pre.port $expectedOriginalVersion 5)){Deny 'ORIGINAL_HOST_HEALTH_FAILED'}
  $j=SaveJournal $pre
  try{
   SvcStop
   ScSetBinary $pre.candidate $pre.config
   SvcStart
   if(-not(Health $pre.port $expectedCanaryVersion 25)){Deny 'CANARY_HEALTH_VERSION_FAILED'}
   VerifyServiceBinary $pre.candidate
   VerifyCanaryLocked $pre.config $pre.port
   OwnersAbsent $pre.recover
   VerifyProxyBaseline
   Output 'HOST_CANARY_ACTIVE_VERIFIED' $true 'Canary 4.5.2 service passed health and old proxy tasks remain Running. Journal retained for rollback.'
   return
  }catch{
   try{
    Restore $pre $j
    Output 'HOST_CANARY_AUTO_ROLLBACK_VERIFIED' $false 'Canary activation failed, original GSC 4.5.1 service restored and healthy.'
    exit 3
   }catch{
    Output 'HOST_CANARY_MANUAL_RECOVERY_REQUIRED' $false 'Automatic rollback unverified. Protected journal and original Host executable retained. DO NOT restart or kill Java/Velocity.'
    exit 4
   }
  }
 }
 if($Mode -eq 'Rollback'){
  $j=ReadJournal $pre
  if($pre.launch.binary -ine $pre.candidate -and $pre.launch.binary -ine [string]$j.original_binary){Deny 'SERVICE_ALREADY_POINTS_TO_OTHER_BINARY'}
  Restore $pre $j
  Output 'HOST_ORIGINAL_RESTORED_VERIFIED' $true 'Existing GSC 4.5.1 service verified healthy. Canary staging and recovery journal preserved.'
  return
 }
}catch{
 # Never include raw exception text: SCM may reveal private command paths.
 Output 'HOST_SWAP_BLOCKED_OR_UNCONFIRMED' $false 'Safety gate failed. No further actions allowed; examine private operator-local evidence.'
 exit 2
}
