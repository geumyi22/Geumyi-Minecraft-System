[CmdletBinding()]
param([switch]$FunctionsOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# P0 G: transfer PRECHECK ONLY. Does not connect to cloud or write any archive.
# Source is an existing private LOCALAPPDATA encrypted archive. It never reads
# original Paper/GSC/Velocity data or passphrases, and outputs no paths/hashes.
function Inspect-P0EncryptedLocal([string]$Root) {
  $status=[ordered]@{
    local_archive_state='NOT_VERIFIED'
    encrypted_parts=0
    exact_archive_entries=0
    encrypted_archive_bytes=0
    all_archive_entries_regular=$false
    sha256_ciphertext_checked=$false
    plaintext_opened=$false
    complete_marker_present=$false
    p0_existing_archive_mutated=$false
  }
  try {
    $dir=Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if(-not $dir.PSIsContainer -or
      (([long]$dir.Attributes -band 0x00441400) -ne 0)) {
      $status.local_archive_state='ARCHIVE_DIRECTORY_UNSAFE';return $status
    }
    $names=@('header.json','manifest.gcm','LOCAL_CAPTURE_VERIFIED.txt')
    foreach($i in 0..19){$names+=('part-{0:D3}.gcm' -f $i)}
    $seen=@(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop)
    if($seen.Count -ne $names.Count){
      $status.local_archive_state='EXTRA_OR_MISSING_ARCHIVE_ENTRY';return $status
    }
    $sum=[long]0
    $partCount=0
    foreach($entry in $seen){
      if($entry.Name -cnotin $names -or $entry.PSIsContainer -or
        (([long]$entry.Attributes -band 0x00441400) -ne 0)){
        $status.local_archive_state='UNEXPECTED_ENTRY_OR_REPARSE';return $status
      }
      $size=[long]$entry.Length
      if($size -lt 1 -or $size -gt 8389632){
        $status.local_archive_state='ENTRY_SIZE_UNSAFE';return $status
      }
      if($entry.Name -clike 'part-???.gcm'){
        $partCount++
      }
      $sum+=$size
      if($sum -gt 67108864){
        $status.local_archive_state='ARCHIVE_TOO_LARGE_FOR_P0_V1';return $status
      }
    }
    if($partCount -ne 20){
      $status.local_archive_state='PART_COUNT_NOT_20';return $status
    }
    $marker=(Get-Item -LiteralPath (Join-Path $Root 'LOCAL_CAPTURE_VERIFIED.txt') -ErrorAction Stop)
    if($marker.Length -gt 512){
      $status.local_archive_state='MARKER_SIZE_UNEXPECTED';return $status
    }
    # The prior independent AES-GCM verifier did content authentication.
    # This inventory intentionally reads no bytes from P0 files.
    $status.local_archive_state='LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE'
    $status.encrypted_parts=20
    $status.exact_archive_entries=23
    $status.encrypted_archive_bytes=$sum
    $status.all_archive_entries_regular=$true
    $status.complete_marker_present=$true
    return $status
  } catch {
    $status.local_archive_state='METADATA_UNAVAILABLE';return $status
  }
}
function Confirm-PrivateP0Location([string]$Actual,[string]$LocalRoot){
  if(-not $LocalRoot -or -not $Actual){return $false}
  try {
    $actualPath=[IO.Path]::GetFullPath($Actual).TrimEnd('\')
    $rootPath=[IO.Path]::GetFullPath($LocalRoot).TrimEnd('\')
    $parent=[IO.Path]::GetDirectoryName($actualPath)
    $expected=[IO.Path]::Combine($rootPath,'Geumyi-P0-Encrypted-Staging')
    if(-not $parent.Equals($expected,[StringComparison]::OrdinalIgnoreCase)){
      return $false
    }
    $leaf=[IO.Path]::GetFileName($actualPath)
    if(-not $leaf.StartsWith('P0-',[StringComparison]::Ordinal)){return $false}
    if($leaf.Length -lt 20){return $false}
    foreach($p in @($rootPath,$expected)){
      $metadata=Get-Item -LiteralPath $p -Force -ErrorAction Stop
      if(-not $metadata.PSIsContainer -or
        (([long]$metadata.Attributes -band 0x00441400) -ne 0)){return $false}
    }
    return $true
  } catch {return $false}
}
if($FunctionsOnly){return}

try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    throw 'WINDOWS_ONLY'
  }
  if(-not $env:LOCALAPPDATA){throw 'LOCAL_APPDATA_UNAVAILABLE'}
  $parent=Join-Path $env:LOCALAPPDATA 'Geumyi-P0-Encrypted-Staging'
  $children=@(Get-ChildItem -LiteralPath $parent -Directory -Filter 'P0-*' -ErrorAction Stop |
    Where-Object{
      Test-Path -LiteralPath (Join-Path $_.FullName 'LOCAL_CAPTURE_VERIFIED.txt') -PathType Leaf
    } | Sort-Object CreationTimeUtc -Descending)
  if($children.Count -lt 1){throw 'NO_COMPLETED_CAPTURE_FOUND'}
  $chosen=$children[0].FullName
  if(-not (Confirm-PrivateP0Location $chosen $env:LOCALAPPDATA)){
    throw 'P0_LOCAL_SOURCE_LOCATION_UNVERIFIED'
  }
  $inventory=Inspect-P0EncryptedLocal $chosen
  $mounted=$false
  try {
    $g=Get-Item -LiteralPath 'G:\' -Force -ErrorAction Stop
    $mounted=[bool]$g.PSIsContainer
  } catch {}
  $result=if($inventory.local_archive_state -eq 'LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE' -and $mounted){
    'P0_CLOUD_TRANSFER_PREFLIGHT_REVIEW_READY'
  }else{'P0_CLOUD_TRANSFER_PREFLIGHT_BLOCKED'}
  # Only local metadata is inspected. Provider account identity, free quota,
  # upload success and web download are NOT verified by checking a drive mount.
  Write-Host ('P0_CLOUD_TRANSFER_PREFLIGHT_STATUS='+$result)
  Write-Host ('P0_ARCHIVE_SET_STATUS='+$inventory.local_archive_state)
  Write-Host ('P0_ENCRYPTED_PARTS='+$inventory.encrypted_parts)
  Write-Host ('P0_ARCHIVE_ENTRIES='+$inventory.exact_archive_entries)
  Write-Host ('P0_ARCHIVE_BYTES='+$inventory.encrypted_archive_bytes)
  Write-Host ('G_MOUNT_ROOT_PRESENT='+$mounted)
  Write-Host 'GOOGLE_ACCOUNT_REMOTE_IDENTITY_INDEPENDENTLY_VERIFIED=false'
  Write-Host 'GOOGLE_UPLOAD_PERFORMED=false'
  Write-Host 'GOOGLE_DOWNLOAD_VERIFIED=false'
  Write-Host 'SERVER_OR_ENCRYPTED_SOURCE_CHANGED=false'
  Write-Host 'P0_STABLE_RELEASE_ALLOWED=false'
  if($result -ne 'P0_CLOUD_TRANSFER_PREFLIGHT_REVIEW_READY'){exit 2}
} catch {
  Write-Host 'P0_CLOUD_TRANSFER_PREFLIGHT_BLOCKED'
  Write-Host 'NO_SERVER_OR_CLOUD_CHANGE'
  exit 2
}
