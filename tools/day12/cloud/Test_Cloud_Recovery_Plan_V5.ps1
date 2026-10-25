[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Day12_Cloud_Recovery_Plan_READ_ONLY.ps1') -FunctionsOnly

function Assert-V5($Condition,[string]$Code) {
  if(-not $Condition){throw ('V5_FIXTURE_FAILED_'+$Code)}
}
function Packet-V5($Profiles) {
  return @{status='OK';shape='TOP_LEVEL_SERVERS';profiles=@($Profiles)}
}
function Record-V5([string]$Id,[string]$Path) {
  $final=Get-MetadataFinalDirectory $Path
  return @{id=$Id;path=$Path;final_path=$final.path}
}
function Test-ReportPrivacyV5($Report,[string[]]$PrivateValues) {
  $json=$Report|ConvertTo-Json -Depth 20
  foreach($private in $PrivateValues){
    if(-not $private){continue}
    Assert-V5 (-not $json.Contains($private) -and -not $json.Contains($private.Replace('\','\\'))) 'PRIVATE_DATA_NOT_EXPORTED'
  }
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_FIXTURES_REQUIRED'}

$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+'\'
$sandbox=[IO.Path]::GetFullPath((Join-Path $tempRoot ('day12-v5-private-user-'+[guid]::NewGuid().ToString('N'))))
Assert-V5 ($sandbox.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) 'SANDBOX_BOUNDARY'
$files=New-Object Collections.ArrayList
$directories=New-Object Collections.ArrayList
$junction=''
$sample=$null
try {
  [void](New-Item -ItemType Directory -Path $sandbox)
  [void]$directories.Add($sandbox)
  $oneDrive=Join-Path $sandbox 'private-onedrive-account'
  $google=Join-Path $sandbox 'private-google-account'
  $staging=Join-Path $sandbox 'private-local-staging-parent'
  foreach($p in @($oneDrive,$google,$staging)){
    [void](New-Item -ItemType Directory -Path $p)
    [void]$directories.Add($p)
  }
  $servers=Join-Path $oneDrive 'Servers'
  [void](New-Item -ItemType Directory -Path $servers)
  [void]$directories.Add($servers)
  $profiles=@()
  $records=@()
  foreach($id in @('wild','playground','other','lobby')){
    $root=Join-Path $servers $id
    [void](New-Item -ItemType Directory -Path $root)
    [void]$directories.Add($root)
    $marker=Join-Path $root 'server.properties'
    [IO.File]::WriteAllText($marker,'private-token-sentinel-v5-do-not-export')
    [void]$files.Add($marker)
    $profiles+=@{id=$id;path=$root}
    $records+=Record-V5 $id $root
  }
  $source=$profiles[0].path
  $sourceMarker=Join-Path $source 'server.properties'
  $sourceHash=(Get-FileHash -LiteralPath $sourceMarker -Algorithm SHA256).Hash

  # Relationship classification is lexical, case-insensitive and boundary aware.
  Assert-V5 ((Path-Relation '' $source) -eq 'UNKNOWN') 'EMPTY_RELATION'
  Assert-V5 ((Path-Relation $source $source.ToUpperInvariant()) -eq 'EQUAL') 'CASE_EQUAL'
  Assert-V5 ((Path-Relation ($source+'\') ($source.Replace('\','/')+'/')) -eq 'EQUAL') 'SLASH_AND_TRAILING_NORMALIZATION'
  Assert-V5 ((Path-Relation ($source+'\candidate') $source) -eq 'FIRST_WITHIN_SECOND') 'FIRST_WITHIN_SECOND'
  Assert-V5 ((Path-Relation $source ($source+'\candidate')) -eq 'SECOND_WITHIN_FIRST') 'SECOND_WITHIN_FIRST'
  Assert-V5 ((Path-Relation ($source+'-backup') $source) -eq 'SEPARATE') 'PREFIX_BOUNDARY'
  Assert-V5 ((Path-Relation 'C:\' 'c:/') -eq 'EQUAL') 'DRIVE_ROOT_EQUAL'
  Assert-V5 ((Path-Relation '\\fixture-server\share\source' '\\fixture-server\share\source-other') -eq 'SEPARATE') 'UNC_PREFIX_BOUNDARY'

  # Existing directory handles establish metadata path identity without a scan.
  $sourceFinal=Get-MetadataFinalDirectory $source
  Assert-V5 ($sourceFinal.status -eq 'NT_NORMALIZED' -and $sourceFinal.path) 'WINDOWS_METADATA_FINAL_PATH'
  $junction=Join-Path $sandbox 'private-junction-alias'
  [void](New-Item -ItemType Junction -Path $junction -Target $source)
  $aliasFinal=Get-MetadataFinalDirectory $junction
  Assert-V5 ($aliasFinal.status -eq 'NT_NORMALIZED' -and (Path-Relation $aliasFinal.path $sourceFinal.path) -eq 'EQUAL') 'JUNCTION_METADATA_ALIAS'
  $unavailable=Get-MetadataFinalDirectory (Join-Path $sandbox 'absent-directory')
  Assert-V5 ($unavailable.status -eq 'UNAVAILABLE' -and -not $unavailable.path) 'MISSING_METADATA_FINAL_PATH'

  $leaf='Geumyi-Recovery-Archives-v5-fixture'
  $candidate=Plan-Candidate $oneDrive $leaf
  Assert-V5 ($candidate.status -eq 'PLANNED_NOT_CREATED' -and -not (Test-Path -LiteralPath $candidate.path)) 'CANDIDATE_NOT_CREATED'
  Assert-V5 ($candidate.final_status -eq 'PROJECTED_FROM_EXISTING_PARENT' -and $candidate.final_path) 'CANDIDATE_METADATA_PROJECTION'
  $separate=Compare-PlannedPath $candidate $records[0]
  Assert-V5 ($separate.lexical -eq 'SEPARATE' -and $separate.metadata -eq 'SEPARATE' -and -not $separate.overlap_observed -and $separate.metadata_comparison_available) 'SIBLING_DESTINATION_SEPARATE'
  $nestedCandidate=Plan-Candidate $source $leaf
  $nested=Compare-PlannedPath $nestedCandidate $records[0]
  Assert-V5 ($nested.lexical -eq 'FIRST_WITHIN_SECOND' -and $nested.overlap_observed) 'ACTUAL_DESTINATION_WITHIN_SOURCE'
  $equal=Compare-PlannedPath @{path=$source;final_path=$sourceFinal.path} $records[0]
  Assert-V5 ($equal.lexical -eq 'EQUAL' -and $equal.overlap_observed) 'ACTUAL_DESTINATION_EQUALS_SOURCE'
  $ancestorFinal=Get-MetadataFinalDirectory $servers
  $ancestor=Compare-PlannedPath @{path=$servers;final_path=$ancestorFinal.path} $records[0]
  Assert-V5 ($ancestor.lexical -eq 'SECOND_WITHIN_FIRST' -and $ancestor.overlap_observed) 'ACTUAL_DESTINATION_CONTAINS_SOURCE'
  $aliasCandidate=Plan-Candidate $junction $leaf
  $aliasComparison=Compare-PlannedPath $aliasCandidate $records[0]
  Assert-V5 ($aliasComparison.lexical -eq 'SEPARATE' -and $aliasComparison.metadata -eq 'FIRST_WITHIN_SECOND' -and $aliasComparison.overlap_observed) 'PHYSICAL_ALIAS_NOT_LEXICALLY_VISIBLE'
  $unknown=Compare-PlannedPath @{path=$candidate.path;final_path=''} @{path=$source;final_path=''}
  Assert-V5 ($unknown.metadata -eq 'UNKNOWN' -and -not $unknown.metadata_comparison_available) 'UNAVAILABLE_METADATA_NOT_PROOF'

  $existingFolderLeaf='Geumyi-Recovery-Staging-v5-existing-folder'
  $existingFolder=Join-Path $staging $existingFolderLeaf
  [void](New-Item -ItemType Directory -Path $existingFolder)
  [void]$directories.Add($existingFolder)
  $existingFileLeaf='Geumyi-Recovery-Staging-v5-existing-file'
  $existingFile=Join-Path $staging $existingFileLeaf
  [IO.File]::WriteAllText($existingFile,'private-existing-file-sentinel')
  [void]$files.Add($existingFile)
  $existingHash=(Get-FileHash -LiteralPath $existingFile -Algorithm SHA256).Hash
  Assert-V5 ((Plan-Candidate $staging $existingFolderLeaf).status -eq 'PATH_ALREADY_EXISTS') 'EXISTING_FOLDER_REFUSED'
  Assert-V5 ((Plan-Candidate $staging $existingFileLeaf).status -eq 'PATH_ALREADY_EXISTS') 'EXISTING_FILE_REFUSED'
  Assert-V5 ((Plan-Candidate (Join-Path $sandbox 'missing-parent') $leaf).status -eq 'PARENT_UNAVAILABLE') 'MISSING_PARENT_REFUSED'
  foreach($invalidLeaf in @('existing-folder','..\escape','Geumyi-Recovery-Archives-v5-..\escape','Geumyi-Recovery-Staging-v5-','Geumyi-Recovery-Archives-v5-fixture/escape')){
    $invalid=Plan-Candidate $staging $invalidLeaf
    Assert-V5 ($invalid.status -eq 'INVALID_PLAN_LEAF' -and -not $invalid.path -and -not $invalid.final_path) 'INVALID_CANDIDATE_LEAF_REFUSED'
  }

  # Deterministic denial: no production ACL or account changes are needed.
  $deniedLeaf='Geumyi-Recovery-Staging-v5-metadata-denied-candidate'
  $deniedPath=Join-Path $staging $deniedLeaf
  try {
    function Get-Item {
      [CmdletBinding()]
      param([string]$LiteralPath,[switch]$Force)
      if($LiteralPath -eq $deniedPath){throw (New-Object UnauthorizedAccessException 'fixture-denied-private-path')}
      return Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath -Force:$Force
    }
    $denied=Plan-Candidate $staging $deniedLeaf
    Assert-V5 ($denied.status -eq 'CANDIDATE_METADATA_UNAVAILABLE') 'DENIED_CANDIDATE_CATEGORICAL'
  } finally {Remove-Item -LiteralPath function:Get-Item}
  Assert-V5 (-not (Test-Path -LiteralPath $deniedPath)) 'DENIED_CANDIDATE_NOT_CREATED'

  # The referenced G: mount is inspected as one exact metadata path, never
  # inferred from its system/internal children. This mock performs no I/O.
  $googleMountFixtureCalls=0
  $googleMountFixtureAccessible=$true
  $literalInspector=(Get-Item -LiteralPath function:Inspect-LiteralDirectory).ScriptBlock
  try {
    function Inspect-LiteralDirectory([string]$Value) {
      Assert-V5 ($Value -eq 'G:\') 'GOOGLE_MOCK_REFERENCED_MOUNT_ONLY'
      $script:googleMountFixtureCalls++
      if($script:googleMountFixtureAccessible){return @{status='ACCESSIBLE';path='G:\';reparse=$false;final_target_verified=$false}}
      return @{status='NOT_FOUND_OR_UNAVAILABLE';path='';reparse=$false;final_target_verified=$false}
    }
    $referencedGoogle=Find-GoogleContainer '' $false
    Assert-V5 ($referencedGoogle.method -eq 'REFERENCED_G_MOUNT_ROOT_UNVERIFIED' -and $referencedGoogle.inspection.path -eq 'G:\') 'REFERENCED_GOOGLE_MOUNT_IS_UNVERIFIED'
    $googleMountFixtureAccessible=$false
    $missingMount=Find-GoogleContainer '' $false
    Assert-V5 (-not $missingMount.inspection.path) 'UNAVAILABLE_GOOGLE_MOUNT_NO_CANDIDATE'
    Assert-V5 ($googleMountFixtureCalls -eq 2) 'GOOGLE_DISCOVERY_ONLY_MOCKED_METADATA_READS'
  } finally {Set-Item -LiteralPath function:Inspect-LiteralDirectory -Value $literalInspector}

  # Provider and selected paths are OS literal names; $ and % are legal name
  # characters here rather than environment expressions from GSC config.
  $literalFolder=Join-Path $staging '$literal%PATH%-folder'
  [void](New-Item -ItemType Directory -Path $literalFolder)
  [void]$directories.Add($literalFolder)
  $literalInspection=Inspect-LiteralDirectory $literalFolder
  Assert-V5 ($literalInspection.status -eq 'ACCESSIBLE' -and (Private-PathEquals $literalInspection.path $literalFolder)) 'LITERAL_DOLLAR_PERCENT_DIRECTORY_METADATA'
  $literalCandidate=Plan-Candidate $literalFolder $leaf
  Assert-V5 ($literalCandidate.status -eq 'PLANNED_NOT_CREATED' -and (Private-PathEquals $literalCandidate.path (Join-Path $literalFolder $leaf))) 'LITERAL_DOLLAR_PERCENT_CANDIDATE_PARENT'
  Assert-V5 (-not (Test-Path -LiteralPath $literalCandidate.path)) 'LITERAL_CANDIDATE_NEVER_CREATED'
  $explicitGoogle=Find-GoogleContainer $literalFolder $false
  Assert-V5 ($explicitGoogle.method -eq 'EXPLICIT_CONTAINER' -and (Private-PathEquals $explicitGoogle.inspection.path $literalFolder)) 'EXPLICIT_GOOGLE_LITERAL_CONTAINER'

  $config=Packet-V5 $profiles
  $api=Packet-V5 $profiles
  $googleParent=Inspect-ExactPath $google
  $oneDriveParent=Inspect-ExactPath $oneDrive
  # The dot-sourced CLI owns a typed string $StagingParent parameter.
  $stagingInspection=Inspect-ExactPath $staging
  $sample=Build-RecoveryPlan $config $api $records $googleParent $oneDriveParent $stagingInspection 'fixture' $true
  Assert-V5 ($sample.schema -eq 3 -and $sample.diagnostic_version -eq 5 -and $sample.synthetic -and $sample.read_only) 'REPORT_SCHEMA'
  Assert-V5 ($sample.result -eq 'PLAN_PATHS_REVIEW_REQUIRED' -and $sample.checks.active_server_roots_found -eq 3 -and $sample.checks.source_profile_count -eq 4) 'DISCOVERED_PLAN_ONLY'
  Assert-V5 ($sample.checks.all_candidates_planned_not_created -and -not $sample.checks.destination_overlap_observed) 'PROVIDER_CONTAINER_IS_NOT_DESTINATION'
  $contained=@($sample.provider_container_relationships|Where-Object{$_.id -eq 'wild' -and $_.lexical -eq 'FIRST_WITHIN_SECOND'})
  Assert-V5 ($contained.Count -eq 1) 'SOURCE_WITHIN_ONEDRIVE_OBSERVED'
  Assert-V5 (@($sample.destinations).Count -eq 3) 'THREE_CANDIDATE_DESTINATIONS'
  Assert-V5 (@($sample.destinations|Where-Object{$_.status -ne 'PLANNED_NOT_CREATED' -or $_.metadata_projection_status -ne 'PROJECTED_FROM_EXISTING_PARENT'}).Count -eq 0) 'DESTINATIONS_PLANNED_NOT_CREATED'
  foreach($role in @('GOOGLE_ARCHIVE','ONEDRIVE_ARCHIVE','LOCAL_STAGING')){
    Assert-V5 (@($sample.destinations|Where-Object{$_.role -eq $role}).Count -eq 1) ('DESTINATION_ROLE_'+$role)
  }
  foreach($gate in @('backup_execution_allowed','cloud_backup_created','actual_cloud_upload_verified','restore_test_passed','stable_release_allowed','physical_overlap_verified')){
    Assert-V5 (-not $sample.checks[$gate]) ('FALSE_CLAIM_'+$gate)
  }
  foreach($blocker in @('EXECUTION_NOT_AUTHORIZED','CONSISTENT_SNAPSHOT_NOT_VERIFIED','ENCRYPTION_NOT_VERIFIED','LOCAL_AND_CLOUD_CAPACITY_NOT_VERIFIED','PROVIDER_ACCOUNT_AND_SYNC_NOT_VERIFIED','RESTORE_NOT_VERIFIED','SOURCE_PLACEHOLDERS_AND_EXTERNAL_STATE_NOT_VERIFIED','CROSS_SERVER_SHARED_STATE_NOT_VERIFIED')){
    Assert-V5 ($sample.execution_blockers -contains $blocker) ('EXECUTION_BLOCKER_'+$blocker)
  }

  $duplicateRecords=@($records)+@($records)
  $dedup=Build-RecoveryPlan $config $api $duplicateRecords $googleParent $oneDriveParent $stagingInspection 'duplicate' $true
  Assert-V5 ($dedup.checks.source_profile_count -eq 4 -and $dedup.checks.active_server_roots_found -eq 3) 'SOURCE_ROLE_DEDUPLICATION'
  $overlap=Build-RecoveryPlan $config $api $records (Inspect-ExactPath $source) $oneDriveParent $stagingInspection 'nested' $true
  Assert-V5 ($overlap.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED' -and $overlap.checks.destination_overlap_observed) 'DESTINATION_OVERLAP_BLOCKED'
  $providerOverlap=Build-RecoveryPlan $config $api $records $oneDriveParent $oneDriveParent $stagingInspection 'same-provider-parent' $true
  Assert-V5 ($providerOverlap.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED' -and $providerOverlap.checks.destination_overlap_observed) 'SAME_PROVIDER_DESTINATIONS_BLOCKED'
  $aliasOverlap=Build-RecoveryPlan $config $api $records (Inspect-ExactPath $junction) $oneDriveParent $stagingInspection 'alias' $true
  Assert-V5 ($aliasOverlap.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED' -and $aliasOverlap.checks.destination_overlap_observed) 'JUNCTION_ALIAS_PLAN_BLOCKED'
  $noParent=Build-RecoveryPlan $config $api $records (Inspect-ExactPath '') $oneDriveParent $stagingInspection 'missing' $true
  Assert-V5 ($noParent.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED' -and -not $noParent.checks.all_candidates_planned_not_created) 'MISSING_PARENT_PLAN_BLOCKED'
  $conflictProfiles=@($profiles|ForEach-Object{@{id=$_.id;path=$_.path}})
  $conflictProfiles[0].path=$google
  $conflict=Build-RecoveryPlan $config (Packet-V5 $conflictProfiles) (@($records)+@(Record-V5 'wild' $google)) $googleParent $oneDriveParent $stagingInspection 'conflict' $true
  Assert-V5 ($conflict.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED' -and $conflict.checks.active_server_roots_found -eq 2 -and $conflict.checks.destination_overlap_observed) 'CONFLICTING_SOURCE_ROOTS_CONSERVATIVE'

  # Source discovery cannot substitute for absent overlap-comparison records.
  $noRecords=Build-RecoveryPlan $config $api @() $googleParent $oneDriveParent $stagingInspection 'no-records' $true
  Assert-V5 ($noRecords.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED') 'NO_SOURCE_RECORDS_BLOCKED'
  $missingRecords=@()
  foreach($id in @('wild','playground','other','lobby')){
    $incomplete=@($records|Where-Object{$_.id -ne $id})
    $missing=Build-RecoveryPlan $config $api $incomplete $googleParent $oneDriveParent $stagingInspection ('missing-'+$id) $true
    Assert-V5 ($missing.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED') ('MISSING_SOURCE_RECORD_BLOCKED_'+$id)
    $missingRecords+=$missing
  }
  $noGsc=Build-RecoveryPlan $config $api $records $googleParent $oneDriveParent $stagingInspection 'no-gsc-state' $false
  Assert-V5 ($noGsc.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED' -and -not $noGsc.checks.gsc_state_protection_scope_present -and $noGsc.plan_reason_codes -contains 'GSC_STATE_SCOPE_UNVERIFIED') 'NONSYNTHETIC_GSC_STATE_REQUIRED'
  $wrongRecords=@($records|Where-Object{$_.id -ne 'wild'})+@(Record-V5 'wild' $staging)
  $wrongScope=Build-RecoveryPlan $config $api $wrongRecords $googleParent $oneDriveParent $stagingInspection 'wrong-scope' $true
  Assert-V5 ($wrongScope.result -eq 'BLOCKED_PLAN_REVIEW_REQUIRED') 'WRONG_SOURCE_RECORD_PATH_BLOCKED'
  $gscRecord=Record-V5 'gsc_state' $servers
  $completeLive=Build-RecoveryPlan $config $api (@($records)+@($gscRecord)) $googleParent $oneDriveParent $stagingInspection 'complete-scope' $false
  Assert-V5 ($completeLive.checks.gsc_state_protection_scope_present -and $completeLive.result -eq 'PLAN_PATHS_REVIEW_REQUIRED') 'COMPLETE_PROTECTED_SCOPE_PLAN_ONLY'
  Assert-V5 (-not $completeLive.checks.backup_execution_allowed -and -not $completeLive.checks.stable_release_allowed) 'COMPLETE_SCOPE_IS_NOT_EXECUTION_APPROVAL'

  foreach($report in (@($sample,$dedup,$overlap,$providerOverlap,$aliasOverlap,$noParent,$conflict,$noRecords,$noGsc,$wrongScope,$completeLive)+$missingRecords)){
    Test-ReportPrivacyV5 $report @($sandbox,$source,$sourceFinal.path,$junction,'private-user','private-onedrive-account','private-google-account','private-token-sentinel','fixture-denied-private-path','C:\Users\')
  }

  # The categorical output directory also stays outside protected/provider
  # roots. This only projects an absent report path; it performs no writes.
  $reportContainers=@($googleParent,$oneDriveParent)
  $safeReport=Join-Path $staging 'new-report'
  $safeNestedReport=Join-Path $staging 'absent-parent\new-report'
  Assert-V5 (Report-LocationIsSeparate $safeReport $records $reportContainers) 'REPORT_LOCATION_SEPARATE'
  Assert-V5 (Report-LocationIsSeparate $safeNestedReport $records $reportContainers) 'REPORT_LOCATION_PROJECTED_ANCESTOR'
  Assert-V5 (Report-LocationIsSeparate (Join-Path $literalFolder 'new-report') $records $reportContainers) 'REPORT_LOCATION_LITERAL_ANCESTOR'
  Assert-V5 (-not (Report-LocationIsSeparate (Join-Path $source 'new-report') $records $reportContainers)) 'REPORT_LOCATION_INSIDE_SOURCE_REFUSED'
  Assert-V5 (-not (Report-LocationIsSeparate (Join-Path $junction 'new-report') $records $reportContainers)) 'REPORT_LOCATION_INSIDE_ALIAS_REFUSED'
  foreach($provider in @($google,$oneDrive)){
    Assert-V5 (-not (Report-LocationIsSeparate (Join-Path $provider 'new-report') $records $reportContainers)) 'REPORT_LOCATION_INSIDE_PROVIDER_REFUSED'
  }
  Assert-V5 (-not (Report-LocationIsSeparate $safeReport @(@{id='wild';path=$source;final_path=''}) $reportContainers)) 'REPORT_LOCATION_UNKNOWN_SOURCE_METADATA_REFUSED'
  # A lexically separate report is still unverified if any present provider
  # root has no final native metadata path. Do not turn UNKNOWN into proof.
  $reportMetadataUnavailablePath=$oneDrive
  $originalMetadataReader=(Get-Item -LiteralPath function:Get-MetadataFinalDirectory).ScriptBlock
  try {
    function Get-MetadataFinalDirectory([string]$Path) {
      if(Private-PathEquals $Path $script:reportMetadataUnavailablePath){return @{status='UNAVAILABLE';path=''}}
      return & $script:originalMetadataReader $Path
    }
    Assert-V5 ((Path-Relation $safeReport $oneDrive) -eq 'SEPARATE') 'REPORT_PROVIDER_METADATA_FIXTURE_LEXICALLY_SEPARATE'
    Assert-V5 (-not (Report-LocationIsSeparate $safeReport $records $reportContainers)) 'REPORT_LOCATION_UNKNOWN_PROVIDER_METADATA_REFUSED'
  } finally {Set-Item -LiteralPath function:Get-MetadataFinalDirectory -Value $originalMetadataReader}
  Assert-V5 (Report-LocationIsSeparate $safeReport $records $reportContainers) 'REPORT_PROVIDER_METADATA_MOCK_RESTORED'
  Assert-V5 (-not (Test-Path -LiteralPath $safeReport) -and -not (Test-Path -LiteralPath $safeNestedReport)) 'REPORT_LOCATION_NEVER_CREATED'
  foreach($parent in @($google,$oneDrive)){
    Assert-V5 (-not (Test-Path -LiteralPath (Join-Path $parent 'Geumyi-Recovery-Archives-v5-fixture'))) 'PLANNED_ARCHIVE_DIRECTORY_STILL_ABSENT'
  }
  Assert-V5 (-not (Test-Path -LiteralPath (Join-Path $staging 'Geumyi-Recovery-Staging-v5-fixture'))) 'PLANNED_STAGING_DIRECTORY_STILL_ABSENT'
  Assert-V5 ((Get-FileHash -LiteralPath $sourceMarker -Algorithm SHA256).Hash -eq $sourceHash) 'SOURCE_BYTES_UNCHANGED'
  Assert-V5 ((Get-FileHash -LiteralPath $existingFile -Algorithm SHA256).Hash -eq $existingHash) 'EXISTING_CANDIDATE_BYTES_UNCHANGED'

  # Production writes are limited to the newly generated categorical report.
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Day12_Cloud_Recovery_Plan_READ_ONLY.ps1'),[ref]$tokens,[ref]$errors)
  Assert-V5 (@($errors).Count -eq 0) 'PRODUCTION_PARSER'
  $commands=$ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)
  foreach($command in $commands){
    $name=$command.GetCommandName()
    Assert-V5 ($name -notin @('Copy-Item','Remove-Item','Move-Item','Set-Acl','Stop-Service','Start-Service','Restart-Service','Stop-Process','Invoke-Expression','Invoke-RestMethod','robocopy','xcopy','mkdir','md')) 'PRODUCTION_MUTATION_COMMAND_ABSENT'
    Assert-V5 ($name -notin @('Get-ChildItem','gci','dir','ls')) 'PRODUCTION_DIRECTORY_ENUMERATION_ABSENT'
    if($name -eq 'New-Item'){
      $parent=$command.Parent
      while($null -ne $parent -and $parent -isnot [Management.Automation.Language.FunctionDefinitionAst]){$parent=$parent.Parent}
      Assert-V5 ($null -ne $parent -and $parent.Name -eq 'Emit-RecoveryPlan') 'MKDIR_ONLY_REPORT_DIRECTORY'
    }
  }
  $calls=$ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst]},$true)
  foreach($call in $calls){
    $name=[string]$call.Member.Value
    Assert-V5 ($name -notin @('GetFiles','GetDirectories','EnumerateFiles','EnumerateDirectories','Copy','Move','Delete','CreateDirectory')) 'NATIVE_SCAN_OR_MUTATION_ABSENT'
    if($name -eq 'WriteAllText'){
      $parent=$call.Parent
      while($null -ne $parent -and $parent -isnot [Management.Automation.Language.FunctionDefinitionAst]){$parent=$parent.Parent}
      Assert-V5 ($null -ne $parent -and $parent.Name -eq 'Emit-RecoveryPlan') 'WRITE_ONLY_SHARE_REPORT'
    }
  }
  Write-Host 'CLOUD_RECOVERY_PLAN_V5_SYNTHETIC_PASS'
  $sample|ConvertTo-Json -Depth 20
} finally {
  # Remove only exact fixture paths; the junction target is never removed here.
  if($junction -and (Test-Path -LiteralPath $junction)){[IO.Directory]::Delete($junction)}
  foreach($p in $files){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force}}
  for($i=$directories.Count-1;$i -ge 0;$i--){[IO.Directory]::Delete($directories[$i])}
}
