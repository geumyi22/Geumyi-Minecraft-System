[CmdletBinding()]
param(
  [switch]$FunctionsOnly,
  [switch]$MeasureSourceMetadata,
  [ValidateRange(100,100000)][int]$MaxEntries=25000,
  [ValidateRange(5,180)][int]$MaxSeconds=45,
  [string]$ConfigPath='',
  [string]$OutputDir=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Day12 capacity-v1: read only, NO backup or sync operations.
# Uses v5's reviewed private-path resolver; exports counts only.
. (Join-Path $PSScriptRoot 'Day12_Cloud_Recovery_Plan_READ_ONLY.ps1') -FunctionsOnly

function Measure-MetadataTree([string]$Root,[int]$EntryLimit,[int]$SecondsLimit) {
  $stack=New-Object 'System.Collections.Generic.Stack[string]'
  $stack.Push($Root)
  $timer=[Diagnostics.Stopwatch]::StartNew()
  [decimal]$bytes=0
  $files=0;$dirs=0;$skipped=0;$visited=0;$failed=$false
  $reason='COMPLETE_METADATA_ONLY'
  # Reparse, OFFLINE and recall-on-access/open may be cloud placeholders.
  # Never open their content or descend through a nested reparse directory.
  $skipMask=0x00441400
  while($stack.Count -gt 0){
    if($timer.Elapsed.TotalSeconds -ge $SecondsLimit){$reason='TIME_BUDGET_EXCEEDED';break}
    if($visited -ge $EntryLimit){$reason='ENTRY_BUDGET_EXCEEDED';break}
    $directory=$stack.Pop()
    try {
      foreach($child in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)){
        if($timer.Elapsed.TotalSeconds -ge $SecondsLimit){$reason='TIME_BUDGET_EXCEEDED';break}
        if($visited -ge $EntryLimit){$reason='ENTRY_BUDGET_EXCEEDED';break}
        $visited++
        if(([long]$child.Attributes -band $skipMask) -ne 0){
          $skipped++;continue
        }
        if($child.PSIsContainer){
          $dirs++
          $stack.Push([string]$child.FullName)
        } else {
          $files++
          # FileInfo.Length reads metadata. Do not open file or hydrate data.
          $bytes += [decimal]$child.Length
        }
      }
      if($reason -ne 'COMPLETE_METADATA_ONLY'){break}
    } catch {
      $failed=$true;$reason='DIRECTORY_METADATA_UNAVAILABLE';break
    }
  }
  $timer.Stop()
  $complete=($reason -eq 'COMPLETE_METADATA_ONLY' -and $skipped -eq 0 -and -not $failed)
  if($skipped -gt 0 -and $reason -eq 'COMPLETE_METADATA_ONLY'){$reason='REPARSE_OR_CLOUD_ITEMS_SKIPPED'}
  return [ordered]@{
    status=$reason;complete=$complete;observed_bytes=[decimal]$bytes
    files_seen=$files;directories_seen=$dirs;excluded_reparse_or_cloud_items=$skipped
    entries_seen=$visited;bounded=$true;contents_opened=$false
  }
}
function Get-ReportedLocalVolume([string]$Directory) {
  $result=[ordered]@{status='NOT_CHECKED';windows_reported_free_bytes=$null
    windows_reported_total_bytes=$null;remote_provider_quota_verified=$false}
  if(-not $Directory){$result.status='DIRECTORY_UNAVAILABLE';return $result}
  try {
    $full=[IO.Path]::GetFullPath($Directory)
    $root=[IO.Path]::GetPathRoot($full)
    $info=New-Object IO.DriveInfo($root)
    if($info.DriveType -ne [IO.DriveType]::Fixed){
      $result.status='NOT_PROVEN_LOCAL_FIXED_VOLUME';return $result
    }
    if(-not $info.IsReady){$result.status='VOLUME_NOT_READY';return $result}
    $result.status='WINDOWS_LOCAL_VOLUME_REPORTED'
    $result.windows_reported_free_bytes=[decimal]$info.AvailableFreeSpace
    $result.windows_reported_total_bytes=[decimal]$info.TotalSize
  } catch {$result.status='VOLUME_METADATA_UNAVAILABLE'}
  return $result
}
function Build-CapacityReport($Records,[bool]$DoMeasure,[int]$Entries,[int]$Seconds,[string]$StagingDir) {
  $expected=@('wild','playground','other','lobby','gsc_state')
  $reasons=New-Object Collections.ArrayList
  $source=@()
  foreach($id in $expected){
    $matching=@($Records|Where-Object{$_.id -eq $id})
    $entry=[ordered]@{role=$id;status='NOT_SCANNED';root_reparse_observed=$false
      observed_bytes=$null;files_seen=0;directories_seen=0
      excluded_reparse_or_cloud_items=0;measurement_complete=$false}
    if($matching.Count -ne 1 -or -not $matching[0].path){
      $entry.status='UNVERIFIED_OR_AMBIGUOUS_ROOT'
      [void]$reasons.Add('SOURCE_ROOT_UNVERIFIED_'+$id.ToUpperInvariant())
    } else {
      $item=Inspect-LiteralDirectory $matching[0].path
      if(-not $item.path){
        $entry.status='SOURCE_ROOT_METADATA_UNAVAILABLE'
        [void]$reasons.Add('SOURCE_METADATA_UNAVAILABLE_'+$id.ToUpperInvariant())
      } else {
        $entry.root_reparse_observed=[bool]$item.reparse
        $entry.status='READY_NOT_MEASURED'
        if($DoMeasure){
          $measure=Measure-MetadataTree $item.path $Entries $Seconds
          $entry.status=$measure.status
          $entry.observed_bytes=$measure.observed_bytes
          $entry.files_seen=$measure.files_seen
          $entry.directories_seen=$measure.directories_seen
          $entry.excluded_reparse_or_cloud_items=$measure.excluded_reparse_or_cloud_items
          $entry.measurement_complete=$measure.complete
          if(-not $measure.complete){[void]$reasons.Add('INCOMPLETE_SOURCE_MEASUREMENT_'+$id.ToUpperInvariant())}
        }
      }
    }
    $source+=,$entry
  }
  # A role folder must not be counted twice through aliases/nested roots.
  # Source paths are held in memory only and never emitted.
  for($i=0;$i -lt $Records.Count;$i++){
    for($j=$i+1;$j -lt $Records.Count;$j++){
      if($Records[$i].id -eq $Records[$j].id){continue}
      $lexical=Path-Relation ([string]$Records[$i].path) ([string]$Records[$j].path)
      $normalized=Path-Relation ([string]$Records[$i].final_path) ([string]$Records[$j].final_path)
      if($lexical -ne 'SEPARATE' -or $normalized -ne 'SEPARATE'){
        [void]$reasons.Add('POSSIBLE_SOURCE_OVERLAP_OR_UNKNOWN')
      }
    }
  }
  $reasonCodes=@($reasons.ToArray()|Select-Object -Unique)
  $allMeasured=$DoMeasure -and $reasonCodes.Count -eq 0
  return [ordered]@{
    schema=1;phase='12.1-recovery-capacity-metadata';generated_utc=[DateTime]::UtcNow.ToString('o')
    read_only=$true;synthetic=$false
    result=$(if($allMeasured){'SOURCE_METADATA_MEASURED_REVIEW_REQUIRED'}else{'CAPACITY_REVIEW_INCOMPLETE'})
    reason_codes=$reasonCodes;per_root_max_entries=$Entries;per_root_max_seconds=$Seconds
    measurement_requested=$DoMeasure;source_metrics=$source
    local_staging_volume=(Get-ReportedLocalVolume $StagingDir)
    google_remote_quota_status='UNKNOWN_REQUIRES_PROVIDER_ACCOUNT_EVIDENCE'
    onedrive_remote_quota_status='UNKNOWN_REQUIRES_PROVIDER_ACCOUNT_EVIDENCE'
    google_drive_virtual_volume_is_not_cloud_quota=$true
    cloud_cache_usage_verified=$false;archive_compression_ratio_assumed=$false
    backup_or_snapshot_created=$false;cloud_upload_performed=$false;restore_test_passed=$false
    worlds_or_services_modified=$false;server_started_or_restarted=$false
    credentials_or_private_paths_exported=$false;source_file_contents_read=$false
    execution_authorized=$false;stable_release_allowed=$false
  }
}
if($FunctionsOnly){return}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
  if(-not $ConfigPath){$ConfigPath=Join-Path $env:ProgramData 'GeumyiServerCenter\server.json'}
  $config=Read-Config $ConfigPath
  $api=Get-LocalSettings
  $records=@(Get-PrivateSourceRecords $config $api $ConfigPath)
  $report=Build-CapacityReport $records ([bool]$MeasureSourceMetadata) $MaxEntries $MaxSeconds $env:LOCALAPPDATA
  # Diagnostics go to a new local, nonsynced location, NEVER a world/provider.
  if(-not $OutputDir){
    $OutputDir=Join-Path $env:LOCALAPPDATA ('Geumyi-ReadOnly-Diagnostics\capacity-v1-'+[guid]::NewGuid().ToString('N'))
  }
  if(Test-Path -LiteralPath $OutputDir){throw 'REFUSE_EXISTING_REPORT_DIRECTORY'}
  $onedrive=Get-OneDriveCandidates
  $groups=@($onedrive.items|Where-Object{$_.inspection.path}|Group-Object {$_.inspection.path.ToUpperInvariant()})
  if($groups.Count -ne 1){throw 'ONEDRIVE_CONTAINER_UNVERIFIED_FOR_REPORT_OUTPUT'}
  $google=Find-GoogleContainer '' $false
  if(-not (Report-LocationIsSeparate $OutputDir $records @($google.inspection,$groups[0].Group[0].inspection))){
    throw 'REPORT_OUTPUT_OVERLAP_OR_METADATA_UNVERIFIED'
  }
  [void](New-Item -Path $OutputDir -ItemType Directory -ErrorAction Stop)
  $out=Join-Path $OutputDir 'DAY12-CAPACITY-METADATA-V1-SHARE-ONLY-THIS.json'
  [IO.File]::WriteAllText($out,($report|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
  Write-Host ('CAPACITY_V1_STATUS='+$report.result)
  Write-Host ('SEND_ONLY='+$out)
} catch {
  Write-Host 'CAPACITY_V1_FAIL_CLOSED_NO_SERVER_CHANGE'
  exit 2
}
