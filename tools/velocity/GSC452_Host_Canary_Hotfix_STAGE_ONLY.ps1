#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
 [ValidateSet('Plan','Stage')][string]$Mode='Plan',
 [ValidateSet('none','candidate-identical','existing-hotfix','bad-optin','backend-offline')]
 [string]$SyntheticScenario='none'
)
# Canary -> Canary HOTFIX preparation ONLY. Cannot stop/start the GSC Host,
# touch Scheduler tasks, spawn/kill JVMs, change service binPath/Environment,
# overwrite the original Canary or mutate a world/Paper configuration.
# The original 4.5.1 -> Canary swap kit is NOT valid for this operation.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$service='Geumyi Server Center Host'
$exeName='GeumyiServerHost-v4.5.2-Velocity-CANARY.exe'
$optFlag='GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN=DIRECT_OWNERSHIP_APPROVED'
$root=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged'
$recovery=Join-Path $root 'Recovery'
$oldStage=Join-Path $root 'CanaryStaging'
$newStage=Join-Path $root 'CanaryHotfix-R2-20261025'
$source=Join-Path $PSScriptRoot $exeName
$sums=Join-Path $PSScriptRoot 'SHA256SUMS.txt'
function Deny([string]$code){throw ('HOTFIX_STAGE_NO_GO_'+$code)}
function PrintResult([string]$code,[bool]$pass,[bool]$synthetic=$false){
 [ordered]@{
  schema=1;check='GSC452_CANARY_TO_CANARY_HOTFIX_PREP'
  mode=$Mode;synthetic=$synthetic;success=$pass;status=$code
  read_only=($Mode -eq 'Plan' -or $synthetic)
  service_operations=0;service_environment_changes=0
  scheduler_operations=0;jvm_operations=0;paper_operations=0;world_operations=0
  existing_staging_overwritten=$false
  live_hotfix_applied=$false
 }|ConvertTo-Json -Compress
}
function TrustDir([string]$path,[bool]$allowTrustedInherit=$false){
 $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
 if(-not $file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  Deny 'STAGING_DIRECTORY_NOT_REGULAR'
 }
 $acl=Get-Acl -LiteralPath $path -ErrorAction Stop
 if(-not $acl.AreAccessRulesProtected -and -not $allowTrustedInherit){
  Deny 'UNTRUSTED_INHERITED_DIRECTORY_ACL'
 }
 foreach($ace in $acl.Access){
  if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow){
   $sid=$ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
   if($sid -notin @('S-1-5-18','S-1-5-32-544')){
    Deny 'UNTRUSTED_DIRECTORY_PRINCIPAL'
   }
  }
 }
}
function SafeHash([string]$path){
 $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  Deny 'HASH_SOURCE_NOT_REGULAR'
 }
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function SafeJSON([string]$path){
 $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
    $item.Length -gt 1048576 -or $item.Length -lt 3){Deny 'PRIVATE_RECORD_INVALID'}
 return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
   ConvertFrom-Json -ErrorAction Stop)
}
function CheckFleet(){
 foreach($target in @('wild','playground','other')){
  $task=Get-ScheduledTask -TaskPath '\' -TaskName ('Geumyi Day10 Velocity '+$target) -ErrorAction Stop
  if([string]$task.State -cne 'Running' -or $task.Settings.Enabled -ne $true){
   Deny 'LEGACY_PROXY_NOT_RUNNING'
  }
  if(Test-Path -LiteralPath (Join-Path $recovery ($target+'.active.json'))){
   Deny 'GSC_PROXY_OWNER_PRESENT'
  }
  $receipt=SafeJSON (Join-Path $recovery ($target+'.receipt.json'))
  if($receipt.schema -ne 1 -or $receipt.target -cne $target -or
     $receipt.cutover_committed -ne $false){
   Deny 'LEGACY_CUTOVER_RECEIPT_UNVERIFIED'
  }
  if(-not(Test-Path -LiteralPath (Join-Path $recovery ($target+'.original.xml')) -PathType Leaf)){
   Deny 'LEGACY_SNAPSHOT_MISSING'
  }
 }
}
function CheckBackend([int]$port){
 if($port -lt 1 -or $port -gt 65535){Deny 'BAD_BACKEND_PORT'}
 $client=New-Object Net.Sockets.TcpClient
 try{
  $async=$client.BeginConnect('127.0.0.1',$port,$null,$null)
  if(-not $async.AsyncWaitHandle.WaitOne(1200)){Deny 'AUTOSTART_BACKEND_NOT_RESPONDING'}
  $client.EndConnect($async)
 }catch{Deny 'AUTOSTART_BACKEND_NOT_RESPONDING'}finally{$client.Close()}
}
function CheckSource(){
 if(-not(Test-Path -LiteralPath $source -PathType Leaf) -or
    -not(Test-Path -LiteralPath $sums -PathType Leaf)){Deny 'OFFICIAL_ARTIFACT_AND_SHA256SUMS_REQUIRED'}
 $expected=@(Get-Content -LiteralPath $sums -ErrorAction Stop |
  Where-Object {$_ -cmatch ('^[a-f0-9]{64}  '+[regex]::Escape($exeName)+'$')})
 if($expected.Count -ne 1){Deny 'UNIQUE_SHA256_SUM_MISSING'}
 $actual=SafeHash $source
 if($actual -cne $expected[0].Substring(0,64)){Deny 'ARTIFACT_SHA256_MISMATCH'}
 return $actual
}
function Inspect(){
 TrustDir $root
 TrustDir $recovery
 TrustDir $oldStage $true
 if(Test-Path -LiteralPath $newStage){
  Deny 'HOTFIX_DIRECTORY_ALREADY_PRESENT_NO_OVERWRITE'
 }
 CheckFleet
 $reg='HKLM:\SYSTEM\CurrentControlSet\Services\'+$service
 $key=Get-Item -LiteralPath $reg -ErrorAction Stop
 if(@($key.GetValueNames()) -notcontains 'Environment' -or
    $key.GetValueKind('Environment') -ne [Microsoft.Win32.RegistryValueKind]::MultiString){
  Deny 'SERVICE_ONLY_OPTIN_NOT_MULTISTRING'
 }
 $items=@($key.GetValue('Environment',$null,
  [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))
 $values=@($items|Where-Object {$_ -match '(?i)^GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN='})
 if($values.Count -ne 1 -or $values[0] -cne $optFlag){
  Deny 'SERVICE_ONLY_OPTIN_NOT_EXACT'
 }
 if([Environment]::GetEnvironmentVariable('GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN','Machine') -ne $null){
  Deny 'UNEXPECTED_GLOBAL_ENVIRONMENT_FLAG'
 }
 $optRecord=SafeJSON (Join-Path $recovery 'host-optin-original-service-env.json')
 if($optRecord.schema -ne 1 -or $optRecord.service -cne $service){
  Deny 'ORIGINAL_OPTIN_RECOVERY_JOURNAL_UNVERIFIED'
 }
 $svc=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
 if($null -eq $svc -or $svc.State -cne 'Running' -or
    $svc.StartName -notin @('LocalSystem','NT AUTHORITY\SYSTEM') -or
    [int]$svc.ProcessId -le 4){Deny 'ACTIVE_CANARY_HOST_NOT_VERIFIED'}
 $m=[regex]::Match([string]$svc.PathName,
  '(?i)^\s*"([^"]+\\GeumyiServerHost-v4\.5\.2-Velocity-CANARY\.exe)"\s+--service\s+--config\s+"([^"]+)"\s*$')
 if(-not $m.Success){Deny 'RUNNING_CANARY_SERVICE_COMMAND_UNVERIFIED'}
 $current=$m.Groups[1].Value
 $cfgPath=$m.Groups[2].Value
 $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$svc.ProcessId) -ErrorAction Stop
 if($null -eq $proc -or [string]::IsNullOrWhiteSpace([string]$proc.ExecutablePath) -or
    [IO.Path]::GetFullPath([string]$proc.ExecutablePath) -ine
    [IO.Path]::GetFullPath($current)){Deny 'CANARY_SERVICE_PROCESS_IDENTITY_DRIFT'}
 $oldReceipt=SafeJSON (Join-Path $oldStage 'STAGING-RECEIPT.json')
 if($oldReceipt.schema -ne 1 -or $oldReceipt.status -cne 'STAGED_NOT_INSTALLED' -or
    (SafeHash $current) -cne [string]$oldReceipt.canary_sha256){
  Deny 'EXISTING_CANARY_HASH_OR_RECEIPT_DRIFT'
 }
 $swap=SafeJSON (Join-Path $oldStage 'HOST-SWAP-PRIVATE-JOURNAL.json')
 if($swap.schema -ne 1 -or [string]$swap.canary_binary -ine $current -or
    [string]$swap.canary_sha256 -cne [string]$oldReceipt.canary_sha256){
  Deny 'ORIGINAL_HOST_SWAP_JOURNAL_DRIFT'
 }
 $cfg=SafeJSON $cfgPath
 $apiPort=[int]$cfg.port
 if($apiPort -ne 8787){Deny 'UNEXPECTED_HOST_LOCAL_API_PORT'}
 foreach($backend in @($cfg.servers)){
  if($backend.auto_start -eq $true){CheckBackend ([int]$backend.java_port)}
 }
 $h=Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:8787/api/health' -TimeoutSec 4 -ErrorAction Stop
 if($h.ok -ne $true -or $h.service -ne $true -or
    [string]$h.version -cne '4.5.2-canary'){
  Deny 'OLD_CANARY_API_UNHEALTHY'
 }
 # Canary GET is read-only, may require up to 15s of Scheduler observation.
 $status=Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:8787/api/v1/velocity/managed/status' -TimeoutSec 25 -ErrorAction Stop
 if($status.ok -ne $true -or $status.canary_enabled -ne $true -or
    $status.read_only -ne $true -or @($status.tasks).Count -ne 3){
  Deny 'ACTIVE_MANAGED_OPTIN_API_UNVERIFIED'
 }
 $newHash=CheckSource
 if($newHash -ceq [string]$oldReceipt.canary_sha256){
  Deny 'NEW_ARTIFACT_IDENTICAL_TO_OLD_CANARY'
 }
 return [pscustomobject]@{newHash=$newHash;oldHash=[string]$oldReceipt.canary_sha256}
}
if($SyntheticScenario -ne 'none'){
 $code=switch($SyntheticScenario){
  'candidate-identical' {'HOTFIX_STAGE_NO_GO_NEW_ARTIFACT_IDENTICAL_TO_OLD_CANARY'}
  'existing-hotfix' {'HOTFIX_STAGE_NO_GO_HOTFIX_DIRECTORY_ALREADY_PRESENT_NO_OVERWRITE'}
  'bad-optin' {'HOTFIX_STAGE_NO_GO_SERVICE_ONLY_OPTIN_NOT_EXACT'}
  'backend-offline' {'HOTFIX_STAGE_NO_GO_AUTOSTART_BACKEND_NOT_RESPONDING'}
 }
 if($code){
  PrintResult $code $false $true
 }else{
  PrintResult 'CI_SYNTHETIC_PREFLIGHT_ONLY_NO_WINDOWS_MUTATIONS' $true $true
 }
 return
}
try{
 Import-Module ScheduledTasks -ErrorAction Stop
 $record=Inspect
 if($Mode -eq 'Plan'){
  PrintResult 'CANARY_TO_CANARY_HOTFIX_PREP_PLAN_PASS_NO_CHANGES' $true
  return
 }
 # Stage requires the operator to type consent, but NEVER restarts anything.
 $typed=Read-Host 'Type STAGE HOST HOTFIX ONLY (no restart or Velocity cutover)'
 if($typed -cne 'STAGE HOST HOTFIX ONLY'){Deny 'STAGING_OPERATOR_CONSENT_REQUIRED'}
 # Private root already ACL-protected; new staging inherits SYSTEM+Admins.
 [void](New-Item -Path $newStage -ItemType Directory -ErrorAction Stop)
 TrustDir $newStage $true
 Copy-Item -LiteralPath $source -Destination (Join-Path $newStage $exeName) -ErrorAction Stop
 Copy-Item -LiteralPath $sums -Destination (Join-Path $newStage 'SHA256SUMS.txt') -ErrorAction Stop
 if((SafeHash (Join-Path $newStage $exeName)) -cne $record.newHash){
  Deny 'STAGED_HOTFIX_ARTIFACT_INTEGRITY_UNVERIFIED'
 }
 $receipt=[ordered]@{
  schema=1;status='HOST_CANARY_HOTFIX_STAGED_NO_INSTALL'
  previous_canary_sha256=$record.oldHash
  new_canary_sha256=$record.newHash
  service_unchanged=$true;service_optin_unchanged=$true;task_operations=0
  created_utc=[DateTimeOffset]::UtcNow.ToString('o')
 }
 $destination=Join-Path $newStage 'HOTFIX-STAGE-RECEIPT.json'
 $stream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,
  [IO.FileAccess]::Write,[IO.FileShare]::None)
 try{
  $bytes=[Text.Encoding]::UTF8.GetBytes(($receipt|ConvertTo-Json -Compress -Depth 5))
  $stream.Write($bytes,0,$bytes.Length)
  $stream.Flush($true)
 }finally{$stream.Dispose()}
 PrintResult 'CANARY_TO_CANARY_HOTFIX_STAGED_NO_INSTALL' $true
}catch{
 # Preserve any partial immutable staging for manual review. NEVER silently
 # delete/retry or overwrite the prior Host swap/opt-in recovery journals.
 PrintResult 'CANARY_TO_CANARY_HOTFIX_BLOCKED_NO_LIVE_SERVICE_MUTATION' $false
 exit 2
}
