[CmdletBinding()]
param([string]$ProxyRoot="", [string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Inventory only: Never installs, moves, deletes or reloads a resource pack.
if([string]::IsNullOrWhiteSpace($ProxyRoot)){
  $pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
  $ProxyRoot=Join-Path $pd "GeumyiServerCenter\Network\Velocity"
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Bedrock-Pack-Inventory"
}
$known=@{
  "1b2f6fbc-e538-4c8f-8687-2e80b538e091"="playground"
  "6f2ab6a2-224b-4a2c-aa6f-76ec99ccdb8f"="wild_bacap_korean"
  "bf592f9d-3c95-57c6-8823-a5d9b53c156b"="wild_chemtech"
}
function Get-SafePackInfo([string]$FilePath){
  $record=[ordered]@{kind="unknown";version="";valid_manifest=$false;error_category=""}
  $archive=$null;$reader=$null;$stream=$null
  try{
    $archive=[System.IO.Compression.ZipFile]::OpenRead($FilePath)
    $entry=@($archive.Entries|Where-Object{$_.FullName -ceq "manifest.json"})
    if($entry.Count -ne 1){throw "ROOT_MANIFEST_MISSING_OR_DUPLICATED"}
    if($entry[0].Length -gt 262144){throw "MANIFEST_TOO_LARGE"}
    $stream=$entry[0].Open()
    $reader=[System.IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
    $manifest=($reader.ReadToEnd()|ConvertFrom-Json)
    if($null -eq $manifest.header -or $null -eq $manifest.header.uuid -or
       $null -eq $manifest.header.version){throw "MANIFEST_FIELDS_MISSING"}
    $uuid=([string]$manifest.header.uuid).ToLowerInvariant()
    $record.kind=if($known.ContainsKey($uuid)){$known[$uuid]}else{"unknown_uuid"}
    $record.version=(@($manifest.header.version)|ForEach-Object{[string]$_}) -join "."
    $record.valid_manifest=$true
  }catch{
    $record.error_category="INVALID_OR_UNREADABLE_MCPACK"
  }finally{
    if($null -ne $reader){$reader.Dispose()}
    elseif($null -ne $stream){$stream.Dispose()}
    if($null -ne $archive){$archive.Dispose()}
  }
  return $record
}
function MappingCount([string]$Dir){
  $result=[ordered]@{verified_structure_found=$false;item_group_count=0;definition_count=0}
  if(-not(Test-Path -LiteralPath $Dir -PathType Container)){return $result}
  $files=@(Get-ChildItem -LiteralPath $Dir -File -Filter "*.json" -ErrorAction SilentlyContinue)
  foreach($file in $files){
    if($file.Length -gt 4MB){continue}
    try{
      $json=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
      if([int]$json.format_version -ne 2 -or $null -eq $json.items){continue}
      $entries=@($json.items.PSObject.Properties)
      $count=0
      foreach($group in $entries){$count+=@($group.Value).Count}
      if($entries.Count -eq 48 -and $count -eq 212){
        $result.verified_structure_found=$true
        $result.item_group_count=$entries.Count
        $result.definition_count=$count
        break
      }
    }catch{}
  }
  return $result
}
$instances=@()
$ports=@{wild=19132;playground=19133;other=19134}
foreach($id in @("wild","playground","other")){
  $base=Join-Path $ProxyRoot $id
  $geyser=Join-Path $base "plugins\Geyser-Velocity"
  $packs=Join-Path $geyser "packs"
  $config=Join-Path $geyser "config.yml"
  $items=@()
  if(Test-Path -LiteralPath $packs -PathType Container){
    foreach($f in @(Get-ChildItem -LiteralPath $packs -File -ErrorAction SilentlyContinue|
      Where-Object{$_.Extension -in @(".mcpack",".zip")})){
      $items+=Get-SafePackInfo $f.FullName
    }
  }
  $types=@($items|Where-Object{$_.valid_manifest -and $_.kind -ne "unknown_uuid"}|
    ForEach-Object{$_.kind})
  $present=@($types|Select-Object -Unique)
  $missing=@("playground","wild_bacap_korean","wild_chemtech"|
    Where-Object{$_ -notin $present})
  $duplicates=@($types|Group-Object|Where-Object{$_.Count -gt 1}|ForEach-Object{$_.Name})
  $mapping=MappingCount (Join-Path $geyser "custom_mappings")
  $instances+=[ordered]@{
    instance=$id;bedrock_udp=$ports[$id]
    proxy_directory_present=(Test-Path -LiteralPath $base -PathType Container)
    geyser_velocity_jar_present=(Test-Path -LiteralPath (Join-Path $base "plugins\Geyser-Velocity.jar") -PathType Leaf)
    geyser_runtime_directory_present=(Test-Path -LiteralPath $geyser -PathType Container)
    config_present=(Test-Path -LiteralPath $config -PathType Leaf)
    packs_directory_present=(Test-Path -LiteralPath $packs -PathType Container)
    archive_count=@($items).Count
    packs=@($items)
    expected_packs_missing=@($missing)
    known_uuid_duplicates=@($duplicates)
    wild_custom_item_mapping=$mapping
    structurally_ready_for_review=($missing.Count -eq 0 -and $duplicates.Count -eq 0 -and
      $mapping.verified_structure_found -and (Test-Path -LiteralPath $config -PathType Leaf))
  }
}
$allReady=@($instances|Where-Object{-not $_.structurally_ready_for_review}).Count -eq 0
$report=[ordered]@{
  schema=1;phase="12.11-bedrock-initial-proxy-packs"
  generated_at=(Get-Date).ToString("o")
  read_only=$true;production_mutation=$false
  report_scope="LOCAL_FILESYSTEM_METADATA_ONLY"
  expected_entrypoints=3;root_present=(Test-Path -LiteralPath $ProxyRoot -PathType Container)
  instances=$instances
  result=$(if($allReady){"STRUCTURAL_REFERENCE_READY_UNVERIFIED"}else{"PACK_LAYOUT_REVIEW_REQUIRED"})
  all_bedrock_pack_instances_loaded_in_game_verified=$false
  bedrock_login_and_server_switch_e2e_verified=$false
  stable_release_allowed=$false
  notes=@(
    "No file paths, account details, credentials, forwarding secrets, hostnames, IPs or raw mapping contents are exported.",
    "A missing pack in an instance directory does not prove absent client-side global resources.",
    "Geyser pack delivery is negotiated at initial Bedrock login; backend changes do not natively renegotiate.",
    "A file with expected UUID is not evidence that its source bytes match an operator-approved pack.",
    "A mapping shape match is not proof of Geyser mapping runtime acceptance or custom item display.",
    "Inventory only: existing runtime was not restarted, reloaded or modified."
  )
}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-Bedrock-Pack-Inventory-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("BEDROCK PROXY PACK INVENTORY: "+$report.result)
Write-Host ("Report: "+$out)
