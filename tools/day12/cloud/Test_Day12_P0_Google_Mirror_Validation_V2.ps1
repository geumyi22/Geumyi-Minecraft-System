[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Synthetic-only: fake user profile + fake shortcut pointing to a SAFE,
# existing Windows binary. WScript.Shell cannot generate a folder-target
# Shell Link, so this fixture tests strict target MISMATCH rejection plus
# valid/invalid profile constraints, never falsely claims a positive G link.
. (Join-Path $PSScriptRoot 'Day12_P0_Google_Encrypted_Copy.ps1') -FunctionsOnly

$root=Join-Path $env:TEMP ('p0-google-mirror-fixture-'+[guid]::NewGuid().ToString('N'))
$fixtureProfile=Join-Path $root 'synthetic-profile'
$mirror=Join-Path $fixtureProfile '내 드라이브'
$other=Join-Path $fixtureProfile 'My Drive'
$fakeG=Join-Path $root 'synthetic-G-root'
foreach($p in @($fixtureProfile,$mirror,$other,$fakeG)){
  [void](New-Item -ItemType Directory -Path $p -Force)
}
if(-not (P0-MirrorCandidateUnderProfile $mirror $fixtureProfile)){
  throw 'VALID_SYNTHETIC_PROFILE_MIRROR_PATH_REJECTED'
}
if(P0-MirrorCandidateUnderProfile $fixtureProfile $fixtureProfile){
  throw 'PROFILE_ROOT_WRONGLY_ACCEPTED'
}
if(P0-MirrorCandidateUnderProfile $fakeG $fixtureProfile){
  throw 'OUTSIDE_PROFILE_WRONGLY_ACCEPTED'
}
if(-not (P0-PathIdentical $mirror $mirror)){
  throw 'IDENTICAL_FULL_PATH_NOT_EQUAL'
}
if(P0-PathIdentical $mirror $other){
  throw 'UNRELATED_SIBLING_FALSE_EQUALITY'
}
$shell=New-Object -ComObject WScript.Shell
$linkFile=Join-Path $fakeG '내 드라이브.lnk'
$link=$shell.CreateShortcut($linkFile)
$link.TargetPath=Join-Path $env:WINDIR 'System32\notepad.exe'
$link.Save()
# Notepad is a valid link target but never the user's mirrored folder.
# Even if C: folder exists and is valid, fake G: link must be rejected.
if(P0-CheckMirrorParent $mirror $fixtureProfile $fakeG){
  throw 'MISMATCHED_GOOGLE_LINK_TARGET_WRONGLY_ACCEPTED'
}
if(P0-CheckMirrorParent $other $fixtureProfile $fakeG){
  throw 'UNRELATED_LOCAL_FOLDER_WRONGLY_ACCEPTED'
}
Write-Host 'P0_GOOGLE_MIRROR_VALIDATION_SYNTHETIC_PASS'
Write-Host 'FAKE_LINK_TARGET_MISMATCH_REFUSED=true'
Write-Host 'REAL_GOOGLE_ACCOUNT_OR_SERVER_ACCESSED=false'
