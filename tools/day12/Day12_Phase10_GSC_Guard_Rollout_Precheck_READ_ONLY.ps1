[CmdletBinding()]
param([switch]$Synthetic,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# Day12 GSC source-v3 rollout compatibility check.
# Existing config only. No service/Java/socket/audit/firewall/restart/update.
# Redacted report. This is NOT live private-binding proof or GSC installation.
$fixed=@(
  [pscustomobject]@{id="wild";java=25570;rcon=25575},
  [pscustomobject]@{id="playground";java=25571;rcon=25576},
  [pscustomobject]@{id="other";java=25572;rcon=25577},
  [pscustomobject]@{id="lobby";java=25573;rcon=25579}
)
function StatusFromProps([string[]]$Lines,[int]$ExpectedJava,[int]$ExpectedRcon){
  $critical=@("server-ip","server-port","enable-rcon","rcon.port")
  $values=@{}
  $issues=@()
  $continued=$false
  foreach($originalLine in @($Lines)){
    $line=([string]$originalLine).TrimStart([char]0xFEFF).TrimStart()
    if($line -eq "" -or $line.StartsWith("#") -or $line.StartsWith("!")){continue}
    if($continued){
      $issues+="MULTILINE_PROPERTY_UNRESOLVED"
      $continued=$false
    }
    if($line.EndsWith("\") -and -not $line.EndsWith("\\")){
      $continued=$true
      $issues+="MULTILINE_PROPERTY_UNRESOLVED"
    }
    if($line -match '^(?<key>[^\s=:]+)\s*(?:\s+|[=:])\s*(?<val>.*)$'){
      $k=[string]$Matches['key'];$v=([string]$Matches['val']).Trim()
      if($k.Contains("\") -and $k -match '^(?i:s|r|e)'){
        $issues+="ESCAPED_KEY_UNRESOLVED"
      }
      if($critical -contains $k){
        if($values.ContainsKey($k)){$issues+="DUPLICATE_"+($k.Replace(".","_").Replace("-","_"))}
        if($v.Contains("\")){$issues+="ENCODED_CRITICAL_VALUE"}
        $values[$k]=$v
      }
    } elseif($line -match '^(?i:server|rcon|enable)'){
      $issues+="CRITICAL_PROPERTY_SYNTAX_UNRESOLVED"
    }
  }
  if($continued){$issues+="MULTILINE_PROPERTY_UNRESOLVED"}
  foreach($k in $critical){
    if(-not $values.ContainsKey($k)){$issues+="MISSING_"+($k.Replace(".","_").Replace("-","_"))}
  }
  if($values.ContainsKey("server-ip") -and $values["server-ip"] -cne "127.0.0.1"){
    $issues+="JAVA_IP_NOT_127_0_0_1"
  }
  if($values.ContainsKey("server-port") -and $values["server-port"] -cne [string]$ExpectedJava){
    $issues+="JAVA_PORT_MISMATCH"
  }
  if($values.ContainsKey("enable-rcon") -and $values["enable-rcon"] -cne "true"){
    $issues+="RCON_DISABLED_OR_UNKNOWN"
  }
  if($values.ContainsKey("rcon.port") -and $values["rcon.port"] -cne [string]$ExpectedRcon){
    $issues+="RCON_PORT_MISMATCH"
  }
  return [pscustomobject]@{
    compatible=(@($issues).Count -eq 0)
    issues=@($issues|Sort-Object -Unique)
  }
}
function EvaluateConfig($Json,$GetProperties){
  $rows=@()
  $all=@()
  foreach($server in $fixed){
    $matches=@($Json.servers|Where-Object{[string]$_.id -eq $server.id})
    $problems=@()
    if($matches.Count -ne 1){$problems+="PROFILE_MISSING_OR_DUPLICATED"}
    else{
      $found=$matches[0]
      if([int]$found.java_port -ne $server.java){$problems+="GSC_JAVA_PORT_MISMATCH"}
      if([int]$found.rcon_port -ne $server.rcon){$problems+="GSC_RCON_PORT_MISMATCH"}
      try{
        $lines=@(& $GetProperties $found)
        $result=StatusFromProps $lines $server.java $server.rcon
        $problems+=@($result.issues)
      }catch{$problems+="SERVER_PROPERTIES_UNAVAILABLE"}
    }
    $problems=@($problems|Sort-Object -Unique)
    $all+=@($problems)
    $rows+=[ordered]@{
      profile=$server.id
      expected_java_port=$server.java
      expected_rcon_port=$server.rcon
      compatible_for_guard=($problems.Count -eq 0)
      issue_codes=$problems
    }
  }
  return [ordered]@{
    result=$(if($all.Count -eq 0){"CONFIG_COMPATIBLE_REVIEW_ONLY"}else{"CHECK_REQUIRED"})
    profiles=$rows
    issue_count=$all.Count
  }
}
if(-not $OutputDir){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-GSC-Guard"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$out=Join-Path $OutputDir ("Day12-GSC-Guard-Precheck-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  $valid=@("server-ip=127.0.0.1","server-port=25570","enable-rcon=true","rcon.port=25575")
  $good=StatusFromProps $valid 25570 25575
  $dupe=StatusFromProps @($valid+"server-ip=0.0.0.0") 25570 25575
  $colon=StatusFromProps @("server-ip:127.0.0.1","server-port:25570","enable-rcon:true","rcon.port:25575") 25570 25575
  $bad=StatusFromProps @("server-ip=0.0.0.0","server-port=25570","enable-rcon=true","rcon.port=25575") 25570 25575
  $other=StatusFromProps @("server-ip=127.0.0.2","server-port=25570","enable-rcon=true","rcon.port=25575") 25570 25575
  $wrongRcon=StatusFromProps @("server-ip=127.0.0.1","server-port=25570","enable-rcon=true","rcon.port=25576") 25570 25575
  $esc=StatusFromProps @($valid+"server\u002dip=0.0.0.0") 25570 25575
  if(-not $good.compatible -or -not $colon.compatible -or $dupe.compatible -or $bad.compatible -or
     $other.compatible -or $wrongRcon.compatible -or $esc.compatible -or
     $dupe.issues -notcontains "DUPLICATE_server_ip" -or
     $esc.issues -notcontains "ESCAPED_KEY_UNRESOLVED"){
    throw "GSC_GUARD_PRECHECK_SYNTHETIC_FAILED"
  }
  $profiles=@()
  foreach($p in $fixed){
    $profiles+= [pscustomobject]@{
      id=$p.id;java_port=$p.java;rcon_port=$p.rcon
    }
  }
  $cfg=[pscustomobject]@{servers=$profiles}
  $fn={param($p)
    @("server-ip=127.0.0.1","server-port=$($p.java_port)","enable-rcon=true","rcon.port=$($p.rcon_port)")
  }
  $fixture=EvaluateConfig $cfg $fn
  if($fixture.result -ne "CONFIG_COMPATIBLE_REVIEW_ONLY" -or $fixture.profiles.Count -ne 4){
    throw "GSC_GUARD_PROFILE_MATRIX_SYNTHETIC_FAILED"
  }
  $profiles[0].rcon_port=25576
  $invalid=EvaluateConfig $cfg $fn
  if($invalid.result -ne "CHECK_REQUIRED" -or $invalid.profiles[0].issue_codes -notcontains "GSC_RCON_PORT_MISMATCH"){
    throw "GSC_GUARD_PROFILE_DRIFT_SYNTHETIC_FAILED"
  }
  [ordered]@{schema=1;phase="12.10-gsc-rollout-guard";synthetic=$true;result="SYNTHETIC_PASS";read_only=$true;
    mutation_performed=$false;backend_ports_private="UNCHANGED_FAIL"}|
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "Day12 GSC Guard precheck synthetic PASS"
  exit 0
}
$cfgPath=Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "GeumyiServerCenter\server.json"
try{
  $cfg=Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if($null -eq $cfg.servers){throw "NO_SERVER_LIST"}
  $getFile={param($srv)
    $path=[string]$srv.path
    if(-not $path -and [string]$srv.path_file){
      $path=(Get-Content -LiteralPath ([Environment]::ExpandEnvironmentVariables([string]$srv.path_file)) -Raw -Encoding UTF8 -ErrorAction Stop).Trim().TrimStart([char]0xFEFF)
    }
    if(-not $path){throw "NO_SERVER_PATH"}
    $dir=[Environment]::ExpandEnvironmentVariables($path)
    $prop=Join-Path $dir "server.properties"
    return @(Get-Content -LiteralPath $prop -Encoding UTF8 -ErrorAction Stop)
  }
  $result=EvaluateConfig $cfg $getFile
}catch{
  $result=[ordered]@{result="CHECK_REQUIRED";profiles=@();issue_count=1;global_issue="GSC_CONFIG_UNAVAILABLE_OR_INVALID"}
}
$report=[ordered]@{
  schema=1;phase="12.10-gsc-rollout-guard";synthetic=$false;read_only=$true
  generated_at=(Get-Date).ToString("o")
  result=$result.result;profiles=$result.profiles;issue_count=$result.issue_count
  error_category=$(if($result.Contains("global_issue")){$result.global_issue}else{"NONE"})
  configuration_modified=$false;windows_policy_modified=$false;service_modified=$false
  server_restarted=$false;backend_ports_private="UNCHANGED_FAIL";secrets_exported=$false
  notes=@(
    "This is a conservative rollout compatibility review for GSC private Java+RCON startup guards; it does not read RCON passwords.",
    "Even CONFIG_COMPATIBLE_REVIEW_ONLY does not verify current socket bind scope, Windows listener table or private ports.",
    "No GSC installation/update, firewall or Minecraft changes were performed."
  )
}
$report|ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("GSC guard rollout precheck: "+$report.result)
Write-Host ("JSON: "+$out)
if($report.result -ne "CONFIG_COMPATIBLE_REVIEW_ONLY"){exit 2}
exit 0
