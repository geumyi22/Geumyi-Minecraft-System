[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$ids=@("wild","playground","other","lobby")
$components=@("gst","gds","statusagent","technology","chemistry")
$portScope=@(25565,25566,25567,25570,25571,25572,25573,25575,25576,25577,25579,8790,8787,19132,19133,19134)
function Prop([object]$Object,[string]$Name,[object]$Default=$null){
  if($null -eq $Object){return $Default}
  if($Object -is [System.Collections.IDictionary]){
    if($Object.Contains($Name)){return $Object[$Name]}
    return $Default
  }
  $p=$Object.PSObject.Properties[$Name]
  if($null -eq $p -or $null -eq $p.Value){return $Default}
  return $p.Value
}
function RelevantPorts([string]$Spec,[int[]]$Wanted){
  if($Spec -in @("*","Any")){return @($Wanted)}
  $seen=New-Object System.Collections.ArrayList
  foreach($part in $Spec.Split(",")){
    $token=$part.Trim()
    if($token -match '^(\d+)$'){
      $p=[int]$Matches[1]
      if($Wanted -contains $p -and -not $seen.Contains($p)){[void]$seen.Add($p)}
    }elseif($token -match '^(\d+)-(\d+)$'){
      $lo=[int]$Matches[1];$hi=[int]$Matches[2]
      if($lo -le $hi){
        foreach($p in $Wanted){if($p -ge $lo -and $p -le $hi -and -not $seen.Contains($p)){[void]$seen.Add($p)}}
      }
    }
  }
  return $seen.ToArray()
}
function ScopeRemote([string]$Value){
  $s=$Value.Trim()
  if($s -in @("Any","*")){return "ANY"}
  if($s -match '(?i)localsubnet'){return "LOCAL_SUBNET_OR_COMPOSITE"}
  if([string]::IsNullOrWhiteSpace($s)){return "UNKNOWN"}
  return "EXPLICIT_RESTRICTED_OR_COMPOSITE"
}
function RoleSid([object]$Identity){
  $sid=""
  try{$sid=[string]$Identity.Translate([System.Security.Principal.SecurityIdentifier]).Value}catch{}
  if(-not $sid){return "OTHER_OR_UNRESOLVED"}
  switch($sid){
    "S-1-5-18" {return "SYSTEM"}
    "S-1-5-32-544" {return "ADMINISTRATORS"}
    "S-1-5-32-545" {return "BUILTIN_USERS"}
    "S-1-1-0" {return "EVERYONE"}
    "S-1-5-11" {return "AUTHENTICATED_USERS"}
    default {return "OTHER_OR_LOCAL_ACCOUNT"}
  }
}
function ACLSummary([string]$Folder,[string]$Label){
  if(-not(Test-Path -LiteralPath $Folder -PathType Container)){
    return [ordered]@{label=$Label;available=$false;entries=@();status="PATH_NOT_PRESENT"}
  }
  try{
    $a=Get-Acl -LiteralPath $Folder -ErrorAction Stop
    $entries=@()
    foreach($ace in @($a.Access)){
      $role=RoleSid $ace.IdentityReference
      $rights=[string]$ace.FileSystemRights
      $writes=($rights -match 'FullControl|Modify|Write|CreateFiles|CreateDirectories|Delete|ChangePermissions|TakeOwnership')
      $entries+= [ordered]@{
        role_group=$role;permission=$(if($writes){"WRITE_OR_MODIFY"}else{"READ_OR_OTHER"})
        access_type=[string]$ace.AccessControlType;inherited=[bool]$ace.IsInherited
      }
    }
    $highRisk=@($entries|Where-Object{$_.role_group -in @("EVERYONE","BUILTIN_USERS","AUTHENTICATED_USERS") -and $_.permission -eq "WRITE_OR_MODIFY" -and $_.access_type -eq "Allow"})
    return [ordered]@{
      label=$Label;available=$true;entry_count=$entries.Count
      broad_write_allow_count=$highRisk.Count;entries=$entries;status="CAPTURED_FOR_REVIEW"
    }
  }catch{
    return [ordered]@{label=$Label;available=$true;entries=@();status="ACL_UNREADABLE"}
  }
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Integrity-Security"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-Integrity-Security-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  $r1=@(RelevantPorts "25570-25573,25579" @(25565,25570,25571,25572,25573,25579))
  $r2=@(RelevantPorts "Any" @(25565,25570))
  $r3=@(RelevantPorts "RPC-EPMap" @(25565,25570))
  if($r1.Count -ne 5 -or $r2.Count -ne 2 -or $r3.Count -ne 0 -or
    (ScopeRemote "Any") -ne "ANY" -or (ScopeRemote "LocalSubnet") -ne "LOCAL_SUBNET_OR_COMPOSITE"){
    throw "Day12 phase2+5 synthetic parser regression"
  }
  [ordered]@{schema=1;phase="12.2+12.5";read_only=$true;synthetic=$true;result="SYNTHETIC_PASS";mutation_performed=$false}|
    ConvertTo-Json -Depth 5|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "Synthetic 12.2/12.5 PASS";exit 0
}
$programData=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$gscRoot=Join-Path $programData "GeumyiServerCenter"
$configFile=Join-Path $gscRoot "server.json"
$manifestFile=Join-Path $PSScriptRoot "..\..\deploy\components.json"
$gsc=$null;$manifest=$null;$configStatus="MISSING";$manifestStatus="MISSING"
try{
  if(Test-Path -LiteralPath $configFile -PathType Leaf){
    $gsc=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8|ConvertFrom-Json
    $configStatus="LOADED"
  }
}catch{$configStatus="UNREADABLE"}
try{
  if(Test-Path -LiteralPath $manifestFile -PathType Leaf){
    $manifest=Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8|ConvertFrom-Json
    $manifestStatus="LOADED"
  }
}catch{$manifestStatus="UNREADABLE"}

# Strict allowlist for file names; never read or export server.json, .env,
# logs, server.properties, credentials or absolute install paths.
$prefixes=@{
  gst="GeumyiServerTools";gds="GeumyiDiscordStatus"
  technology="GeumyiTechnology";chemistry="GeumyiChemistry"
  statusagent="GeumyiStatusAgent"
}
$location=@{}
foreach($entry in @(Prop $gsc "servers" @())){
  if($null -eq $entry){continue}
  $id=([string](Prop $entry "id" "")).ToLowerInvariant()
  if($id -notin $ids){continue}
  $dir=[string](Prop $entry "path" "")
  if(-not [string]::IsNullOrWhiteSpace($dir)){$location[$id]=$dir}
}
$rows=@()
$checks=@()
foreach($id in $ids){
  $folder=if($location.ContainsKey($id)){Join-Path $location[$id] "plugins"}else{""}
  $exists=$folder -and (Test-Path -LiteralPath $folder -PathType Container)
  $jars=@()
  if($exists){
    try{$jars=@(Get-ChildItem -LiteralPath $folder -Filter "*.jar" -File -ErrorAction Stop)}catch{}
  }
  foreach($component in @("gst","gds","technology","chemistry")){
    $meta=Prop (Prop $manifest "components") $component
    $targets=@(Prop $meta "targets" @())
    $expectedForServer=($targets -contains "*" -or $targets -contains $id)
    $referenceVersion=[string](Prop $meta "version" "")
    $expectedFile=[string](Prop $meta "artifact_glob" "")
    $found=@()
    foreach($jar in $jars){
      if($jar.Name -notmatch ('^'+[regex]::Escape($prefixes[$component])+'(?:-|\.jar)')){continue}
      try{
        $sha=(Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $found+= [ordered]@{
          filename=$jar.Name;sha256=$sha;size_bytes=[int64]$jar.Length
          name_matches_manifest=($jar.Name -eq $expectedFile)
        }
      }catch{$found+=[ordered]@{filename=$jar.Name;sha256="UNREADABLE";size_bytes=[int64]$jar.Length;name_matches_manifest=$false}}
    }
    $state=if(-not $exists){"PLUGIN_DIR_NOT_FOUND"}
      elseif($found.Count -eq 0 -and $expectedForServer){"EXPECTED_JAR_NOT_FOUND"}
      elseif($found.Count -eq 0){"NOT_INSTALLED"}
      elseif($found.Count -gt 1){"DUPLICATE_JAR_CANDIDATES"}
      elseif($found.Count -eq 1 -and $found[0].name_matches_manifest){"FINGERPRINT_CAPTURED_FILENAME_MATCH"}
      else{"FINGERPRINT_CAPTURED_FILENAME_DIFFERS"}
    $rows+= [ordered]@{
      server_id=$id;component_id=$component;expected_target=$expectedForServer
      manifest_version=$referenceVersion;manifest_filename=$expectedFile
      state=$state;matches=$found
      hash_authenticated_against_trusted_release=$false
    }
  }
}
# The StatusAgent is host-targeted. Search only conservative known directories;
# "not found" means not found IN THIS SEARCH SCOPE, never "not installed".
$agentFolders=@(
  $gscRoot,(Join-Path $gscRoot "StatusAgent"),(Join-Path $gscRoot "Agent"),
  (Join-Path $gscRoot "Agents"),(Join-Path $gscRoot "Tools")
)
$agentMatches=@()
foreach($dir in $agentFolders){
  if(-not(Test-Path -LiteralPath $dir -PathType Container)){continue}
  try{
    foreach($jar in @(Get-ChildItem -LiteralPath $dir -Filter "GeumyiStatusAgent*.jar" -File -ErrorAction Stop)){
      $sha=(Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      $agentMatches+= [ordered]@{folder_role="HOST_CANDIDATE";filename=$jar.Name;sha256=$sha;size_bytes=[int64]$jar.Length}
    }
  }catch{}
}
$rows+= [ordered]@{
  server_id="host";component_id="statusagent";expected_target=$true
  manifest_version=[string](Prop (Prop (Prop $manifest "components") "statusagent") "version" "")
  state=$(if($agentMatches.Count){"FINGERPRINT_CAPTURED_SEARCH_SCOPE"}else{"NOT_FOUND_IN_LIMITED_SEARCH_SCOPE"})
  matches=$agentMatches;searched_candidate_directories=$agentFolders.Count
  hash_authenticated_against_trusted_release=$false
}

$acl=@(ACLSummary $gscRoot "GSC_PROGRAMDATA")
foreach($id in $ids){
  if($location.ContainsKey($id)){
    $acl+= ACLSummary (Join-Path $location[$id] "plugins") ("PLUGINS_"+$id.ToUpperInvariant())
  }
}
# Only selected firewall properties are exported. Rule names, program paths,
# individual user SIDs, remote addresses and rule descriptions are redacted.
$fwStatus="UNAVAILABLE";$fwScanned=0;$fwRows=@();$fwCount=0;$fwInconclusive=0
try{
  $rules=@(Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction Stop)
  $fwStatus="CAPTURED";$fwScanned=$rules.Count
  foreach($rule in $rules){
    $pf=$null;$af=$null;$ap=$null
    try{$pf=Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$fwInconclusive++;continue}
    try{$af=Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{}
    try{$ap=Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{}
    $portVal=[string](Prop $pf "LocalPort" "UNKNOWN")
    $protocol=[string](Prop $pf "Protocol" "UNKNOWN")
    $matchPorts=@(RelevantPorts $portVal $portScope)
    $projectNamed=([string]$rule.DisplayName -match '(?i)Geumyi|Minecraft|Velocity|GSC')
    if(-not $projectNamed -and $matchPorts.Count -eq 0){continue}
    $rawRemote=[string](Prop $af "RemoteAddress" "UNKNOWN")
    $prog=[string](Prop $ap "Program" "Any")
    $fwRows+= [ordered]@{
      rule_index=$fwCount
      action=[string]$rule.Action;profile=[string]$rule.Profile
      protocol=$protocol;target_port_matches=@($matchPorts)
      port_scope=$(if($portVal -in @("Any","*")){"ANY"}elseif($matchPorts.Count){"MATCHED"}else{"UNKNOWN_OR_OTHER"})
      remote_address_scope=(ScopeRemote $rawRemote)
      program_scope=$(if($prog -eq "Any"){"ANY"}else{"SPECIFIC_OR_UNKNOWN"})
      project_naming_match=$projectNamed
      complete_filters=($null -ne $af -and $null -ne $ap)
    }
    $fwCount++
  }
}catch{
  $fwStatus="ERROR_OR_UNAVAILABLE"
}
$problems=@($rows|Where-Object{$_.expected_target -and $_.state -in @("EXPECTED_JAR_NOT_FOUND","PLUGIN_DIR_NOT_FOUND","DUPLICATE_JAR_CANDIDATES")})
$broadACL=@($acl|Where-Object{(Prop $_ "broad_write_allow_count" 0) -gt 0})
$result=if($configStatus -eq "LOADED" -and $manifestStatus -eq "LOADED"){"CAPTURED_FOR_REVIEW"}else{"CHECK_REQUIRED"}
$report=[ordered]@{
  schema=1;phase="12.2+12.5";read_only=$true;synthetic=$false
  generated_at=(Get-Date).ToString("o");result=$result
  reference=[ordered]@{
    config=$configStatus;manifest=$manifestStatus
    source="deploy/components.json";trusted_hash_reference_available=$false
  }
  fingerprints=[ordered]@{components=$rows;expected_location_warnings=$problems.Count}
  security=[ordered]@{
    acl=$acl;broad_acl_write_warning_count=$broadACL.Count
    firewall=[ordered]@{
      status=$fwStatus;inbound_enabled_rules_inspected=$fwScanned
      matching_rules=@($fwRows);port_filter_inspection_failures=$fwInconclusive
    }
  }
  notes=@(
    "Filename/version matching and computed SHA-256 are not proof of authenticated upstream provenance.",
    "Missing statusagent in limited host search scope does not establish absence from system.",
    "Firewall report is a review inventory, not Windows Filtering Platform effective enforcement.",
    "All absolute server paths, usernames, tokens, passwords, firewall rule names, program paths and remote addresses are omitted.",
    "ACL and firewall changes, deploy, backups, server start/restart, and final gate changes are NOT performed."
  )
  mutation_performed=$false;secrets_exported=$false
}
$report|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Day12 12.2+12.5 READ-ONLY: "+$result)
Write-Host ("Artifact fingerprints: "+$rows.Count+" component-location rows")
Write-Host ("Firewall rules reviewed: "+$fwScanned+"; selected: "+$fwRows.Count)
Write-Host ("Report: "+$out)
if($result -ne "CAPTURED_FOR_REVIEW"){exit 2}
exit 0
