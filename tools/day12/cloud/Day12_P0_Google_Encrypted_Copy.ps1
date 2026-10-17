[CmdletBinding()]
param([switch]$FunctionsOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Copies only existing ENCRYPTED P0 archive entries from local staging to a
# NEW Google Drive mounted directory. Cloud sync is asynchronous; success is
# NOT remote upload proof. Never touches Paper, GSC, OneDrive or plaintext.
# Preserve our entry-point mode before dot-sourcing a helper that has the SAME
# parameter name. Dot sourcing can bind the helper's -FunctionsOnly switch in
# the caller scope, making a production invocation silently exit code 0.
$script:P0_Copy_EntryMode = -not [bool]$FunctionsOnly
. (Join-Path $PSScriptRoot 'Day12_P0_Google_Transfer_Preflight_READ_ONLY.ps1') -FunctionsOnly

function P0-Refuse([string]$Code) {throw ('P0_GOOGLE_COPY_'+$Code)}

function P0-ExpectedCipherNames {
  $names=@('header.json','manifest.gcm','LOCAL_CAPTURE_VERIFIED.txt')
  foreach($i in 0..19){$names+=('part-{0:D3}.gcm' -f $i)}
  return $names
}

function P0-CheckMirrorParent(
  [string]$Candidate,
  [string]$ProfileRoot,
  [string]$ShortcutRoot
) {
  # Mirrored Google Drive: G: has a shortcut to the real local My Drive folder.
  # The shortcut TARGET must resolve to the exact selected user-profile folder.
  # No heuristic acceptance of arbitrary C: paths or cloud sync claims.
  if([string]::IsNullOrWhiteSpace($Candidate) -or
     [string]::IsNullOrWhiteSpace($ProfileRoot) -or
     [string]::IsNullOrWhiteSpace($ShortcutRoot)){return $false}
  try {
    $full=[IO.Path]::GetFullPath($Candidate).TrimEnd('\')
    $profilePath=[IO.Path]::GetFullPath($ProfileRoot).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($full) -ine $profilePath){return $false}
    $leaf=[IO.Path]::GetFileName($full)
    if($leaf -cnotin @('My Drive','내 드라이브')){return $false}
    foreach($p in @($profilePath,$full)){
      $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
      if(-not $item.PSIsContainer -or
        (([long]$item.Attributes -band 0x00441400) -ne 0)){return $false}
    }
    $root=Get-Item -LiteralPath $ShortcutRoot -Force -ErrorAction Stop
    if(-not $root.PSIsContainer){return $false}
    $links=@(Get-ChildItem -LiteralPath $ShortcutRoot -File -Force -ErrorAction Stop |
      Where-Object{$_.Extension -ieq '.lnk' -and
                   $_.BaseName -in @('My Drive','내 드라이브')})
    if($links.Count -ne 1){return $false}
    $link=$links[0]
    if((([long]$link.Attributes -band 0x00000400) -ne 0)){return $false}
    $shell=New-Object -ComObject WScript.Shell
    $target=$shell.CreateShortcut($link.FullName).TargetPath
    if([string]::IsNullOrWhiteSpace($target)){return $false}
    $resolved=[IO.Path]::GetFullPath($target).TrimEnd('\')
    return $resolved.Equals($full,[StringComparison]::OrdinalIgnoreCase)
  } catch {return $false}
}

function P0-CopyCipherFile([string]$From,[string]$To) {
  # This function MUST NOT run before exact archive and destination guards.
  $info=Get-Item -LiteralPath $From -Force -ErrorAction Stop
  if($info.PSIsContainer -or
    (([long]$info.Attributes -band 0x00441400) -ne 0) -or
    $info.Length -lt 1 -or $info.Length -gt 8389632) {
    P0-Refuse 'UNSAFE_ENCRYPTED_FILE'
  }
  $source=$null;$dest=$null
  try {
    $source=New-Object IO.FileStream($From,[IO.FileMode]::Open,
      [IO.FileAccess]::Read,[IO.FileShare]::Read)
    # Exclusive, never overwrites an existing Google object.
    $dest=New-Object IO.FileStream($To,[IO.FileMode]::CreateNew,
      [IO.FileAccess]::Write,[IO.FileShare]::None)
    $buffer=New-Object byte[] 65536
    $total=[long]0
    while(($read=$source.Read($buffer,0,$buffer.Length)) -gt 0) {
      $total+=$read
      if($total -gt 8389632){P0-Refuse 'FILE_LIMIT_EXCEEDED'}
      $dest.Write($buffer,0,$read)
    }
    $dest.Flush()
    if($total -ne [long]$info.Length){P0-Refuse 'SOURCE_SIZE_CHANGED'}
  } finally {
    if($null -ne $dest){$dest.Dispose()}
    if($null -ne $source){$source.Dispose()}
  }
}

function P0-ExactCipherInventory([string]$Folder) {
  $expected=@(P0-ExpectedCipherNames)
  $actual=@(Get-ChildItem -LiteralPath $Folder -Force -ErrorAction Stop)
  if($actual.Count -ne 23){P0-Refuse 'DESTINATION_COUNT_INVALID'}
  $sum=[long]0
  foreach($entry in $actual){
    if($entry.Name -cnotin $expected -or $entry.PSIsContainer -or
      (([long]$entry.Attributes -band 0x00441400) -ne 0)){
      P0-Refuse 'DESTINATION_ENTRY_UNEXPECTED'
    }
    if($entry.Length -lt 1 -or $entry.Length -gt 8389632){
      P0-Refuse 'DESTINATION_ENTRY_SIZE_INVALID'
    }
    $sum+=[long]$entry.Length
  }
  return $sum
}

function P0-CopyCipherSet([string]$Source,[string]$GoogleParent,[string]$Leaf) {
  # Caller verifies source is the approved latest local capture and GoogleParent
  # is an EXACT shortcut-verified mirrored My Drive folder, not an arbitrary
  # local directory. Tested using a disposable synthetic .lnk target.
  if($Leaf -notmatch '^Geumyi-P0-Encrypted-Config-[0-9]{8}-[0-9]{6}-[a-f0-9]{16}$'){
    P0-Refuse 'NEW_LEAF_NAME_INVALID'
  }
  $folder=[IO.Path]::Combine($GoogleParent,$Leaf)
  if(Test-Path -LiteralPath $folder){P0-Refuse 'DESTINATION_ALREADY_EXISTS'}
  $sourceState=Inspect-P0EncryptedLocal $Source
  if($sourceState.local_archive_state -ne 'LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE'){
    P0-Refuse 'SOURCE_RECHECK_FAILED'
  }
  if([long]$sourceState.encrypted_archive_bytes -gt 67108864){
    P0-Refuse 'SOURCE_AGGREGATE_LIMIT'
  }
  # New child only. If anything fails after this point, the directory is
  # INCOMPLETE; NEVER delete it automatically or report remote success.
  [void][IO.Directory]::CreateDirectory($folder)
  $names=@(P0-ExpectedCipherNames)
  $verified=0
  $total=[long]0
  foreach($name in $names){
    $from=Join-Path $Source $name
    $to=Join-Path $folder $name
    $sourceHashBefore=(Get-FileHash -LiteralPath $from -Algorithm SHA256 -ErrorAction Stop).Hash
    P0-CopyCipherFile $from $to
    $sourceHashAfter=(Get-FileHash -LiteralPath $from -Algorithm SHA256 -ErrorAction Stop).Hash
    $copyHash=(Get-FileHash -LiteralPath $to -Algorithm SHA256 -ErrorAction Stop).Hash
    if($sourceHashBefore -cne $sourceHashAfter -or
      $sourceHashBefore -cne $copyHash){
      P0-Refuse 'CIPHERTEXT_HASH_MISMATCH_OR_SOURCE_CHANGED'
    }
    $verified++
  }
  $total=P0-ExactCipherInventory $folder
  if($verified -ne 23 -or $total -ne [long]$sourceState.encrypted_archive_bytes){
    P0-Refuse 'DESTINATION_SET_NOT_IDENTICAL'
  }
  return [ordered]@{
    completed=$true
    copied_entries=23
    encrypted_part_count=20
    bytes=$total
    leaf=$Leaf
    original_source_unchanged_by_copy=$true
    cloud_remote_sync_confirmed=$false
  }
}

if(-not $script:P0_Copy_EntryMode){return}
Write-Host 'P0_GOOGLE_COPY_ENTRYPOINT_STARTED'

try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    P0-Refuse 'WINDOWS_ONLY'
  }
  $local=$env:LOCALAPPDATA
  if(-not $local){P0-Refuse 'LOCALAPPDATA_MISSING'}
  $base=Join-Path $local 'Geumyi-P0-Encrypted-Staging'
  $archives=@(Get-ChildItem -LiteralPath $base -Directory -Filter 'P0-*' -ErrorAction Stop |
    Where-Object{
      Test-Path -LiteralPath (Join-Path $_.FullName 'LOCAL_CAPTURE_VERIFIED.txt') -PathType Leaf
    } | Sort-Object CreationTimeUtc -Descending)
  if($archives.Count -lt 1){P0-Refuse 'LOCAL_BACKUP_NOT_FOUND'}
  $source=$archives[0].FullName
  if(-not(Confirm-PrivateP0Location $source $local)){
    P0-Refuse 'LOCAL_BACKUP_LOCATION_INVALID'
  }
  $state=Inspect-P0EncryptedLocal $source
  if($state.local_archive_state -ne 'LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE'){
    P0-Refuse 'LOCAL_BACKUP_INCOMPLETE'
  }
  # The most recent actual user preflight reported exactly 81,413 bytes.
  # Refuse a silent switch to a different backup or unexpected size.
  if([long]$state.encrypted_archive_bytes -ne 81413){
    P0-Refuse 'ARCHIVE_IDENTITY_SIZE_CHANGED'
  }
  Write-Host '======================================================'
  Write-Host 'Geumyi Day12 P0 - copy ENCRYPTED files to verified mirror only'
  Write-Host '23 encrypted-backup entries. Exact local total: 81413 bytes.'
  Write-Host 'NO server/OneDrive source reads, no plaintext, no backup deletion.'
  Write-Host 'A mirrored local copy is NOT proof of Google remote sync.'
  Write-Host '======================================================'
  Write-Host 'Google Drive MIRROR mode is confirmed by operator.'
  Write-Host 'G: contains a My Drive SHORTCUT to a local user-profile folder.'
  Write-Host 'Only the local folder matching that G: shortcut is accepted.'
  Write-Host 'Check the signed-in Google account in Drive for desktop.'
  $google=(Read-Host 'Paste the LOCAL mirrored My Drive folder path (C: user profile)').Trim().Trim('"')
  if(-not(P0-CheckMirrorParent $google $env:USERPROFILE 'G:\')){
    P0-Refuse 'GOOGLE_MIRROR_SHORTCUT_TARGET_NOT_VERIFIED'
  }
  $approval=Read-Host 'Type GOOGLE_P0_ENCRYPTED_UPLOAD_APPROVED to copy 23 encrypted entries'
  if($approval -cne 'GOOGLE_P0_ENCRYPTED_UPLOAD_APPROVED'){
    P0-Refuse 'OPERATOR_CONFIRMATION_REFUSED'
  }
  # After confirmation, repeat exact source and Google-parent checks.
  if(-not(P0-CheckMirrorParent $google $env:USERPROFILE 'G:\')){
    P0-Refuse 'GOOGLE_MIRROR_SHORTCUT_CHANGED'
  }
  $current=Inspect-P0EncryptedLocal $source
  if($current.local_archive_state -ne 'LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE' -or
    [long]$current.encrypted_archive_bytes -ne 81413){
    P0-Refuse 'SOURCE_CHANGED_BEFORE_UPLOAD'
  }
  $leaf='Geumyi-P0-Encrypted-Config-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+
    ([guid]::NewGuid().ToString('N').Substring(0,16))
  $out=P0-CopyCipherSet $source $google $leaf
  Write-Host 'P0_GOOGLE_MIRROR_COPY_HASH_VERIFIED=23'
  Write-Host ('P0_GOOGLE_MIRROR_COPY_BYTES='+$out.bytes)
  Write-Host ('P0_GOOGLE_MIRROR_NEW_FOLDER_NAME='+$out.leaf)
  Write-Host 'P0_GOOGLE_MIRROR_COPY_COMPLETE=true'
  Write-Host 'P0_GOOGLE_REMOTE_UPLOAD_VERIFIED=false'
  Write-Host 'P0_INDEPENDENT_WEB_DOWNLOAD_VERIFIED=false'
  Write-Host 'P0_SOURCE_WRITE_PERFORMED=false'
  Write-Host 'P0_STABLE_RELEASE_ALLOWED=false'
  Write-Host 'SEND_ONLY: the P0_ status lines. NEVER send recovery keys or backup files.'
} catch {
  Write-Host 'P0_GOOGLE_COPY_FAILED_OR_INCOMPLETE'
  Write-Host 'P0_NO_AUTOMATIC_CLEANUP_OR_OVERWRITE'
  Write-Host 'P0_GOOGLE_REMOTE_UPLOAD_VERIFIED=false'
  if($_.Exception.Message -match '^P0_GOOGLE_COPY_[A-Z_]+$'){
    Write-Host $_.Exception.Message
  }
  exit 2
}
