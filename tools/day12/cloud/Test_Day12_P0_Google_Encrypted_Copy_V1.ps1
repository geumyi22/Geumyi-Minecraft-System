[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Disposable synthetic-only file copy rehearsal. Production G: never accessed.
. (Join-Path $PSScriptRoot 'Day12_P0_Google_Encrypted_Copy.ps1') -FunctionsOnly
$root=Join-Path $env:TEMP ('geumyi-p0-encrypted-copy-fixture-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $root 'synthetic-existing-local-P0'
$fakeDrive=Join-Path $root 'synthetic-cloud-provider'
[void](New-Item -ItemType Directory -Path $source -Force)
[void](New-Item -ItemType Directory -Path $fakeDrive -Force)
$names=@(P0-ExpectedCipherNames)
if($names.Count -ne 23){throw 'WRONG_EXPECTED_ARCHIVE_SET'}
foreach($name in $names){
  [IO.File]::WriteAllText((Join-Path $source $name),
    ('FAKE ENCRYPTED TEST BYTES NOT REAL: '+$name),(New-Object Text.UTF8Encoding($false)))
}
$srcBefore=@{}
foreach($name in $names){
  $srcBefore[$name]=(Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash
}
$leaf='Geumyi-P0-Encrypted-Config-20261017-050000-0123456789abcdef'
$copied=P0-CopyCipherSet $source $fakeDrive $leaf
if(-not $copied.completed -or $copied.copied_entries -ne 23 -or
  $copied.encrypted_part_count -ne 20 -or $copied.bytes -lt 23){
  throw 'SYNTHETIC_COPY_DID_NOT_VERIFY'
}
$destination=Join-Path $fakeDrive $leaf
foreach($name in $names){
  $sourceHash=(Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash
  $destHash=(Get-FileHash -LiteralPath (Join-Path $destination $name) -Algorithm SHA256).Hash
  if($sourceHash -cne $srcBefore[$name] -or $sourceHash -cne $destHash){
    throw 'SYNTHETIC_SOURCE_CHANGED_OR_COPY_DIFFERENT'
  }
}
$blocked=$false
try{[void](P0-CopyCipherSet $source $fakeDrive $leaf)}catch{$blocked=$true}
if(-not $blocked){throw 'DESTINATION_OVERWRITE_NOT_REFUSED'}
$wrongLeaf=$false
try{[void](P0-CopyCipherSet $source $fakeDrive '../outside')}catch{$wrongLeaf=$true}
if(-not $wrongLeaf){throw 'UNSAFE_NEW_LEAF_NOT_REFUSED'}
$bad=Join-Path $root 'synthetic-missing-source'
[void](New-Item -ItemType Directory -Path $bad -Force)
foreach($name in @($names|Where-Object{$_ -ne 'part-019.gcm'})){
  [IO.File]::WriteAllText((Join-Path $bad $name),'FAKE')
}
$missingRejected=$false
try{
  [void](P0-CopyCipherSet $bad $fakeDrive 'Geumyi-P0-Encrypted-Config-20261017-050001-0123456789abcdef')
}catch{$missingRejected=$true}
if(-not $missingRejected){throw 'MISSING_PART_NOT_REFUSED'}
if(-not $copied.original_source_unchanged_by_copy -or $copied.cloud_remote_sync_confirmed){
  throw 'UNSUPPORTED_CLOUD_CLAIM'
}
Write-Host 'P0_GOOGLE_ENCRYPTED_COPY_SYNTHETIC_PASS'
Write-Host 'SYNTHETIC_23_ITEMS_HASH_IDENTICAL=true'
Write-Host 'SYNTHETIC_DESTINATION_OVERWRITE_REFUSED=true'
Write-Host 'SYNTHETIC_MISSING_PART_REFUSED=true'
Write-Host 'PRODUCTION_G_DRIVE_ACCESSED=false'
