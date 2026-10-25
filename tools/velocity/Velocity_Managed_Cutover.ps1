#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Preflight','VerifyExisting','Snapshot','Cutover','DrainAndCutover','Rollback')]
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
 # OBSERVATION ONLY. Never acquire transient TCP/UDP sockets on production.
 # Any TCP endpoint (including ESTABLISHED) on the local front port blocks
 # cutover; sockets may outlive their listening endpoint. Treat query
 # exceptions as UNKNOWN -> not free, never infer authorization from absence.
 $pair=$expectedPorts[$target]
 try {
  $tcp=@(Get-NetTCPConnection -ErrorAction Stop |
    Where-Object {[int]$_.LocalPort -eq [int]$pair[0]})
  $udp=@(Get-NetUDPEndpoint -ErrorAction Stop |
    Where-Object {[int]$_.LocalPort -eq [int]$pair[1]})
  return ($tcp.Count -eq 0 -and $udp.Count -eq 0)
 }catch{return $false}
}
# Only the target-specific Geyser UDP kernel owner anchors the legacy JVM.
# Never print, stop by PID, or guess Java identity from task name alone.
function GetLegacyProxyProcessAnchor([string]$target){
 try{
  $pair=$expectedPorts[$target]
  $udp=@(Get-NetUDPEndpoint -LocalPort ([int]$pair[1]) -ErrorAction Stop)
  $ids=@($udp|ForEach-Object {[int]$_.OwningProcess}|Select-Object -Unique)
  if($ids.Count -ne 1 -or $ids[0] -le 4){Deny 'NO_UNIQUE_GEYSER_UDP_OWNER'}
  $owner=Get-CimInstance Win32_Process -Filter ("ProcessId = "+$ids[0]) -ErrorAction Stop
  if($null -eq $owner -or [string]$owner.Name -notin @('java.exe','javaw.exe') -or
     [string]$owner.CommandLine -notmatch '(?i)(?:^|\s)-jar\s+(?:"[^"]*velocity\.jar"|\S*velocity\.jar)(?:\s|$)' -or
     $null -eq $owner.CreationDate){
   Deny 'GEYSER_UDP_OWNER_NOT_VERIFIED_VELOCITY_JAVA'
  }
  $tracked=@([pscustomobject]@{PID=[int]$owner.ProcessId;Started=[string]$owner.CreationDate})
  # A separate Java launcher may parent the UDP-owner JVM.
  if([int]$owner.ParentProcessId -gt 4){
   $parent=Get-CimInstance Win32_Process -Filter ("ProcessId = "+[int]$owner.ParentProcessId) -ErrorAction Stop
   if($null -ne $parent -and [string]$parent.Name -in @('java.exe','javaw.exe') -and
      [string]$parent.CommandLine -match '(?i)(?:^|\s)-jar\s+(?:"[^"]*velocity\.jar"|\S*velocity\.jar)(?:\s|$)' -and
      $null -ne $parent.CreationDate){
    $tracked+=([pscustomobject]@{PID=[int]$parent.ProcessId;Started=[string]$parent.CreationDate})
   }
  }
  return $tracked
 }catch{
  Deny 'LEGACY_PROCESS_UDP_IDENTITY_NOT_ATTESTED'
 }
}
function TrackedLegacyExited($tracked){
 try{
  foreach($p in @($tracked)){
   $current=Get-CimInstance Win32_Process -Filter ("ProcessId = "+[int]$p.PID) -ErrorAction Stop
   if($null -ne $current -and [string]$current.CreationDate -ceq [string]$p.Started){
    return $false
   }
  }
  return $true
 }catch{return $false}
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
function LocalLauncherManifest([string]$target,[string]$xml){
 $x=[xml]$xml
 $cmd=$x.SelectSingleNode("//*[local-name()='Actions']/*[local-name()='Exec']/*[local-name()='Command']")
 $args=$x.SelectSingleNode("//*[local-name()='Actions']/*[local-name()='Exec']/*[local-name()='Arguments']")
 $dir=$x.SelectSingleNode("//*[local-name()='Actions']/*[local-name()='Exec']/*[local-name()='WorkingDirectory']")
 if($null -eq $cmd -or $null -eq $args -or $null -eq $dir){Deny 'MISSING_EXEC_ACTION'}
 $java=[string]$cmd.InnerText
 $work=[string]$dir.InnerText
 $line=([string]$args.InnerText).Trim()
 # Intentionally SMALL allowlist, not a shell parser. Do not infer unsafe
 # or unknown JVM arguments from an existing privileged Scheduler task.
 # If a real task differs, stop and explicitly review its launcher locally.
 $allowed='(?i)^((?:-(?:Xms|Xmx)[1-9][0-9]*[mMgG]\s+|-XX:[+-][A-Za-z0-9_]+\s+)*)-jar\s+"?velocity\.jar"?$'
 if($line -notmatch $allowed){Deny 'EXISTING_JVM_ARGUMENTS_REQUIRE_MANUAL_REVIEW'}
 $argv=@($line -split '\s+'|ForEach-Object {$_.Trim('"')})
 if($argv.Count -lt 2 -or $argv.Count -gt 40){Deny 'INVALID_MANAGED_ARGUMENT_COUNT'}
 if(-not [IO.Path]::IsPathRooted($java) -or
    [IO.Path]::GetFileName($java) -ine 'java.exe' -or
    -not (Test-Path -LiteralPath $java -PathType Leaf)){Deny 'SCHEDULER_JAVA_PATH_UNVERIFIED'}
 return [ordered]@{
  schema=1
  target=$target
  java_executable=$java
  working_directory=$work
  args=@($argv)
  expected_jar_sha256='35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8'
 }
}
function ManifestFile([string]$target){
 $pd=$env:ProgramData
 if([string]::IsNullOrWhiteSpace($pd)){Deny 'PROGRAMDATA_UNAVAILABLE'}
 return Join-Path (Join-Path $pd 'GeumyiServerCenter\VelocityManaged') ($target+'.json')
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
# Inspect the EXISTING protected operator archive, never create a second
# snapshot or change a Scheduled Task. Missing/inconsistent evidence FAILS.
# Successful evidence inspection does NOT prove a legacy child JVM is stopped.
if($Mode -eq 'VerifyExisting'){
 $evidence=VerifyBackup $preflightPaths $Target
 if($evidence.Receipt.original_task_state -notin @('Running','Ready')){
  Deny 'SNAPSHOT_ORIGIN_NOT_AN_ACTIVE_OR_READY_TASK'
 }
 if((TaskDefinitionDigest $xml) -cne (TaskDefinitionDigest $evidence.XML)){
  Deny 'SCHEDULED_TASK_DEFINITION_CHANGED_SINCE_SNAPSHOT'
 }
 $manifestPath=ManifestFile $Target
 AssertPrivateFolder (Split-Path -Parent $manifestPath)
 if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){
  Deny 'PROTECTED_LAUNCH_MANIFEST_MISSING'
 }
 $expectedManifest=LocalLauncherManifest $Target $evidence.XML
 $actualManifest=Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 if($actualManifest.schema -ne 1 -or $actualManifest.target -cne $Target -or
    $actualManifest.java_executable -cne $expectedManifest.java_executable -or
    $actualManifest.working_directory -cne $expectedManifest.working_directory -or
    $actualManifest.expected_jar_sha256 -cne $expectedManifest.expected_jar_sha256 -or
    (@($actualManifest.args)-join [char]0) -cne (@($expectedManifest.args)-join [char]0)){
  Deny 'PROTECTED_LAUNCH_MANIFEST_DOES_NOT_MATCH_ORIGINAL_TASK'
 }
 # Check actual original JAR bytes, not just the private launcher manifest.
 # The disposable CI fixture has no real Velocity JAR and must report false.
 $jarMatches=$false
 $jar=Join-Path $expectedManifest.working_directory 'velocity.jar'
 try{
  $jarInfo=Get-Item -LiteralPath $jar -Force -ErrorAction Stop
  if(-not $jarInfo.PSIsContainer -and
     -not ($jarInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)){
    $jarMatches=((Get-FileHash -LiteralPath $jar -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -ceq
      $expectedManifest.expected_jar_sha256)
  }
 }catch{$jarMatches=$false}
 [ordered]@{
  schema=1
  check='GSC452_EXISTING_CUTOVER_EVIDENCE_READ_ONLY'
  target=$Target
  read_only=$true
  protected_original_snapshot_valid=$true
  protected_manifest_matches_original=$true
  task_definition_matches_original=$true
  velocity_jar_sha256_matches_pin=$jarMatches
  task_state=$state
  proxy_ports_free=$portsFree
  owner_marker_present=$ownerPresent
  cutover_already_committed=[bool]$evidence.Receipt.cutover_committed
  task_to_child_jvm_shutdown_proven=$false
  operator_cutover_authorized=$false
  status='EXISTING_EVIDENCE_VERIFIED_LIVE_CUTOVER_NOT_AUTHORIZED'
  next_step='VERIFY_LEGACY_TASK_AND_CHILD_JVM_SHUTDOWN_BEFORE_ANY_MUTATION'
 }|ConvertTo-Json -Compress
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
 $manifest=LocalLauncherManifest $Target $xml
 $manifestPath=ManifestFile $Target
 if(Test-Path -LiteralPath $manifestPath){Deny 'STAGED_MANIFEST_ALREADY_EXISTS'}
 # Both private parent and backup child receive explicit SYSTEM+Administrators
 # access, no inherited Users/Everyone rights; never export the launcher.
 MakePrivateFolder (Split-Path -Parent $manifestPath)
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
  [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 4),
      (New-Object Text.UTF8Encoding($false)))
  [void](VerifyBackup $paths $Target)
  AssertPrivateFolder (Split-Path -Parent $manifestPath)
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
# One-target maintenance. Disable future Scheduler launches before requesting
# STOP on the exact existing task. The external Velocity JVM has no GSC-owned
# stdin, so this is NOT console-graceful shutdown; players may disconnect.
# There is NO taskkill or JVM PID kill. Failures remain Disabled (safe no-spawn)
# and require recovery. A task stop alone does not attest child JVM exit.
if($Mode -eq 'DrainAndCutover'){
 if($state -ne 'Running'){Deny 'LEGACY_RUNNING_TASK_REQUIRED_FOR_CONTROLLED_DRAIN'}
 if([bool]$stored.Receipt.cutover_committed){Deny 'CUTOVER_ALREADY_COMMITTED'}
 if((TaskDefinitionDigest $xml) -cne (TaskDefinitionDigest $stored.XML)){
  Deny 'TASK_DEFINITION_CHANGED_SINCE_SNAPSHOT'
 }
 $manifestFile=ManifestFile $Target
 AssertPrivateFolder (Split-Path -Parent $manifestFile)
 if(-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)){
  Deny 'LOCAL_JAVA_LAUNCH_MANIFEST_MISSING'
 }
 $expectedManifest=LocalLauncherManifest $Target $stored.XML
 $actualManifest=Get-Content -LiteralPath $manifestFile -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 if($actualManifest.schema -ne 1 -or $actualManifest.target -cne $Target -or
    $actualManifest.java_executable -cne $expectedManifest.java_executable -or
    $actualManifest.working_directory -cne $expectedManifest.working_directory -or
    $actualManifest.expected_jar_sha256 -cne $expectedManifest.expected_jar_sha256 -or
    (@($actualManifest.args)-join [char]0) -cne (@($expectedManifest.args)-join [char]0)){
  Deny 'STAGED_MANIFEST_DRIFT'
 }
 # Check actual bytes before any player interruption, not the manifest only.
 $jar=Join-Path $expectedManifest.working_directory 'velocity.jar'
 $ji=Get-Item -LiteralPath $jar -Force -ErrorAction Stop
 if($ji.PSIsContainer -or ($ji.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
    (Get-FileHash -LiteralPath $jar -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne
    $expectedManifest.expected_jar_sha256){
  Deny 'VELOCITY_JAR_BYTES_DIFFER_FROM_PIN'
 }
 $tracked=@(GetLegacyProxyProcessAnchor $Target)
 if($tracked.Count -lt 1 -or (TrackedLegacyExited $tracked)){
  Deny 'LEGACY_UDP_JVM_EXITED_BEFORE_DRAIN'
 }
 Disable-ScheduledTask -TaskPath '\' -TaskName $taskNames[$Target] -ErrorAction Stop|Out-Null
 if((TaskState $Target) -ne 'Disabled'){
  Deny 'DISABLE_FUTURE_RESTARTS_NOT_CONFIRMED_MANUAL_RECOVERY_REQUIRED'
 }
 try{
  Stop-ScheduledTask -TaskPath '\' -TaskName $taskNames[$Target] -ErrorAction Stop
 }catch{
  Deny 'EXACT_LEGACY_TASK_STOP_FAILED_REMAINS_DISABLED_MANUAL_RECOVERY'
 }
 $deadline=[DateTime]::UtcNow.AddSeconds(40)
 $drained=$false
 do{
  if((TaskState $Target) -eq 'Disabled' -and -not (Test-Path -LiteralPath $ownerMarker) -and
     (TrackedLegacyExited $tracked) -and (PortsFree $Target)){
   $drained=$true;break
  }
  Start-Sleep -Milliseconds 500
 }while([DateTime]::UtcNow -lt $deadline)
 if(-not $drained){
  Deny 'CHILD_JVM_OR_PORT_PERSISTS_TASK_LEFT_DISABLED_DO_NOT_START_ANOTHER_PROXY'
 }
 if((TaskDefinitionDigest (GetTaskXml $Target)) -cne (TaskDefinitionDigest $stored.XML) -or
    (TaskState $Target) -ne 'Disabled' -or -not (PortsFree $Target) -or
    -not (TrackedLegacyExited $tracked)){
  Deny 'DRAIN_POSTCHECK_CHANGED_TASK_LEFT_DISABLED'
 }
 $stored.Receipt.cutover_committed=$true
 [IO.File]::WriteAllText($paths.Receipt,($stored.Receipt|ConvertTo-Json -Depth 4),
     (New-Object Text.UTF8Encoding($false)))
 Write-Host 'ONE_TARGET_LEGACY_TASK_DISABLED_JAVA_OWNER_GONE_PORTS_FREE_RECEIPT_COMMITTED'
 Write-Host 'GSC_PROXY_NOT_STARTED_REQUIRE_SEPARATE_AUTHENTICATED_HOST_OPT_IN_AND_CLIENT_E2E'
 return
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
 # Manifest was generated locally from the exact approved original task, NOT
 # supplied in HTTP JSON. Reject any after-snapshot launcher drift.
 $manifestFile=ManifestFile $Target
 AssertPrivateFolder (Split-Path -Parent $manifestFile)
 if(-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)){
  Deny 'LOCAL_JAVA_LAUNCH_MANIFEST_MISSING'
 }
 $expectedManifest=LocalLauncherManifest $Target $stored.XML
 $actualManifest=Get-Content -LiteralPath $manifestFile -Raw|ConvertFrom-Json
 if($actualManifest.schema -ne 1 -or $actualManifest.target -cne $Target -or
    $actualManifest.java_executable -cne $expectedManifest.java_executable -or
    $actualManifest.working_directory -cne $expectedManifest.working_directory -or
    $actualManifest.expected_jar_sha256 -cne $expectedManifest.expected_jar_sha256 -or
    (@($actualManifest.args)-join [char]0) -cne (@($expectedManifest.args)-join [char]0)){
   Deny 'STAGED_MANIFEST_DRIFT'
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
