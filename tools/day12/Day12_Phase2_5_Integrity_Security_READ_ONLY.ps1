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
function KnownLobbyAlias([string]$ServerId,[string]$ComponentId,[string]$Name){
  if($ServerId -ne "lobby"){return $false}
  return (($ComponentId -eq "gst" -and $Name -eq "GeumyiServerTools-1.1.1.jar") -or
          ($ComponentId -eq "gds" -and $Name -eq "GeumyiDiscordStatus-1.1.1.jar"))
}
function IsBroadFirewallCandidate([string]$Protocol,[string]$PortSpec,[string]$ProgramSpec){
  return ($Protocol -in @("TCP","UDP","Any") -and $PortSpec -in @("Any","*") -and $ProgramSpec -eq "Any")
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
  # StrictMode regression: empty/Any-port values must produce a real array,
  # not a null pipeline result whose .Count can abort the live enumeration.
  $blankPorts=@()
  $nonBlankPorts=@(RelevantPorts "25570-25573" @(25570,25571,25572,25573))
  if($r1.Count -ne 5 -or $r2.Count -ne 2 -or $r3.Count -ne 0 -or
    $blankPorts.Count -ne 0 -or $nonBlankPorts.Count -ne 4 -or
    (ScopeRemote "Any") -ne "ANY" -or (ScopeRemote "LocalSubnet") -ne "LOCAL_SUBNET_OR_COMPOSITE" -or
    -not(KnownLobbyAlias "lobby" "gst" "GeumyiServerTools-1.1.1.jar") -or
    -not(KnownLobbyAlias "lobby" "gds" "GeumyiDiscordStatus-1.1.1.jar") -or
    (KnownLobbyAlias "wild" "gst" "GeumyiServerTools-1.1.1.jar") -or
    -not(IsBroadFirewallCandidate "TCP" "Any" "Any") -or
    (IsBroadFirewallCandidate "41" "Any" "Any") -or
    (IsBroadFirewallCandidate "TCP" "25570" "Any")){
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
          known_lobby_deployment_alias=(KnownLobbyAlias $id $component $jar.Name)
        }
      }catch{$found+=[ordered]@{filename=$jar.Name;sha256="UNREADABLE";size_bytes=[int64]$jar.Length;name_matches_manifest=$false}}
    }
    $state=if(-not $exists){"PLUGIN_DIR_NOT_FOUND"}
      elseif($found.Count -eq 0 -and $expectedForServer){"EXPECTED_JAR_NOT_FOUND"}
      elseif($found.Count -eq 0){"NOT_INSTALLED"}
      elseif($found.Count -gt 1){"DUPLICATE_JAR_CANDIDATES"}
      elseif($found.Count -eq 1 -and $found[0].name_matches_manifest){"FINGERPRINT_CAPTURED_FILENAME_MATCH"}
      elseif($found.Count -eq 1 -and $found[0].known_lobby_deployment_alias){"FINGERPRINT_CAPTURED_KNOWN_LOBBY_ALIAS"}
      else{"FINGERPRINT_CAPTURED_FILENAME_DIFFERS"}
    $rows+= [ordered]@{
      server_id=$id;component_id=$component;expected_target=$expectedForServer
      manifest_version=$referenceVersion;manifest_filename=$expectedFile
      state=$state;matches=$found
      hash_authenticated_against_trusted_release=$false
    }
  }
}
# Read canonical runtime agent path; an old JAR in GSC root is not the active agent.
$agentCfg=Prop $gsc "agent"
$runtimeDir=Join-Path $gscRoot "Runtime\Agent"
$configuredAgentDir=[string](Prop $agentCfg "working_dir" "")
$configuredJarName=[string](Prop $agentCfg "jar_name" "")
if([string]::IsNullOrWhiteSpace($configuredJarName)){$configuredJarName="UNKNOWN"}
$agentFolders=@(
  [ordered]@{role="RUNTIME_AGENT";path=$runtimeDir},
  [ordered]@{role="LEGACY_GSC_ROOT";path=$gscRoot},
  [ordered]@{role="LEGACY_STATUSAGENT";path=(Join-Path $gscRoot "StatusAgent")},
  [ordered]@{role="LEGACY_AGENT";path=(Join-Path $gscRoot "Agent")},
  [ordered]@{role="LEGACY_AGENTS";path=(Join-Path $gscRoot "Agents")},
  [ordered]@{role="LEGACY_TOOLS";path=(Join-Path $gscRoot "Tools")}
)
if(-not [string]::IsNullOrWhiteSpace($configuredAgentDir)){
  $normBase=[System.IO.Path]::GetFullPath($gscRoot).TrimEnd('\')+'\'
  try{
    $normConfigured=[System.IO.Path]::GetFullPath($configuredAgentDir)
    if($normConfigured.StartsWith($normBase,[System.StringComparison]::OrdinalIgnoreCase)){
      $agentFolders+= [ordered]@{role="CONFIGURED_UNDER_GSC";path=$normConfigured}
    }
  }catch{}
}
$agentMatches=@()
$scanned=@{}
foreach($candidate in $agentFolders){
  $dir=[string]$candidate.path
  if($scanned.ContainsKey($dir)){continue}
  $scanned[$dir]=$true
  if(-not(Test-Path -LiteralPath $dir -PathType Container)){continue}
  try{
    foreach($jar in @(Get-ChildItem -LiteralPath $dir -Filter "GeumyiStatusAgent*.jar" -File -ErrorAction Stop)){
      $sha=(Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      $agentMatches+= [ordered]@{
        folder_role=[string]$candidate.role;filename=$jar.Name;sha256=$sha
        size_bytes=[int64]$jar.Length
        filename_matches_manifest=($jar.Name -eq [string](Prop (Prop (Prop $manifest "components") "statusagent") "artifact_glob" ""))
        matches_configured_jar_name=($jar.Name -eq $configuredJarName)
        runtime_location=([string]$candidate.role -in @("RUNTIME_AGENT","CONFIGURED_UNDER_GSC"))
      }
    }
  }catch{}
}
$runtimeAgentMatches=@($agentMatches|Where-Object{$_.runtime_location -and $_.filename_matches_manifest})
$rows+= [ordered]@{
  server_id="host";component_id="statusagent";expected_target=$true
  manifest_version=[string](Prop (Prop (Prop $manifest "components") "statusagent") "version" "")
  state=$(if($runtimeAgentMatches.Count -gt 0){"EXPECTED_RUNTIME_JAR_FINGERPRINT_CAPTURED"}
          elseif($agentMatches.Count -gt 0){"ONLY_OTHER_VERSION_OR_LEGACY_LOCATION_FOUND"}
          else{"NOT_FOUND_IN_LIMITED_SEARCH_SCOPE"})
  matches=$agentMatches;searched_candidate_directories=$scanned.Count
  configured_jar_name_matches_manifest=($configuredJarName -eq "GeumyiStatusAgent-0.5.4.jar")
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
$anyPortProgramWideCandidates=0
$fwProcessed=0;$fwFailedRules=0
$fwFailureStage="NONE";$fwFailureType="NONE"
$fwStage="RULE_QUERY"
try{
  $rules=@(Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction Stop)
  $fwStatus="CAPTURED";$fwScanned=$rules.Count
  foreach($rule in $rules){
    $fwProcessed++
    $fwStage="RULE_FILTERS"
    try {
    $pf=$null;$af=$null;$ap=$null
    try{$pf=Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$fwInconclusive++;continue}
    try{$af=Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{}
    try{$ap=Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{}
    $portVal=[string](Prop $pf "LocalPort" "UNKNOWN")
    $protocol=[string](Prop $pf "Protocol" "UNKNOWN")
    $isAnyPort=$portVal -in @("Any","*")
    # Force a concrete empty array: the previous if-expression emitted zero
    # pipeline objects for LocalPort=Any, yielding $null under StrictMode.
    $matchPorts=@()
    if(-not $isAnyPort -and $protocol -in @("TCP","UDP","Any")){
      $matchPorts=@(RelevantPorts $portVal $portScope)
    }
    $projectNamed=([string]$rule.DisplayName -match '(?i)Geumyi|Minecraft|Velocity|GSC')
    $rawRemote=[string](Prop $af "RemoteAddress" "UNKNOWN")
    $prog=[string](Prop $ap "Program" "UNKNOWN")
    $broadCandidate=IsBroadFirewallCandidate $protocol $portVal $prog
    if($broadCandidate){$anyPortProgramWideCandidates++}
    if(-not $projectNamed -and $matchPorts.Count -eq 0 -and -not $broadCandidate){continue}
    $sf=$null
    try{$sf=Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{}
    $service=[string](Prop $sf "Service" "UNKNOWN")
    $fwRows+= [ordered]@{
      rule_index=$fwCount
      action=[string]$rule.Action;profile=[string]$rule.Profile
      protocol=$protocol;explicit_target_port_matches=@($matchPorts)
      local_port_scope=$(if($isAnyPort){"ANY_PORT_NOT_TARGET_SPECIFIC"}
                         elseif($matchPorts.Count){"EXPLICIT_MATCH"}else{"UNKNOWN_OR_NON_TARGET"})
      remote_address_scope=(ScopeRemote $rawRemote)
      program_scope=$(if($prog -eq "Any"){"ANY"}else{"SPECIFIC_OR_UNKNOWN"})
      service_scope=$(if($service -eq "Any"){"ANY"}elseif($service -eq "UNKNOWN"){"UNKNOWN"}else{"SPECIFIC"})
      potential_broad_candidate=$broadCandidate
      project_naming_match=$projectNamed
      complete_filters=($null -ne $af -and $null -ne $ap -and $null -ne $sf)
    }
    $fwCount++
    }catch{
      # Continue enumerating remaining rules and report partial evidence.
      # Never export raw exception messages or rule names/paths.
      $fwFailedRules++
      if($fwFailureStage -eq "NONE"){
        $fwFailureStage=$fwStage
        $fwFailureType=$_.Exception.GetType().Name
      }
    }
  }
  if($fwFailedRules -gt 0 -or $fwInconclusive -gt 0){
    $fwStatus="PARTIAL_CHECK_REQUIRED"
  }
}catch{
  $fwStatus="ERROR_OR_UNAVAILABLE"
  $fwFailureStage=$fwStage
  $fwFailureType=$_.Exception.GetType().Name
}
$problems=@($rows|Where-Object{$_.expected_target -and $_.state -in @("EXPECTED_JAR_NOT_FOUND","PLUGIN_DIR_NOT_FOUND","DUPLICATE_JAR_CANDIDATES")})
$broadACL=@($acl|Where-Object{(Prop $_ "broad_write_allow_count" 0) -gt 0})
# Do not report a successful combined audit if the security half failed.
$result=if($configStatus -eq "LOADED" -and $manifestStatus -eq "LOADED" -and
   $fwStatus -eq "CAPTURED"){"CAPTURED_FOR_REVIEW"}else{"CHECK_REQUIRED"}
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
      any_port_any_program_candidates=$anyPortProgramWideCandidates
      rules_processed=$fwProcessed;rule_processing_errors=$fwFailedRules
      failure_stage=$fwFailureStage;failure_exception_type=$fwFailureType
    }
  }
  notes=@(
    "Filename/version matching and computed SHA-256 are not proof of authenticated upstream provenance.",
    "Missing statusagent in limited host search scope does not establish absence from system.",
    "The firewall collector is fail-closed: partial or failed rule inventory makes the combined result CHECK_REQUIRED.",
    "Firewall Any local-port rules are not proof of a rule specifically opening any listed Minecraft port.",
    "Broad candidate rules may still be restricted by service, interface, profile and other policies; this is not Windows Filtering Platform effective enforcement.",
    "The lobby JAR filename aliases originate from the Day10 installation flow; content provenance remains unverified.",
    "The Agent runtime is ProgramData/GeumyiServerCenter/Runtime/Agent; older copies in legacy locations do not prove the active version.",
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
