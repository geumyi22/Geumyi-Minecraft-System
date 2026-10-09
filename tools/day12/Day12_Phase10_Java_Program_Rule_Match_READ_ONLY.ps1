[CmdletBinding()]
param([string]$OutputDir="", [switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Read-only targeted correlation between current Java executable images
# and Windows ActiveStore inbound firewall APPLICATION filters.
# No raw paths, PIDs, rule names, command lines or IP addresses in the report.
# Program-path correlation is NOT per-Minecraft-backend ownership, live socket
# bind evidence, effective WFP authorization, IPv6 isolation or a release PASS.
$privatePorts=@(25570,25571,25572,25573,25575,25576,25577,25579)
$publicPorts=@(25565,25566,25567)

function Get-Field($Object,[string]$Name,[string]$Fallback="UNKNOWN") {
  if($null -eq $Object){return $Fallback}
  $p=$Object.PSObject.Properties[$Name]
  if($null -eq $p -or $null -eq $p.Value){return $Fallback}
  return [string]$p.Value
}
function Normalize-Exe([string]$PathText) {
  if([string]::IsNullOrWhiteSpace($PathText)){return $null}
  $s=$PathText.Trim().Trim('"')
  if($s -in @("*","Any","System")){return $null}
  $s=[Environment]::ExpandEnvironmentVariables($s)
  if($s.Contains("*") -or $s.Contains("?") -or $s.Contains("%")){return $null}
  if($s -notmatch '^[a-zA-Z]:\\' -and $s -notmatch '^\\\\[^\\]+\\[^\\]+\\'){return $null}
  try {
    return [IO.Path]::GetFullPath($s).TrimEnd('\').ToUpperInvariant()
  }catch {return $null}
}
function Compare-Program([string]$Raw,[string[]]$JavaImages,[bool]$Complete) {
  if($Raw -in @("Any","*")){return "ALL_PROGRAMS"}
  if([string]::IsNullOrWhiteSpace($Raw) -or $Raw -eq "UNKNOWN"){return "PROGRAM_UNRESOLVED"}
  if($Raw -eq "System"){return "SPECIAL_SYSTEM_SCOPE"}
  $key=Normalize-Exe $Raw
  if($null -eq $key){return "PROGRAM_UNRESOLVED"}
  if(@($JavaImages | Where-Object {$_ -eq $key}).Count -gt 0){
    return "MATCHES_RUNNING_JAVA_EXE"
  }
  if(-not $Complete){return "JAVA_IMAGE_INVENTORY_INCOMPLETE"}
  return "NO_RUNNING_JAVA_EXE_MATCH"
}
function TcpScope([string]$Protocol) {
  switch($Protocol.Trim().ToUpperInvariant()){
    "TCP" {return "TCP"} "6" {return "TCP"} "ANY" {return "ANY"}
    "*" {return "ANY"} "256" {return "ANY"}
    "UDP" {return "OTHER"} "17" {return "OTHER"}
    "ICMPV4" {return "OTHER"} "ICMPV6" {return "OTHER"}
    "ICMP" {return "OTHER"} "1" {return "OTHER"}
    "58" {return "OTHER"} "IGMP" {return "OTHER"}
    "2" {return "OTHER"} "IPV6" {return "OTHER"}
    "41" {return "OTHER"}
    default {return "UNKNOWN"}
  }
}
function PortScope([string]$Raw,[int]$Port) {
  if([string]::IsNullOrWhiteSpace($Raw)){return "UNKNOWN"}
  $tokens=@($Raw.Split(",") | ForEach-Object {$_.Trim()})
  $unknown=$false
  foreach($v in $tokens){
    if($v -in @("Any","*")){return "MATCH"}
    if($v -match '^\d{1,5}$'){
      if([int]$v -eq $Port){return "MATCH"}
      if([int]$v -gt 65535){$unknown=$true}
      continue
    }
    if($v -match '^(\d{1,5})\s*-\s*(\d{1,5})$'){
      $a=[int]$Matches[1];$b=[int]$Matches[2]
      if($a -gt $b -or $b -gt 65535){$unknown=$true;continue}
      if($Port -ge $a -and $Port -le $b){return "MATCH"}
      continue
    }
    $unknown=$true
  }
  if($unknown){return "UNKNOWN"}
  return "NO_MATCH"
}
function ProfileScope([string]$RuleProfile,[string[]]$Active){
  if($Active.Count -eq 0){return "UNKNOWN"}
  if($RuleProfile -in @("Any","*")){return "MATCH"}
  $names=@($RuleProfile.Split(",")|ForEach-Object {$_.Trim()})
  if($names.Count -eq 0 -or @($names|Where-Object{$_ -notin @("Domain","Private","Public")}).Count -gt 0){
    return "UNKNOWN"
  }
  if(@($names|Where-Object{$Active -contains $_}).Count -gt 0){return "MATCH"}
  return "NO_MATCH"
}
function Build-Review($Rules,[int[]]$Ports,[string[]]$Active,[string[]]$JavaImages,[bool]$Complete) {
  $result=@()
  foreach($port in $Ports){
    $cases=@()
    foreach($r in @($Rules)){
      $pr=TcpScope (Get-Field $r "protocol")
      if($pr -eq "OTHER"){continue}
      $pt=PortScope (Get-Field $r "local_port") $port
      if($pt -eq "NO_MATCH"){continue}
      $pf=ProfileScope (Get-Field $r "profile") $Active
      if($pf -eq "NO_MATCH"){continue}
      $prog=Compare-Program (Get-Field $r "program") $JavaImages $Complete
      $candidate=if($pr -eq "UNKNOWN" -or $pt -eq "UNKNOWN" -or $pf -eq "UNKNOWN"){"UNKNOWN_RULE_SCOPE"}else{"POTENTIAL_MATCH"}
      $cases+=[pscustomobject]@{
        ordinal=[int]$r.ordinal
        action=Get-Field $r "action"
        program_match=$prog
        candidate_scope=$candidate
        protocol_scope=$pr
        port_scope=$pt
        profile_scope=$pf
      }
    }
    $categories=@("ALL_PROGRAMS","MATCHES_RUNNING_JAVA_EXE","NO_RUNNING_JAVA_EXE_MATCH",
      "SPECIAL_SYSTEM_SCOPE","PROGRAM_UNRESOLVED","JAVA_IMAGE_INVENTORY_INCOMPLETE")
    $counts=[ordered]@{}
    foreach($kind in $categories){
      $counts[$kind]=@($cases | Where-Object {$_.action -eq "Allow" -and $_.program_match -eq $kind}).Count
    }
    $result += [ordered]@{
      port=$port
      result="PROGRAM_RULE_CANDIDATES_ONLY"
      allow_counts=$counts
      block_rule_count=@($cases|Where-Object{$_.action -eq "Block"}).Count
      unknown_scope_count=@($cases|Where-Object{$_.candidate_scope -eq "UNKNOWN_RULE_SCOPE"}).Count
      # ordinal is only meaningful for this exact snapshot. Not a stable
      # rule identifier and NEVER an authorization to disable any rule.
      candidates=$cases
    }
  }
  return @($result)
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Java-Rule-Match"
}
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
$out=Join-Path $OutputDir ("Day12-Java-Rule-Match-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  $images=@((Normalize-Exe "C:\Java\bin\java.exe"))
  $fake=@(
    [pscustomobject]@{ordinal=1;action="Allow";protocol="TCP";local_port="Any";profile="Private";program="Any"},
    [pscustomobject]@{ordinal=2;action="Allow";protocol="6";local_port="25570-25573";profile="Private";program="C:\Java\bin\java.exe"},
    [pscustomobject]@{ordinal=3;action="Allow";protocol="TCP";local_port="25570";profile="Private";program="C:\Other\daemon.exe"},
    [pscustomobject]@{ordinal=4;action="Allow";protocol="ICMPv6";local_port="Any";profile="Any";program="Any"},
    [pscustomobject]@{ordinal=5;action="Block";protocol="TCP";local_port="25570";profile="Public";program="C:\Java\bin\java.exe"},
    [pscustomobject]@{ordinal=6;action="Allow";protocol="TCP";local_port="RPC";profile="Private";program="System"},
    [pscustomobject]@{ordinal=7;action="Allow";protocol="TCP";local_port="25570";profile="Private";program="%UNKNOWN_ABC%\java.exe"},
    [pscustomobject]@{ordinal=8;action="Allow";protocol="TCP";local_port="25570";profile="Private";program="C:\JAVA\bin\JAVA.EXE"}
  )
  $rows=@(Build-Review $fake @(25570,25571) @("Private") $images $true)
  $a=@($rows|Where-Object {$_.port -eq 25570})[0]
  $b=@($rows|Where-Object {$_.port -eq 25571})[0]
  if($a.allow_counts.ALL_PROGRAMS -ne 1 -or
     $a.allow_counts.MATCHES_RUNNING_JAVA_EXE -ne 2 -or
     $a.allow_counts.NO_RUNNING_JAVA_EXE_MATCH -ne 1 -or
     $a.allow_counts.PROGRAM_UNRESOLVED -ne 1 -or
     $a.allow_counts.SPECIAL_SYSTEM_SCOPE -ne 1 -or
     $a.block_rule_count -ne 0 -or $a.unknown_scope_count -ne 1 -or
     $b.allow_counts.MATCHES_RUNNING_JAVA_EXE -ne 1 -or
     (Compare-Program "C:\Other\daemon.exe" @() $false) -ne "JAVA_IMAGE_INVENTORY_INCOMPLETE" -or
     (Compare-Program "C:\Java\bin\java.exe" $images $true) -ne "MATCHES_RUNNING_JAVA_EXE"){
    throw "JAVA_APPLICATION_RULE_SYNTHETIC_CLASSIFIER_FAILED"
  }
  [ordered]@{
    schema=1;phase="12.10-java-program-rule"
    synthetic=$true;read_only=$true;result="SYNTHETIC_PASS"
    mutation_performed=$false;secrets_exported=$false
    canonical_backend_ports_private="UNCHANGED_FAIL"
    categories=$a.allow_counts
  }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host ("Java program rule synthetic PASS: "+$out)
  exit 0
}
$errors=@()
$javaImages=@()
$javaTotal=0
$javaPathCount=0
$javaInventoryComplete=$false
$rules=@()
$profiles=@()
$ruleCount=0
$filterFailures=0
try {
  $java=@(Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe'" -ErrorAction Stop)
  $javaTotal=$java.Count
  foreach($j in $java) {
    $key=Normalize-Exe (Get-Field $j "ExecutablePath" "")
    if($null -eq $key){continue}
    $javaPathCount++
    if($javaImages -notcontains $key){$javaImages+=$key}
  }
  $javaInventoryComplete=($javaPathCount -eq $javaTotal -and $javaTotal -gt 0)
  if(-not $javaInventoryComplete){$errors+="JAVA_IMAGE_PATHS_INCOMPLETE"}
}catch{$errors+="JAVA_IMAGE_QUERY_FAILED"}
try{
  $nets=@(Get-NetConnectionProfile -ErrorAction Stop)
  foreach($n in $nets){
    $v=Get-Field $n "NetworkCategory"
    if($v -eq "DomainAuthenticated"){$v="Domain"}
    if($v -in @("Domain","Private","Public") -and $profiles -notcontains $v){$profiles+=$v}
  }
  if($profiles.Count -eq 0){$errors+="ACTIVE_NETWORK_PROFILES_UNKNOWN"}
}catch{$errors+="ACTIVE_NETWORK_PROFILES_QUERY_FAILED"}
try{
  $active=@(Get-NetFirewallRule -PolicyStore ActiveStore -Enabled True -Direction Inbound -ErrorAction Stop)
  foreach($r in $active){
    $ruleCount++
    try{$pf=Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction Stop}
    catch{$filterFailures++;$errors+="RULE_PORT_FILTER_FAILED";continue}
    $proto=Get-Field $pf "Protocol"
    if((TcpScope $proto) -eq "OTHER"){continue}
    $rawPort=Get-Field $pf "LocalPort"
    $relevant=$false
    foreach($target in @($privatePorts+$publicPorts)){
      if((PortScope $rawPort $target) -ne "NO_MATCH"){$relevant=$true;break}
    }
    if(-not $relevant){continue}
    try{$app=Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $r -ErrorAction Stop}
    catch{$filterFailures++;$errors+="RULE_APPLICATION_FILTER_FAILED";continue}
    $rules+=[pscustomobject]@{
      ordinal=$ruleCount
      action=Get-Field $r "Action"
      profile=Get-Field $r "Profile"
      protocol=$proto
      local_port=$rawPort
      program=Get-Field $app "Program"
    }
  }
}catch{$errors+="ACTIVE_FIREWALL_RULE_QUERY_FAILED"}
$private=@(Build-Review $rules $privatePorts $profiles $javaImages $javaInventoryComplete)
$public=@(Build-Review $rules $publicPorts $profiles $javaImages $javaInventoryComplete)
$errors=@($errors|Sort-Object -Unique)
$status=if($errors.Count -gt 0){"CHECK_REQUIRED"}else{"CAPTURED_FOR_REVIEW"}
$report=[ordered]@{
  schema=1;phase="12.10-java-program-rule"
  generated_at=(Get-Date).ToString("o")
  result=$status;synthetic=$false;read_only=$true
  java_process_count=$javaTotal
  java_process_executable_paths_observed=$javaPathCount
  distinct_java_images_observed=$javaImages.Count
  java_executable_inventory_complete=$javaInventoryComplete
  active_network_profile_set=@($profiles|Sort-Object)
  enabled_inbound_rule_count=$ruleCount
  associated_filter_failures=$filterFailures
  backend_port_results=$private
  public_port_results=$public
  error_categories=$errors
  mutation_performed=$false;secrets_exported=$false
  canonical_backend_ports_private="UNCHANGED_FAIL"
  notes=@(
    "Exact program executable-path equality compared locally; no paths, process IDs, command lines, raw firewall rule names or IP addresses exported.",
    "MATCHES_RUNNING_JAVA_EXE means a rule's application filter matches any currently observed java.exe/javaw.exe image, not a specific Minecraft server, backend or live socket.",
    "NO_RUNNING_JAVA_EXE_MATCH can become relevant after an executable change or if Java process access was incomplete; never use to authorize rule deletion.",
    "ALL_PROGRAMS candidates may apply to Java, but service, remote source, firewall precedence, IPv6 and interface conditions are not evaluated.",
    "A missing Java executable path is an incomplete inventory and never produces security PASS.",
    "This tool does not change Windows Firewall, ports, audit settings, services, worlds or backups.",
    "Canonical 12.10 backend_ports_private remains FAIL until separate owner/bind proof."
  )
}
$report|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Java application rule correlation: "+$status)
Write-Host ("Java process records: "+$javaTotal+"; executable paths observed: "+$javaPathCount)
Write-Host ("JSON: "+$out)
if($status -ne "CAPTURED_FOR_REVIEW"){exit 2}
exit 0
