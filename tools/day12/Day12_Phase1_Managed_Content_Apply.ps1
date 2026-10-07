[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ManifestPath,
  [string]$OutputDir="",
  [string]$Confirm="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function H256([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function H1([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA1).Hash.ToLowerInvariant()}
function AtomicWrite([string]$path,[string]$text){
  $tmp=$path+".day12-new";[IO.File]::WriteAllText($tmp,$text,(New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $path -Force
}
function SetProp([string]$text,[string]$key,[string]$value){
  $lines=$text -split "\r?\n";$done=$false
  for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -match ("^"+[regex]::Escape($key)+"=")){$lines[$i]=$key+"="+$value;$done=$true}}
  if(-not$done){$lines += ($key+"="+$value)}
  return ($lines -join [Environment]::NewLine)
}
function ValidateZip([string]$path,[string]$kind){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z=[IO.Compression.ZipFile]::OpenRead($path)
  try{
    $names=@($z.Entries|ForEach-Object{$_.FullName.Replace("\","/")})
    if($names -notcontains "pack.mcmeta"){throw "pack.mcmeta missing"}
    if($kind -eq "datapack" -and @($names|Where-Object{$_ -like "data/*"}).Count -eq 0){throw "data/ content missing"}
  }finally{$z.Dispose()}
}
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase1"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase1-ContentApply-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  $tmp=Join-Path $env:TEMP ("Geumyi-Day12-Content-"+[guid]::NewGuid().ToString("N"));New-Item -ItemType Directory -Force -Path $tmp|Out-Null
  try{
    $prop=Join-Path $tmp "server.properties";[IO.File]::WriteAllText($prop,"level-name=world"+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    $t=Get-Content $prop -Raw;$t=SetProp $t "resource-pack-sha1" ("a"*40);AtomicWrite $prop $t
    $ok=(Get-Content $prop -Raw) -match "resource-pack-sha1="
    [ordered]@{schema=1;phase="12.1-apply";synthetic=$true;result=$(if($ok){"SYNTHETIC_PASS"}else{"FAIL"});mutation_scope="temp-only"}|ConvertTo-Json|Set-Content $out -Encoding UTF8
    if(-not$ok){exit 2}
  }finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
  Write-Host "SYNTHETIC PASS";exit 0
}
if($Confirm -ne "APPLY_DAY12_MANAGED_CONTENT"){Write-Host "[BLOCKED] explicit confirmation required";exit 23}
$m=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if([int]$m.schema -ne 1){throw "unsupported manifest schema"}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"};$root=Join-Path $pd "GeumyiServerCenter"
$cfg=Get-Content -LiteralPath (Join-Path $root "server.json") -Raw -Encoding UTF8|ConvertFrom-Json
$targets=@($m.resourcepacks)+@($m.datapacks)|Where-Object{[bool]$_.enabled}
if($targets.Count -eq 0){throw "No enabled managed-content entries"}
$serverIds=@($targets|ForEach-Object{[string]$_.server_id}|Select-Object -Unique)
# Live mutation is permitted only with every target server offline.
try{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/status" -TimeoutSec 15}catch{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/status" -TimeoutSec 15}
$online=@($status.servers|Where-Object{$serverIds -contains [string]$_.id -and [bool]$_.online})
if($online.Count){throw ("Target servers must be OFFLINE: "+(($online|ForEach-Object{$_.id})-join ","))}
$txRoot=Join-Path $root ("ContentTransactions\"+(Get-Date -Format "yyyyMMdd-HHmmss"));New-Item -ItemType Directory -Force -Path $txRoot|Out-Null
$steps=New-Object System.Collections.ArrayList
try{
  foreach($x in $targets){
    $sid=[string]$x.server_id;$s=@($cfg.servers|Where-Object{[string]$_.id -eq $sid}|Select-Object -First 1)
    if($s.Count -ne 1){throw "Unknown server: $sid"}
    $dir=[string]$s[0].path;$src=[string]$x.source_zip
    if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "Source missing: $src"}
    ValidateZip $src ([string]$x.kind)
    $sha=H256 $src;if([string]$x.expected_sha256 -and $sha -ne ([string]$x.expected_sha256).ToLowerInvariant()){throw "SHA-256 mismatch: $($x.id)"}
    $bdir=Join-Path $txRoot $sid;New-Item -ItemType Directory -Force -Path $bdir|Out-Null
    if([string]$x.kind -eq "java_resourcepack"){
      if(-not([string]$x.public_url -match '^https://')){throw "HTTPS public_url required: $($x.id)"}
      $sha1=H1 $src;if([string]$x.expected_sha1 -and $sha1 -ne ([string]$x.expected_sha1).ToLowerInvariant()){throw "SHA-1 mismatch: $($x.id)"}
      $props=Join-Path $dir "server.properties";Copy-Item -LiteralPath $props -Destination (Join-Path $bdir "server.properties.before") -Force
      $text=Get-Content -LiteralPath $props -Raw
      $text=SetProp $text "resource-pack" ([string]$x.public_url)
      $text=SetProp $text "resource-pack-sha1" $sha1
      if([string]$x.resource_pack_id){$text=SetProp $text "resource-pack-id" ([string]$x.resource_pack_id)}
      AtomicWrite $props $text
      [void]$steps.Add([ordered]@{id=[string]$x.id;server_id=$sid;kind="java_resourcepack";pass=$true;sha256=$sha;sha1=$sha1})
    }elseif([string]$x.kind -eq "datapack"){
      $level="world";$props=Join-Path $dir "server.properties"
      foreach($line in Get-Content $props){if($line -match '^level-name=(.+)$'){$level=$Matches[1].Trim()}}
      $dd=Join-Path $dir ($level+"\datapacks");New-Item -ItemType Directory -Force -Path $dd|Out-Null
      $name=[string]$x.target_file;if([string]::IsNullOrWhiteSpace($name)){$name=[IO.Path]::GetFileName($src)}
      if([IO.Path]::GetFileName($name) -ne $name -or -not$name.ToLowerInvariant().EndsWith(".zip")){throw "unsafe target_file"}
      $dst=Join-Path $dd $name
      if(Test-Path -LiteralPath $dst){Copy-Item -LiteralPath $dst -Destination (Join-Path $bdir ($name+".before")) -Force}
      $tmp=$dst+".day12-new";Copy-Item -LiteralPath $src -Destination $tmp -Force
      if((H256 $tmp) -ne $sha){throw "staged datapack hash mismatch"}
      Move-Item -LiteralPath $tmp -Destination $dst -Force
      [void]$steps.Add([ordered]@{id=[string]$x.id;server_id=$sid;kind="datapack";pass=$true;file=$name;sha256=$sha})
    }else{throw "Unsupported live apply kind: $($x.kind)"}
  }
  $result="APPLIED_PENDING_RESTART_E2E"
}catch{
  $result="FAILED_ROLLBACK_REQUIRED";[void]$steps.Add([ordered]@{pass=$false;error=[string]$_.Exception.Message})
}
$r=[ordered]@{schema=1;phase="12.1-apply";generated_at=(Get-Date).ToString("o");result=$result;transaction_root=$txRoot;steps=@($steps);servers_started_or_stopped=$false;bedrock_geyser_apply_performed=$false}
$r|ConvertTo-Json -Depth 10|Set-Content $out -Encoding UTF8
Write-Host ("RESULT: "+$result);Write-Host ("REPORT: "+$out)
if($result -ne "APPLIED_PENDING_RESTART_E2E"){exit 2}
