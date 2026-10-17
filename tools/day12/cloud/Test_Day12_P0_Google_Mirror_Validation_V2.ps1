[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Synthetic only: fake profile and fake Google G: root. No real Google access.
# Shortcut is created with ANSI temporary name and target, then renamed to
# Korean filename to prove production Unicode Shell.Application resolution.
. (Join-Path $PSScriptRoot 'Day12_P0_Google_Encrypted_Copy.ps1') -FunctionsOnly

$root=Join-Path $env:TEMP ('p0-google-mirror-fixture-'+[guid]::NewGuid().ToString('N'))
$fixtureProfile=Join-Path $root 'synthetic-profile'
$mirror=Join-Path $fixtureProfile 'My Drive'
$koreanMirror=Join-Path $fixtureProfile '내 드라이브'
$fakeG=Join-Path $root 'synthetic-G-root'
foreach($p in @($fixtureProfile,$mirror,$koreanMirror,$fakeG)){
  [void](New-Item -ItemType Directory -Path $p -Force)
}
if(-not (P0-MirrorCandidateUnderProfile $mirror $fixtureProfile)){throw 'SYNTHETIC_VALID_PROFILE_PATH_REFUSED'}
if(-not (P0-MirrorCandidateUnderProfile $koreanMirror $fixtureProfile)){throw 'SYNTHETIC_KOREAN_PROFILE_PATH_REFUSED'}
if(P0-MirrorCandidateUnderProfile $fixtureProfile $fixtureProfile){throw 'SYNTHETIC_PROFILE_ROOT_ACCEPTED'}
if(P0-MirrorCandidateUnderProfile $fakeG $fixtureProfile){throw 'SYNTHETIC_OUTSIDE_PATH_ACCEPTED'}
if(-not (P0-PathIdentical $koreanMirror $koreanMirror)){throw 'SYNTHETIC_KOREAN_PATH_COMPARISON_FAILED'}
if(P0-PathIdentical $mirror $koreanMirror){throw 'SYNTHETIC_PATH_MISMATCH_ACCEPTED'}

$shell=New-Object -ComObject WScript.Shell
$asciiLink=Join-Path $fakeG 'TemporaryMirrorShortcut.lnk'
$link=$shell.CreateShortcut($asciiLink)
$link.TargetPath=$mirror
$link.Save()
# The real Google shortcut has a Korean name. Only the temporary test
# shortcut is created by WScript; the live verifier NEVER invokes WScript.
Rename-Item -LiteralPath $asciiLink -NewName '내 드라이브.lnk' -ErrorAction Stop

if(-not (P0-CheckMirrorParent $mirror $fixtureProfile $fakeG)){
  throw 'SYNTHETIC_MATCHING_KOREAN_NAMED_SHORTCUT_REFUSED'
}
if(P0-CheckMirrorParent $koreanMirror $fixtureProfile $fakeG){
  throw 'SYNTHETIC_SHORTCUT_TARGET_MISMATCH_ACCEPTED'
}
if(P0-CheckMirrorParent $fakeG $fixtureProfile $fakeG){
  throw 'SYNTHETIC_OUTSIDE_PROFILE_REFUSED_INCORRECTLY'
}
Write-Host 'P0_GOOGLE_MIRROR_VALIDATION_SYNTHETIC_PASS'
Write-Host 'UNICODE_LINK_AND_MATCHED_FOLDER_VERIFIED=true'
Write-Host 'KOREAN_PATH_AND_MISMATCH_GUARDS_PASS=true'
Write-Host 'REAL_GOOGLE_OR_SERVER_ACCESSED=false'
