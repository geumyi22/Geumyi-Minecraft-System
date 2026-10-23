#requires -Version 5.1
[CmdletBinding()]
param()
# Strict READ ONLY: NO service, process, task, ACL, registry, config or world change.
# Never disclose private paths, names, SIDs, task XML or config values.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$c=[ordered]@{
 service_running=$false
 service_binary_matches_running_process=$false
 service_start_arguments_verified=$false
 service_account_class='UNKNOWN'
 original_host_backup_matches_live=$false
 staged_canary_integrity_verified=$false
 protected_recovery_folders=$false
 original_task_snapshots_intact=$false
 legacy_tasks_running=0
 owner_markers_absent=$false
 config_exists=$false
 localhost_host_health_responding=$false
 host_version='UNVERIFIED'
}
function SafeFile([string]$p){
 if([string]::IsNullOrWhiteSpace($p) -or -not [IO.Path]::IsPathRooted($p)){return $false}
 try{$x=Get-Item -LiteralPath $p -ErrorAction Stop;return (-not $x.PSIsContainer -and -not $x.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint))}catch{return $false}
}
function FileHash([string]$p){
 if(-not(SafeFile $p)){return ''}
 try{return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}catch{return ''}
}
function PrivateDir([string]$p){
 try{
  $x=Get-Item -LiteralPath $p -ErrorAction Stop
  if(-not $x.PSIsContainer -or $x.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){return $false}
  $acl=Get-Acl -LiteralPath $p -ErrorAction Stop
  if(-not $acl.AreAccessRulesProtected){return $false}
  foreach($ace in $acl.Access){
   $sid=$ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
   if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
     $sid -notin @('S-1-5-18','S-1-5-32-544')){return $false}
  }
  return $true
 }catch{return $false}
}
function JSONRead([string]$p,[long]$max=8192){
 try{
  if(-not(SafeFile $p)){return $null}
  $f=Get-Item -LiteralPath $p
  if($f.Length -lt 3 -or $f.Length -gt $max){return $null}
  return (Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
 }catch{return $null}
}
function SnapshotOK([string]$id,[string]$root,[string]$recovery){
 try{
  $original=Join-Path $recovery ($id+'.original.xml')
  $r=JSONRead (Join-Path $recovery ($id+'.receipt.json'))
  $manifest=JSONRead (Join-Path $root ($id+'.json'))
  if($null -eq $r -or $null -eq $manifest -or -not(SafeFile $original)){return $false}
  $x=Get-Item -LiteralPath $original
  if($x.Length -lt 20 -or $x.Length -gt 65536){return $false}
  $text=[IO.File]::ReadAllText($original)
  $bytes=[Text.Encoding]::Unicode.GetBytes($text)
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  return ($r.schema -eq 1 -and $r.target -ceq $id -and
   $r.cutover_committed -eq $false -and $r.original_sha256 -ceq $hash -and
   $manifest.schema -eq 1 -and $manifest.target -ceq $id -and
   $manifest.expected_jar_sha256 -ceq '35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8')
 }catch{return $false}
}
try{
 $pd=$env:ProgramData
 if([string]::IsNullOrWhiteSpace($pd) -or -not [IO.Path]::IsPathRooted($pd)){throw 'blocked'}
 $root=Join-Path $pd 'GeumyiServerCenter\VelocityManaged'
 $rec=Join-Path $root 'Recovery'
 $stage=Join-Path $root 'CanaryStaging'
 $c.protected_recovery_folders=((PrivateDir $root) -and (PrivateDir $rec))
 $ok=$c.protected_recovery_folders
 $allAbsent=$true
 foreach($id in @('wild','playground','other')){
  if(-not(SnapshotOK $id $root $rec)){$ok=$false}
  if(Test-Path -LiteralPath (Join-Path $rec ($id+'.active.json'))){$allAbsent=$false}
  try{
   $task=Get-ScheduledTask -TaskName ('Geumyi Day10 Velocity '+$id) -TaskPath '\' -ErrorAction Stop
   if([string]$task.State -ceq 'Running'){$c.legacy_tasks_running++}
  }catch{}
 }
 $c.original_task_snapshots_intact=$ok
 $c.owner_markers_absent=$allAbsent
 $receipt=JSONRead (Join-Path $stage 'STAGING-RECEIPT.json')
 $new=Join-Path $stage 'GeumyiServerHost-v4.5.2-Velocity-CANARY.exe'
 $old=Join-Path $stage 'GeumyiServerHost-ORIGINAL.exe'
 if($null -ne $receipt -and $receipt.schema -eq 1 -and
    $receipt.status -ceq 'STAGED_NOT_INSTALLED'){
  $h=FileHash $new
  $c.staged_canary_integrity_verified=($h -cne '' -and $h -ceq $receipt.canary_sha256)
 }
 $svc=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
 if($null -ne $svc){
  $c.service_running=($svc.State -ceq 'Running' -and [int]$svc.ProcessId -gt 0)
  $c.service_account_class=if($svc.StartName -in @('LocalSystem','NT AUTHORITY\SYSTEM')){'LOCAL_SYSTEM'}else{'OTHER_ACCOUNT_REVIEW'}
  $line=[string]$svc.PathName
  $match=[regex]::Match($line,'(?i)^\s*"([^"]+\\GeumyiServerHost\.exe)"\s+--service\s+--config\s+"([^"]+)"\s*$')
  if(-not $match.Success){$match=[regex]::Match($line,'(?i)^\s*([^\s"]+\\GeumyiServerHost\.exe)\s+--service\s+--config\s+"([^"]+)"\s*$')}
  $c.service_start_arguments_verified=$match.Success
  if($match.Success -and $c.service_running){
   $live=$match.Groups[1].Value
   $cfg=$match.Groups[2].Value
   $liveHash=FileHash $live
   $c.config_exists=(SafeFile $cfg)
   if($null -ne $receipt){
    $c.original_host_backup_matches_live=($liveHash -cne '' -and
      (FileHash $old) -ceq $liveHash -and
      $receipt.original_host_sha256 -ceq $liveHash)
   }
   try{
    $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$svc.ProcessId) -ErrorAction Stop
    if($null -ne $proc -and $proc.ExecutablePath){
     $c.service_binary_matches_running_process=([IO.Path]::GetFullPath([string]$proc.ExecutablePath) -ieq [IO.Path]::GetFullPath($live))
    }
   }catch{}
   if($c.config_exists){
    $config=JSONRead $cfg 1048576
    if($null -ne $config -and $null -ne $config.port){
     $port=[int]$config.port
     if($port -ge 1024 -and $port -le 65535){
      try{
       $health=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$port+'/api/health') -Method Get -TimeoutSec 3 -ErrorAction Stop
       if($health.ok -eq $true -and $health.service -eq $true){
        $c.localhost_host_health_responding=$true
        if([string]$health.version -match '^[0-9]+\.[0-9]+\.[0-9]+([-A-Za-z0-9.]+)?$'){
         $c.host_version=[string]$health.version
        }
       }
      }catch{}
     }
    }
   }
  }
 }
}catch{
 # Deliberately no internal exception text: Windows can embed paths/usernames.
}
$pass=($c.service_running -and $c.service_account_class -ceq 'LOCAL_SYSTEM' -and
 $c.host_version -ne 'UNVERIFIED' -and $c.host_version -notlike '4.5.2*' -and
 $c.service_binary_matches_running_process -and
 $c.service_start_arguments_verified -and $c.original_host_backup_matches_live -and
 $c.staged_canary_integrity_verified -and $c.protected_recovery_folders -and
 $c.original_task_snapshots_intact -and $c.legacy_tasks_running -eq 3 -and
 $c.owner_markers_absent -and $c.config_exists -and $c.localhost_host_health_responding)
[ordered]@{
 schema=1;check='HOST_SWAP_AND_ROLLBACK_PREFLIGHT';read_only=$true
 preflight_passed=[bool]$pass;checks=$c
 service_stopped=$false;service_binary_changed=$false;task_mutations=0
 java_operations=0;rollback_executed=$false;host_cutover_authorized=$false
 status=if($pass){'HOST_SWAP_ROLLBACK_PREFLIGHT_PASS_NO_INSTALL'}else{'HOST_SWAP_ROLLBACK_PREFLIGHT_BLOCKED_NO_CHANGE'}
 next='REVIEW_SERVICE_REPLACEMENT_AND_ORPHAN_RECOVERY_BEFORE_INSTALL'
}|ConvertTo-Json -Depth 5
