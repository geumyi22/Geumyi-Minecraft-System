[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Day12_P0_Google_Transfer_Preflight_READ_ONLY.ps1') -FunctionsOnly
$base=Join-Path $env:TEMP ('p0-cloud-preflight-synthetic-'+[guid]::NewGuid().ToString('N'))
$local=Join-Path $base 'LocalAppData'
$archive=Join-Path (Join-Path $local 'Geumyi-P0-Encrypted-Staging') 'P0-SYNTHETIC-ABCDEF0123456789'
[void](New-Item -ItemType Directory -Path $archive -Force)
$names=@('header.json','manifest.gcm','LOCAL_CAPTURE_VERIFIED.txt')
foreach($i in 0..19){$names+=('part-{0:D3}.gcm' -f $i)}
foreach($name in $names){
  [IO.File]::WriteAllText((Join-Path $archive $name),'SYNTHETIC_TEST_DATA_ONLY')
}
if(-not (Confirm-PrivateP0Location $archive $local)){throw 'SYNTHETIC_PRIVATE_PATH_NOT_RECOGNIZED'}
$ok=Inspect-P0EncryptedLocal $archive
if($ok.local_archive_state -ne 'LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE' -or
   $ok.encrypted_parts -ne 20 -or $ok.exact_archive_entries -ne 23 -or
   $ok.plaintext_opened -or $ok.p0_existing_archive_mutated){
  throw 'SYNTHETIC_P0_COMPLETENESS_REJECTED'
}
$extra=Join-Path (Split-Path -Parent $archive) 'P0-SYNTHETIC-EXTRA-ABCDEF01'
[void](New-Item -ItemType Directory -Path $extra -Force)
foreach($n in $names){[IO.File]::WriteAllText((Join-Path $extra $n),'SYNTHETIC')}
[IO.File]::WriteAllText((Join-Path $extra 'unexpected.txt'),'SYNTHETIC')
if((Inspect-P0EncryptedLocal $extra).local_archive_state -eq 'LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE'){
  throw 'SYNTHETIC_EXTRA_ITEM_ACCEPTED'
}
$missing=Join-Path (Split-Path -Parent $archive) 'P0-SYNTHETIC-MISSING-ABCDEF01'
[void](New-Item -ItemType Directory -Path $missing -Force)
foreach($n in @($names|Where-Object{$_ -ne 'part-019.gcm'})){
  [IO.File]::WriteAllText((Join-Path $missing $n),'SYNTHETIC')
}
if((Inspect-P0EncryptedLocal $missing).local_archive_state -eq 'LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE'){
  throw 'SYNTHETIC_MISSING_ITEM_ACCEPTED'
}
if(Confirm-PrivateP0Location (Join-Path $base 'OtherFolder') $local){
  throw 'SYNTHETIC_PATH_ESCAPE_ACCEPTED'
}
Write-Host 'P0_GOOGLE_TRANSFER_PREFLIGHT_SYNTHETIC_PASS'
