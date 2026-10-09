[CmdletBinding()]
param([string]$OutputDir="", [switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Day 12.10: evaluate ActiveStore rule *candidates* for eight backend TCP ports.
# Strictly non-mutating. NEVER claim this emulates Windows Filtering Platform
# or establishes effective reachability, ownership, IPv6 isolation or bind safety.
$privatePorts=@(25570,25571,25572,25573,25575,25576,25577,25579)
$positivePorts=@(25565,25566,25567) # TCP Velocity public positive-control RULE context.
function Val($O,[string]$N,[string]$Default="UNKNOWN"){
  if($null -eq $O){return $Default}
  if($O -is [System.Collections.IDictionary]){
    if($O.Contains($N)){return [string]$O[$N]}
    return $Default
  }
  $p=$O.PSObject.Properties[$N]
  if($null -eq $p -or $null -eq $p.Value){return $Default}
  return [string]$p.Value
}
function ProtocolScope([string]$Raw){
  switch ($Raw.Trim().ToUpperInvariant()){
    "TCP" {return "TCP"}
    "6" {return "TCP"}
    "ANY" {return "ANY"}
    "*" {return "ANY"}
    "256" {return "ANY"}
    "UDP" {return "OTHER"}
    "17" {return "OTHER"}
    default {return "UNKNOWN"}
  }
}
function PortOverlap([string]$Raw,[int]$Target){
  # PASS is never an output. UNKNOWN is deliberately inclusive for unsupported
  # native keywords (RPC, RPC-EPMap, dynamic ports, etc).
  if([string]::IsNullOrWhiteSpace($Raw)){return "UNKNOWN"}
  $tokens=@($Raw.Split(",") | ForEach-Object {$_.Trim()})
  $unknown=$false
  foreach($token in $tokens){
    if($token -in @("*","Any")){return "MATCH"}
    if($token -match '^[0-9]{1,5}$'){
      $v=[int]$token
      if($v -le 65535 -and $v -eq $Target){return "MATCH"}
      if($v -gt 65535){$unknown=$true}
      continue
    }
    if($token -match '^([0-9]{1,5})\s*-\s*([0-9]{1,5})$'){
      $lo=[int]$Matches[1];$hi=[int]$Matches[2]
      if($lo -gt $hi -or $hi -gt 65535){$unknown=$true;continue}
      if($Target -ge $lo -and $Target -le $hi){return "MATCH"}
      continue
    }
    $unknown=$true
  }
  if($unknown){return "UNKNOWN"}
  return "NO_MATCH"
}
function ActiveOverlap([string]$RuleProfile,[string[]]$Active){
  if($Active.Count -eq 0){return "UNKNOWN"}
  if($RuleProfile -in @("*","Any")){return "MATCH"}
  if([string]::IsNullOrWhiteSpace($RuleProfile)){return "UNKNOWN"}
  $tokens=@($RuleProfile.Split(",")|ForEach-Object {$_.Trim()})
  if(@($tokens|Where-Object {$_ -notin @("Domain","Private","Public")}).Count){
    return "UNKNOWN"
  }
  if(@($tokens|Where-Object{$Active -contains $_}).Count){return "MATCH"}
  return "NO_MATCH"
}
function CoarseScope($Raw) {
  if($null -eq $Raw){return "UNKNOWN"}
  $val=[string]$Raw
  if($val -in @("Any","*")){return "ANY"}
  if([string]::IsNullOrWhiteSpace($val)){return "UNKNOWN"}
  if($val -match '(?i)LocalSubnet'){return "LOCAL_SUBNET_OR_COMPOSITE"}
  return "RESTRICTED_OR_COMPOSITE_REDACTED"
}
function ProgramScope($Raw){
  if($null -eq $Raw){return "UNKNOWN"}
  if([string]$Raw -in @("Any","*")){return "ANY"}
  if([string]::IsNullOrWhiteSpace([string]$Raw)){return "UNKNOWN"}
  return "SPECIFIC_REDACTED"
}
function MatchTarget($Rule,[int]$Port,[string[]]$Active){
  $proto=ProtocolScope (Val $Rule "protocol")
  if($proto -eq "OTHER"){return "NO_MATCH"}
  $overlap=PortOverlap (Val $Rule "local_port") $Port
  if($overlap -eq "NO_MATCH"){return "NO_MATCH"}
  $profile=ActiveOverlap (Val $Rule "profile") $Active
  if($profile -eq "NO_MATCH"){return "NO_MATCH"}
  if($proto -eq "UNKNOWN" -or $overlap -eq "UNKNOWN" -or $profile -eq "UNKNOWN"){
    return "POSSIBLE_UNKNOWN"
  }
  return "CANDIDATE"
}
function SummarizeTarget($Rules,[int]$Port,[string[]]$Active){
  $rows=@()
  foreach($r in @($Rules)){
    $match=MatchTarget $r $Port $Active
    if($match -eq "NO_MATCH"){continue}
    $rows+= [ordered]@{
      ordinal=[int]$r.ordinal
      classification=$match
      action=(Val $r "action")
      profile=(Val $r "profile")
      protocol=(Val $r "protocol")
      local_port_match=(PortOverlap (Val $r "local_port") $Port)
      program_scope=(Val $r "program_scope")
      local_address_scope=(Val $r "local_address_scope")
      remote_address_scope=(Val $r "remote_address_scope")
      interface_scope=(Val $r "interface_scope")
      service_scope=(Val $r "service_scope")
      authentication_scope=(Val $r "authentication_scope")
      override_block_rules=(Val $r "override_block_rules")
      policy_source_type=(Val $r "policy_source_type")
      # Matching rule is a candidate, never a true WFP effective decision.
    }
  }
  $allows=@($rows|Where-Object{$_.action -eq "Allow"}).Count
  $blocks=@($rows|Where-Object{$_.action -eq "Block"}).Count
  $unknowns=@($rows|Where-Object{$_.classification -eq "POSSIBLE_UNKNOWN"}).Count
  $bypass=@($rows|Where-Object{$_.override_block_rules -notin @("False","false","NotAllowed","No","0")}).Count
  return [ordered]@{
    port=$Port
    result="CANDIDATE_REVIEW_ONLY"
    allowed_rule_candidates=$allows
    block_rule_candidates=$blocks
    ambiguous_rule_candidates=$unknowns
    bypass_or_unknown_security_rule_candidates=$bypass
    rules=$rows
  }
}
function Evaluate($Rules,[string[]]$Active,[int[]]$Ports){
  $out=@()
  foreach($p in $Ports){$out+=,(SummarizeTarget $Rules $p $Active)}
  return @($out)
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Firewall-Target"
}
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
$out=Join-Path $OutputDir ("Day12-Firewall-Target-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  $rules=@(
    [pscustomobject]@{ordinal=1;action="Allow";protocol="TCP";local_port="Any";profile="Any";program_scope="ANY";local_address_scope="ANY";remote_address_scope="ANY";interface_scope="ANY";service_scope="ANY";authentication_scope="NotRequired";override_block_rules="False";policy_source_type="Local"},
    [pscustomobject]@{ordinal=2;action="Block";protocol="6";local_port="25570-25573";profile="Private";program_scope="ANY";local_address_scope="ANY";remote_address_scope="ANY";interface_scope="ANY";service_scope="ANY";authentication_scope="NotRequired";override_block_rules="False";policy_source_type="Local"},
    [pscustomobject]@{ordinal=3;action="Allow";protocol="UDP";local_port="Any";profile="Any";program_scope="ANY";local_address_scope="ANY";remote_address_scope="ANY";interface_scope="ANY";service_scope="ANY";authentication_scope="NotRequired";override_block_rules="False";policy_source_type="Local"},
    [pscustomobject]@{ordinal=4;action="Allow";protocol="TCP";local_port="RPC";profile="Private";program_scope="ANY";local_address_scope="ANY";remote_address_scope="ANY";interface_scope="ANY";service_scope="ANY";authentication_scope="NotRequired";override_block_rules="False";policy_source_type="Local"},
    [pscustomobject]@{ordinal=5;action="Allow";protocol="TCP";local_port="25575,25577";profile="Public";program_scope="ANY";local_address_scope="ANY";remote_address_scope="ANY";interface_scope="ANY";service_scope="ANY";authentication_scope="NotRequired";override_block_rules="False";policy_source_type="Local"},
    [pscustomobject]@{ordinal=6;action="Allow";protocol="TCP";local_port="25570";profile="Private";program_scope="SPECIFIC_REDACTED";local_address_scope="RESTRICTED_OR_COMPOSITE_REDACTED";remote_address_scope="LOCAL_SUBNET_OR_COMPOSITE";interface_scope="SPECIFIC_REDACTED";service_scope="ANY";authentication_scope="Required";override_block_rules="True";policy_source_type="GroupPolicy"},
    [pscustomobject]@{ordinal=7;action="Allow";protocol="TCP";local_port="25570";profile="INVALID-PROFILE";program_scope="ANY";local_address_scope="ANY";remote_address_scope="ANY";interface_scope="ANY";service_scope="ANY";authentication_scope="NotRequired";override_block_rules="False";policy_source_type="Local"}
  )
  $eval=@(Evaluate $rules @("Private") @(25570,25571,25575,25576))
  $a=@($eval|Where-Object{$_.port -eq 25570})[0]
  $b=@($eval|Where-Object{$_.port -eq 25575})[0]
  $c=@($eval|Where-Object{$_.port -eq 25576})[0]
  if((ProtocolScope "6") -ne "TCP" -or (ProtocolScope "17") -ne "OTHER" -or
     (PortOverlap "25570-25573" 25571) -ne "MATCH" -or
     (PortOverlap "25575,25577" 25576) -ne "NO_MATCH" -or
     (PortOverlap "RPC" 25575) -ne "UNKNOWN" -or
     (ActiveOverlap "Public" @("Private")) -ne "NO_MATCH" -or
     (ActiveOverlap "INVALID-PROFILE" @("Private")) -ne "UNKNOWN" -or
     $a.block_rule_candidates -ne 1 -or $a.allowed_rule_candidates -ne 4 -or
     $a.ambiguous_rule_candidates -ne 2 -or
     $b.allowed_rule_candidates -ne 2 -or $b.ambiguous_rule_candidates -ne 1 -or
     $c.allowed_rule_candidates -ne 2 -or $c.block_rule_candidates -ne 0) {
    throw "FIREWALL_PORT_RULE_SYNTHETIC_CLASSIFICATION_FAILED"
  }
  [ordered]@{
    schema=1;phase="12.10-firewall-target";synthetic=$true;read_only=$true
    result="SYNTHETIC_PASS";firewall_mutation_performed=$false;secrets_exported=$false
    simulation=@($eval)
    canonical_backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "Firewall target candidate rules synthetic PASS"
  exit 0
}
$errors=@()
$activeProfiles=@()
$profileStates=@()
$rawRules=@()
$skipped=0
$num=0
try {
  $networks=@(Get-NetConnectionProfile -ErrorAction Stop)
  foreach($n in $networks){
    $category=Val $n "NetworkCategory"
    if($category -eq "DomainAuthenticated"){$category="Domain"}
    if($category -in @("Domain","Private","Public") -and $activeProfiles -notcontains $category){
      $activeProfiles+=$category
    }
  }
}catch{$errors+="NETWORK_PROFILE_QUERY_FAILED"}
try {
  $profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
  foreach($p in $profiles){
    $profileStates+=[ordered]@{
      name=Val $p "Name"
      enabled=Val $p "Enabled"
      default_inbound_action=Val $p "DefaultInboundAction"
      allow_inbound_rules=Val $p "AllowInboundRules"
      allow_local_firewall_rules=Val $p "AllowLocalFirewallRules"
    }
  }
}catch{$errors+="FIREWALL_PROFILE_QUERY_FAILED"}
try {
  $fw=@(Get-NetFirewallRule -PolicyStore ActiveStore -Direction Inbound -Enabled True -ErrorAction Stop)
  $num=0
  foreach($r in $fw){
    $num++
    try {
      $port=Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
      $app=Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
      $address=Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
      $intf=Get-NetFirewallInterfaceFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
      $inttype=Get-NetFirewallInterfaceTypeFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
      $svc=Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
      $security=Get-NetFirewallSecurityFilter -AssociatedNetFirewallRule $r -ErrorAction Stop
    }catch{
      $skipped++
      $errors+="ASSOCIATED_FILTER_QUERY_FAILED"
      continue
    }
    $proto=Val $port "Protocol"
    $protoScope=ProtocolScope $proto
    if($protoScope -eq "OTHER"){continue}
    $matches=$false
    foreach($p in @($privatePorts+$positivePorts)){
      if((PortOverlap (Val $port "LocalPort") $p) -ne "NO_MATCH"){$matches=$true;break}
    }
    if(-not $matches){continue}
    # All sensitive source attributes are reduced to coarse classifications;
    # no raw rule names/IDs, local/remote IPs, app paths or interface aliases.
    $alias=Val $intf "InterfaceAlias"
    $ifaceScope=if($alias -in @("Any","*")){"ANY"}
      elseif($alias -eq "UNKNOWN"){"UNKNOWN"}
      else{"SPECIFIC_REDACTED"}
    $rawRules+= [pscustomobject]@{
      ordinal=$num
      action=Val $r "Action"
      profile=Val $r "Profile"
      protocol=$proto
      local_port=Val $port "LocalPort"
      program_scope=ProgramScope (Val $app "Program")
      local_address_scope=CoarseScope (Val $address "LocalAddress")
      remote_address_scope=CoarseScope (Val $address "RemoteAddress")
      interface_scope=$ifaceScope
      interface_type_scope=Val $inttype "InterfaceType"
      service_scope=CoarseScope (Val $svc "Service")
      authentication_scope=Val $security "Authentication"
      override_block_rules=Val $security "OverrideBlockRules"
      policy_source_type=Val $r "PolicyStoreSourceType"
    }
  }
}catch{$errors+="ACTIVE_STORE_RULES_QUERY_FAILED"}
$review=@(Evaluate $rawRules $activeProfiles $privatePorts)
$public=@(Evaluate $rawRules $activeProfiles $positivePorts)
$errors=@($errors|Sort-Object -Unique)
$result=if($errors.Count -gt 0 -or $activeProfiles.Count -eq 0 -or $profileStates.Count -eq 0){
  "CHECK_REQUIRED"
}else{"CAPTURED_FOR_REVIEW"}
$report=[ordered]@{
  schema=1;phase="12.10-firewall-target";synthetic=$false;read_only=$true
  result=$result;generated_at=(Get-Date).ToString("o")
  active_network_profiles=@($activeProfiles|Sort-Object)
  firewall_profiles=$profileStates
  enabled_inbound_rules_examined=$num
  rule_candidates_matched=$rawRules.Count
  rule_filter_read_failures=$skipped
  backend_tcp_port_review=$review
  public_tcp_control_rule_review=$public
  error_categories=$errors
  canonical_backend_ports_private="UNCHANGED_FAIL"
  notes=@(
    "Enabling/disabling rules and firewall/audit policy is forbidden; this scan is read-only.",
    "Rule candidates DO NOT prove effective packet filtering. Block precedence, authenticated bypass, GPO, route, IPv6 and IPsec are not emulated.",
    "All wildcard, range, named dynamic port, ambiguous active-profile candidates are kept for review, not silently excluded.",
    "Raw addresses, names, GUIDs, app paths and interface aliases are not exported; port strings may contain standard Windows dynamic target keyword.",
    "Historical successful 0/8 LAN private connects from one vantage are insufficient to prove all external isolation.",
    "No runtime socket address or owner evidence is produced. A candidate block rule is NEVER a backend_ports_private PASS."
  )
  mutation_performed=$false;secrets_exported=$false
}
$report|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Firewall target rule candidates: "+$result)
Write-Host ("Rules examined: "+$num+"; candidates: "+$rawRules.Count+"; filter errors: "+$skipped)
Write-Host ("Report: "+$out)
if($result -ne "CAPTURED_FOR_REVIEW"){exit 2}
exit 0
