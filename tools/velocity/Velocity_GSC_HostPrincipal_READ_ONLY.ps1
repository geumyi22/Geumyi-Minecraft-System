#requires -Version 5.1
[CmdletBinding()]
param(
 [switch]$Synthetic,
 [ValidateSet('HostDifferent','HostSame','NoHost','MultipleHosts')]
 [string]$SyntheticCase='HostDifferent'
)
# Source of the exact installed GSC host binary name: GSC/ServerCenter/build.ps1
# Only GeumyiServerHost.exe, NOT the interactive GeumyiServerCenter.exe client.
# No account/SID, user name, PID, path, task XML, secret or process command line
# is emitted. This IS NOT a cryptographic executable identity or service proof.
# No task, process, server, DPAPI, ACL, event log or privilege mutation.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $Synthetic -and $SyntheticCase -ne 'HostDifferent'){
 throw 'SyntheticCase requires -Synthetic'
}
$targets=@(
 [pscustomobject]@{id='wild';task='Geumyi Day10 Velocity wild'},
 [pscustomobject]@{id='playground';task='Geumyi Day10 Velocity playground'},
 [pscustomobject]@{id='other';task='Geumyi Day10 Velocity other'}
)
function New-Finding([string]$id){
 return [ordered]@{
  id=$id
  task_running=$false
  task_principal_resolved=$false
  host_vs_task_principal='UNKNOWN'
  trusted_process_identity_verified=$false
  dpapi_compatible=$false
  live_control_authorized=$false
  result='GSC_HOST_PRINCIPAL_UNVERIFIED_NO_GO'
 }
}
function Compare-SIDs([string]$a,[string]$b){
 if([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)){
  return 'UNKNOWN'
 }
 if($a -ceq $b){return 'MATCH'}
 return 'DIFFERENT'
}
function Resolve-AccountSID([string]$name){
 if([string]::IsNullOrWhiteSpace($name)){return ''}
 try {
  if($name -match '^S-1-(?:[0-9]+-)+[0-9]+$'){
   return [string]([System.Security.Principal.SecurityIdentifier]::new($name)).Value
  }
  $account=[System.Security.Principal.NTAccount]::new($name)
  return [string]$account.Translate([System.Security.Principal.SecurityIdentifier]).Value
 }catch{return ''}
}
function OwnerSID($process){
 if($null -eq $process){return ''}
 try {
  $r=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
  if($null -ne $r -and [int]$r.ReturnValue -eq 0 -and
     -not [string]::IsNullOrWhiteSpace([string]$r.Sid)){
   return [string]$r.Sid
  }
 }catch{}
 return ''
}
$report=[ordered]@{
 schema=1
 kind='GEUMYI_GSC_452_HOST_RUNTIME_PRINCIPAL_READ_ONLY'
 collected_at_utc=[DateTimeOffset]::UtcNow.ToString('o')
 synthetic=[bool]$Synthetic
 read_only=$true
 server_state_changed=$false
 task_state_modified=$false
 acl_modified=$false
 dpapi_access_attempted=$false
 event_log_settings_changed=$false
 privilege_elevation_attempted=$false
 source_authenticated=$false
 host_executable_identity_verified=$false
 gsc_service_runtime_attested=$false
 live_control_authorized=$false
 collector_vs_host='UNKNOWN'
 gsc_host_process_count_category='UNKNOWN'
 result='GSC_HOST_PRINCIPAL_SCOPE_UNVERIFIED_NO_GO'
 instances=@()
}
if($Synthetic){
 $category=if($SyntheticCase -eq 'NoHost'){'NONE'}elseif($SyntheticCase -eq 'MultipleHosts'){'MULTIPLE'}else{'ONE'}
 $report.gsc_host_process_count_category=$category
 $match=if($SyntheticCase -eq 'HostSame'){'MATCH'}elseif($SyntheticCase -eq 'HostDifferent'){'DIFFERENT'}else{'UNKNOWN'}
 $report.collector_vs_host=$match
 foreach($t in $targets){
  $entry=New-Finding $t.id
  $entry.task_running=$true
  $entry.task_principal_resolved=$true
  $entry.host_vs_task_principal=$match
  $entry.result='SYNTHETIC_HOST_RELATIONSHIP_NEVER_AUTHENTICATED'
  $report.instances+=$entry
 }
 $report.result='SYNTHETIC_HOST_SCHEMA_NO_GO'
 $report|ConvertTo-Json -Compress -Depth 7
 exit 0
}
$collectorSID=''
try{
 $identity=[System.Security.Principal.WindowsIdentity]::GetCurrent()
 if($null -ne $identity -and $null -ne $identity.User){
  $collectorSID=[string]$identity.User.Value
 }
}catch{$collectorSID=''}
$hostSID=''
try{
 $hosts=@(Get-CimInstance Win32_Process -Filter "Name = 'GeumyiServerHost.exe'" -ErrorAction Stop)
 $report.gsc_host_process_count_category=if($hosts.Count -eq 0){'NONE'}elseif($hosts.Count -eq 1){'ONE'}else{'MULTIPLE'}
 if($hosts.Count -eq 1){$hostSID=OwnerSID $hosts[0]}
}catch{$report.gsc_host_process_count_category='UNKNOWN'}
$report.collector_vs_host=Compare-SIDs $collectorSID $hostSID
$fullyResolved=($report.gsc_host_process_count_category -eq 'ONE' -and
 -not [string]::IsNullOrWhiteSpace($hostSID))
foreach($t in $targets){
 $entry=New-Finding $t.id
 try{
  $tasks=@(Get-ScheduledTask -TaskName $t.task -TaskPath '\' -ErrorAction Stop)
  if($tasks.Count -eq 1){
   $entry.task_running=[string]$tasks[0].State -eq 'Running'
   $taskSID=Resolve-AccountSID ([string]$tasks[0].Principal.UserId)
   $entry.task_principal_resolved=-not [string]::IsNullOrWhiteSpace($taskSID)
   $entry.host_vs_task_principal=Compare-SIDs $hostSID $taskSID
  }
 }catch{}
 if(-not $entry.task_running -or -not $entry.task_principal_resolved -or
    $entry.host_vs_task_principal -eq 'UNKNOWN'){
  $fullyResolved=$false
 }
 $entry.result=if($entry.host_vs_task_principal -eq 'UNKNOWN'){
  'GSC_HOST_PRINCIPAL_UNVERIFIED_NO_GO'
 }else{'GSC_HOST_TASK_ACCOUNT_RELATIONSHIP_ONLY_NO_GO'}
 $report.instances+=$entry
}
if($fullyResolved){$report.result='GSC_HOST_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED'}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if([string]::IsNullOrWhiteSpace($desktop) -or
 -not (Test-Path -LiteralPath $desktop -PathType Container)){
 Write-Host 'Desktop is not available. NO settings were modified.'
 exit 2
}
$dir=Join-Path $desktop 'Geumyi-Velocity-ReadOnly-Reports'
[void](New-Item -ItemType Directory -Force -Path $dir)
$file=Join-Path $dir ('Velocity-GSC-HostPrincipal-READ-ONLY-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
[IO.File]::WriteAllText($file,($report|ConvertTo-Json -Depth 7),
 (New-Object Text.UTF8Encoding($false)))
Write-Host ('READ ONLY result: '+$report.result)
Write-Host ('Sanitized report: '+$file)
Write-Host 'Share ONLY JSON. No usernames, process IDs, SIDs, paths, keys or tasks exported.'
