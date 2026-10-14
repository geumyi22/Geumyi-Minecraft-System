[CmdletBinding()]
param(
  [switch]$Synthetic,[switch]$QuietSynthetic,[switch]$FunctionsOnly,[switch]$Interactive,
  [string]$GoogleDriveRoot='',[string]$OneDriveRoot='',
  [string]$StagingParent='',[string]$ConfigPath='',[string]$OutputDir=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Import reviewed v4 discovery FUNCTIONS only. Preserve this script's options.
$v5Options=@{}
foreach($key in @('Synthetic','QuietSynthetic','FunctionsOnly','Interactive','GoogleDriveRoot','OneDriveRoot','StagingParent','ConfigPath','OutputDir')){
  $v5Options[$key]=Get-Variable -Name $key -ValueOnly
}
. (Join-Path $PSScriptRoot 'Day12_Cloud_Recovery_Preflight_READ_ONLY.ps1') -FunctionsOnly
foreach($key in $v5Options.Keys){Set-Variable -Name $key -Value $v5Options[$key]}

function Path-Relation([string]$A,[string]$B) {
  if(-not $A -or -not $B){return 'UNKNOWN'}
  $a=$A.Replace('/','\').TrimEnd('\');$b=$B.Replace('/','\').TrimEnd('\')
  if($a.Equals($b,[StringComparison]::OrdinalIgnoreCase)){return 'EQUAL'}
  if($a.StartsWith($b+'\',[StringComparison]::OrdinalIgnoreCase)){return 'FIRST_WITHIN_SECOND'}
  if($b.StartsWith($a+'\',[StringComparison]::OrdinalIgnoreCase)){return 'SECOND_WITHIN_FIRST'}
  return 'SEPARATE'
}
function Get-MetadataFinalDirectory([string]$Path) {
  if(-not $Path){return @{status='UNAVAILABLE';path=''}}
  try {
    if(-not ('Day12DirectoryMetadataV5' -as [type])){
      Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Day12DirectoryMetadataV5 {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern SafeFileHandle CreateFileW(string name,uint access,uint sharing,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle,StringBuilder path,uint size,uint flags);
  public static string Read(string path) {
    // Zero desired access: metadata only; OPEN_EXISTING; no privileges enabled.
    // Full sharing, directory semantics and OPEN_NO_RECALL; no content reads.
    using(SafeFileHandle handle=CreateFileW(path,0,7,IntPtr.Zero,3,0x02100000,IntPtr.Zero)) {
      if(handle.IsInvalid) return "";
      StringBuilder result=new StringBuilder(1024);
      uint count=GetFinalPathNameByHandleW(handle,result,(uint)result.Capacity,2);
      if(count==0) return "";
      if(count >= result.Capacity) {
        if(count>32768) return "";
        result=new StringBuilder((int)count+1);
        count=GetFinalPathNameByHandleW(handle,result,(uint)result.Capacity,2);
        if(count==0 || count>=result.Capacity) return "";
      }
      return result.ToString();
    }
  }
}
'@
    }
    $final=[Day12DirectoryMetadataV5]::Read($Path)
    if($final){return @{status='NT_NORMALIZED';path=$final}}
  } catch {}
  return @{status='UNAVAILABLE';path=''}
}
function Inspect-LiteralDirectory([string]$Path) {
  # OS-discovered/selected paths are literal names, not config expressions.
  $r=@{status='EMPTY';path='';reparse=$false;final_target_verified=$false}
  if(-not $Path){return $r}
  if($Path -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)'){$r.status='RELATIVE_HOST_CONTEXT_REQUIRED';return $r}
  try {
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(-not $item.PSIsContainer){$r.status='WRONG_PATH_TYPE';return $r}
    $r.path=[IO.Path]::GetFullPath($item.FullName)
    $r.reparse=($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    $r.status=if($r.reparse){'ACCESSIBLE_REPARSE'}else{'ACCESSIBLE'}
  } catch [UnauthorizedAccessException] {$r.status='ACCESS_DENIED'}
    catch [System.Management.Automation.ItemNotFoundException] {$r.status='NOT_FOUND_OR_UNAVAILABLE'}
    catch {$r.status='METADATA_UNAVAILABLE'}
  return $r
}
function Plan-Candidate([string]$Parent,[string]$Leaf) {
  $r=@{path='';status='PARENT_UNAVAILABLE';final_path='';final_status='UNAVAILABLE'}
  # Fixed application-generated leaf only; no operator-controlled traversal.
  if($Leaf -notmatch '^Geumyi-Recovery-(Archives|Staging)-v5-[A-Za-z0-9-]+$'){
    $r.status='INVALID_PLAN_LEAF';return $r
  }
  $p=Inspect-LiteralDirectory $Parent
  if(-not $p.path){return $r}
  $r.path=Join-Path $p.path $Leaf
  try {
    [void](Get-Item -LiteralPath $r.path -Force -ErrorAction Stop)
    $r.status='PATH_ALREADY_EXISTS';return $r
  } catch [System.Management.Automation.ItemNotFoundException] {
    $r.status='PLANNED_NOT_CREATED'
  } catch {$r.status='CANDIDATE_METADATA_UNAVAILABLE';return $r}
  $final=Get-MetadataFinalDirectory $p.path
  if($final.path){
    $r.final_path=$final.path.TrimEnd('\')+'\'+$Leaf
    $r.final_status='PROJECTED_FROM_EXISTING_PARENT'
  }
  return $r
}
function Compare-PlannedPath($Candidate,$SourceRecord) {
  $lexical=Path-Relation $Candidate.path $SourceRecord.path
  $metadata=Path-Relation $Candidate.final_path $SourceRecord.final_path
  $overlap=@('EQUAL','FIRST_WITHIN_SECOND','SECOND_WITHIN_FIRST')
  return [ordered]@{lexical=$lexical;metadata=$metadata
    overlap_observed=($lexical -in $overlap -or $metadata -in $overlap)
    metadata_comparison_available=($metadata -ne 'UNKNOWN')}
}
function Get-PrivateSourceRecords($Config,$Api,[string]$ConfigFile) {
  $records=New-Object Collections.ArrayList
  foreach($packet in @($Config,$Api)){
    foreach($profile in $packet.profiles){
      $id=[string](Field $profile 'id' '')
      if($id -notin @('wild','playground','other','lobby')){continue}
      $resolved=Resolve-ServerProfile $profile
      if(-not $resolved.root.path){continue}
      if(@($records|Where-Object{$_.id -eq $id -and (Private-PathEquals $_.path $resolved.root.path)}).Count){continue}
      $final=Get-MetadataFinalDirectory $resolved.root.path
      [void]$records.Add(@{id=$id;path=$resolved.root.path;final_path=$final.path})
    }
  }
  $state=Inspect-LiteralDirectory (Split-Path -Parent $ConfigFile)
  if($state.path){
    $final=Get-MetadataFinalDirectory $state.path
    [void]$records.Add(@{id='gsc_state';path=$state.path;final_path=$final.path})
  }
  return @($records.ToArray())
}
function Find-GoogleContainer([string]$Explicit,[bool]$Ask) {
  if($Explicit){return @{inspection=(Inspect-LiteralDirectory $Explicit);method='EXPLICIT_CONTAINER';count=1}}
  if($Ask){return @{inspection=(Inspect-LiteralDirectory (Select-ExistingFolder 'Select EXISTING Google Drive archive parent (not a live server folder)'));method='FOLDER_PICKER';count=1}}
  # G: was explicitly identified in prior operator evidence. Its mount root is
  # an UNVERIFIED intended-provider candidate; no account directory inference.
  # Never enumerate its children or choose a system folder such as recycle bin.
  $root=Inspect-LiteralDirectory 'G:\'
  $method=if($root.path){'REFERENCED_G_MOUNT_ROOT_UNVERIFIED'}else{'G_CONTAINER_UNAVAILABLE'}
  return @{inspection=$root;method=$method;count=$(if($root.path){1}else{0})}
}
function Build-RecoveryPlan($Config,$Api,$SourceRecords,$GoogleParent,$OneDriveParent,$StagingParent,[string]$PlanId,[bool]$IsSynthetic) {
  $sources=Inspect-Sources $Config $Api
  $fail=New-Object Collections.ArrayList
  $containers=@(@{role='GOOGLE';item=$GoogleParent},@{role='ONEDRIVE';item=$OneDriveParent})
  $privateDestinations=@(
    @{role='GOOGLE_ARCHIVE';candidate=(Plan-Candidate $GoogleParent.path ('Geumyi-Recovery-Archives-v5-'+$PlanId))},
    @{role='ONEDRIVE_ARCHIVE';candidate=(Plan-Candidate $OneDriveParent.path ('Geumyi-Recovery-Archives-v5-'+$PlanId))},
    @{role='LOCAL_STAGING';candidate=(Plan-Candidate $StagingParent.path ('Geumyi-Recovery-Staging-v5-'+$PlanId))}
  )
  $containerRelations=@();$destinationRelations=@();$destinationPairs=@();$destinationSummaries=@();$stagingContainerRelations=@()
  $anyOverlap=$false;$allMetadata=$true
  $allowedRecords=@($SourceRecords|Where-Object{$_.id -in @('wild','playground','other','lobby','gsc_state')})
  foreach($container in $containers){
    $final=Get-MetadataFinalDirectory $container.item.path
    foreach($record in $allowedRecords){
      $containerRelations+= [ordered]@{id=$record.id;provider=$container.role
        lexical=(Path-Relation $record.path $container.item.path)
        metadata=(Path-Relation $record.final_path $final.path)}
    }
  }
  foreach($destination in $privateDestinations){
    $candidate=$destination.candidate
    $destinationSummaries+=[ordered]@{role=$destination.role;status=$candidate.status;metadata_projection_status=$candidate.final_status}
    if($candidate.status -ne 'PLANNED_NOT_CREATED'){[void]$fail.Add('CANDIDATE_NOT_AVAILABLE_'+$destination.role)}
    foreach($record in $allowedRecords){
      $relation=Compare-PlannedPath $candidate $record
      $destinationRelations+=[ordered]@{destination=$destination.role;id=$record.id
        lexical=$relation.lexical;metadata=$relation.metadata;overlap_observed=$relation.overlap_observed}
      if($relation.overlap_observed){$anyOverlap=$true}
      if(-not $relation.metadata_comparison_available){$allMetadata=$false}
    }
  }
  for($i=0;$i -lt $privateDestinations.Count;$i++){
    for($j=$i+1;$j -lt $privateDestinations.Count;$j++){
      $left=$privateDestinations[$i];$right=$privateDestinations[$j]
      $relation=Compare-PlannedPath $left.candidate $right.candidate
      $destinationPairs+=[ordered]@{first=$left.role;second=$right.role;lexical=$relation.lexical;metadata=$relation.metadata;overlap_observed=$relation.overlap_observed}
      if($relation.overlap_observed){$anyOverlap=$true}
      if(-not $relation.metadata_comparison_available){$allMetadata=$false}
    }
  }
  # Staging must be outside both entire provider containers, including aliases.
  foreach($container in $containers){
    $final=Get-MetadataFinalDirectory $container.item.path
    $relation=Compare-PlannedPath $privateDestinations[2].candidate @{path=$container.item.path;final_path=$final.path}
    $stagingContainerRelations+=[ordered]@{provider=$container.role;lexical=$relation.lexical;metadata=$relation.metadata;overlap_observed=$relation.overlap_observed}
    if($relation.overlap_observed){[void]$fail.Add('LOCAL_STAGING_WITHIN_OR_CONTAINS_'+$container.role);$anyOverlap=$true}
    if(-not $relation.metadata_comparison_available){$allMetadata=$false}
  }
  $active=@($sources.profiles|Where-Object{$_.id -ne 'other' -and $_.root_found}).Count
  if($active -ne 3){[void]$fail.Add('ACTIVE_SOURCE_PATHS_UNVERIFIED')}
  # A complete profile list is insufficient if an internal comparison record
  # was omitted. Require every accessible config/API root, including Other.
  foreach($id in @('wild','playground','other','lobby')){
    if(@($sources.profiles|Where-Object{$_.id -eq $id -and $_.root_found}).Count -ne 1){[void]$fail.Add('SOURCE_SCOPE_UNVERIFIED_'+$id.ToUpperInvariant())}
    if(@($allowedRecords|Where-Object{$_.id -eq $id -and $_.path}).Count -eq 0){[void]$fail.Add('SOURCE_COMPARISON_RECORD_MISSING_'+$id.ToUpperInvariant())}
  }
  foreach($packet in @($Config,$Api)){
    foreach($profile in $packet.profiles){
      $id=[string](Field $profile 'id' '')
      if($id -notin @('wild','playground','other','lobby')){continue}
      $root=(Resolve-ServerProfile $profile).root.path
      if($root -and @($allowedRecords|Where-Object{$_.id -eq $id -and (Private-PathEquals $_.path $root)}).Count -eq 0){
        [void]$fail.Add('SOURCE_COMPARISON_SCOPE_INCOMPLETE_'+$id.ToUpperInvariant())
      }
    }
  }
  $gscPresent=@($allowedRecords|Where-Object{$_.id -eq 'gsc_state'}).Count -gt 0
  if(-not $IsSynthetic -and -not $gscPresent){[void]$fail.Add('GSC_STATE_SCOPE_UNVERIFIED')}
  if($anyOverlap){[void]$fail.Add('ACTUAL_CANDIDATE_OVERLAP')}
  if(-not $allMetadata){[void]$fail.Add('METADATA_FINAL_PATH_COMPARISON_UNAVAILABLE')}
  $result=if($fail.Count){'BLOCKED_PLAN_REVIEW_REQUIRED'}else{'PLAN_PATHS_REVIEW_REQUIRED'}
  return [ordered]@{
    schema=3;diagnostic_version=5;phase='12-cloud-recovery-destination-and-consistency-plan'
    generated_utc=[DateTime]::UtcNow.ToString('o');synthetic=$IsSynthetic;read_only=$true
    result=$result;plan_reason_codes=@($fail.ToArray()|Select-Object -Unique);plan_id=$PlanId
    checks=[ordered]@{source_profile_count=@($sources.profiles|Where-Object{$_.config_profile_count -gt 0 -or $_.api_profile_count -gt 0}).Count
      active_server_roots_found=$active;gsc_state_protection_scope_present=$gscPresent
      all_candidates_planned_not_created=(@($privateDestinations|Where-Object{$_.candidate.status -ne 'PLANNED_NOT_CREATED'}).Count -eq 0)
      destination_overlap_observed=$anyOverlap;metadata_final_path_comparisons_available=$allMetadata
      physical_overlap_verified=$false;backup_execution_allowed=$false;cloud_backup_created=$false
      actual_cloud_upload_verified=$false;restore_test_passed=$false;stable_release_allowed=$false
      provider_identity_verified=$false;source_sizes_estimated=$false;capacity_sufficient_verified=$false
      snapshot_consistency_verified=$false;other_expected_offline=$true;other_writer_absence_verified=$false
      data_loss_assessed=$false;data_loss_detected=$false}
    gsc_config_status=$Config.status;gsc_api_status=$Api.status;server_profiles=$sources.profiles
    provider_container_relationships=$containerRelations;destinations=$destinationSummaries
    destination_source_relationships=$destinationRelations;destination_pair_relationships=$destinationPairs
    local_staging_container_relationships=$stagingContainerRelations
    google_reported_volume=(Inspect-ReportedVolume $GoogleParent.path)
    consistency_plan=@(
      @{id='wild';operator_expected_state='ONLINE';method='VERIFIED_GRACEFUL_OFFLINE_OR_PROVEN_APP_CONSISTENT_SNAPSHOT';executed=$false},
      @{id='playground';operator_expected_state='ONLINE';method='VERIFIED_GRACEFUL_OFFLINE_OR_PROVEN_APP_CONSISTENT_SNAPSHOT';executed=$false},
      @{id='lobby';operator_expected_state='ONLINE';method='VERIFIED_GRACEFUL_OFFLINE_OR_PROVEN_APP_CONSISTENT_SNAPSHOT';executed=$false},
      @{id='other';operator_expected_state='OFFLINE';method='KEEP_OFFLINE_VERIFY_NO_WRITERS';executed=$false})
    execution_blockers=@('EXECUTION_NOT_AUTHORIZED','CONSISTENT_SNAPSHOT_NOT_VERIFIED','ENCRYPTION_NOT_VERIFIED',
      'LOCAL_AND_CLOUD_CAPACITY_NOT_VERIFIED','PROVIDER_ACCOUNT_AND_SYNC_NOT_VERIFIED','RESTORE_NOT_VERIFIED',
      'SOURCE_PLACEHOLDERS_AND_EXTERNAL_STATE_NOT_VERIFIED','CROSS_SERVER_SHARED_STATE_NOT_VERIFIED')
    private_paths_exported=$false;credentials_exported=$false;destination_directories_created=$false
    server_backup_deleted_or_created=$false;cloud_upload_performed=$false;service_world_network_acl_firewall_changed=$false
    notes=@('Source inside a provider container is an observation, not actual archive destination overlap.',
      'Candidates are absent projected paths, not reserved or writable destinations; revalidate before any future write.',
      'Directory handles query metadata only. No source file content, world recursion, placeholder hydration or backup API is requested.',
      'A sibling archive in the same OneDrive account shares failure domains; independent Google copy and tested restore remain required.',
      'World save-off/save-all alone does not freeze plugin state. Existing GSC ZIP/hash flags are not encrypted cloud recovery proof.',
      'FAT32 is Windows-reported only. Actual large-file enforcement, DriveFS cache and cloud free quota remain unverified.')
  }
}
function Report-LocationIsSeparate([string]$Dir,$Records,[object[]]$Containers) {
  $Dir=[IO.Path]::GetFullPath($Dir)
  $parent=Split-Path -Parent $Dir
  $parts=New-Object Collections.ArrayList
  [void]$parts.Add((Split-Path -Leaf $Dir))
  for($attempt=0;$attempt -lt 32;$attempt++){
    $inspected=Inspect-LiteralDirectory $parent
    if($inspected.path){break}
    if($inspected.status -notin @('NOT_FOUND_OR_UNAVAILABLE','EMPTY')){return $false}
    $next=Split-Path -Parent $parent
    if(-not $next -or $next -eq $parent){return $false}
    [void]$parts.Insert(0,(Split-Path -Leaf $parent));$parent=$next
  }
  if(-not $inspected.path){return $false}
  $final=Get-MetadataFinalDirectory $inspected.path
  if(-not $final.path){return $false}
  $projected=$final.path.TrimEnd('\')+'\'+($parts -join '\')
  foreach($record in $Records){
    if((Path-Relation $Dir $record.path) -ne 'SEPARATE' -or (Path-Relation $projected $record.final_path) -ne 'SEPARATE'){return $false}
  }
  foreach($container in $Containers){
    if(-not $container.path){continue}
    $finalContainer=Get-MetadataFinalDirectory $container.path
    if(-not $finalContainer.path){return $false}
    if((Path-Relation $Dir $container.path) -ne 'SEPARATE'){return $false}
    if((Path-Relation $projected $finalContainer.path) -ne 'SEPARATE'){return $false}
  }
  return $true
}
function Emit-RecoveryPlan($Report,[string]$Dir,$Records=@(),[object[]]$Containers=@()) {
  if($Report.synthetic){$Report|ConvertTo-Json -Depth 16;return}
  if(-not $Dir){$Dir=Join-Path $env:LOCALAPPDATA ('Geumyi-ReadOnly-Diagnostics\plan-v5-'+$Report.plan_id)}
  if(Test-Path -LiteralPath $Dir){throw 'REFUSE_EXISTING_REPORT_DIRECTORY'}
  if(-not (Report-LocationIsSeparate $Dir $Records $Containers)){throw 'REPORT_LOCATION_UNVERIFIED_OR_OVERLAPPING'}
  [void](New-Item -ItemType Directory -Path $Dir)
  $file=Join-Path $Dir 'DAY12-CLOUD-RECOVERY-PLAN-V5-SHARE-ONLY-THIS.json'
  [IO.File]::WriteAllText($file,($Report|ConvertTo-Json -Depth 16),(New-Object Text.UTF8Encoding($false)))
  Write-Host ('Recovery v5: '+$Report.result)
  Write-Host ('Send ONLY: '+$file)
  if($Interactive){Start-Process -FilePath explorer.exe -ArgumentList ('"'+$Dir+'"')}
}
if($FunctionsOnly){return}
if($Synthetic){
  if($QuietSynthetic){& (Join-Path $PSScriptRoot 'Test_Cloud_Recovery_Plan_V5.ps1')|Out-Null}
  else{& (Join-Path $PSScriptRoot 'Test_Cloud_Recovery_Plan_V5.ps1')}
  if(-not $?){throw 'V5_SYNTHETIC_FAILED'}
  exit 0
}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
  if(-not $ConfigPath){$ConfigPath=Join-Path $env:ProgramData 'GeumyiServerCenter\server.json'}
  $config=Read-Config $ConfigPath;$api=Get-LocalSettings
  $records=@(Get-PrivateSourceRecords $config $api $ConfigPath)
  $google=Find-GoogleContainer $GoogleDriveRoot ([bool]$Interactive)
  $oneDrive=Get-OneDriveCandidates
  if($OneDriveRoot){$choice=@{path=$OneDriveRoot;method='EXPLICIT_CONTAINER'}}
  elseif($Interactive){$choice=Choose-OneDrive $oneDrive '' $true}
  else {
    $groups=@($oneDrive.items|Where-Object{$_.inspection.path}|Group-Object {$_.inspection.path.ToUpperInvariant()})
    $choice=@{path='';method='ONEDRIVE_CONTAINER_AMBIGUOUS_OR_UNAVAILABLE'}
    if($groups.Count -eq 1){$choice=@{path=$groups[0].Group[0].inspection.path;method='AUTO_SINGLE_DISCOVERY_UNVERIFIED'}}
  }
  if(-not $StagingParent){$StagingParent=$env:LOCALAPPDATA}
  $plan=Build-RecoveryPlan $config $api $records $google.inspection (Inspect-LiteralDirectory $choice.path) (Inspect-LiteralDirectory $StagingParent) ([guid]::NewGuid().ToString('N')) $false
  $plan['container_selection']=[ordered]@{google=$google.method;google_candidate_count=$google.count;onedrive=$choice.method;provider_identity_verified=$false}
  Emit-RecoveryPlan $plan $OutputDir $records @($google.inspection,(Inspect-LiteralDirectory $choice.path))
  exit 0
} catch {Write-Host 'V5_READ_ONLY_PLAN_RUNTIME_BLOCKED';exit 2}
