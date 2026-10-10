[CmdletBinding()]
param(
  [string]$OutputDir="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# Checks existing 12.7 known-good cache bytes against the original operator
# manifest. No cache Build, repair, offline transition, restart or writes to
# production. "HASHES_MATCH" is not offline-start E2E.
function Check-Manifest([string]$CacheRoot,[string]$ManifestFile) {
  $r=[ordered]@{
    schema=1;phase="12.7-cached-bytes-integrity";synthetic=$false
    read_only=$true;cache_modified=$false;network_requests=0
    checked=0;missing=0;mismatched_sha256=0;mismatched_size=0
    invalid_record=0;duplicate_names=0;reparse_blocked=0
    manifest_valid=$false;result="CHECK_REQUIRED"
    offline_known_good_startup_proven=$false
    canonical_backend_ports_private="UNCHANGED_FAIL"
  }
  if(-not(Test-Path -LiteralPath $ManifestFile -PathType Leaf)){return $r}
  try{$manifest=Get-Content -LiteralPath $ManifestFile -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop}
  catch{return $r}
  $files=@($manifest.files)
  if($files.Count -lt 1 -or $files.Count -gt 10000){return $r}
  $r.manifest_valid=$true
  $names=@{}
  foreach($f in $files){
    $name=[string]$f.cache_name
    $hash=[string]$f.sha256
    $size=0L
    $valid=($name -cmatch '^[A-Za-z0-9_.-]{1,240}$' -and
      $name -notin @(".","..") -and $hash -cmatch '^[a-fA-F0-9]{64}$' -and
      [long]::TryParse([string]$f.size,[ref]$size) -and $size -ge 0)
    if(-not $valid){$r.invalid_record++;continue}
    if($names.ContainsKey($name.ToLowerInvariant())){$r.duplicate_names++;continue}
    $names[$name.ToLowerInvariant()]=$true
    $file=Join-Path $CacheRoot $name
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){$r.missing++;continue}
    try {
      $item=Get-Item -LiteralPath $file -ErrorAction Stop
      if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        $r.reparse_blocked++;continue
      }
      if([long]$item.Length -ne $size){$r.mismatched_size++;continue}
      $actual=(Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
      if($actual -ne $hash.ToLowerInvariant()){$r.mismatched_sha256++;continue}
      $r.checked++
    }catch{$r.missing++}
  }
  $r.result=if($r.checked -eq $files.Count -and
    $r.missing -eq 0 -and $r.mismatched_sha256 -eq 0 -and
    $r.mismatched_size -eq 0 -and $r.invalid_record -eq 0 -and
    $r.duplicate_names -eq 0 -and $r.reparse_blocked -eq 0){"CACHED_BYTES_HASHES_MATCH"}
    else{"CACHE_INTEGRITY_REVIEW_REQUIRED"}
  return $r
}
function Assert-Synthetic {
  $fixture=Join-Path $env:TEMP ("Geumyi-12-7-CI-"+[guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $fixture|Out-Null
  try{
    $cached=Join-Path $fixture "host.jar"
    [IO.File]::WriteAllText($cached,"known-good")
    $hash=(Get-FileHash -LiteralPath $cached -Algorithm SHA256).Hash.ToLowerInvariant()
    $length=(Get-Item -LiteralPath $cached).Length
    $m=Join-Path $fixture "known-good-manifest.json"
    $record=[ordered]@{files=@([ordered]@{cache_name="host.jar";sha256=$hash;size=$length})}
    $record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $m -Encoding UTF8
    $pass=Check-Manifest $fixture $m
    if($pass.result -ne "CACHED_BYTES_HASHES_MATCH" -or $pass.checked -ne 1 -or
       $pass.offline_known_good_startup_proven){throw "CACHE_MATCH_SYNTHETIC_FAILURE"}
    [IO.File]::WriteAllText($cached,"altered")
    $bad=Check-Manifest $fixture $m
    if($bad.result -eq "CACHED_BYTES_HASHES_MATCH"){throw "CACHE_TAMPERING_FALSE_PASS"}
    [IO.File]::WriteAllText($cached,"known-good")
    $record.files=@([ordered]@{cache_name="../escape.jar";sha256=$hash;size=$length})
    $record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $m -Encoding UTF8
    $traversal=Check-Manifest $fixture $m
    if($traversal.result -eq "CACHED_BYTES_HASHES_MATCH" -or
       $traversal.invalid_record -ne 1){throw "CACHE_TRAVERSAL_FALSE_PASS"}
    $record.files=@(
      [ordered]@{cache_name="host.jar";sha256=$hash;size=$length},
      [ordered]@{cache_name="host.jar";sha256=$hash;size=$length}
    )
    $record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $m -Encoding UTF8
    $dup=Check-Manifest $fixture $m
    if($dup.result -eq "CACHED_BYTES_HASHES_MATCH" -or
       $dup.duplicate_names -ne 1){throw "CACHE_DUPLICATE_FALSE_PASS"}
  }finally{
    if([IO.Directory]::Exists($fixture)){[IO.Directory]::Delete($fixture,$true)}
  }
}
if(-not $OutputDir){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) (
    "Geumyi-Day12-Cache-Integrity-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
}
if($Synthetic){
  Assert-Synthetic
  New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
  $syntheticReport=[ordered]@{schema=1;phase="12.7-cached-bytes-integrity"
    synthetic=$true;result="SYNTHETIC_PASS";read_only=$true
    network_requests=0;cache_modified=$false
    offline_known_good_startup_proven=$false
    canonical_backend_ports_private="UNCHANGED_FAIL"}
  $syntheticReport|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutputDir "Day12-Cache-Integrity-Synthetic.json") -Encoding UTF8
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "SERVER_PC_WINDOWS_ONLY"}
if($null -eq (Get-Service "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){
  throw "REFUSE_SUBPC_OR_UNIDENTIFIED_HOST"
}
$root=Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "GeumyiServerCenter\ArtifactCache\known-good\day12"
$report=Check-Manifest $root (Join-Path $root "known-good-manifest.json")
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir "Day12-Cache-Integrity-READ-ONLY.json"
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Known-good read-only bytes result: "+[string]$report.result)
Write-Host ("SHA256 matched: "+[string]$report.checked+"; missing: "+[string]$report.missing+
  "; mismatched hashes: "+[string]$report.mismatched_sha256)
Write-Host ("Output: "+$out)
Write-Host "Offline startup and Stable remain UNVERIFIED/BLOCKED."
if($report.result -ne "CACHED_BYTES_HASHES_MATCH"){exit 2}
exit 0
