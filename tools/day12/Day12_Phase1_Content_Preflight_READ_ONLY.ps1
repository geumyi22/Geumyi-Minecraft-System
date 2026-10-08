[CmdletBinding()]
param(
  [string]$BaseUrl="http://127.0.0.1:8790",
  [string]$ManifestPath="",
  [string]$OutputDir="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase1"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase1-ContentPreflight-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
function H256([string]$p){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){return ""};(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function H1([string]$p){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){return ""};(Get-FileHash -LiteralPath $p -Algorithm SHA1).Hash.ToLowerInvariant()}
function J([string]$p){try{Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$p) -Method GET -TimeoutSec 15}catch{$null}}
function Optional([object]$Value,[string]$Field,[object]$Default=$null){
  foreach($part in $Field.Split('.')){
    if($null -eq $Value){return $Default}
    $property=$Value.PSObject.Properties[$part]
    if($null -eq $property){return $Default}
    $Value=$property.Value
  }
  if($null -eq $Value){return $Default}
  return $Value
}
function ReadProps([string]$p){
  $o=[ordered]@{}
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){return $o}
  foreach($line in Get-Content -LiteralPath $p -ErrorAction SilentlyContinue){
    if($line -match '^\s*#' -or $line -notmatch '='){continue}
    $kv=$line -split '=',2;$k=$kv[0].Trim();$v=$kv[1].Trim()
    if($k -in @("resource-pack","resource-pack-sha1","resource-pack-id","require-resource-pack","level-name")){
      if($k -eq "resource-pack"){$o[$k]=[ordered]@{configured=(-not[string]::IsNullOrWhiteSpace($v));scheme=$(if($v -match '^https://'){"https"}elseif($v){"other"}else{""})}}
      else{$o[$k]=$v}
    }
  }
  return $o
}
if($Synthetic){
  # Regression: older/partial inventory payloads may omit server/datapacks.
  $inventoryFixture=[pscustomobject]@{ok=$true}
  if($null -ne (Optional $inventoryFixture "server.online" $null)){throw "inventory optional-field regression"}
  [ordered]@{schema=1;phase="12.1";mode="READ_ONLY";synthetic=$true;result="SYNTHETIC_PASS";servers=@();manifest=[ordered]@{configured=$false}}|ConvertTo-Json -Depth 10|Set-Content $out -Encoding UTF8
  Write-Host "SYNTHETIC PASS";exit 0
}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root=Join-Path $pd "GeumyiServerCenter";$cfgPath=Join-Path $root "server.json"
if(-not(Test-Path -LiteralPath $cfgPath)){throw "server.json missing"}
$cfg=Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8|ConvertFrom-Json
$servers=@()
foreach($s in @($cfg.servers)){
  $dir=[string]$s.path;$props=Join-Path $dir "server.properties"
  $inv=J ("/api/v1/servers/"+[uri]::EscapeDataString([string]$s.id)+"/inventory")
  $level="world";$safe=ReadProps $props;if($safe["level-name"]){$level=[string]$safe["level-name"]}
  $dd=Join-Path $dir ($level+"\datapacks")
  $localDp=@()
  if(Test-Path -LiteralPath $dd){$localDp=@(Get-ChildItem -LiteralPath $dd -File -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{name=$_.Name;size=[int64]$_.Length;sha256=H256 $_.FullName}})}
  $servers += [ordered]@{
    id=[string]$s.id;online=$(if($null -ne (Optional $inv "server.online" $null)){[bool](Optional $inv "server.online" $false)}else{$null})
    resource_pack=$safe;datapacks_api=@(Optional $inv "datapacks" @());datapacks_local=$localDp
  }
}
$proxyRoot=Join-Path $root "Network\FourServer"
$bedrock=@()
foreach($id in @("wild","playground","other")){
  $p=Join-Path $proxyRoot $id
  $candidates=@(
    (Join-Path $p "plugins\Geyser-Velocity\packs"),
    (Join-Path $p "plugins\Geyser\packs"),
    (Join-Path $p "packs")
  )
  $found=@($candidates|Where-Object{Test-Path -LiteralPath $_ -PathType Container})
  $files=@()
  foreach($d in $found){$files+=@(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{name=$_.Name;size=[int64]$_.Length;sha256=H256 $_.FullName}})}
  $bedrock += [ordered]@{id=$id;candidate_pack_dirs_found=$found.Count;files=$files;apply_supported=$false;note="Inventory only until exact live Geyser pack directory is confirmed."}
}
$m=$null;$mrows=@()
if($ManifestPath -and (Test-Path -LiteralPath $ManifestPath)){
  $m=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
  foreach($x in @($m.resourcepacks)+@($m.datapacks)){
    if(-not[bool]$x.enabled){continue}
    $src=[string]$x.source_zip
    $exists=Test-Path -LiteralPath $src -PathType Leaf
    $sha256=if($exists){H256 $src}else{""}
    $sha1=if($exists){H1 $src}else{""}
    $mrows += [ordered]@{id=[string]$x.id;kind=[string]$x.kind;server_id=[string]$x.server_id;source_exists=$exists;sha256=$sha256;sha1=$sha1;expected_sha256=[string]$x.expected_sha256;hash_match=($exists -and ([string]::IsNullOrWhiteSpace([string]$x.expected_sha256) -or $sha256 -eq ([string]$x.expected_sha256).ToLowerInvariant()))}
  }
}
$r=[ordered]@{schema=1;phase="12.1";mode="READ_ONLY";synthetic=$false;generated_at=(Get-Date).ToString("o");result="CAPTURED";servers=$servers;bedrock_geyser=$bedrock;manifest=[ordered]@{configured=($null-ne$m);entries=$mrows};mutation_performed=$false}
$r|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "DAY 12 PHASE 1 CONTENT PREFLIGHT CAPTURED";Write-Host ("Report: "+$out)
