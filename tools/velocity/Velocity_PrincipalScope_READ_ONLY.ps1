#requires -Version 5.1
[CmdletBinding()]
param([switch]$Synthetic)

# GSC v4.5.2 Canary: NO credentials, SID, usernames, process IDs, task XML,
# paths or keys in output. NO privilege elevation, DPAPI calls, task mutation,
# client login, event-log enabling, server process control or firewall changes.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$targets=@(
 [pscustomobject]@{id='wild';task='Geumyi Day10 Velocity wild';udp=19132},
 [pscustomobject]@{id='playground';task='Geumyi Day10 Velocity playground';udp=19133},
 [pscustomobject]@{id='other';task='Geumyi Day10 Velocity other';udp=19134}
)
$report=[ordered]@{
 schema=1
 kind='GEUMYI_GSC_452_VELOCITY_WINDOWS_PRINCIPAL_SCOPE_READ_ONLY'
 collected_at_utc=[DateTimeOffset]::UtcNow.ToString('o')
 synthetic=[bool]$Synthetic
 read_only=$true
 server_state_changed=$false
 task_state_modified=$false
 acl_modified=$false
 audit_log_settings_changed=$false
 dpapi_access_attempted=$false
 privilege_elevation_attempted=$false
 source_authenticated=$false
 live_control_authorized=$false
 collector_account_kind='UNKNOWN'
 result='PRINCIPAL_SCOPE_EVIDENCE_INCOMPLETE_NO_GO'
 instances=@()
}
function New-Finding([string]$id){
 return [ordered]@{
  id=$id
  task_running=$false
  task_principal_resolved=$false
  udp_java_owner_resolved=$false
  java_parent_and_child_same_owner='UNKNOWN'
  task_principal_vs_udp_java_owner='UNKNOWN'
  task_principal_vs_collector='UNKNOWN'
  udp_java_owner_vs_collector='UNKNOWN'
  reliable_task_to_jvm_identity_verified=$false
  dpapi_cross_process_compatibility_verified=$false
  live_control_authorized=$false
  result='PRINCIPAL_COMPARISON_INCOMPLETE_NO_GO'
 }
}
function Compare-Sids([string]$left,[string]$right){
 if([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)){
  return 'UNKNOWN'
 }
 return $(if($left -ceq $right){'MATCH'}else{'DIFFERENT'})
}
function Resolve-IdentitySID([string]$identity){
 if([string]::IsNullOrWhiteSpace($identity)){return ''}
 try {
  if($identity -match '^S-1-(?:[0-9]+-)+[0-9]+$') {
   $sid=New-Object System.Security.Principal.SecurityIdentifier($identity)
   return [string]$sid.Value
  }
  $account=New-Object System.Security.Principal.NTAccount($identity)
  return [string]$account.Translate([System.Security.Principal.SecurityIdentifier]).Value
 }catch{return ''}
}
function Process-OwnerSID($item){
 if($null -eq $item){return ''}
 try{
  $answer=Invoke-CimMethod -InputObject $item -MethodName GetOwnerSid -ErrorAction Stop
  if($null -ne $answer -and [int]$answer.ReturnValue -eq 0 -and
     -not [string]::IsNullOrWhiteSpace([string]$answer.Sid)){
   return [string]$answer.Sid
  }
 }catch{}
 return ''
}
if($Synthetic){
 $report.collector_account_kind='USER_OR_OTHER'
 foreach($t in $targets){
  $x=New-Finding $t.id
  $x.task_running=$true
  $x.task_principal_resolved=$true
  $x.udp_java_owner_resolved=$true
  $x.java_parent_and_child_same_owner='MATCH'
  $x.task_principal_vs_udp_java_owner='MATCH'
  $x.task_principal_vs_collector='MATCH'
  $x.udp_java_owner_vs_collector='MATCH'
  $x.result='SYNTHETIC_RELATIONSHIPS_NEVER_OS_AUTHENTICATED'
  $report.instances+=$x
 }
 $report.result='SYNTHETIC_SCHEMA_ONLY_NO_GO'
 $report|ConvertTo-Json -Compress -Depth 7
 exit 0
}
$collectorSid=''
try{
 $identity=[System.Security.Principal.WindowsIdentity]::GetCurrent()
 if($null -ne $identity -and $null -ne $identity.User){
  $collectorSid=[string]$identity.User.Value
  $report.collector_account_kind=if($collectorSid -eq 'S-1-5-18'){'SYSTEM'}elseif(
   $collectorSid -in @('S-1-5-19','S-1-5-20') -or
   $collectorSid -like 'S-1-5-80-*'){'SERVICE'}else{'USER_OR_OTHER'}
 }
}catch{$collectorSid=''}
$processes=@()
$udpRows=@()
try{$processes=@(Get-CimInstance Win32_Process -ErrorAction Stop)}catch{$processes=@()}
try{$udpRows=@(Get-NetUDPEndpoint -ErrorAction Stop)}catch{$udpRows=@()}
$allResolved=$true
foreach($t in $targets){
 $x=New-Finding $t.id
 $taskSID=''
 try{
  $tasks=@(Get-ScheduledTask -TaskName $t.task -TaskPath '\' -ErrorAction Stop)
  if($tasks.Count -eq 1){
   $x.task_running=[string]$tasks[0].State -eq 'Running'
   $taskSID=Resolve-IdentitySID ([string]$tasks[0].Principal.UserId)
   $x.task_principal_resolved=-not [string]::IsNullOrWhiteSpace($taskSID)
  }
 }catch{}
 $javaChildSID=''
 $javaParentSID=''
 try{
  $ownerPids=@($udpRows|Where-Object {[int]$_.LocalPort -eq $t.udp}|
   ForEach-Object {[int]$_.OwningProcess}|Select-Object -Unique)
  if($ownerPids.Count -eq 1 -and $ownerPids[0] -gt 0){
   $javaChildren=@($processes|Where-Object {
    [int]$_.ProcessId -eq $ownerPids[0] -and
    [string]$_.Name -in @('java.exe','javaw.exe')
   })
   if($javaChildren.Count -eq 1){
    $javaParents=@($processes|Where-Object {
     [int]$_.ProcessId -eq [int]$javaChildren[0].ParentProcessId -and
     [string]$_.Name -in @('java.exe','javaw.exe')
    })
    if($javaParents.Count -eq 1){
     if([datetime]$javaParents[0].CreationDate -le
        [datetime]$javaChildren[0].CreationDate){
      $javaChildSID=Process-OwnerSID $javaChildren[0]
      $javaParentSID=Process-OwnerSID $javaParents[0]
     }
    }
   }
  }
 }catch{}
 $x.udp_java_owner_resolved=-not [string]::IsNullOrWhiteSpace($javaChildSID)
 $x.java_parent_and_child_same_owner=Compare-Sids $javaParentSID $javaChildSID
 $x.task_principal_vs_udp_java_owner=Compare-Sids $taskSID $javaChildSID
 $x.task_principal_vs_collector=Compare-Sids $taskSID $collectorSid
 $x.udp_java_owner_vs_collector=Compare-Sids $javaChildSID $collectorSid
 if(-not $x.task_running -or -not $x.task_principal_resolved -or
    -not $x.udp_java_owner_resolved -or
    $x.java_parent_and_child_same_owner -eq 'UNKNOWN'){
  $allResolved=$false
  $x.result='PRINCIPAL_COMPARISON_INCOMPLETE_NO_GO'
 }else{
  $x.result='PRINCIPAL_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED'
 }
 # Even same-account hints do NOT prove same GSC host runtime principal,
 # Windows DACL policy, Java executable authenticity or shared DPAPI key.
 $report.instances+=$x
}
if($allResolved){
 $report.result='THREE_PRINCIPAL_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED'
}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if([string]::IsNullOrWhiteSpace($desktop) -or
   -not (Test-Path -LiteralPath $desktop -PathType Container)){
 Write-Host 'Desktop unavailable; no server or security settings changed.'
 exit 2
}
$dir=Join-Path $desktop 'Geumyi-Velocity-ReadOnly-Reports'
[void](New-Item -ItemType Directory -Path $dir -Force)
$file=Join-Path $dir ('Velocity-PrincipalScope-READ-ONLY-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
[IO.File]::WriteAllText($file,($report|ConvertTo-Json -Depth 7),
 (New-Object Text.UTF8Encoding($false)))
Write-Host ('READ ONLY result: '+$report.result)
Write-Host ('Sanitized report: '+$file)
Write-Host 'Share ONLY this JSON; never export raw SIDs, usernames, task XML, keys or commands.'
