[CmdletBinding()]
param([switch]$FunctionsOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

# Script imports existing read-only v4/v5 resolver: privately reads GSC config
# and path-pointer files to locate exact server roots; no credentials exported.
$operatorFunctionsOnly=[bool]$FunctionsOnly
. (Join-Path $PSScriptRoot 'Day12_Cloud_Recovery_Plan_READ_ONLY.ps1') -FunctionsOnly
if($operatorFunctionsOnly){return}

function Fail-Local([string]$Reason) {
  # Intentionally no source paths, credentials, filenames or private values.
  throw ('P0_GATE_'+$Reason)
}
function Convert-PrivateSecureString([Security.SecureString]$Value) {
  $ptr=[IntPtr]::Zero
  try {
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    if($ptr -ne [IntPtr]::Zero){
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
  }
}
function Compare-LocalLiteral([string]$A,[string]$B) {
  try {
    return [IO.Path]::GetFullPath($A).TrimEnd('\').Equals(
      [IO.Path]::GetFullPath($B).TrimEnd('\'),
      [StringComparison]::OrdinalIgnoreCase)
  } catch {return $false}
}
function Source-RootForRole($Records,[string]$Role,[string]$CloudRoot) {
  $matching=@($Records|Where-Object{$_.id -eq $Role})
  if($matching.Count -ne 1){Fail-Local 'SOURCE_MAPPING_AMBIGUOUS'}
  $r=$matching[0]
  $dir=Inspect-LiteralDirectory ([string]$r.path)
  if(-not $dir.path){Fail-Local 'SOURCE_ROOT_UNAVAILABLE'}
  if($Role -eq 'gsc_state'){
    $rootExpected=Join-Path $env:ProgramData 'GeumyiServerCenter'
    if(-not(Compare-LocalLiteral $dir.path $rootExpected)){
      Fail-Local 'GSC_ROOT_NOT_DEFAULT'
    }
  } else {
    if(-not(Private-PathInside $dir.path $CloudRoot)){
      Fail-Local 'PAPER_NOT_UNDER_VERIFIED_ONEDRIVE'
    }
  }
  return $dir.path
}
function Exact-Candidate([string]$Root,[string]$Relative,[bool]$AllowOneDrive) {
  # No directory recursion or world/plugin data globbing.
  if($Relative -match '\.\.|^[\\/]'){Fail-Local 'INVALID_RELATIVE_FILE'}
  $full=Join-Path $Root $Relative
  try {
    $file=Get-Item -LiteralPath $full -Force -ErrorAction Stop
  } catch {Fail-Local 'REQUIRED_CONFIG_NOT_ACCESSIBLE'}
  if($file.PSIsContainer){Fail-Local 'REQUIRED_CONFIG_IS_DIRECTORY'}
  # No content read in this stage. Cloud reparse metadata is expected for Paper
  # and explicitly permitted for THESE FOUR small server.properties only.
  $isReparse=(([long]$file.Attributes -band 0x00000400) -ne 0)
  if($isReparse -and -not $AllowOneDrive){Fail-Local 'LOCAL_CONFIG_REPARSE_REFUSED'}
  if($file.Length -lt 1 -or $file.Length -gt 8388608){
    Fail-Local 'CONFIG_SIZE_OUTSIDE_P0_LIMIT'
  }
  return $full
}
function Confirm-Day10Proxy([string]$Id,[string]$ProxyRoot) {
  $root=Join-Path $ProxyRoot $Id
  $inspected=Inspect-LiteralDirectory $root
  if(-not $inspected.path){Fail-Local 'PROXY_ROOT_MISSING'}
  $expectedTask='Geumyi Day10 Velocity '+$Id
  $tasks=@(Get-ScheduledTask -TaskName $expectedTask -ErrorAction SilentlyContinue)
  if($tasks.Count -ne 1){Fail-Local 'PROXY_SCHEDULED_TASK_AMBIGUOUS'}
  $task=$tasks[0]
  if([string]$task.State -ne 'Running'){Fail-Local 'PROXY_TASK_NOT_RUNNING'}
  $actions=@($task.Actions)
  if($actions.Count -ne 1){Fail-Local 'PROXY_TASK_ACTION_AMBIGUOUS'}
  if(-not(Compare-LocalLiteral ([string]$actions[0].WorkingDirectory) $root)){
    Fail-Local 'PROXY_TASK_WORKDIR_MISMATCH'
  }
  $execName=[IO.Path]::GetFileName([string]$actions[0].Execute)
  if($execName -ine 'java.exe' -or
     ([string]$actions[0].Arguments).Trim() -cne '-Xms256M -Xmx512M -jar velocity.jar'){
    Fail-Local 'PROXY_TASK_ACTION_CHANGED'
  }
  return $root
}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    Fail-Local 'WINDOWS_REQUIRED'
  }
  if(-not $env:LOCALAPPDATA -or -not $env:ProgramData){
    Fail-Local 'WINDOWS_ENVIRONMENT_MISSING'
  }
  $exe=Join-Path $PSScriptRoot 'p0-local-capture.exe'
  if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){
    Fail-Local 'ENCRYPTION_BINARY_MISSING'
  }
  $cfgPath=Join-Path $env:ProgramData 'GeumyiServerCenter\server.json'
  $cfg=Read-Config $cfgPath
  $api=Get-LocalSettings
  if($cfg.status -ne 'OK' -or $api.status -ne 'OK'){
    Fail-Local 'GSC_CONFIG_API_NOT_BOTH_AVAILABLE'
  }
  $records=@(Get-PrivateSourceRecords $cfg $api $cfgPath)
  $drive=Get-OneDriveCandidates
  $ondrive=@($drive.items|Where-Object{$_.inspection.path}|
    Group-Object {$_.inspection.path.ToUpperInvariant()})
  if($ondrive.Count -ne 1){Fail-Local 'ONEDRIVE_ROOT_AMBIGUOUS'}
  $cloudRoot=[string]$ondrive[0].Group[0].inspection.path
  $one=Inspect-LiteralDirectory $cloudRoot
  if(-not $one.path){Fail-Local 'ONEDRIVE_ROOT_UNAVAILABLE'}
  $gsc=Source-RootForRole $records 'gsc_state' $cloudRoot
  $files=New-Object Collections.ArrayList
  [void]$files.Add(@{name='gsc/server.json';
      source=(Exact-Candidate $gsc 'server.json' $false)})
  foreach($role in @('wild','playground','other','lobby')){
    $root=Source-RootForRole $records $role $cloudRoot
    [void]$files.Add(@{name=('paper/'+$role+'/server.properties');
      source=(Exact-Candidate $root 'server.properties' $true)})
  }
  $proxyRoot=Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer'
  foreach($role in @('wild','playground','other')){
    $root=Confirm-Day10Proxy $role $proxyRoot
    foreach($rel in @(
       'velocity.toml','forwarding.secret',
       'plugins\Geyser-Velocity\config.yml',
       'plugins\floodgate\config.yml',
       'plugins\floodgate\key.pem')){
      $normalized=$rel.Replace('\','/')
      [void]$files.Add(@{name=('proxy/'+$role+'/'+$normalized);
        source=(Exact-Candidate $root $rel $false)})
    }
  }
  if($files.Count -ne 20){Fail-Local 'P0_EXACT_FILE_COUNT_MISMATCH'}
  $google=Find-GoogleContainer '' $false
  if(-not $google.inspection.path){Fail-Local 'GOOGLE_PROVIDER_MOUNT_NOT_VERIFIED'}
  $localStaging=Join-Path $env:LOCALAPPDATA 'Geumyi-P0-Encrypted-Staging'
  $dest=Join-Path $localStaging ('P0-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
  $allRecords=@($records)+@(
    @{id='velocity-wild';path=(Join-Path $proxyRoot 'wild');final_path=''},
    @{id='velocity-playground';path=(Join-Path $proxyRoot 'playground');final_path=''},
    @{id='velocity-other';path=(Join-Path $proxyRoot 'other');final_path=''}
  )
  foreach($r in $allRecords){
    if(-not $r.final_path){
      $f=Get-MetadataFinalDirectory ([string]$r.path)
      if(-not $f.path){Fail-Local 'SOURCE_FINAL_PATH_UNVERIFIED'}
      $r.final_path=$f.path
    }
  }
  if(-not (Report-LocationIsSeparate $dest $allRecords @($one,$google.inspection))){
    Fail-Local 'STAGING_MAY_OVERLAP_SOURCE_OR_CLOUD'
  }
  Write-Host '========================================================'
  Write-Host 'Day12 P0 LOCAL ENCRYPTED CAPTURE - exact 20 settings files'
  Write-Host '4 Paper configs + GSC config + 3 Velocity x 5 private files'
  Write-Host 'Reads ONLY selected files, may hydrate OneDrive placeholders.'
  Write-Host 'NO world content. NO upload. NO server restart or changes.'
  Write-Host 'Output: LOCALAPPDATA/Geumyi-P0-Encrypted-Staging (not cloud).'
  Write-Host 'Password is needed for FUTURE recovery. Store OFFLINE.'
  Write-Host 'If password is lost, the encrypted capture may be unreadable.'
  Write-Host '========================================================'
  $confirm=Read-Host 'Type SOURCE_SELECTED_CONSENT to allow selected file reads'
  if($confirm -cne 'SOURCE_SELECTED_CONSENT'){Fail-Local 'OPERATOR_CONFIRMATION_NOT_GIVEN'}
  $secure1=Read-Host 'Enter new recovery passphrase (20+ characters, NOT shown)' -AsSecureString
  $secure2=Read-Host 'Repeat recovery passphrase (NOT shown)' -AsSecureString
  $pass1=Convert-PrivateSecureString $secure1
  $pass2=Convert-PrivateSecureString $secure2
  if(-not $pass1.Equals($pass2,[StringComparison]::Ordinal) -or
      $pass1.Length -lt 20 -or $pass1.Length -gt 256){
    Fail-Local 'RECOVERY_PASSPHRASE_UNACCEPTABLE'
  }
  $secure1.Dispose();$secure2.Dispose();$secure1=$null;$secure2=$null
  $payload=@{
    passphrase=$pass1
    dest=$dest
    files=@($files.ToArray())
  } | ConvertTo-Json -Compress -Depth 5
  $pass1=$null;$pass2=$null
  # No secret or source path on command line, environment variables or disk.
  # Force UTF-8 pipe for Windows PowerShell 5.1, including Korean passwords.
  $OutputEncoding=New-Object System.Text.UTF8Encoding($false)
  $run=@($payload|& $exe --capture)
  $payload=$null
  if($LASTEXITCODE -ne 0 -or ($run|Out-String) -notmatch 'P0_LOCAL_ENCRYPTED_CAPTURE_VERIFIED'){
    $run|ForEach-Object{if($_ -match '^P0_(CAPTURE_|PRIVATE_)'){Write-Host $_}}
    Fail-Local 'ENCRYPTED_CAPTURE_INCOMPLETE'
  }
  Write-Host 'P0_LOCAL_ENCRYPTED_CAPTURE_VERIFIED'
  Write-Host ('LOCAL_ENCRYPTED_FOLDER='+$dest)
  Write-Host 'NO_GOOGLE_DRIVE_UPLOAD_PERFORMED'
  Write-Host 'NO_REAL_REMOTE_RESTORE_TEST_PERFORMED'
  Write-Host 'NO_PAPER_OR_GSC_SERVICE_WAS_RESTARTED'
  Write-Host 'Do not share source files, encrypted folder, password or key.'
  Write-Host 'SEND_ONLY: screenshot excluding local user profile names and passwords.'
} catch {
  Write-Host 'P0_CAPTURE_SAFELY_BLOCKED_OR_INCOMPLETE'
  Write-Host 'Do NOT upload partial archives or paste any secret.'
  # Print only whitelisted high-level gate tag (never exception stack/source paths).
  if($_.Exception.Message -match '^P0_GATE_[A-Z_]+$'){
    Write-Host $_.Exception.Message
  }
  exit 2
}
