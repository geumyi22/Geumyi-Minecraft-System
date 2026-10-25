$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Day12_Recovery_Capacity_Metadata_READ_ONLY.ps1') -FunctionsOnly

if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_TEST_ONLY'}
$base=Join-Path $env:TEMP ('day12-capacity-disposable-'+[guid]::NewGuid().ToString('N'))
$before=@{}
try {
  [void](New-Item -ItemType Directory -Path $base -ErrorAction Stop)
  $roles=@('wild','playground','other','lobby','gsc_state')
  $records=@()
  foreach($role in $roles){
    $dir=Join-Path $base $role
    [void](New-Item -ItemType Directory -Path $dir -ErrorAction Stop)
    $file=Join-Path $dir 'fixture.bin'
    [IO.File]::WriteAllBytes($file,[byte[]](1,2,3,4))
    $before[$role]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $records+=@{id=$role;path=$dir;final_path=$dir}
  }
  $m=Measure-MetadataTree (Join-Path $base 'wild') 100 10
  if(-not $m.complete -or $m.observed_bytes -ne 4 -or $m.files_seen -ne 1 -or
      $m.directories_seen -ne 0 -or $m.excluded_reparse_or_cloud_items -ne 0){
    throw 'BASIC_METADATA_SIZE_NOT_VERIFIED'
  }
  $limited=Measure-MetadataTree (Join-Path $base 'wild') 100 10
  if($limited.observed_bytes -ne 4){throw 'METADATA_NOT_REPEATABLE'}
  $ok=Build-CapacityReport $records $true 100 10 $env:TEMP
  if($ok.result -ne 'SOURCE_METADATA_MEASURED_REVIEW_REQUIRED' -or
     $ok.source_metrics.Count -ne 5 -or $ok.backup_or_snapshot_created -or
     $ok.cloud_upload_performed -or $ok.restore_test_passed -or
     $ok.stable_release_allowed -or $ok.credentials_or_private_paths_exported){
    throw 'BAD_SCOPED_REPORT'
  }
  foreach($item in $ok.source_metrics){
    if(-not $item.measurement_complete -or $item.observed_bytes -ne 4){throw 'ROLE_BYTES_NOT_VERIFIED'}
  }
  $txt=$ok|ConvertTo-Json -Depth 12
  if($txt.Contains($base) -or $txt.Contains('fixture.bin')){throw 'PRIVATE_PATH_LEAK'}
  if($ok.google_remote_quota_status -ne 'UNKNOWN_REQUIRES_PROVIDER_ACCOUNT_EVIDENCE' -or
     $ok.onedrive_remote_quota_status -ne 'UNKNOWN_REQUIRES_PROVIDER_ACCOUNT_EVIDENCE'){
    throw 'REMOTE_QUOTA_FALSE_CLAIM'
  }
  $missing=@($records|Where-Object{$_.id -ne 'other'})
  $blocked=Build-CapacityReport $missing $true 100 10 $env:TEMP
  if($blocked.result -ne 'CAPACITY_REVIEW_INCOMPLETE' -or
     @($blocked.reason_codes|Where-Object{$_ -like '*OTHER*'}).Count -eq 0){
    throw 'MISSING_OTHER_NOT_BLOCKED'
  }
  $duplicate=@($records)+@{id='wild';path=(Join-Path $base 'playground');final_path=(Join-Path $base 'playground')}
  $blockedDuplicate=Build-CapacityReport $duplicate $false 100 10 $env:TEMP
  if($blockedDuplicate.result -ne 'CAPACITY_REVIEW_INCOMPLETE'){
    throw 'AMBIGUOUS_ROOT_NOT_BLOCKED'
  }
  foreach($role in $roles){
    $file=Join-Path (Join-Path $base $role) 'fixture.bin'
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $before[$role]){
      throw 'DISPOSABLE_FIXTURE_MODIFIED_BY_READER'
    }
  }
  Write-Output 'CAPACITY_V1_WINDOWS_DISPOSABLE_PASS'
} finally {
  if(Test-Path -LiteralPath $base){
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction Stop
  }
}
