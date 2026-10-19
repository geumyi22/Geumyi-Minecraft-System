#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Preflight','Snapshot','Cutover','Rollback')]
    [string]$Mode='Preflight',
    [Parameter(Mandatory=$true)]
    [ValidateSet('wild','playground','other')]
    [string]$Target,
    [string]$Ticket='',
    [switch]$Approved,
    [switch]$Synthetic,
    [ValidateSet('Running','Ready','Disabled','Queued','Missing')]
    [string]$SyntheticState='Running'
)
# Cutover is an EXPLICIT operator-maintenance action, never automatic.
# Default read-only. No process Stop/kill, JVM commands, elevation, event logs,
# firewall/ACL updates to an existing task, or game/world modifications.
# The original task XML is retained locally, NOT exported for sharing.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$taskNames=@{
    wild='Geumyi Day10 Velocity wild'
    playground='Geumyi Day10 Velocity playground'
    other='Geumyi Day10 Velocity other'
}
$expectedPorts=@{
    wild=@(25565,19132)
    playground=@(25566,19133)
    other=@(25567,19134)
}
function Deny([string]$why){throw "CUTOVER_NO_GO: $why"}
function IsAdministrator {
 try {
  $principal=[Security.Principal.WindowsPrincipal]::new(
     [Security.Principal.WindowsIdentity]::GetCurrent())
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 }catch{return $false}
}
function PortsFree([string]$target){
 $pair=$expectedPorts[$target]
 $listener=$null
 $udp=$null
 try {
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Any,[int]$pair[0])
  $listener.Start()
  $listener.Stop()
  $udp=[Net.Sockets.UdpClient]::new([int]$pair[1])
  $udp.Close()
  return $true
 }catch{
  if($null -ne $listener){try{$listener.Stop()}catch{}}
  if($null -ne $udp){try{$udp.Close()}catch{}}
  return $false
 }
}
function TaskState([string]$target){
 $t=Get-ScheduledTask -TaskPath '\' -TaskName $taskNames[$target] -ErrorAction Stop
 if($null -eq $t){Deny 'TASK_MISSING'}
 return [string]$t.State
}
function GetTaskXml([string]$target){
 return [string](Export-ScheduledTask -TaskName $taskNames[$target] -TaskPath '\' -ErrorAction Stop)
}
function HashText([string]$value){
 $bytes=[Text.Encoding]::Unicode.GetBytes($value)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
 finally{$sha.Dispose();[Array]::Clear($bytes,0,$bytes.Length)}
}
# Scheduler changes Settings/Enabled when disabling a task. Compare every
# other canonical XML node to catch drift, without treating the intended
# enable/disable flip as a definition mutation.
function TaskDefinitionDigest([string]$text){
 $xml=[xml]$text
 $enabled=$xml.SelectSingleNode("//*[local-name()='Settings']/*[local-name()='Enabled']")
 if($null -ne $enabled){[void]$enabled.ParentNode.RemoveChild($enabled)}
 return HashText $xml.OuterXml
}
function AssertTaskShape([string]$target,[string]$xml){
 $root=[xml]$xml
 $actions=@($root.SelectNodes("//*[local-name()='Actions']/*"))
 if($actions.Count -ne 1 -or $actions[0].LocalName -ne 'Exec'){
  Deny 'UNEXPECTED_TASK_ACTIONS'
 }
 $cmd=$root.SelectSingleNode("//*[local-name()='Actions']/*[local-name()='Exec']/*[local-name()='Command']")
 $args=$root.SelectSingleNode("//*[local-name()='Actions']/*[local-name()='Exec']/*[local-name()='Arguments']")
 $dir=$root.SelectSingleNode("//*[local-name()='Actions']/*[local-name()='Exec']/*[local-name()='WorkingDirectory']")
 if($null -eq $cmd -or $null -eq $args -or $null -eq $dir -or
    $cmd.InnerText -notmatch '(?i)\\java\.exe$' -or
    $args.InnerText -notmatch '(?i)(?:^|\s)-jar\s+"?velocity\.jar"?(?:\s|$)' -or
    $dir.InnerText -notmatch ('(?i)\\GeumyiServerCenter\\Network\\FourServer\\'+$target+'$')){
  Deny 'TASK_COMMAND_OR_DIRECTORY_MISMATCH'
 }
 $count=$root.SelectSingleNode("//*[local-name()='RestartOnFailure']/*[local-name()='Count']")
 $instances=$root.SelectSingleNode("//*[local-name()='MultipleInstancesPolicy']")
 if($null -eq $count -or [string]$count.InnerText -ne '999' -or
    $null -eq $instances -or [string]$instances.InnerText -ne 'IgnoreNew'){
   Deny 'TASK_POLICY_DRIFT'
 }
}
function PrivateFolder {
 $pd=$env:ProgramData
 if([string]::IsNullOrWhiteSpace($pd) -or -not [IO.Path]::IsPathRooted($pd)){
  Deny 'PROGRAMDATA_UNAVAILABLE'
 }
 return Join-Path $pd 'GeumyiServerCenter\VelocityManaged\Recovery'
}
function AssertPrivateFolder([string]$folder){
 if(-not (Test-Path -LiteralPath $folder -PathType Container)){
  Deny 'NO_PRIVATE_RECOVERY_DIRECTORY'
 }
 # Fail closed if full inherited ACEs are allowed. Configurable explicit
 # SYSTEM+Administrators rights, with no Everyone/Users/Authenticated Users.
 $acl=Get-Acl -LiteralPath $folder
 if(-not $acl.AreAccessRulesProtected){Deny 'RECOVERY_DIRECTORY_INHERITS_ACL'}
 foreach($ace in $acl.Access){
  $sid=''
  try{$sid=([Security.Principal.NTAccount]::new(
       [string]$ace.IdentityReference)).Translate(
       [Security.Principal.SecurityIdentifier]).Value}catch{
   $sid=[string]$ace.IdentityReference
  }
  if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
     $sid -notin @('S-1-5-18','S-1-5-32-544')){
    Deny 'RECOVERY_DIRECTORY_BROAD_OR_UNKNOWN_ACL'
  }
 }
}
function MakePrivateFolder([string]$folder){
 if(Test-Path -LiteralPath $folder){AssertPrivateFolder $folder;return}
 # Only inside the fixed ProgramData directory. No existing ACL is edited.
 [void](New-Item -ItemType Directory -Path $folder -Force)
 $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
 $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @($system,$admins)){
  $rule=[Security.AccessControl.FileSystemAccessRule]::new(
   $sid,[Security.AccessControl.FileSystemRights]::FullControl,
   [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
   [Security.AccessControl.PropagationFlags]::None,
   [Security.AccessControl.AccessControlType]::Allow)
  $acl.AddAccessRule($rule)
 }
 Set-Acl -LiteralPath $folder -AclObject $acl
 AssertPrivateFolder $folder
}
function ReceiptPaths([string]$target){
 $folder=PrivateFolder
 return [pscustomobject]@{
  Dir=$folder
  Original=Join-Path $folder ($target+'.original.xml')
  Receipt=Join-Path $folder ($target+'.receipt.json')
 }
}
function VerifyBackup($paths,[string]$target){
 AssertPrivateFolder $paths.Dir
 foreach($file in @($paths.Original,$paths.Receipt)){
  if(-not (Test-Path -LiteralPath $file -PathType Leaf)){Deny 'SNAPSHOT_INCOMPLETE'}
 }
 $xml=[IO.File]::ReadAllText($paths.Original)
 $receipt=[IO.File]::ReadAllText($paths.Receipt)|ConvertFrom-Json
 if($receipt.schema -ne 1 -or $receipt.target -cne $target -or
    $receipt.ticket -notmatch '^[A-Z0-9-]{8,64}$' -or
    $receipt.original_sha256 -cne (HashText $xml)){
  Deny 'ORIGINAL_SNAPSHOT_INTEGRITY_FAILURE'
 }
 AssertTaskShape $target $xml
 return [pscustomobject]@{XML=$xml;Receipt=$receipt}
}
if($Synthetic){
 if($Mode -ne 'Preflight'){Deny 'SYNTHETIC_NEVER_MUTATES'}
 $canMigrate=$SyntheticState -eq 'Ready'
 $result=[ordered]@{schema=1;target=$Target;synthetic=$true;read_only=$true
   legacy_task_state=$SyntheticState;ready_for_cutover=$canMigrate
   live_control_authorized=$false;status='SYNTHETIC_NO_GO'}
 $result|ConvertTo-Json -Compress
 return
}
# Actual task inspection requires Windows, but does not require elevation.
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
 Deny 'WINDOWS_REQUIRED'
}
Import-Module ScheduledTasks -ErrorAction Stop
$state=TaskState $Target
$xml=GetTaskXml $Target
AssertTaskShape $Target $xml
$portsFree=PortsFree $Target
$preflightPaths=ReceiptPaths $Target
$ownerPresent=Test-Path -LiteralPath (Join-Path $preflightPaths.Dir ($Target+'.active.json'))
$ready=($state -eq 'Ready' -and $portsFree -and -not $ownerPresent)
if($Mode -eq 'Preflight'){
 [ordered]@{schema=1;target=$Target;read_only=$true
    task_state=$state;proxy_ports_free=$portsFree
    owner_marker_present=$ownerPresent
    ready_for_cutover=$ready;live_control_authorized=$false
    status='READ_ONLY_PRECHECK_NOT_APPROVAL'}|ConvertTo-Json -Compress
 return
}
if(-not (IsAdministrator)){Deny 'OPERATOR_ADMIN_REQUIRED_FOR_MANUAL_MAINTENANCE'}
if(-not $Approved -or $Ticket -notmatch '^[A-Z0-9-]{8,64}$'){
 Deny 'EXPLICIT_MAINTENANCE_APPROVAL_AND_TICKET_REQUIRED'
}
$paths=ReceiptPaths $Target
if($Mode -eq 'Snapshot'){
 if($state -eq 'Disabled'){Deny 'TASK_ALREADY_DISABLED'}
 if(Test-Path -LiteralPath $paths.Original -PathType Leaf){
  Deny 'EXISTING_SNAPSHOT_MUST_NOT_BE_OVERWRITTEN'
 }
 MakePrivateFolder $paths.Dir
 $hash=HashText $xml
 $receipt=[ordered]@{
  schema=1;target=$Target;ticket=$Ticket;original_sha256=$hash
  original_task_state=$state;cutover_committed=$false
  created_utc=[DateTimeOffset]::UtcNow.ToString('o')
 }
 try{
  [IO.File]::WriteAllText($paths.Original,$xml,(New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($paths.Receipt,($receipt|ConvertTo-Json -Depth 4),
      (New-Object Text.UTF8Encoding($false)))
  [void](VerifyBackup $paths $Target)
 }catch{
  Deny 'LOCAL_SNAPSHOT_VALIDATION_FAILED_NO_TASK_CHANGED'
 }
 Write-Host 'SNAPSHOT_LOCAL_PRIVATE_ARCHIVE_CREATED_NO_TASK_CHANGED'
 return
}
$stored=VerifyBackup $paths $Target
if($stored.Receipt.ticket -cne $Ticket){Deny 'MAINTENANCE_TICKET_MISMATCH'}
# GSC's durable owner marker may outlive its hosting process. Neither
# cutover nor rollback may reactivate the old scheduler task while the marker
# is present. Never silently delete a marker just because ports look free.
$ownerMarker=Join-Path $paths.Dir ($Target+'.active.json')
if(Test-Path -LiteralPath $ownerMarker){
 Deny 'GSC_OWNED_OR_ORPHANED_JVM_REQUIRES_SEPARATE_RECOVERY'
}
if($Mode -eq 'Cutover'){
 if($stored.Receipt.cutover_committed -eq $true){
  Deny 'CUTOVER_ALREADY_COMMITTED'
 }
 if(-not $ready){
  Deny 'LEGACY_TASK_MUST_BE_READY_AND_ALL_PROXY_PORTS_FREE'
 }
 if((TaskDefinitionDigest $xml) -cne (TaskDefinitionDigest $stored.XML)){
  Deny 'TASK_DEFINITION_CHANGED_SINCE_SNAPSHOT'
 }
 # IMPORTANT: disabling a task DOES NOT terminate a running JVM.
 # This procedure refuses to disable a running task or kill a process.
 Disable-ScheduledTask -TaskName $taskNames[$Target] -TaskPath '\' -ErrorAction Stop|Out-Null
 try{
  if((TaskState $Target) -ne 'Disabled'){Deny 'TASK_DISABLE_NOT_CONFIRMED'}
  if(-not (PortsFree $Target)){Deny 'PORT_OCCUPIED_AFTER_DISABLE'}
  $stored.Receipt.cutover_committed=$true
  [IO.File]::WriteAllText($paths.Receipt,(
    $stored.Receipt|ConvertTo-Json -Depth 4),
    (New-Object Text.UTF8Encoding($false)))
  Write-Host 'CUTOVER_LEGACY_TASK_DISABLED_ONLY_GSC_START_NOT_PERFORMED'
 }catch{
  # Roll back only our own changed task when ports remain free.
  if(PortsFree $Target){
   try{Enable-ScheduledTask -TaskName $taskNames[$Target] -TaskPath '\' -ErrorAction Stop|Out-Null}catch{}
  }
  throw
 }
 return
}
if($Mode -eq 'Rollback'){
 if($state -ne 'Disabled' -or -not $portsFree){
  Deny 'ROLLBACK_BLOCKED_UNTIL_GSC_JVM_EXIT_AND_PORTS_FREE'
 }
 # Fail-closed: original task XML and disabled status must still correspond.
 # Do not register a replacement task containing raw credentials or run Java.
 # A crash between disabling the task and persisting the receipt is
 # recoverable too: only this captured original task may be restored.
 if((TaskDefinitionDigest $xml) -cne (TaskDefinitionDigest $stored.XML)){
  Deny 'TASK_DEFINITION_DRIFT_REQUIRES_MANUAL_RECOVERY'
 }
 Enable-ScheduledTask -TaskName $taskNames[$Target] -TaskPath '\' -ErrorAction Stop |Out-Null
 if((TaskState $Target) -ne 'Ready'){Deny 'ROLLBACK_ENABLE_UNCONFIRMED'}
 $stored.Receipt.cutover_committed=$false
 [IO.File]::WriteAllText($paths.Receipt,(
   $stored.Receipt|ConvertTo-Json -Depth 4),
   (New-Object Text.UTF8Encoding($false)))
 Write-Host 'ROLLBACK_TASK_REENABLED_NO_JVM_STARTED_SNAPSHOT_PRESERVED'
 return
}
Deny 'UNKNOWN_MODE'
