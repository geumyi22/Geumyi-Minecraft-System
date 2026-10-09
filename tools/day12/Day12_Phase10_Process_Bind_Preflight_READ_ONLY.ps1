[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Day12.10 process/config provenance read-only preflight.
# Never exports command lines, process IDs, usernames, absolute paths or
# server.json properties other than a strict harmless allowlist.
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Process-Bind"}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-Process-Bind-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$expected=@(
  [pscustomobject]@{id="wild";java=25570;rcon=25575},
  [pscustomobject]@{id="playground";java=25571;rcon=25576},
  [pscustomobject]@{id="other";java=25572;rcon=25577},
  [pscustomobject]@{id="lobby";java=25573;rcon=25579}
)
function Get-Prop([object]$Object,[string]$Name,[object]$Default=$null){
  if($null -eq $Object){return $Default}
  $p=$Object.PSObject.Properties[$Name]
  if($null -eq $p -or $null -eq $p.Value){return $Default}
  return $p.Value
}
function Scope([string]$Value){
  if([string]::IsNullOrWhiteSpace($Value)){return "EMPTY_DEFAULT_OR_WILDCARD"}
  $ip=$null
  if([System.Net.IPAddress]::TryParse($Value,[ref]$ip)){
    if([System.Net.IPAddress]::IsLoopback($ip)){return "LOOPBACK_CONFIG"}
    if($Value -in @("0.0.0.0","::")){return "WILDCARD_CONFIG"}
    return "NON_LOOPBACK_CONFIG_REDACTED"
  }
  return "UNRECOGNIZED_HOST_OR_VALUE_REDACTED"
}
function Parse-Allowed([string[]]$Lines){
  $known=@{}
  foreach($line in @($Lines)){
    $v=([string]$line).Trim()
    if($v -notmatch '^(server-ip|server-port|enable-rcon|rcon\.port|rcon\.ip)\s*=\s*(.*?)\s*$'){continue}
    $known[[string]$Matches[1].ToLowerInvariant()]=[string]$Matches[2]
  }
  return [ordered]@{
    server_ip_scope=if($known.ContainsKey("server-ip")){Scope $known["server-ip"]}else{"PROPERTY_MISSING"}
    java_port=if($known.ContainsKey("server-port")){$known["server-port"]}else{"PROPERTY_MISSING"}
    rcon_enabled=if($known.ContainsKey("enable-rcon")){$known["enable-rcon"]}else{"PROPERTY_MISSING"}
    rcon_port=if($known.ContainsKey("rcon.port")){$known["rcon.port"]}else{"PROPERTY_MISSING"}
    rcon_ip_scope=if($known.ContainsKey("rcon.ip")){Scope $known["rcon.ip"]}else{"PROPERTY_NOT_PRESENT"}
  }
}
function Kind([string]$CommandLine,[string]$Name){
  if([string]::IsNullOrWhiteSpace($CommandLine)){return "COMMAND_LINE_NOT_READABLE"}
  if($Name -notin @("java.exe","javaw.exe")){return "OTHER"}
  if($CommandLine -match '(?i)velocity[^\\\s"]*\.jar'){return "VELOCITY_LIKELY"}
  if($CommandLine -match '(?i)(?:paper|purpur)[^\\\s"]*\.jar'){return "PAPER_LIKELY"}
  if($CommandLine -match '(?i)fabric[^\\\s"]*\.jar'){return "FABRIC_LIKELY"}
  if($CommandLine -match '(?i)\-jar\s+'){return "JAVA_JAR_UNKNOWN"}
  return "JAVA_COMMAND_UNKNOWN"
}
if($Synthetic){
  $p=Parse-Allowed @("server-ip=127.0.0.1","server-port=25570","enable-rcon=true","rcon.port=25575","rcon.password=SHOULD_NOT_BE_EMITTED")
  if($p.server_ip_scope -ne "LOOPBACK_CONFIG" -or $p.java_port -ne "25570" -or $p.rcon_port -ne "25575" -or
     (Scope "0.0.0.0") -ne "WILDCARD_CONFIG" -or (Kind '-jar paper-1.21.jar' 'java.exe') -ne "PAPER_LIKELY"){
    throw "Day12 process/config allowlist regression"
  }
  # PowerShell Group-Object by member name must consume a PSObject property,
  # not an OrderedDictionary's indexer (which grouped all real Java processes
  # under an empty category in the Oct-10 operator report).
  $fixture=@(
    [pscustomobject]@{kind=(Kind '-jar paper-1.21.jar' 'java.exe')},
    [pscustomobject]@{kind=(Kind '-jar velocity-3.4.jar' 'java.exe')}
  )
  $groups=@($fixture|Group-Object kind)
  if($groups.Count -ne 2 -or @($groups|Where-Object{$_.Name -eq 'PAPER_LIKELY'}).Count -ne 1 -or
    @($groups|Where-Object{$_.Name -eq 'VELOCITY_LIKELY'}).Count -ne 1){
    throw 'JAVA_KIND_GROUPING_REGRESSION'
  }
  $json=($p|ConvertTo-Json -Depth 6)
  if($json.Contains("SHOULD_NOT_BE_EMITTED")){throw "SECRET_LEAK"}
  [ordered]@{schema=1;synthetic=$true;phase="12.10-process-bind-preflight"
    result="SYNTHETIC_PASS";allowlist_ok=$true;no_password_export=$true
    read_only=$true;mutation_performed=$false
  }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "Process/config allowlist synthetic PASS"
  exit 0
}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root=Join-Path $pd "GeumyiServerCenter"
$configPath=Join-Path $root "server.json"
$cfg=$null;$cfgStatus="CONFIG_MISSING"
try{
  if(Test-Path -LiteralPath $configPath -PathType Leaf){
    $cfg=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    $cfgStatus="CAPTURED"
  }
}catch{$cfgStatus="CONFIG_UNREADABLE"}
$byId=@{}
if($null -ne $cfg){
  foreach($s in @(Get-Prop $cfg "servers" @())){
    if($null -eq $s){continue}
    $id=([string](Get-Prop $s "id" "")).ToLowerInvariant()
    if($id -in @("wild","playground","other","lobby")){$byId[$id]=$s}
  }
}
$serverRows=@()
foreach($target in $expected){
  $id=$target.id;$s=$null
  if($byId.ContainsKey($id)){$s=$byId[$id]}
  $configuredDir=[string](Get-Prop $s "path" "")
  $propFile=if($configuredDir){Join-Path $configuredDir "server.properties"}else{""}
  $present=$false;$bind=[ordered]@{server_ip_scope="UNAVAILABLE";java_port="UNAVAILABLE"
    rcon_enabled="UNAVAILABLE";rcon_port="UNAVAILABLE";rcon_ip_scope="UNAVAILABLE"}
  if($propFile -and (Test-Path -LiteralPath $propFile -PathType Leaf)){
    try{$bind=Parse-Allowed @(Get-Content -LiteralPath $propFile -ErrorAction Stop);$present=$true}catch{}
  }
  $serverRows+= [pscustomobject]@{id=$id;expected_java=$target.java;expected_rcon=$target.rcon
    configured_in_gsc=($null -ne $s);properties_readable=$present
    properties=$bind;process_commandline_references_server_path=$false
    process_reference_match_count=0
    note="Process argument path matches are heuristics, not proof of effective listening address"}
}
$processState="UNAVAILABLE";$java=@();$center=@();$readableCommands=0
try{
  $ps=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe' OR Name LIKE 'Geumyi%'" -ErrorAction Stop)
  $processState="CAPTURED"
  foreach($proc in $ps){
    if($null -eq $proc){continue}
    $name=([string](Get-Prop $proc "Name" "")).ToLowerInvariant()
    $cmd=[string](Get-Prop $proc "CommandLine" "")
    if($name -in @("java.exe","javaw.exe")){
      $java+= [pscustomobject]@{kind=(Kind $cmd $name);command_line_readable=(-not [string]::IsNullOrWhiteSpace($cmd))}
      if($cmd){$readableCommands++}
      foreach($row in $serverRows){
        $cfgEntry=if($byId.ContainsKey($row.id)){$byId[$row.id]}else{$null}
        $dir=[string](Get-Prop $cfgEntry "path" "")
        if($cmd -and $dir -and $cmd.IndexOf($dir,[StringComparison]::OrdinalIgnoreCase) -ge 0){
          $row.process_commandline_references_server_path=$true
          $row.process_reference_match_count++
        }
      }
    }else{$center+= [ordered]@{name_family="GEUMYI_PROCESS";command_line_readable=([bool]$cmd)}}
  }
}catch{$processState="CIM_QUERY_FAILED"}
$compStatus="UNAVAILABLE";$compCount=$null;$otherCompCount=$null
try{
  $cmd=Get-Command Get-NetIPInterface -ErrorAction Stop
  if(-not $cmd.Parameters.ContainsKey("IncludeAllCompartments")){
    $compStatus="ALL_COMPARTMENTS_SWITCH_NOT_AVAILABLE"
  }else{
    $interfaces=@(Get-NetIPInterface -IncludeAllCompartments -ErrorAction Stop)
    $values=@($interfaces|ForEach-Object{
      $v=Get-Prop $_ "CompartmentId" $null
      if($null -ne $v){[string]$v}
    }|Where-Object{$_ -ne $null}|Select-Object -Unique)
    $compStatus="CAPTURED_INTERFACE_METADATA_ONLY"
    $compCount=$values.Count
    $otherCompCount=@($values|Where-Object{$_ -ne "1"}).Count
  }
}catch{$compStatus="INTERFACE_QUERY_ERROR"}
$mode=if($cfgStatus -eq "CAPTURED" -and $processState -eq "CAPTURED"){"CAPTURED_REVIEW_REQUIRED"}else{"CHECK_REQUIRED"}
$report=[ordered]@{
  schema=1;phase="12.10-process-bind-preflight";synthetic=$false;read_only=$true
  generated_at=(Get-Date).ToString("o");result=$mode
  gsc_config_status=$cfgStatus
  server_config_summary=$serverRows
  process_inventory=[ordered]@{
    status=$processState
    java_process_count=$java.Count
    readable_java_command_lines=$readableCommands
    java_process_kind_counts=@($java|Group-Object kind|ForEach-Object{[ordered]@{kind=$_.Name;count=$_.Count}})
    gsc_named_process_count=$center.Count
  }
  network_compartment_interface_metadata=[ordered]@{
    status=$compStatus;distinct_compartment_count=$compCount;nondefault_compartment_count=$otherCompCount
  }
  notes=@(
    "Redacted process metadata only; no PID, process command line, executable path, user, hostname, RCON password or IP other than coarse scope is written.",
    "server.properties values describe on-disk configuration, not necessarily effective running binding.",
    "Java command-line references to configured path are heuristic and may be absent even for a managed server.",
    "Network interface compartment metadata cannot prove a Minecraft TCP socket belongs to a compartment.",
    "Get-NetTCPConnection itself has no IncludeAllCompartments switch on current Windows PowerShell docs.",
    "No TCP listen table scan, socket connection, server restart, firewall, ACL, world, cache, backup or release gate mutation."
  )
  mutation_performed=$false;secrets_exported=$false
}
$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Day12 process bind preflight: "+$mode)
Write-Host ("Report: "+$out)
if($mode -eq "CHECK_REQUIRED"){exit 2}
exit 0
