[CmdletBinding()]
param(
  [switch]$Synthetic,
  [switch]$Interactive,
  [string]$GoogleDriveRoot="",
  [string]$OneDriveRoot="",
  [string]$ConfigPath="",
  [string]$OutputDir=""
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# This is a READ-ONLY discovery tool, not a backup or synchronization program.
# Google Drive Desktop / OneDrive login alone does not establish cloud sync,
# remaining quota, verified copies, backup consistency or recovery capability.

function Select-ExistingFolder([string]$Description) {
  Add-Type -AssemblyName System.Windows.Forms
  $dlg=New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description=$Description
  $dlg.ShowNewFolderButton=$false
  if($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    return ""
  }
  return [string]$dlg.SelectedPath
}
function CanonicalDirectory([string]$Path) {
  if([string]::IsNullOrWhiteSpace($Path)){return ""}
  $p=$Path.Trim().Trim('"')
  if(-not (Test-Path -LiteralPath $p -PathType Container)){return ""}
  try {
    $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      # A cloud virtual volume can use reparse points internally, so requiring
      # no junction is limited to the SELECTED DIRECTORY itself.
      return ""
    }
    return [IO.Path]::GetFullPath($i.FullName).TrimEnd('\')
  } catch {return ""}
}
function PathIsInside([string]$Child,[string]$Parent) {
  if(-not $Child -or -not $Parent){return $false}
  $a=$Child.TrimEnd('\');$b=$Parent.TrimEnd('\')
  return $a.Equals($b,[StringComparison]::OrdinalIgnoreCase) -or
    $a.StartsWith($b+'\',[StringComparison]::OrdinalIgnoreCase)
}
function CanConnectLocalTcp([int]$Port) {
  if($Port -le 0 -or $Port -gt 65535){return $false}
  $c=New-Object Net.Sockets.TcpClient
  $ar=$null
  try {
    $ar=$c.BeginConnect("127.0.0.1",$Port,$null,$null)
    if(-not $ar.AsyncWaitHandle.WaitOne(350,$false)){return $false}
    $c.EndConnect($ar);return $c.Connected
  }catch{return $false}
  finally{if($null -ne $ar){$ar.AsyncWaitHandle.Close()};$c.Dispose()}
}
function Get-OneDriveCandidateRoots {
  $roots=@()
  foreach($variable in @("OneDrive","OneDriveConsumer","OneDriveCommercial")){
    $v=[Environment]::GetEnvironmentVariable($variable)
    if(-not [string]::IsNullOrWhiteSpace($v)){
      $root=CanonicalDirectory $v
      if($root){$roots+= $root}
    }
  }
  return @($roots|Select-Object -Unique)
}
function InspectConfig([string]$Path) {
  $res=[ordered]@{
    status="CONFIG_UNAVAILABLE";host_version="UNKNOWN";expected_other="OFFLINE"
    profiles=@();world_consistency_proven=$false
    config_mutated=$false;server_root_paths_exported=$false
  }
  if(-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)){return $res}
  try {
    $cfg=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if($null -eq $cfg.servers){return $res}
    foreach($sv in @($cfg.servers)){
      $id=[string]$sv.id
      if($id -notin @("wild","playground","lobby","other")){continue}
      $serverRoot=""
      $candidate=[string]$sv.path
      if(-not [string]::IsNullOrWhiteSpace($candidate)){
        $serverRoot=CanonicalDirectory $candidate
      }
      $role=[ordered]@{
        id=$id;root_found=[bool]$serverRoot;configured_java_port=[int]$sv.java_port
        loopback_tcp_reachable=$(if($serverRoot){CanConnectLocalTcp ([int]$sv.java_port)}else{$false})
        root_bytes_estimated=$false;root_bytes=$null
        quiescent_offline_snapshot_proven=$false
      }
      $res.profiles+= $role
    }
    $res.status="CONFIG_READ_ONLY_PARSED"
  }catch{$res.status="CONFIG_PARSE_OR_ACCESS_ERROR"}
  return $res
}
function Decide([object]$Cfg,[string]$Google,[string]$Microsoft,[string[]]$KnownOneDriveRoots,[bool]$GoogleClient,[bool]$OneDriveClient,[bool]$HostRunning) {
  $fail=New-Object System.Collections.ArrayList
  if(-not $HostRunning){[void]$fail.Add("GSC_HOST_SERVICE_NOT_RUNNING")}
  if([string]$Cfg.status -ne "CONFIG_READ_ONLY_PARSED"){[void]$fail.Add("GSC_SERVER_CONFIG_UNAVAILABLE")}
  $profiles=@($Cfg.profiles)
  foreach($id in @("wild","playground","lobby")){
    if(@($profiles|Where-Object{$_.id -eq $id -and $_.root_found}).Count -ne 1){
      [void]$fail.Add("ACTIVE_SERVER_ROOT_UNVERIFIED_"+$id.ToUpperInvariant())
    }
  }
  if(@($profiles|Where-Object{$_.id -eq "other"}).Count -ne 1) {
    [void]$fail.Add("OTHER_EXPECTED_PROFILE_NOT_FOUND")
  }
  if(-not $Google){[void]$fail.Add("GOOGLE_DRIVE_FOLDER_NOT_SELECTED_OR_UNREACHABLE")}
  if(-not $Microsoft){[void]$fail.Add("ONEDRIVE_FOLDER_NOT_SELECTED_OR_UNREACHABLE")}
  if($Google -and $Microsoft -and
      ((PathIsInside $Google $Microsoft) -or (PathIsInside $Microsoft $Google))){
    [void]$fail.Add("CLOUD_DESTINATION_OVERLAP")
  }
  $matchingOneDrive=@($KnownOneDriveRoots|Where-Object{PathIsInside $Microsoft $_}).Count -gt 0
  if($Microsoft -and -not $matchingOneDrive){
    [void]$fail.Add("ONEDRIVE_ENVIRONMENT_PATH_NOT_CONFIRMED")
  }
  # NEVER declare Google volume to be genuine only based on user-selected path.
  # A mounted drive root / DriveFS process is insufficient evidence of web copy.
  if(-not $GoogleClient){[void]$fail.Add("GOOGLE_DRIVE_CLIENT_NOT_OBSERVED")}
  if(-not $OneDriveClient){[void]$fail.Add("ONEDRIVE_CLIENT_NOT_OBSERVED")}
  return [ordered]@{
    result=$(if($fail.Count -eq 0){"DESTINATIONS_AND_SOURCE_DISCOVERED_REVIEW_REQUIRED"}else{"BLOCKED_DISCOVERY_REVIEW_REQUIRED"})
    reason_codes=@($fail|Select-Object -Unique)
    discovered_server_profile_count=$profiles.Count
    active_server_roots_found=@($profiles|Where-Object{$_.id -in @("wild","playground","lobby") -and $_.root_found}).Count
    other_server_operator_expected_offline=$true
    other_backend_actual_process_state_verified=$false
    provider_folder_identity_proven=$false
    onedrive_folder_matches_environment=$matchingOneDrive
    google_drive_client_process_observed=$GoogleClient
    onedrive_client_process_observed=$OneDriveClient
    claimed_google_quota_tb=2
    claimed_onedrive_quota_tb=1
    actual_cloud_free_quota_verified=$false
    actual_cloud_upload_verified=$false
    local_cloud_cache_disk_requirement_verified=$false
    minecraft_world_snapshot_consistency_verified=$false
    cloud_backup_created=$false
    restore_test_passed=$false
    stable_release_allowed=$false
    server_profiles=$profiles
  }
}
function Emit([object]$Data,[bool]$IsSynthetic,[string]$Dir) {
  $report=[ordered]@{
    schema=1;phase="12-cloud-disaster-recovery-preflight";read_only=$true
    generated_utc=(Get-Date).ToUniversalTime().ToString("o")
    synthetic=$IsSynthetic
    result=$Data.result;checks=$Data
    private_paths_exported=$false;credentials_exported=$false
    cloud_upload_performed=$false;server_backup_deleted_or_created=$false
    service_world_network_acl_firewall_changed=$false
    notes=@(
      "Folder discovery does not prove account ownership or that either cloud finished synchronizing.",
      "The user confirmed Google Drive 2TB / OneDrive 1TB subscription, NOT actual free bytes.",
      "All three currently online worlds must be consistently snapshotted; live file copy alone is NOT a valid rollback asset.",
      "Other backend is expected OFFLINE; this script never starts or stops it.",
      "World backups may contain tokens and player data: never paste archive/config into ChatGPT or commit to GitHub."
    )
  }
  $json=$report|ConvertTo-Json -Depth 12
  if($IsSynthetic){$json;return}
  if(-not $Dir){
    $desktop=[Environment]::GetFolderPath("Desktop")
    $Dir=Join-Path $desktop ("Geumyi-Cloud-Preflight-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
  }
  if(Test-Path -LiteralPath $Dir){throw "REFUSE_REUSE_REPORT_DIRECTORY"}
  [void](New-Item -ItemType Directory -Path $Dir -ErrorAction Stop)
  $file=Join-Path $Dir "DAY12-CLOUD-PREFLIGHT-SHARE-ONLY-THIS.json"
  [IO.File]::WriteAllText($file,$json,(New-Object Text.UTF8Encoding($false)))
  Write-Host ("Cloud recovery preflight: "+$Data.result)
  Write-Host ("Send ONLY: "+$file)
}
if($Synthetic){
  $cfg=[pscustomobject]@{status="CONFIG_READ_ONLY_PARSED";profiles=@(
    [pscustomobject]@{id="wild";root_found=$true},
    [pscustomobject]@{id="playground";root_found=$true},
    [pscustomobject]@{id="lobby";root_found=$true},
    [pscustomobject]@{id="other";root_found=$true}
  )}
  $good=Decide $cfg "G:\My Drive" "C:\Users\Fixture\OneDrive" @("C:\Users\Fixture\OneDrive") $true $true $true
  $badSource=Decide ([pscustomobject]@{status="CONFIG_UNAVAILABLE";profiles=@()}) "G:\My Drive" "C:\Users\Fixture\OneDrive" @("C:\Users\Fixture\OneDrive") $true $true $true
  $badSync=Decide $cfg "G:\My Drive" "C:\Users\Fixture\OneDrive" @("C:\Users\Fixture\OneDrive") $false $true $true
  $badOverlap=Decide $cfg "G:\My Drive" "G:\My Drive\OneDrive" @("G:\My Drive") $true $true $true
  if($good.result -ne "DESTINATIONS_AND_SOURCE_DISCOVERED_REVIEW_REQUIRED" -or
     $good.stable_release_allowed -or $good.cloud_backup_created -or
     $badSource.result -ne "BLOCKED_DISCOVERY_REVIEW_REQUIRED" -or
     $badSync.result -ne "BLOCKED_DISCOVERY_REVIEW_REQUIRED" -or
     $badOverlap.result -ne "BLOCKED_DISCOVERY_REVIEW_REQUIRED"){
    throw "CLOUD_PREFLIGHT_SYNTHETIC_FAIL_CLOSED_REGRESSION"
  }
  Write-Host "CLOUD_PREFLIGHT_SYNTHETIC_PASS"
  Emit $good $true ""
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "WINDOWS_SERVER_PC_ONLY"}
if($Interactive) {
  if(-not $GoogleDriveRoot){$GoogleDriveRoot=Select-ExistingFolder "Select Google Drive synced folder (My Drive) on this Windows PC"}
  if(-not $OneDriveRoot){$OneDriveRoot=Select-ExistingFolder "Select Microsoft OneDrive synced folder on this Windows PC"}
}
$google=CanonicalDirectory $GoogleDriveRoot
$microsoft=CanonicalDirectory $OneDriveRoot
$roots=@(Get-OneDriveCandidateRoots)
if(-not $ConfigPath){
  $ConfigPath=Join-Path $env:ProgramData "GeumyiServerCenter\server.json"
}
$cfg=InspectConfig $ConfigPath
$gProcess=@(Get-Process -Name "GoogleDriveFS" -ErrorAction SilentlyContinue).Count -gt 0
$mProcess=@(Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue).Count -gt 0
$svc=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
$hostRunning=($null -ne $svc -and $svc.Status -eq "Running")
$decision=Decide $cfg $google $microsoft $roots $gProcess $mProcess $hostRunning
Emit $decision $false $OutputDir
exit 0
