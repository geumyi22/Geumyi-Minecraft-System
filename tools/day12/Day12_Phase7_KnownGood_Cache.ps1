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
  try{$a=Join-Path $t "a.bin";Set-Content $a "known-good" -NoNewline;Copy-Item $a (Join-Path $t "copy.bin");$ok=(Get-Sha256 $a) -eq (Get-Sha256 (Join-Path $t "copy.bin"));[ordered]@{schema=1;phase="12.7";synthetic=$true;result=$(if($ok){"SYNTHETIC_PASS"}else{"FAIL"})}|ConvertTo-Json|Set-Content $out -Encoding UTF8;if(-not$ok){exit 2}}finally{Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue};exit 0
}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"};$root=Join-Path $pd "GeumyiServerCenter";$cacheRoot=Join-Path $root "ArtifactCache\known-good\day12"
if($Mode -eq "Build"){
  if($Confirm -ne "BUILD_DAY12_KNOWN_GOOD_CACHE"){Write-Host "[BLOCKED] explicit confirmation required";exit 23}
  if(-not(Test-Path $Phase0BReport)){throw "Phase0BReport required"}
  $p0=Get-Content $Phase0BReport -Raw -Encoding UTF8|ConvertFrom-Json
  if([string]$p0.phase -ne "12.0B" -or [string]$p0.result -ne "PASS"){
    throw "An actual Phase 12.0B PASS report is required before cache build"
  }
  $required=@("wild","playground","other","lobby")
  $confirmed=@($p0.steps | Where-Object {
    [string]$_.step -eq "create_verify_protect" -and
    [bool]$_.pass -and [bool]$_.retention_exempt -and
    [string]$_.file -match '-full-backup-.*\.zip$' -and
    [string]$_.sha256 -match '^[a-fA-F0-9]{64}$'
  })
  $ids=@($confirmed | ForEach-Object {[string]$_.server_id})
  if($confirmed.Count -ne 4 -or @($ids | Select-Object -Unique).Count -ne 4 -or @($required | Where-Object {$ids -notcontains $_}).Count -gt 0){
    throw "Phase 12.0B report does not confirm four verified, protected, retention-exempt FULL backups"
  }
  New-Item -ItemType Directory -Force -Path $cacheRoot|Out-Null
}
$files=New-Object System.Collections.ArrayList
function AddFile([string]$src,[string]$logical){
  if(-not(Test-Path -LiteralPath $src -PathType Leaf)){return}
  $sha=Get-Sha256 $src;$size=[int64](Get-Item $src).Length
  $safe=($logical -replace '[^A-Za-z0-9_.-]','_')
  if([string]::IsNullOrWhiteSpace($safe)){throw "Invalid cache logical name"}
  if($Mode -eq "Build"){
    $dst=Join-Path $cacheRoot $safe
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if((Get-Sha256 $dst)-ne$sha){throw "cache hash mismatch: $logical"}
  }
  # The recovery kit requires the physical cache_name, not only the original basename.
  [void]$files.Add([ordered]@{logical=$logical;cache_name=$safe;name=[IO.Path]::GetFileName($src);size=$size;sha256=$sha})
}
$pf=if($env:ProgramFiles){$env:ProgramFiles}else{"C:\Program Files"}
# A test fixture may override this locator only inside GitHub Actions.
if($env:GITHUB_ACTIONS -eq "true" -and $env:DAY12_TEST_PROGRAMFILES){
  $pf=[string]$env:DAY12_TEST_PROGRAMFILES
}
$inst=Join-Path $pf "Geumyi Server Center"
if($env:GITHUB_ACTIONS -ne "true" -or -not $env:DAY12_TEST_PROGRAMFILES){
  try {
    $service=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
    $raw=[string]$service.PathName
    $candidate=""
    if($raw -match '^"([^"]+\.exe)"'){$candidate=$Matches[1]}
    elseif($raw -match '^(.+?\.exe)(?:\s|$)'){$candidate=$Matches[1]}
    if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){
      $inst=Split-Path -Parent $candidate
    }
  }catch{}
}
$hostBinary=Join-Path $inst "GeumyiServerHost.exe"
$clientBinary=Join-Path $inst "GeumyiServerCenter.exe"
if($Mode -eq "Build" -and (-not(Test-Path -LiteralPath $hostBinary -PathType Leaf) -or -not(Test-Path -LiteralPath $clientBinary -PathType Leaf))){
  throw "GSC Host/Client executables are missing; refusing incomplete known-good cache"
}
AddFile $hostBinary "gsc-host"
AddFile $clientBinary "gsc-client"
$cfgPath=Join-Path $root "server.json"
if(Test-Path $cfgPath){$cfg=Get-Content $cfgPath -Raw -Encoding UTF8|ConvertFrom-Json;foreach($s in @($cfg.servers)){foreach($j in Get-ChildItem (Join-Path ([string]$s.path) "plugins") -Filter *.jar -File -ErrorAction SilentlyContinue){AddFile $j.FullName ("server-"+[string]$s.id+"-"+$j.Name)}}}
$proxy=Join-Path $root "Network\FourServer";foreach($id in @("wild","playground","other")){foreach($j in Get-ChildItem (Join-Path $proxy ($id+"\plugins")) -Filter *.jar -File -ErrorAction SilentlyContinue){AddFile $j.FullName ("proxy-"+$id+"-"+$j.Name)}}
# Assert every cache record includes the on-disk name expected by Verify-KnownGood.
if($Mode -eq "Build"){
  foreach($row in @($files)){
    $cached=Join-Path $cacheRoot ([string]$row.cache_name)
    if(-not(Test-Path -LiteralPath $cached -PathType Leaf) -or (Get-Sha256 $cached) -ne [string]$row.sha256){
      throw ("Known-good cached artifact missing or changed: "+[string]$row.logical)
    }
  }
}
$r=[ordered]@{schema=1;phase="12.7";mode=$Mode;generated_at=(Get-Date).ToString("o");result=$(if($files.Count -eq 0){"CHECK_REQUIRED"}elseif($Mode -eq "Build"){"PASS"}else{"CAPTURED"});cache_root_created=($Mode -eq "Build");files=@($files);live_files_modified=$false;network_required=$false}
if($Mode -eq "Build"){$r|ConvertTo-Json -Depth 10|Set-Content (Join-Path $cacheRoot "known-good-manifest.json") -Encoding UTF8}
$r|ConvertTo-Json -Depth 10|Set-Content $out -Encoding UTF8
Write-Host ("KNOWN-GOOD CACHE "+$Mode+": "+$r.result);Write-Host ("Report: "+$out);if(-not$files.Count){exit 2}
