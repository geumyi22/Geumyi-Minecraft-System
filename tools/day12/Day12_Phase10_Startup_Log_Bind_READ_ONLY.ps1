[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Startup-Bind"}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-Startup-Bind-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$targets=@(
 [pscustomobject]@{id="wild";java=25570;rcon=25575},
 [pscustomobject]@{id="playground";java=25571;rcon=25576},
 [pscustomobject]@{id="other";java=25572;rcon=25577},
 [pscustomobject]@{id="lobby";java=25573;rcon=25579}
)
function Get-Scope([string]$v){
  $v=$v.Trim().Trim('[',']').ToLowerInvariant()
  if($v -in @("*","0.0.0.0","::")){return "WILDCARD"}
  if($v -eq "localhost"){return "LOOPBACK"}
  $ip=$null
  if([System.Net.IPAddress]::TryParse($v,[ref]$ip)){
    if([System.Net.IPAddress]::IsLoopback($ip)){return "LOOPBACK"}
    return "NON_LOOPBACK_REDACTED"
  }
  return "UNKNOWN_REDACTED"
}
function Parse-Startup([string[]]$lines,[int]$java,[int]$rcon){
  $j=@();$r=@()
  foreach($line in $lines){
    if([string]$line -match '(?i)Starting Minecraft server on\s+(\[[^\]]+\]|[^\s,]+):(\d{2,5})(?:\s|$)'){
      $j+= [pscustomobject]@{scope=(Get-Scope ([string]$Matches[1]));expected_port=([int]$Matches[2] -eq $java)}
    }
    if([string]$line -match '(?i)RCON running on\s+(\[[^\]]+\]|[^\s,]+):(\d{2,5})(?:\s|$)'){
      $r+= [pscustomobject]@{scope=(Get-Scope ([string]$Matches[1]));expected_port=([int]$Matches[2] -eq $rcon)}
    }
  }
  return [pscustomobject]@{java=@($j);rcon=@($r)}
}
function Status([object[]]$records){
  if($records.Count -eq 0){return "NO_STARTUP_BIND_MESSAGE"}
  if(@($records|Where-Object{$_.scope -ne "LOOPBACK" -or -not $_.expected_port}).Count -gt 0){return "REVIEW_REQUIRED"}
  return "APPLICATION_REPORTED_LOOPBACK"
}
function Read-Beginning([string]$path){
  $stream=$null
  try{
    $stream=[System.IO.File]::Open($path,[System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
    $limit=6291456
    $n=[int][math]::Min([int64]$limit,$stream.Length)
    $bytes=New-Object byte[] $n
    $offset=0
    while($offset -lt $n){
      $got=$stream.Read($bytes,$offset,$n-$offset)
      if($got -le 0){break}
      $offset+=$got
    }
    $txt=[System.Text.Encoding]::UTF8.GetString($bytes,0,$offset)
    return [pscustomobject]@{
      lines=@($txt.Split([char]10))
      scanned_bytes=$offset
      truncated=($stream.Length -gt $limit)
    }
  }finally{if($null -ne $stream){$stream.Dispose()}}
}
if($Synthetic){
  $good=Parse-Startup @(
    '[INFO]: Starting Minecraft server on 127.0.0.1:25570',
    '[INFO]: RCON running on [::1]:25575',
    'rcon.password=PRIVATE_SENTINEL'
  ) 25570 25575
  $bad=Parse-Startup @(
    '[INFO]: Starting Minecraft server on *:25570',
    '[INFO]: RCON running on 0.0.0.0:25575'
  ) 25570 25575
  if((Status $good.java) -ne "APPLICATION_REPORTED_LOOPBACK" -or
     (Status $good.rcon) -ne "APPLICATION_REPORTED_LOOPBACK" -or
     (Status $bad.java) -ne "REVIEW_REQUIRED" -or
     (Status $bad.rcon) -ne "REVIEW_REQUIRED"){throw "STARTUP_BIND_PARSER_REGRESSION"}
  if(($good|ConvertTo-Json -Depth 6).Contains("PRIVATE_SENTINEL")){throw "LOG_SECRET_LEAK"}
  [ordered]@{schema=1;phase="12.10-startup-log-bind";synthetic=$true;read_only=$true
    result="SYNTHETIC_PASS";parser_verified=$true;mutation_performed=$false
  }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
  exit 0
}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$cfgPath=Join-Path (Join-Path $pd "GeumyiServerCenter") "server.json"
$config=$null;$configStatus="UNAVAILABLE"
try{
  if(Test-Path -LiteralPath $cfgPath -PathType Leaf){
    $config=Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    $configStatus="CAPTURED"
  }
}catch{$configStatus="CONFIG_UNREADABLE"}
$results=@()
$profiles=if($null -ne $config){@($config.servers)}else{@()}
foreach($target in $targets){
  $dir=""
  foreach($svc in $profiles){
    if($null -ne $svc -and ([string]$svc.id).ToLowerInvariant() -eq $target.id){
      $dir=[string]$svc.path;break
    }
  }
  $file=if($dir){Join-Path (Join-Path $dir "logs") "latest.log"}else{""}
  $status="LOG_NOT_FOUND";$age=$null;$truncated=$false;$scanned=0
  $parsed=[pscustomobject]@{java=@();rcon=@()}
  if($file -and (Test-Path -LiteralPath $file -PathType Leaf)){
    try{
      $info=Get-Item -LiteralPath $file -ErrorAction Stop
      $age=[math]::Round(((Get-Date)-$info.LastWriteTime).TotalMinutes,1)
      $excerpt=Read-Beginning $file
      $parsed=Parse-Startup $excerpt.lines $target.java $target.rcon
      $status="CAPTURED";$truncated=$excerpt.truncated;$scanned=$excerpt.scanned_bytes
    }catch{$status="LOG_UNREADABLE"}
  }
  $results+= [pscustomobject]@{
    id=$target.id;latest_log_status=$status;log_age_minutes=$age
    scanned_bytes=$scanned;scan_truncated=$truncated
    java=[pscustomobject]@{status=(Status $parsed.java)
      observations=@($parsed.java).Count
      scopes=@($parsed.java|ForEach-Object{$_.scope}|Select-Object -Unique)}
    rcon=[pscustomobject]@{status=(Status $parsed.rcon)
      observations=@($parsed.rcon).Count
      scopes=@($parsed.rcon|ForEach-Object{$_.scope}|Select-Object -Unique)}
  }
}
[ordered]@{schema=1;phase="12.10-startup-log-bind";synthetic=$false;read_only=$true
  generated_at=(Get-Date).ToString("o");result="CAPTURED_REVIEW_REQUIRED"
  config_status=$configStatus;services=$results
  notes=@(
    "Reads only first 6 MiB of current latest.log per configured server.",
    "Reports application startup messages, NOT authoritative current Windows socket binding.",
    "Java and RCON bind scope are checked separately; Java loopback never implies RCON loopback.",
    "A missing message may reflect changed log format, rotation, or truncation.",
    "No raw lines, IPs, credentials, usernames, paths, PIDs or chat content are exported.",
    "No TCP probes, firewall, ACL, server process or world changes.",
    "Does not bypass the final Day12 backend_ports_private fail-closed gate."
  );mutation_performed=$false;secrets_exported=$false
}|ConvertTo-Json -Depth 11|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("12.10 application startup bind report: "+$out)
exit 0
