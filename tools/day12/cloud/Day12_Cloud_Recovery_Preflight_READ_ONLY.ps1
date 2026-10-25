[CmdletBinding()]
param(
  [switch]$Synthetic, [switch]$Interactive, [switch]$FunctionsOnly,
  [string]$GoogleDriveRoot='', [string]$OneDriveRoot='',
  [string]$ConfigPath='', [string]$OutputDir=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# v4: only metadata for exact paths; never enumerate a server/world directory.
# Raw API/config/registry/shell data stays in memory. BuildReport is an allowlist.
function Field($Object,[string]$Name,$Default=$null) {
  if($null -eq $Object){return $Default}
  if($Object -is [Collections.IDictionary]){
    if($Object.Contains($Name)){return ,$Object[$Name]};return $Default
  }
  $p=$Object.PSObject.Properties[$Name]
  if($null -ne $p){return ,$p.Value};return $Default
}
function Expand-PrivatePath([string]$Value) {
  $p=$Value.Trim().Trim([char]0xfeff).Trim().Trim('"').Trim()
  $p=[Environment]::ExpandEnvironmentVariables($p)
  # Host configuredServerDir uses Go os.ExpandEnv ($NAME and ${NAME}).
  $p=[regex]::Replace($p,'\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))',{
    param($m)
    $name=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
    $v=[Environment]::GetEnvironmentVariable($name)
    if($null -eq $v){return $m.Value};return $v
  })
  return $p
}
function Inspect-ExactPath([string]$Value,[bool]$Directory=$true) {
  $r=[ordered]@{status='EMPTY';path='';reparse=$false;final_target_verified=$false}
  if([string]::IsNullOrWhiteSpace($Value)){return $r}
  try {
    $p=Expand-PrivatePath $Value
    if($p -match '%[^%]+%|\$(?:\{|[A-Za-z_])'){$r.status='ENVIRONMENT_UNRESOLVED';return $r}
    # A relative path uses the Host working directory, NOT necessarily the
    # server.json directory or this operator's working directory. Never guess.
    if($p -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)'){
      $r.status='RELATIVE_HOST_CONTEXT_REQUIRED';return $r
    }
    $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    $r.reparse=($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if([bool]$i.PSIsContainer -ne $Directory){$r.status='WRONG_PATH_TYPE';return $r}
    $r.path=[IO.Path]::GetFullPath($i.FullName)
    $r.status=if($r.reparse){'ACCESSIBLE_REPARSE'}else{'ACCESSIBLE'}
  } catch [UnauthorizedAccessException] {$r.status='ACCESS_DENIED'}
    catch [System.Management.Automation.ItemNotFoundException] {$r.status='NOT_FOUND_OR_UNAVAILABLE'}
    catch {$r.status='METADATA_UNAVAILABLE'}
  return $r
}
function Read-SmallPrivateText([string]$Path) {
  # Explicit config/path pointer only. Never read a world or recurse.
  $reader=$null
  try {
    $reader=New-Object IO.StreamReader($Path,[Text.Encoding]::UTF8,$true)
    $buffer=New-Object char[] 1048577
    $count=$reader.ReadBlock($buffer,0,$buffer.Length)
    if($count -gt 1048576){return @{status='TEXT_TOO_LARGE';text=''}}
    return @{status='OK';text=(-join $buffer[0..([Math]::Max(0,$count-1))]).Trim([char]0)}
  } catch [UnauthorizedAccessException] {return @{status='ACCESS_DENIED';text=''}}
    catch {return @{status='READ_UNAVAILABLE';text=''}}
  finally {if($null -ne $reader){$reader.Dispose()}}
}
function Resolve-ServerProfile($Profile) {
  $direct=[string](Field $Profile 'path' '')
  $pointer=[string](Field $Profile 'path_file' '')
  $source='NO_CONFIGURED_PATH';$pointerStatus='NOT_USED';$candidate=''
  if(-not [string]::IsNullOrWhiteSpace($direct)){
    $source='DIRECT_PATH';$candidate=$direct
    # Match Host precedence: a nonempty direct path wins even if inaccessible.
    if($pointer){$pointerStatus='DIRECT_PATH_PRECEDENCE'}
  } elseif(-not [string]::IsNullOrWhiteSpace($pointer)){
    $source='PATH_FILE';$p=Inspect-ExactPath $pointer $false
    $pointerStatus=$p.status
    if($p.path){
      $text=Read-SmallPrivateText $p.path;$pointerStatus=$text.status
      if($text.status -eq 'OK'){$candidate=$text.text}
    }
  }
  $root=Inspect-ExactPath $candidate
  $marker='NOT_CHECKED'
  if($root.path){$marker=(Inspect-ExactPath (Join-Path $root.path 'server.properties') $false).status}
  return [ordered]@{source=$source;pointer_status=$pointerStatus;root=$root;server_properties_metadata=$marker}
}
function Parse-SettingsShape($Data) {
  # Source contract: main.go apiSettings => {servers:[{id,path,path_file,...}]}.
  # Explicit wrapper compatibility only; no recursive arbitrary key searching.
  $lists=@();$shapes=@()
  $top=Field $Data 'servers'
  if($null -ne $top){$lists+= ,$top;$shapes+='TOP_LEVEL_SERVERS'}
  foreach($wrapper in @('data','settings','config')){
    $inner=Field (Field $Data $wrapper) 'servers'
    if($null -ne $inner){$lists+= ,$inner;$shapes+=($wrapper.ToUpperInvariant()+'_SERVERS')}
  }
  if($lists.Count -eq 0){return @{status='NO_SERVER_LIST';profiles=@()}}
  if($lists.Count -ne 1){return @{status='AMBIGUOUS_SERVER_LIST';profiles=@()}}
  if($lists[0] -isnot [Array]){return @{status='INVALID_SERVER_LIST';profiles=@()}}
  return @{status=$shapes[0];profiles=@($lists[0])}
}
function Get-LocalSettings {
  $response=$null;$reader=$null
  try {
    $request=[Net.HttpWebRequest]::Create('http://127.0.0.1:8790/api/settings')
    $request.Method='GET';$request.Proxy=$null;$request.AllowAutoRedirect=$false
    $request.Timeout=5000;$request.ReadWriteTimeout=5000
    $response=$request.GetResponse()
    if([int]$response.StatusCode -ne 200){return @{status='HTTP_NOT_OK';shape='NOT_PARSED';profiles=@()}}
    $reader=New-Object IO.StreamReader($response.GetResponseStream())
    $buffer=New-Object char[] 1048577;$count=$reader.ReadBlock($buffer,0,$buffer.Length)
    if($count -gt 1048576){return @{status='RESPONSE_TOO_LARGE';shape='NOT_PARSED';profiles=@()}}
    $data=(-join $buffer[0..([Math]::Max(0,$count-1))]).Trim([char]0)|ConvertFrom-Json
    $parsed=Parse-SettingsShape $data
    return @{status='OK';shape=$parsed.status;profiles=$parsed.profiles}
  } catch {
    $status=if($null -ne $response){'API_JSON_OR_SCHEMA_INVALID'}else{'API_UNAVAILABLE'}
    $errorResponse=Field $_.Exception 'Response'
    if($null -ne $errorResponse){
      $code=[int]$errorResponse.StatusCode
      if($code -in @(401,403)){$status='API_READ_ACCESS_DENIED'}
      elseif($code -eq 404){$status='API_NOT_FOUND'}
      elseif($code -ge 300 -and $code -lt 400){$status='REDIRECT_REFUSED'}
      else{$status='API_RESPONSE_UNUSABLE'}
      $errorResponse.Close()
    }
    return @{status=$status;shape='NOT_PARSED';profiles=@()}
  } finally {if($reader){$reader.Dispose()};if($response){$response.Close()}}
}
function Read-Config([string]$Path) {
  $p=Inspect-ExactPath $Path $false
  if(-not $p.path){return @{status=$p.status;shape='NOT_PARSED';profiles=@()}}
  $text=Read-SmallPrivateText $p.path
  if($text.status -ne 'OK'){return @{status=$text.status;shape='NOT_PARSED';profiles=@()}}
  try {
    $parsed=Parse-SettingsShape ($text.text|ConvertFrom-Json)
    return @{status='OK';shape=$parsed.status;profiles=$parsed.profiles}
  } catch {return @{status='CONFIG_JSON_INVALID';shape='NOT_PARSED';profiles=@()}}
}
function Private-PathEquals([string]$A,[string]$B) {
  return $A.TrimEnd('\','/').Equals($B.TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)
}
function Private-PathInside([string]$Child,[string]$Parent) {
  if(-not $Child -or -not $Parent){return $false}
  return (Private-PathEquals $Child $Parent) -or $Child.StartsWith($Parent.TrimEnd('\','/')+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Inspect-Sources($Config,$Api) {
  $profiles=@();$roots=@()
  foreach($id in @('wild','playground','other','lobby')){
    $local=@($Config.profiles|Where-Object{[string](Field $_ 'id' '') -ceq $id})
    $remote=@($Api.profiles|Where-Object{[string](Field $_ 'id' '') -ceq $id})
    $c=Resolve-ServerProfile $(if($local.Count -eq 1){$local[0]}else{$null})
    $a=Resolve-ServerProfile $(if($remote.Count -eq 1){$remote[0]}else{$null})
    $chosen=$c;$method='CONFIG';$conflict=$false
    if($a.root.path){$chosen=$a;$method='LOCAL_SETTINGS_GET'}
    if($c.root.path -and $a.root.path -and -not (Private-PathEquals $c.root.path $a.root.path)){$conflict=$true}
    $duplicate=$local.Count -gt 1 -or $remote.Count -gt 1
    $found=[bool]$chosen.root.path -and -not $duplicate -and -not $conflict
    # Keep both internally for conservative overlap classification.
    if($c.root.path){$roots+=$c.root.path};if($a.root.path){$roots+=$a.root.path}
    $profiles+= [ordered]@{
      id=$id;expected_state=$(if($id -eq 'other'){'OFFLINE'}else{'ONLINE_OPERATOR_EXPECTATION'})
      config_profile_count=$local.Count;api_profile_count=$remote.Count
      root_found=$found;root_resolution_method=$method
      config_path_source=$c.source;config_path_status=$c.root.status;config_pointer_status=$c.pointer_status
      api_path_source=$a.source;api_path_status=$a.root.status;api_pointer_status=$a.pointer_status
      config_api_path_conflict=$conflict;duplicate_profile=$duplicate
      root_reparse_observed=$chosen.root.reparse;final_target_verified=$false
      server_properties_metadata=$chosen.server_properties_metadata
      root_bytes_estimated=$false;root_bytes=$null;quiescent_offline_snapshot_proven=$false
    }
  }
  return @{profiles=$profiles;internal_resolved_roots=$roots}
}
function Add-PrivateCandidate($Candidates,[string]$Path,[string]$Source) {
  if([string]::IsNullOrWhiteSpace($Path)){return}
  $p=Inspect-ExactPath $Path
  $existing=@($Candidates|Where-Object{Private-PathEquals $_.raw $Path})
  if($existing.Count -eq 0){[void]$Candidates.Add(@{raw=$Path;source=$Source;inspection=$p})}
}
function Read-OneDriveKnownFolder {
  try {
    if(-not ('Day12KnownFolderV4' -as [type])){
      Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Day12KnownFolderV4 {
  [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid id, uint flags, IntPtr token, out IntPtr path);
  public static string Read() {
    Guid id = new Guid("A52BBA46-E9E1-435f-B3D9-28DAA648C0F6"); IntPtr p;
    int hr = SHGetKnownFolderPath(ref id, 0x4000, IntPtr.Zero, out p);
    if (hr != 0) return "";
    try { return Marshal.PtrToStringUni(p); } finally { Marshal.FreeCoTaskMem(p); }
  }
}
'@
    }
    $v=[Day12KnownFolderV4]::Read()
    return $v
  } catch {return ''}
}
function Read-OneDriveShellRoot {
  $shellApp=$null;$folder=$null
  try {
    $shellApp=New-Object -ComObject Shell.Application
    $folder=$shellApp.NameSpace('shell:OneDrive')
    if($null -ne $folder){
      if($folder.Self.IsFileSystem){return @{status='OBSERVED';path=[string]$folder.Self.Path}}
      return @{status='NAMESPACE_ONLY';path=''}
    }
  } catch {} finally {
    if($folder){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($folder)}
    if($shellApp){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shellApp)}
  }
  return @{status='UNAVAILABLE';path=''}
}
function Get-OneDriveCandidates {
  $items=New-Object Collections.ArrayList
  $signals=[ordered]@{environment='ABSENT';known_folder='UNAVAILABLE';registry='ABSENT';shell_namespace='UNAVAILABLE'}
  foreach($name in @('OneDrive','OneDriveConsumer','OneDriveCommercial')){
    $v=[Environment]::GetEnvironmentVariable($name)
    if($v){$signals.environment='OBSERVED';Add-PrivateCandidate $items $v 'ENVIRONMENT'}
  }
  $v=Read-OneDriveKnownFolder
  if($v){$signals.known_folder='OBSERVED';Add-PrivateCandidate $items $v 'SHELL_KNOWN_FOLDER'}
  # Enumerate registry metadata only, bounded to immediate account/sync-root keys.
  try {
    $base='HKCU:\Software\Microsoft\OneDrive\Accounts'
    foreach($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue|Select-Object -First 32)){
      $v=[string](Field (Get-ItemProperty -LiteralPath $key.PSPath) 'UserFolder' '')
      if($v){$signals.registry='OBSERVED';Add-PrivateCandidate $items $v 'REGISTRY_ACCOUNT'}
    }
    $shell=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    foreach($name in @('{A52BBA46-E9E1-435f-B3D9-28DAA648C0F6}','OneDrive','SkyDrive')){
      $v=[string](Field $shell $name '')
      if($v){$signals.registry='OBSERVED';Add-PrivateCandidate $items $v 'REGISTRY_KNOWN_FOLDER'}
    }
    foreach($hive in @('HKCU:','HKLM:')){
      $base=$hive+'\Software\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager'
      foreach($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue|Where-Object{$_.PSChildName -like 'OneDrive!*'}|Select-Object -First 32)){
        $values=Get-ItemProperty -LiteralPath ($key.PSPath+'\UserSyncRoots') -ErrorAction SilentlyContinue
        if($null -eq $values){continue}
        foreach($property in $values.PSObject.Properties){
          if($property.Name -like 'PS*' -or $property.Value -isnot [string]){continue}
          $signals.registry='OBSERVED';Add-PrivateCandidate $items $property.Value 'REGISTRY_SYNC_ROOT'
        }
      }
    }
  } catch {$signals.registry='PARTIAL_OR_UNAVAILABLE'}
  $shellRoot=Read-OneDriveShellRoot;$signals.shell_namespace=$shellRoot.status
  if($shellRoot.path){Add-PrivateCandidate $items $shellRoot.path 'SHELL_NAMESPACE_FILESYSTEM'}
  return @{items=@($items.ToArray());signals=$signals}
}
function Select-ExistingFolder([string]$Description) {
  Add-Type -AssemblyName System.Windows.Forms
  $dlg=New-Object Windows.Forms.FolderBrowserDialog
  try {
    $dlg.Description=$Description;$dlg.ShowNewFolderButton=$false
    if($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){return [string]$dlg.SelectedPath}
    return ''
  } finally {$dlg.Dispose()}
}
function Choose-OneDrive($Candidates,[string]$Explicit,[bool]$Ask) {
  if($Explicit){return @{path=$Explicit;method='EXPLICIT_PATH';operator_confirmed=$false}}
  $available=@($Candidates.items|Where-Object{$_.inspection.path}|Group-Object {$_.inspection.path.ToUpperInvariant()})
  if($Ask -and $available.Count -gt 0){
    Write-Host 'Existing OneDrive filesystem candidates (shown locally only):'
    for($i=0;$i -lt $available.Count;$i++){Write-Host (('{0}: {1}' -f ($i+1),$available[$i].Group[0].inspection.path))}
    Write-Host 'Enter the number of your intended OneDrive folder to confirm, or Enter to browse. This does not verify the account or sync.'
    $answer=Read-Host;$n=0
    if([int]::TryParse($answer,[ref]$n) -and $n -ge 1 -and $n -le $available.Count){
      return @{path=$available[$n-1].Group[0].inspection.path;method='OPERATOR_CONFIRMED_CANDIDATE';operator_confirmed=$true}
    }
  }
  if($Ask){return @{path=(Select-ExistingFolder 'Select the EXISTING OneDrive filesystem folder');method='FOLDER_PICKER';operator_confirmed=$false}}
  return @{path='';method='NOT_SELECTED';operator_confirmed=$false}
}
function Inspect-ReportedVolume([string]$Path) {
  $r=[ordered]@{status='NOT_OBSERVED';filesystem_reported='UNKNOWN';reparse_supported=$true
    actual_backing_filesystem_verified=$false;volume_capacity_is_cloud_quota=$false
    reported_fat32_single_file_limit_bytes=$null;single_file_limit_enforcement_verified=$false
    greater_than_4gib_file_support_verified=$false;drivefs_emulation_possible=$true}
  if(-not $Path){return $r}
  try {
    $d=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($Path))
    $format=$d.DriveFormat.ToUpperInvariant()
    if($format -in @('NTFS','REFS','FAT32','EXFAT','FAT','FAT16')){$r.filesystem_reported=$format}else{$r.filesystem_reported='OTHER'}
    $r.status='WINDOWS_REPORTED_ONLY'
    if($format -eq 'FAT32'){$r.reported_fat32_single_file_limit_bytes=4294967295L}
  } catch {$r.status='VOLUME_METADATA_UNAVAILABLE'}
  return $r
}
function Classify-Volume($Volume) {
  if($Volume.filesystem_reported -eq 'FAT32'){return 'REPORTED_FAT32_VERIFY_ACTUAL_FILE_LIMIT_BEFORE_ARCHIVE'}
  return 'BACKING_FILESYSTEM_AND_LARGE_FILE_SUPPORT_UNVERIFIED'
}
function BuildReport($Config,$Api,$Sources,$Google,$Microsoft,$OneDrive,$Choice,[bool]$GoogleClient,[bool]$MicrosoftClient,[bool]$HostRunning,[bool]$IsSynthetic) {
  $reasons=New-Object Collections.ArrayList
  foreach($id in @('wild','playground','lobby')){
    if(@($Sources.profiles|Where-Object{$_.id -eq $id -and $_.root_found}).Count -ne 1){[void]$reasons.Add('ACTIVE_SERVER_ROOT_UNVERIFIED_'+$id.ToUpperInvariant())}
  }
  $other=@($Sources.profiles|Where-Object{$_.id -eq 'other'})
  if($other.Count -ne 1 -or ($other[0].config_profile_count -eq 0 -and $other[0].api_profile_count -eq 0)){
    [void]$reasons.Add('OTHER_EXPECTED_PROFILE_NOT_FOUND')
  }
  if(-not $Google.path){[void]$reasons.Add('GOOGLE_DRIVE_PATH_UNRESOLVED')}
  if(-not $Microsoft.path){[void]$reasons.Add('ONEDRIVE_PATH_UNRESOLVED')}
  if(-not $GoogleClient){[void]$reasons.Add('GOOGLE_DRIVE_CLIENT_NOT_OBSERVED')}
  if(-not $MicrosoftClient){[void]$reasons.Add('ONEDRIVE_CLIENT_NOT_OBSERVED')}
  $overlap=$false
  foreach($root in @($Sources.internal_resolved_roots)){
    foreach($cloud in @($Google.path,$Microsoft.path)){
      if((Private-PathInside $root $cloud) -or (Private-PathInside $cloud $root)){$overlap=$true}
    }
  }
  if((Private-PathInside $Google.path $Microsoft.path) -or (Private-PathInside $Microsoft.path $Google.path)){$overlap=$true}
  if($overlap){[void]$reasons.Add('LEXICAL_DESTINATION_OVERLAP')}
  $match=@($OneDrive.items|Where-Object{$_.inspection.path -and (Private-PathInside $Microsoft.path $_.inspection.path)}).Count -gt 0
  $volume=Inspect-ReportedVolume $Google.path
  $checks=[ordered]@{
    result=$(if($reasons.Count){'BLOCKED_DISCOVERY_REVIEW_REQUIRED'}else{'DESTINATIONS_AND_SOURCE_DISCOVERED_REVIEW_REQUIRED'})
    reason_codes=@($reasons.ToArray());gsc_config_status=$Config.status;gsc_config_shape=$Config.shape
    gsc_settings_local_readonly_status=$Api.status;gsc_settings_shape=$Api.shape
    gsc_host_service_running_observed=$HostRunning
    active_server_roots_found=@($Sources.profiles|Where-Object{$_.id -ne 'other' -and $_.root_found}).Count
    server_profiles=$Sources.profiles;other_server_operator_expected_offline=$true;other_backend_actual_process_state_verified=$false
    google_path_status=$Google.status;google_reparse_observed=$Google.reparse;google_reported_volume=$volume
    google_large_file_policy=(Classify-Volume $volume)
    onedrive_path_status=$Microsoft.status;onedrive_reparse_observed=$Microsoft.reparse
    onedrive_discovery_signals=$OneDrive.signals;onedrive_candidate_count=@($OneDrive.items).Count
    onedrive_accessible_candidate_count=@($OneDrive.items|Where-Object{$_.inspection.path}).Count
    onedrive_selection_method=$Choice.method;onedrive_operator_confirmed=$Choice.operator_confirmed
    onedrive_selected_path_matches_discovery=$match;provider_folder_identity_proven=$false
    google_drive_client_process_observed=$GoogleClient;onedrive_client_process_observed=$MicrosoftClient
    lexical_overlap_observed=$overlap;physical_overlap_verified=$false
    live_data_loss_detected=$false;live_data_loss_assessed=$false;world_consistency_proven=$false
    claimed_google_quota_tb=2;claimed_onedrive_quota_tb=1
    actual_cloud_free_quota_verified=$false;actual_cloud_upload_verified=$false
    local_cloud_cache_disk_requirement_verified=$false;minecraft_world_snapshot_consistency_verified=$false
    cloud_backup_created=$false;restore_test_passed=$false;stable_release_allowed=$false
  }
  return [ordered]@{
    schema=2;diagnostic_version=4;phase='12-cloud-disaster-recovery-preflight';read_only=$true
    generated_utc=[DateTime]::UtcNow.ToString('o');synthetic=$IsSynthetic;result=$checks.result;checks=$checks
    private_paths_exported=$false;server_root_paths_exported=$false;credentials_exported=$false
    cloud_upload_performed=$false;server_backup_deleted_or_created=$false;service_world_network_acl_firewall_changed=$false
    notes=@('Discovery failure does not establish missing worlds, stopped servers or data loss.',
      'Metadata accessibility, registry matches and operator confirmation do not verify cloud account identity or synchronization.',
      'Windows DriveFS volume capacity/free space is not the Google 2TB cloud quota. Local cache space remains unverified.',
      'Actual FAT32 limits one file to 4294967295 bytes; an emulated DriveFS format report does not prove enforcement. No test file was written.',
      'Other is intentionally OFFLINE. Previous backup was deleted; no current recovery archive is established.')
  }
}
function Emit-Report($Report,[string]$Dir) {
  $json=$Report|ConvertTo-Json -Depth 15
  if($Report.synthetic){$json;return}
  if(-not $Dir){
    # Avoid Desktop/Documents: they may themselves be OneDrive-synced.
    $Dir=Join-Path $env:LOCALAPPDATA ('Geumyi-ReadOnly-Diagnostics\v4-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
  }
  if(Test-Path -LiteralPath $Dir){throw 'REFUSE_REUSE_REPORT_DIRECTORY'}
  [void](New-Item -ItemType Directory -Path $Dir)
  $file=Join-Path $Dir 'DAY12-CLOUD-PREFLIGHT-V4-SHARE-ONLY-THIS.json'
  [IO.File]::WriteAllText($file,$json,(New-Object Text.UTF8Encoding($false)))
  Write-Host ('Cloud v4 read-only discovery: '+$Report.result)
  Write-Host ('Send ONLY: '+$file)
  if($Interactive){Start-Process -FilePath explorer.exe -ArgumentList ('"'+$Dir+'"')}
}
if($FunctionsOnly){return}
if($Synthetic){
  & (Join-Path $PSScriptRoot 'Test_Cloud_Preflight_V4.ps1')
  if(-not $?){throw 'CLOUD_PREFLIGHT_SYNTHETIC_FAILED'}
  exit 0
}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_SERVER_PC_ONLY'}
  if(-not $ConfigPath){$ConfigPath=Join-Path $env:ProgramData 'GeumyiServerCenter\server.json'}
  $config=Read-Config $ConfigPath
  # API still queried when config missing/unreadable; no early return.
  $api=Get-LocalSettings;$sources=Inspect-Sources $config $api
  $oneDrive=Get-OneDriveCandidates
  if($Interactive -and -not $GoogleDriveRoot){$GoogleDriveRoot=Select-ExistingFolder 'Select EXISTING Google Drive My Drive (G: virtual drive is supported)'}
  $choice=Choose-OneDrive $oneDrive $OneDriveRoot ([bool]$Interactive)
  $google=Inspect-ExactPath $GoogleDriveRoot;$microsoft=Inspect-ExactPath $choice.path
  $g=@(Get-Process -Name GoogleDriveFS -ErrorAction SilentlyContinue).Count -gt 0
  $m=@(Get-Process -Name OneDrive -ErrorAction SilentlyContinue).Count -gt 0
  $svc=Get-Service -Name 'Geumyi Server Center Host' -ErrorAction SilentlyContinue
  $hostRunning=$null -ne $svc -and $svc.Status -eq 'Running'
  Emit-Report (BuildReport $config $api $sources $google $microsoft $oneDrive $choice $g $m $hostRunning $false) $OutputDir
  exit 0
} catch {
  Write-Host 'V4_DIAGNOSTIC_RUNTIME_BLOCKED: No server or cloud changes were requested. Do not send raw config or error details.'
  exit 2
}
