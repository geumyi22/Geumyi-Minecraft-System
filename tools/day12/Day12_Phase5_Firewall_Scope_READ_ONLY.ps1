[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Get-Field([object]$Item,[string]$Key,[object]$Fallback=$null){
  if($null -eq $Item){return $Fallback}
  $prop=$Item.PSObject.Properties[$Key]
  if($null -eq $prop -or $null -eq $prop.Value){return $Fallback}
  return $prop.Value
}
function BroadCandidate([object]$Port,[object]$App){
  $proto=[string](Get-Field $Port "Protocol" "UNKNOWN")
  $local=[string](Get-Field $Port "LocalPort" "UNKNOWN")
  $program=[string](Get-Field $App "Program" "UNKNOWN")
  return ($proto -in @("TCP","UDP","Any") -and $local -in @("*","Any") -and $program -eq "Any")
}
function Scope([object]$Raw){
  if($null -eq $Raw){return "UNKNOWN"}
  $v=[string]$Raw
  if($v -in @("Any","*")){return "ANY"}
  if($v -eq ""){return "UNKNOWN"}
  if($v -match '(?i)localsubnet'){return "LOCAL_SUBNET_OR_COMPOSITE"}
  return "RESTRICTED_OR_COMPOSITE_REDACTED"
}
function CurrentProfileMatches([object]$RuleProfile,[string[]]$Active){
  $rp=([string]$RuleProfile).Trim()
  if($rp -eq "Any"){return $true}
  $tokens=@($rp.Split(",")|ForEach-Object{$_.Trim()})
  return (@($Active|Where-Object{$tokens -contains $_}).Count -gt 0)
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Firewall-Scope"
}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-Firewall-Scope-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  if(-not(BroadCandidate ([pscustomobject]@{Protocol="TCP";LocalPort="Any"}) ([pscustomobject]@{Program="Any"})) -or
      (BroadCandidate ([pscustomobject]@{Protocol="UDP";LocalPort="19132"}) ([pscustomobject]@{Program="Any"}) -or
      (BroadCandidate ([pscustomobject]@{Protocol="41";LocalPort="Any"}) ([pscustomobject]@{Program="Any"}) -or
      -not(CurrentProfileMatches "Domain, Private" @("Private")) -or
      (CurrentProfileMatches "Public" @("Private")) -or
      (Scope "10.0.0.10") -ne "RESTRICTED_OR_COMPOSITE_REDACTED"){
    throw "Synthetic firewall-scope rules failed"
  }
  [ordered]@{
    schema=1;phase="12.5-firewall-scope";read_only=$true;synthetic=$true
    result="SYNTHETIC_PASS";mutation_performed=$false
  }|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "Day12 firewall-scope synthetic PASS"
  exit 0
}
$phase="PROFILE_DISCOVERY"
$errors=@()
$profileStates=@()
$activeProfiles=@()
try{
  $networkCategories=@(Get-NetConnectionProfile -ErrorAction Stop|ForEach-Object{
    [string](Get-Field $_ "NetworkCategory" "UNKNOWN")
  })
  foreach($c in $networkCategories){
    if($c -eq "DomainAuthenticated"){$c="Domain"}
    if($c -in @("Domain","Private","Public") -and $activeProfiles -notcontains $c){$activeProfiles+= $c}
  }
}catch{$errors+="NETWORK_CATEGORY_UNAVAILABLE"}
try{
  $fwProfiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
  foreach($p in $fwProfiles){
    $profileStates+= [ordered]@{
      name=[string](Get-Field $p "Name" "UNKNOWN")
      enabled=[string](Get-Field $p "Enabled" "UNKNOWN")
      default_inbound_action=[string](Get-Field $p "DefaultInboundAction" "UNKNOWN")
      allow_inbound_rules=[string](Get-Field $p "AllowInboundRules" "UNKNOWN")
      allow_local_firewall_rules=[string](Get-Field $p "AllowLocalFirewallRules" "UNKNOWN")
    }
  }
}catch{$errors+="ACTIVE_PROFILES_UNAVAILABLE"}
$phase="ACTIVE_ALLOW_RULES"
$candidates=@()
$checked=0;$filtersFailed=0;$ruleReadStatus="UNAVAILABLE"
try{
  $rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -Direction Inbound -Enabled True -Action Allow -ErrorAction Stop)
  $ruleReadStatus="CAPTURED"
  foreach($rule in $rules){
    $checked++
    try{
      $pf=Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop
      $app=Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop
    }catch{$filtersFailed++;continue}
    if(-not(BroadCandidate $pf $app)){continue}
    $address=$null;$interfaceType=$null;$iface=$null;$service=$null;$security=$null
    try{$address=Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$errors+="ADDRESS_FILTER_UNAVAILABLE"}
    try{$interfaceType=Get-NetFirewallInterfaceTypeFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$errors+="INTERFACE_TYPE_FILTER_UNAVAILABLE"}
    try{$iface=Get-NetFirewallInterfaceFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$errors+="INTERFACE_FILTER_UNAVAILABLE"}
    try{$service=Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$errors+="SERVICE_FILTER_UNAVAILABLE"}
    try{$security=Get-NetFirewallSecurityFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$errors+="SECURITY_FILTER_UNAVAILABLE"}
    $profile=[string](Get-Field $rule "Profile" "UNKNOWN")
    $interfaceText=[string](Get-Field $iface "InterfaceAlias" "UNKNOWN")
    $interfaceClass=[string](Get-Field $interfaceType "InterfaceType" "UNKNOWN")
    $candidate=[ordered]@{
      candidate_number=($candidates.Count+1)
      profile=$profile
      matches_active_network_categories=$(if($activeProfiles.Count){CurrentProfileMatches $profile $activeProfiles}else{$null})
      protocol=[string](Get-Field $pf "Protocol" "UNKNOWN")
      remote_address_scope=(Scope (Get-Field $address "RemoteAddress" $null))
      local_address_scope=(Scope (Get-Field $address "LocalAddress" $null))
      service_scope=(Scope (Get-Field $service "Service" $null))
      interface_scope=$(if($interfaceText -in @("Any","*")){"ANY"}elseif($interfaceText -eq "UNKNOWN"){"UNKNOWN"}else{"SPECIFIC_REDACTED"})
      interface_type=$interfaceClass
      policy_source_type=[string](Get-Field $rule "PolicyStoreSourceType" "UNKNOWN")
      primary_status=[string](Get-Field $rule "PrimaryStatus" "UNKNOWN")
      edge_traversal=[string](Get-Field $rule "EdgeTraversalPolicy" "UNKNOWN")
      security_authentication=[string](Get-Field $security "Authentication" "UNKNOWN")
      security_encryption=[string](Get-Field $security "Encryption" "UNKNOWN")
      origin_is_named_for_geumyi=([string](Get-Field $rule "DisplayName" "") -match '(?i)Geumyi|Minecraft|Velocity|GSC')
    }
    $candidates+= $candidate
  }
}catch{
  $ruleReadStatus="FAILED"
  $errors+="ACTIVE_RULE_ENUMERATION_FAILURE_"+$phase
}
$errors=@($errors|Sort-Object -Unique)
$state=if($ruleReadStatus -eq "CAPTURED" -and $filtersFailed -eq 0 -and
 $profileStates.Count -gt 0 -and $activeProfiles.Count -gt 0 -and
 $errors.Count -eq 0){"CAPTURED_FOR_REVIEW"}else{"CHECK_REQUIRED"}
$report=[ordered]@{
  schema=1;phase="12.5-firewall-scope";read_only=$true;synthetic=$false
  generated_at=(Get-Date).ToString("o");result=$state
  active_network_category_set=@($activeProfiles|Sort-Object)
  effective_firewall_profiles=$profileStates
  active_allow_rules_examined=$checked;port_application_filter_failures=$filtersFailed
  candidate_count=$candidates.Count;candidates=$candidates
  error_categories=$errors
  notes=@(
    "Read-only inventory of ActiveStore inbound Enabled Allow rules with Any application, Any port and TCP/UDP/Any protocol.",
    "No raw firewall rule names/identifiers, IP addresses, interface aliases, usernames, tokens, executable paths or local hostnames are exported.",
    "Active profile match is advisory, not a complete WFP effective-policy authorization decision.",
    "Blocking rules, IPsec, LocalAddress, InterfaceType, interface aliases, group policy and active firewall profile can constrain broad Allow rules.",
    "CAPTURED_FOR_REVIEW is evidence collection only; never a final 12.5, 12.10 or Stable PASS."
  )
  mutation_performed=$false;secrets_exported=$false
}
$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Firewall policy scope read-only: "+$state)
Write-Host ("Active allow rules scanned: "+$checked)
Write-Host ("Broad candidate rules: "+$candidates.Count)
Write-Host ("Report: "+$out)
if($state -ne "CAPTURED_FOR_REVIEW"){exit 2}
exit 0
