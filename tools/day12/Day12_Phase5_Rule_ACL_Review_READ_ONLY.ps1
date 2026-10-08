[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Field([object]$O,[string]$Key,[object]$Default=$null){
  if($null -eq $O){return $Default}
  $p=$O.PSObject.Properties[$Key]
  if($null -eq $p -or $null -eq $p.Value){return $Default}
  return $p.Value
}
function RuleCategory([string]$Text){
  # Classification is a HINT, not a verified publisher/origin.
  if($Text -match '(?i)tailscale|wireguard|zerotier|openvpn|vpn'){return "VPN_OR_OVERLAY_HINT"}
  if($Text -match '(?i)hyper-v|hyperv|wsl|subsystem for linux|docker|container|hns'){return "VIRTUALIZATION_HINT"}
  if($Text -match '(?i)remote desktop|terminal services|remote assistance|winrm|quick assist|rdp'){return "REMOTE_MANAGEMENT_HINT"}
  if($Text -match '(?i)core networking|network discovery|file and printer|windows defender|microsoft windows|delivery optimization|windows update'){return "WINDOWS_FEATURE_HINT"}
  if($Text -match '(?i)minecraft|geumyi|velocity|paper|java'){return "MINECRAFT_OR_JAVA_HINT"}
  if($Text -match '(?i)xbox|game bar|gaming|steam|epic games'){return "GAMING_HINT"}
  if($Text -match '(?i)bonjour|chromecast|upnp|mdns|discovery'){return "DISCOVERY_HINT"}
  return "UNCLASSIFIED"
}
function ProfileOverlap([string]$Rule,[string[]]$Active){
  if($Rule -eq "Any"){return $true}
  $names=@($Rule.Split(",")|ForEach-Object{$_.Trim()})
  return (@($Active|Where-Object{$names -contains $_}).Count -gt 0)
}
function BroadRule([object]$Port,[object]$App){
  return ([string](Field $Port "LocalPort" "UNKNOWN") -in @("Any","*") -and
    [string](Field $App "Program" "UNKNOWN") -eq "Any" -and
    [string](Field $Port "Protocol" "UNKNOWN") -in @("TCP","UDP","Any"))
}
function SidGroup([object]$Identity){
  $sid=""
  try{$sid=[string]$Identity.Translate([System.Security.Principal.SecurityIdentifier]).Value}catch{}
  switch($sid){
    "S-1-5-18" {return "SYSTEM"}
    "S-1-5-32-544" {return "ADMINISTRATORS"}
    "S-1-5-32-545" {return "BUILTIN_USERS"}
    "S-1-1-0" {return "EVERYONE"}
    "S-1-5-11" {return "AUTHENTICATED_USERS"}
    "S-1-3-0" {return "CREATOR_OWNER"}
    default {return "OTHER_OR_UNRESOLVED"}
  }
}
function Rights([object]$ACE){
  $mask=[int64]$ACE.FileSystemRights
  $t=[System.Security.AccessControl.FileSystemRights]
  # Exact bitmask tests; a general string 'Write' match misclassifies rights.
  $writeData=($mask -band [int64]$t::WriteData) -ne 0
  $appendData=($mask -band [int64]$t::AppendData) -ne 0
  $delete=($mask -band [int64]$t::Delete) -ne 0
  # Directory-specific DeleteChild may allow removal of child files even if
  # the child file's own ACL does not grant DELETE.
  $deleteChild=($mask -band [int64]$t::DeleteSubdirectoriesAndFiles) -ne 0
  $changePermissions=($mask -band [int64]$t::ChangePermissions) -ne 0
  $ownership=($mask -band [int64]$t::TakeOwnership) -ne 0
  $writeAttrs=($mask -band [int64]$t::WriteAttributes) -ne 0
  return [ordered]@{
    write_data_or_create_files=$writeData
    append_data_or_create_dirs=$appendData
    delete=$delete
    delete_children=$deleteChild
    change_permissions=$changePermissions
    take_ownership=$ownership
    write_attributes=$writeAttrs
    potentially_mutating=($writeData -or $appendData -or $delete -or $deleteChild -or $changePermissions -or $ownership)
  }
}
function ACLRecord([string]$Path,[string]$Role,[bool]$IsFile){
  if(-not (Test-Path -LiteralPath $Path -PathType $(if($IsFile){"Leaf"}else{"Container"}))){
    return [ordered]@{target_role=$Role;exists=$false;status="NOT_FOUND";aces=@()}
  }
  try{
    $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
    $rows=@()
    foreach($ace in @($acl.Access)){
      # PowerShell variables are case-insensitive: $role overwrote $Role
      # parameter, corrupting target_role in successful ACL captures.
      $principalGroup=SidGroup $ace.IdentityReference
      $rights=Rights $ace
      $rows+= [ordered]@{
        principal_group=$principalGroup;access_type=[string]$ace.AccessControlType
        inherited=[bool]$ace.IsInherited
        inheritance_flags=[string]$ace.InheritanceFlags
        propagation_flags=[string]$ace.PropagationFlags
        rights=$rights
      }
    }
    $broadAllow=@($rows|Where-Object{
      $_.principal_group -in @("EVERYONE","AUTHENTICATED_USERS","BUILTIN_USERS") -and
      $_.access_type -eq "Allow" -and $_.rights.potentially_mutating
    })
    return [ordered]@{
      target_role=$Role;exists=$true;status="CAPTURED";protected_acl=[bool]$acl.AreAccessRulesProtected
      ace_count=$rows.Count;broad_mutating_allow_ace_count=$broadAllow.Count
      aces=$rows
    }
  }catch{
    return [ordered]@{target_role=$Role;exists=$true;status="ACL_READ_FAILED";aces=@()}
  }
}
function AddrScope([object]$Value){
  $s=[string]$Value
  if($s -in @("Any","*")){return "ANY"}
  if($s -match '(?i)localsubnet'){return "LOCAL_SUBNET_OR_COMPOSITE"}
  if([string]::IsNullOrWhiteSpace($s)){return "UNKNOWN"}
  return "RESTRICTED_REDACTED"
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Rule-ACL-Review"
}
New-Item -Path $OutputDir -ItemType Directory -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-Rule-ACL-Review-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  $a=RuleCategory "Tailscale Client"
  $b=RuleCategory "Windows Remote Desktop"
  $c=RuleCategory "Unmapped CustomAppName"
  $d=ProfileOverlap "Domain, Private" @("Private")
  $e=ProfileOverlap "Public" @("Private")
  $x=BroadRule ([pscustomobject]@{LocalPort="Any";Protocol="TCP"}) ([pscustomobject]@{Program="Any"})
  $y=BroadRule ([pscustomobject]@{LocalPort="8787";Protocol="TCP"}) ([pscustomobject]@{Program="Any"})
  $z=AddrScope "192.168.0.1"
  $aceTest=[pscustomobject]@{FileSystemRights=[System.Security.AccessControl.FileSystemRights]::WriteData}
  $rightsTest=Rights $aceTest
  $delChildTest=Rights ([pscustomobject]@{
    FileSystemRights=[System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles
  })
  # Use the already-created temporary output directory, never production.
  # This catches ACL target-role/ACE principal variable collisions on Windows.
  $aclSynthetic=ACLRecord $OutputDir "SYNTHETIC_OUTPUT_DIR" $false
  if($a -ne "VPN_OR_OVERLAY_HINT" -or $b -ne "REMOTE_MANAGEMENT_HINT" -or
    $c -ne "UNCLASSIFIED" -or (-not $d) -or $e -or (-not $x) -or $y -or
    $z -ne "RESTRICTED_REDACTED" -or
    (-not $rightsTest.write_data_or_create_files) -or
    (-not $rightsTest.potentially_mutating) -or $rightsTest.delete -or
    (-not $delChildTest.delete_children) -or (-not $delChildTest.potentially_mutating) -or
    $aclSynthetic.status -ne "CAPTURED" -or
    $aclSynthetic.target_role -ne "SYNTHETIC_OUTPUT_DIR"){
    throw "Rule classification parser regression"
  }
  [ordered]@{schema=1;phase="12.5-rule-acl";read_only=$true;synthetic=$true
    result="SYNTHETIC_PASS";mutation_performed=$false
  }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "Synthetic firewall rule and ACL classifier: PASS"
  exit 0
}
$errors=@();$profiles=@()
try{
  foreach($cat in @(Get-NetConnectionProfile -ErrorAction Stop)){
    $p=[string](Field $cat "NetworkCategory" "UNKNOWN")
    if($p -eq "DomainAuthenticated"){$p="Domain"}
    if($p -in @("Domain","Private","Public") -and $profiles -notcontains $p){$profiles+= $p}
  }
}catch{$errors+="ACTIVE_NETWORK_PROFILE_UNAVAILABLE"}
$ruleCount=0;$filterFailures=0;$rulesOut=@();$ruleQuery="UNAVAILABLE"
try{
  $rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -Direction Inbound -Enabled True -Action Allow -ErrorAction Stop)
  $ruleQuery="CAPTURED"
  foreach($rule in $rules){
    $ruleCount++
    try{
      $pf=Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop
      $app=Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop
    }catch{$filterFailures++;continue}
    if(-not (BroadRule $pf $app)){continue}
    $addr=$null;$svc=$null;$sec=$null
    try{$addr=Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$errors+="ADDRESS_FILTER_FAILED"}
    try{$svc=Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$errors+="SERVICE_FILTER_FAILED"}
    try{$sec=Get-NetFirewallSecurityFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop}catch{$errors+="SECURITY_FILTER_FAILED"}
    $nameText=([string](Field $rule "DisplayName" ""))+" "+([string](Field $rule "DisplayGroup" ""))+
      " "+([string](Field $rule "Name" ""))+" "+([string](Field $rule "Group" ""))
    $profile=[string](Field $rule "Profile" "UNKNOWN")
    $localAddr=AddrScope (Field $addr "LocalAddress" "")
    $remoteAddr=AddrScope (Field $addr "RemoteAddress" "")
    $cls=RuleCategory $nameText
    $rulesOut+= [ordered]@{
      ordinal=$rulesOut.Count+1
      classification_hint=$cls;classification_is_verified=$false
      has_display_group=(-not [string]::IsNullOrWhiteSpace([string](Field $rule "DisplayGroup" "")))
      active_network_profile_overlap=$(if($profiles.Count -gt 0){ProfileOverlap $profile $profiles}else{$null})
      profile=$profile;protocol=[string](Field $pf "Protocol" "UNKNOWN")
      local_scope=$localAddr;remote_scope=$remoteAddr
      service_scope=$(if([string](Field $svc "Service" "") -eq "Any"){"ANY"}else{"SPECIFIC_OR_UNKNOWN"})
      policy_source_type=[string](Field $rule "PolicyStoreSourceType" "UNKNOWN")
      edge_policy=[string](Field $rule "EdgeTraversalPolicy" "UNKNOWN")
      auth_mode=[string](Field $sec "Authentication" "UNKNOWN")
      action=[string](Field $rule "Action" "UNKNOWN")
      broad_review_priority=$(if($profile -eq "Any" -or $profile -match "Public"){"HIGHER_REVIEW"}
        else{"NORMAL_REVIEW"})
    }
  }
}catch{$errors+="FIREWALL_ACTIVE_RULE_QUERY_FAILED";$ruleQuery="FAILED"}
$programData=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root=Join-Path $programData "GeumyiServerCenter"
$aclTargets=@(
  (ACLRecord $root "GSC_PROGRAMDATA_DIR" $false),
  (ACLRecord (Join-Path $root "server.json") "GSC_SERVER_JSON" $true),
  (ACLRecord (Join-Path $root "Runtime") "GSC_RUNTIME_DIR" $false),
  (ACLRecord (Join-Path $root "Runtime\Agent") "STATUSAGENT_RUNTIME_DIR" $false),
  (ACLRecord (Join-Path $root "Runtime\Agent\GeumyiStatusAgent-0.5.4.jar") "STATUSAGENT_054_JAR" $true)
)
$errors=@($errors|Sort-Object -Unique)
$aclFail=@($aclTargets|Where-Object{$_.status -ne "CAPTURED"})
$result=if($ruleQuery -eq "CAPTURED" -and $filterFailures -eq 0 -and
 $profiles.Count -gt 0 -and $errors.Count -eq 0 -and $aclFail.Count -eq 0){
  "CAPTURED_FOR_REVIEW"
}else{"CHECK_REQUIRED"}
[ordered]@{
 schema=1;phase="12.5-rule-acl";read_only=$true;synthetic=$false
 generated_at=(Get-Date).ToString("o");result=$result
 network_profile_set=@($profiles|Sort-Object)
 active_allow_rules_examined=$ruleCount;filter_read_failures=$filterFailures
 broad_rule_count=$rulesOut.Count;broad_rules=$rulesOut
 protected_file_acl_summaries=$aclTargets
 error_categories=$errors
 notes=@(
  "Firewall rule names/groups are classified in-memory only; names, usernames, raw IPs, SIDs and executable paths are NOT exported.",
  "Rule classification is a heuristic hint, not publisher attestation or verified need.",
  "ACL ACE details are read-only flags, not computed effective permission for any Windows user token.",
  "Wide Allow rules can be constrained by other firewall rules and OS policy; no actual external access or vulnerability is proven.",
  "Never remove rules or alter ACLs, services, backups, GSC binaries, configuration or final release gates based solely on these findings."
 )
 mutation_performed=$false;secrets_exported=$false
}|ConvertTo-Json -Depth 18|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Day12 12.5 READ-ONLY rule and ACL review: "+$result)
Write-Host ("Broad firewall candidates: "+$rulesOut.Count+"; ACL targets reviewed: "+$aclTargets.Count)
Write-Host ("Report: "+$out)
if($result -ne "CAPTURED_FOR_REVIEW"){exit 2}
exit 0
