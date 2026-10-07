[CmdletBinding()]
param(
  [ValidateSet("Audit","Build")][string]$Mode="Audit",
  [string]$Phase0BReport="",
  [string]$OutputDir="",
  [string]$Confirm="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
function Get-Sha256([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase7"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase7-Cache-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  $t=Join-Path $env:TEMP ("Geumyi-Cache-"+[guid]::NewGuid().ToString("N"));New-Item -ItemType Directory -Force -Path $t|Out-Null
  try{$a=Join-Path $t "a.bin";Set-Content $a "known-good" -NoNewline;Copy-Item $a (Join-Path $t "copy.bin");$ok=(Get-Sha256 $a)-eq(H (Join-Path $t "copy.bin"));[ordered]@{schema=1;phase="12.7";synthetic=$true;result=$(if($ok){"SYNTHETIC_PASS"}else{"FAIL"})}|ConvertTo-Json|Set-Content $out -Encoding UTF8;if(-not$ok){exit 2}}finally{Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue};exit 0
}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"};$root=Join-Path $pd "GeumyiServerCenter";$cacheRoot=Join-Path $root "ArtifactCache\known-good\day12"
if($Mode -eq "Build"){
  if($Confirm -ne "BUILD_DAY12_KNOWN_GOOD_CACHE"){Write-Host "[BLOCKED] explicit confirmation required";exit 23}
  if(-not(Test-Path $Phase0BReport)){throw "Phase0BReport required"}
  $p0=Get-Content $Phase0BReport -Raw -Encoding UTF8|ConvertFrom-Json
  if([string]$p0.result -ne "PASS"){throw "Phase 12.0B PASS report required before cache build"}
  New-Item -ItemType Directory -Force -Path $cacheRoot|Out-Null
}
$files=New-Object System.Collections.ArrayList
function AddFile([string]$src,[string]$logical){
  if(-not(Test-Path -LiteralPath $src -PathType Leaf)){return}
  $sha=Get-Sha256 $src;$size=[int64](Get-Item $src).Length
  if($Mode -eq "Build"){
    $safe=($logical -replace '[^A-Za-z0-9_.-]','_');$dst=Join-Path $cacheRoot $safe
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if((Get-Sha256 $dst)-ne$sha){throw "cache hash mismatch: $logical"}
  }
  [void]$files.Add([ordered]@{logical=$logical;name=[IO.Path]::GetFileName($src);size=$size;sha256=$sha})
}
$pf=if($env:ProgramFiles){$env:ProgramFiles}else{"C:\Program Files"};$inst=Join-Path $pf "Geumyi Server Center"
AddFile (Join-Path $inst "GeumyiServerHost.exe") "gsc-host"
AddFile (Join-Path $inst "GeumyiServerCenter.exe") "gsc-client"
$cfgPath=Join-Path $root "server.json"
if(Test-Path $cfgPath){$cfg=Get-Content $cfgPath -Raw -Encoding UTF8|ConvertFrom-Json;foreach($s in @($cfg.servers)){foreach($j in Get-ChildItem (Join-Path ([string]$s.path) "plugins") -Filter *.jar -File -ErrorAction SilentlyContinue){AddFile $j.FullName ("server-"+[string]$s.id+"-"+$j.Name)}}}
$proxy=Join-Path $root "Network\FourServer";foreach($id in @("wild","playground","other")){foreach($j in Get-ChildItem (Join-Path $proxy ($id+"\plugins")) -Filter *.jar -File -ErrorAction SilentlyContinue){AddFile $j.FullName ("proxy-"+$id+"-"+$j.Name)}}
$r=[ordered]@{schema=1;phase="12.7";mode=$Mode;generated_at=(Get-Date).ToString("o");result=$(if($files.Count){"CAPTURED"}else{"CHECK_REQUIRED"});cache_root_created=($Mode -eq "Build");files=@($files);live_files_modified=$false;network_required=$false}
if($Mode -eq "Build"){$r|ConvertTo-Json -Depth 10|Set-Content (Join-Path $cacheRoot "known-good-manifest.json") -Encoding UTF8}
$r|ConvertTo-Json -Depth 10|Set-Content $out -Encoding UTF8
Write-Host ("KNOWN-GOOD CACHE "+$Mode+": "+$r.result);Write-Host ("Report: "+$out);if(-not$files.Count){exit 2}
