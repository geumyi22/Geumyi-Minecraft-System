[CmdletBinding()]
param(
  [switch]$FunctionsOnly,
  [string]$ConfigPath='',
  [string]$OutputDir=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Exact-candidate metadata only: no candidate content reads or folder enumeration.
# Existing v4/v5 path resolver DOES read GSC config/path-pointer text in private memory.
# This is NOT an operational backup or a complete recovery configuration inventory.
$p0FunctionsOnly=[bool]$FunctionsOnly
$p0ConfigPath=$ConfigPath
$p0OutputDir=$OutputDir
. (Join-Path $PSScriptRoot 'Day12_Cloud_Recovery_Plan_READ_ONLY.ps1') -FunctionsOnly
$ConfigPath=$p0ConfigPath
$OutputDir=$p0OutputDir

function Inspect-P0Candidate([string]$Root,[string]$Relative) {
  if(-not $Root){return 'ROOT_NOT_VERIFIED'}
  if($Relative -notmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$' -or
     $Relative.Contains('..')){return 'UNSAFE_RELATIVE_NAME'}
  $chunks=$Relative.Split('/')
  $parent=$Root
  # A nested reparse directory could escape the previously vetted root.
  # Root itself may be a known OneDrive cloud reparse path; do not open file data.
  for($i=0;$i -lt ($chunks.Length-1);$i++){
    $parent=Join-Path $parent $chunks[$i]
    try {
      $intermediate=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
      if(-not $intermediate.PSIsContainer){return 'PARENT_NOT_DIRECTORY'}
      if(([long]$intermediate.Attributes -band 0x00441400) -ne 0){
        return 'NESTED_REPARSE_OR_CLOUD_PARENT_BLOCKED'
      }
    } catch [System.Management.Automation.ItemNotFoundException] {
      return 'PARENT_NOT_PRESENT'
    } catch {
      return 'PARENT_METADATA_UNAVAILABLE'
    }
  }
  $target=Join-Path $parent $chunks[$chunks.Length-1]
  try {
    $item=Get-Item -LiteralPath $target -Force -ErrorAction Stop
    if($item.PSIsContainer){return 'EXPECTED_FILE_IS_DIRECTORY'}
    if(([long]$item.Attributes -band 0x00441400) -ne 0){
      return 'CLOUD_OR_REPARSE_CONTENT_NOT_INSPECTED'
    }
    return 'LOCAL_FILE_METADATA_OBSERVED'
  } catch [System.Management.Automation.ItemNotFoundException] {
    return 'FILE_NOT_PRESENT'
  } catch [UnauthorizedAccessException] {
    return 'ACCESS_DENIED'
  } catch {
    return 'FILE_METADATA_UNAVAILABLE'
  }
}
function P0-Candidates([string]$Role) {
  if($Role -eq 'gsc_state'){
    return @(@{file='server.json';tier='REQUIRED';secret=$true})
  }
  $items=@(
    @{file='server.properties';tier='REQUIRED';secret=$true},
    @{file='bukkit.yml';tier='CONDITIONAL';secret=$false},
    @{file='spigot.yml';tier='CONDITIONAL';secret=$false},
    @{file='permissions.yml';tier='CONDITIONAL';secret=$false},
    @{file='ops.json';tier='CONDITIONAL';secret=$false},
    @{file='whitelist.json';tier='CONDITIONAL';secret=$false},
    @{file='banned-players.json';tier='CONDITIONAL';secret=$false},
    @{file='banned-ips.json';tier='CONDITIONAL';secret=$false},
    @{file='config/paper-global.yml';tier='CONDITIONAL';secret=$true},
    @{file='config/paper-world-defaults.yml';tier='CONDITIONAL';secret=$false},
    @{file='start.bat';tier='CONDITIONAL';secret=$true},
    @{file='start.cmd';tier='CONDITIONAL';secret=$true},
    @{file='eula.txt';tier='CONDITIONAL';secret=$false}
  )
  if($Role -in @('wild','other')){
    $items+=@(
      @{file='plugins/GeumyiTechnology/config.yml';tier='CONDITIONAL';secret=$true},
      @{file='plugins/GeumyiChemistry/config.yml';tier='CONDITIONAL';secret=$true}
    )
  }
  return $items
}
function Build-P0PresenceReport($SourceRecords) {
  $scopes=@('wild','playground','other','lobby','gsc_state')
  $out=@()
  $reasons=New-Object Collections.ArrayList
  foreach($role in $scopes){
    $records=@($SourceRecords|Where-Object{$_.id -eq $role})
    $rootStatus='UNVERIFIED'
    $privateRoot=''
    if($records.Count -eq 1 -and $records[0].path){
      $item=Inspect-LiteralDirectory ([string]$records[0].path)
      if($item.path){
        $rootStatus='EXACT_ROOT_METADATA_ACCESSIBLE'
        $privateRoot=$item.path
      }
    }
    if(-not $privateRoot){[void]$reasons.Add('SOURCE_ROOT_UNVERIFIED_'+$role.ToUpperInvariant())}
    $entries=@()
    foreach($candidate in @(P0-Candidates $role)){
      $status=Inspect-P0Candidate $privateRoot $candidate.file
      $entries+=@{name=$candidate.file;tier=$candidate.tier;
        may_contain_secrets=[bool]$candidate.secret;metadata_status=$status}
      if($candidate.tier -eq 'REQUIRED' -and $status -notin @(
          'LOCAL_FILE_METADATA_OBSERVED','CLOUD_OR_REPARSE_CONTENT_NOT_INSPECTED')){
        [void]$reasons.Add('REQUIRED_CONFIG_METADATA_UNVERIFIED_'+$role.ToUpperInvariant())
      }
    }
    $out+=@{role=$role;source_root_status=$rootStatus;candidate_files=$entries}
  }
  # v5 discovers Paper roots but not all three distinct live Velocity process roots.
  [void]$reasons.Add('THREE_VELOCITY_PROXY_ROOTS_AND_SECRETS_NOT_INVENTORIED')
  [void]$reasons.Add('CROSS_SERVER_PLUGIN_AND_RUNTIME_STATE_NOT_INVENTORIED')
  return [ordered]@{
    schema=1;phase='day12-P0-core-config-presence';generated_utc=[DateTime]::UtcNow.ToString('o')
    result='P0_PRESENCE_REVIEW_REQUIRED';read_only=$true
    paper_and_gsc_candidates=$out
    proxy_roles=@('public-java-25565','public-java-25566','public-java-25567')
    proxy_status='EXPLICIT_ROOT_MAPPING_REQUIRED'
    reason_codes=@($reasons.ToArray()|Select-Object -Unique)
    secret_values_exported=$false;absolute_paths_exported=$false
    candidate_file_content_bytes_opened=0;resolver_config_and_path_pointer_text_read_in_memory=$true
    source_folder_recursion_performed=$false
    cloud_placeholder_hydration_requested=$false
    backup_created=$false;encryption_performed=$false;upload_performed=$false
    server_or_sync_changed=$false;other_started=$false
    live_snapshot_consistency_verified=$false;restore_verified=$false
    p0_backup_allowed=$false;stable_release_allowed=$false
  }
}
if($p0FunctionsOnly){return}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
  if(-not $ConfigPath){$ConfigPath=Join-Path $env:ProgramData 'GeumyiServerCenter\server.json'}
  $config=Read-Config $ConfigPath
  $api=Get-LocalSettings
  $records=@(Get-PrivateSourceRecords $config $api $ConfigPath)
  $report=Build-P0PresenceReport $records
  if(-not $OutputDir){
    $OutputDir=Join-Path $env:LOCALAPPDATA ('Geumyi-ReadOnly-Diagnostics\p0-presence-'+[guid]::NewGuid().ToString('N'))
  }
  if(Test-Path -LiteralPath $OutputDir){throw 'REFUSE_EXISTING_REPORT_DIRECTORY'}
  $od=Get-OneDriveCandidates
  $groups=@($od.items|Where-Object{$_.inspection.path}|Group-Object {$_.inspection.path.ToUpperInvariant()})
  if($groups.Count -ne 1){throw 'ONEDRIVE_REPORT_EXCLUSION_UNVERIFIED'}
  $google=Find-GoogleContainer '' $false
  if(-not (Report-LocationIsSeparate $OutputDir $records @($google.inspection,$groups[0].Group[0].inspection))){
    throw 'REPORT_OUTPUT_LOCATION_UNVERIFIED'
  }
  [void](New-Item -ItemType Directory -Path $OutputDir -ErrorAction Stop)
  $file=Join-Path $OutputDir 'DAY12-P0-PRESENCE-V1-SHARE-ONLY-THIS.json'
  [IO.File]::WriteAllText($file,($report|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
  Write-Host ('P0_METADATA_STATUS='+$report.result)
  Write-Host ('SEND_ONLY='+$file)
} catch {
  Write-Host 'P0_METADATA_BLOCKED_NO_SOURCE_OR_CLOUD_CHANGE'
  exit 2
}
