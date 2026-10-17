[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Fixture ONLY. Local temp fake user home, fake G: shortcut, no real provider.
. (Join-Path $PSScriptRoot 'Day12_P0_Google_Encrypted_Copy.ps1') -FunctionsOnly

$root=Join-Path $env:TEMP ('p0-google-mirror-fixture-'+[guid]::NewGuid().ToString('N'))
$fixtureProfile=Join-Path $root 'synthetic-profile'
$mirror=Join-Path $fixtureProfile '내 드라이브'
$other=Join-Path $fixtureProfile 'My Drive'
$fakeG=Join-Path $root 'synthetic-G-root'
foreach($p in @($fixtureProfile,$mirror,$other,$fakeG)){
  [void](New-Item -ItemType Directory -Path $p -Force)
}
Write-Host 'SYNTHETIC_STEP_FOLDERS_CREATED'
$shell=New-Object -ComObject WScript.Shell
Write-Host 'SYNTHETIC_STEP_COM_CREATED'
$linkFile=Join-Path $fakeG '내 드라이브.lnk'
$link=$shell.CreateShortcut($linkFile)
Write-Host 'SYNTHETIC_STEP_SHORTCUT_OBJECT_CREATED'
$link.TargetPath=$mirror
Write-Host 'SYNTHETIC_STEP_TARGET_SET'
$link.Save()
Write-Host 'SYNTHETIC_STEP_SHORTCUT_SAVED'
Write-Host 'SYNTHETIC_STEP_BEFORE_VALIDATION'
if(-not (P0-CheckMirrorParent $mirror $fixtureProfile $fakeG)){
  throw 'VALID_SYNTHETIC_MIRROR_SHORTCUT_REJECTED'
}
if(P0-CheckMirrorParent $other $fixtureProfile $fakeG){
  throw 'SIBLING_LOCAL_FOLDER_MUST_NOT_BE_ACCEPTED'
}
if(P0-CheckMirrorParent $fixtureProfile $fixtureProfile $fakeG){
  throw 'HOME_ROOT_MUST_NOT_BE_ACCEPTED'
}
if(P0-CheckMirrorParent $fakeG $fixtureProfile $fakeG){
  throw 'FAKE_G_ROOT_MUST_NOT_BE_ACCEPTED'
}
# Shortcut target drift must cause immediate rejection before copy.
$target=Join-Path $root 'other-target'
[void](New-Item -ItemType Directory -Path $target -Force)
$link=$shell.CreateShortcut($linkFile)
$link.TargetPath=$target
$link.Save()
if(P0-CheckMirrorParent $mirror $fixtureProfile $fakeG){
  throw 'SHORTCUT_TARGET_MISMATCH_NOT_REJECTED'
}
Write-Host 'P0_GOOGLE_MIRROR_SHORTCUT_SYNTHETIC_PASS'
Write-Host 'TEST_REAL_GOOGLE_OR_SERVER_ACCESSED=false'
