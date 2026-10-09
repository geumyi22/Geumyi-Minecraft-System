[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "Day12_Native_TCP_Provider_READ_ONLY.ps1")
$ports=@(25571,25573,25575,25576)
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Provider-Diff"}
New-Item -Path $OutputDir -ItemType Directory -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-Provider-Diff-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
function Scope([string]$Address){
  $ip=$null;$s=$Address.Trim('[',']')
  if($s -in @("0.0.0.0","::","*")){return "WILDCARD"}
  if([System.Net.IPAddress]::TryParse($s,[ref]$ip)){
    if([System.Net.IPAddress]::IsLoopback($ip)){return "LOOPBACK"}
    return "NON_LOOPBACK_REDACTED"
  }
  return "UNKNOWN"
}
function SafeRows([object[]]$Entries,[string]$Provider){
  $r=@()
  foreach($e in @($Entries)){
    if($null -eq $e -or $ports -notcontains [int]$e.port){continue}
    $r+= [pscustomobject]@{port=[int]$e.port;scope=(Scope ([string]$e.address));provider=$Provider}
  }
  return @($r)
}
function CIMRows([switch]$Filtered){
  $source=if($Filtered){"CIM_PER_PORT"}else{"CIM_UNFILTERED"}
  $rows=@();$details=@();$lookups=if($Filtered){@($ports)}else{@(0)}
  foreach($p in $lookups){
    try{
      $raw=if($Filtered){@(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction Stop)}
           else{@(Get-NetTCPConnection -State Listen -ErrorAction Stop)}
      $n=0
      foreach($e in $raw){
        if($null -eq $e -or $ports -notcontains [int]$e.LocalPort){continue}
        $n++
        $rows+= [pscustomobject]@{port=[int]$e.LocalPort;scope=(Scope ([string]$e.LocalAddress));provider=$source}
      }
      $details+= [pscustomobject]@{port=if($Filtered){$p}else{0};status="CAPTURED";matched=$n}
    }catch{
      $cat=[string]$_.CategoryInfo.Category
      $reason=if($cat -eq "ObjectNotFound"){"NO_MATCHING_INSTANCE"}else{"CIM_QUERY_ERROR"}
      $details+= [pscustomobject]@{port=if($Filtered){$p}else{0};status="ERROR";reason=$reason;matched=0}
    }
  }
  return [pscustomobject]@{rows=@($rows);details=@($details)}
}
function Netstat {
  $meta=[ordered]@{status="UNAVAILABLE";exit_code=$null;reason="UNKNOWN"}
  $rows=@()
  try{
    $exe=Join-Path $env:WINDIR "System32\netstat.exe"
    if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){
      $meta.reason="EXECUTABLE_MISSING";return [pscustomobject]@{meta=$meta;rows=@()}
    }
    $lines=@(& $exe -ano -p TCP 2>$null);$code=[int]$LASTEXITCODE
    $meta.exit_code=$code
    if($code -ne 0){$meta.status="ERROR";$meta.reason="NONZERO_EXIT";return [pscustomobject]@{meta=$meta;rows=@()}}
    foreach($line in $lines){
      if([string]$line -notmatch '^\s*TCP\s+(\S+)\s+\S+\s+LISTENING\s+\d+\s*$'){continue}
      $local=[string]$Matches[1]
      if($local -notmatch '^(.+):(\d+)$'){continue}
      $p=[int]$Matches[2]
      if($ports -notcontains $p){continue}
      $rows+= [pscustomobject]@{port=$p;scope=(Scope ([string]$Matches[1]));provider="NETSTAT"}
    }
    $meta.status="CAPTURED";$meta.reason="NONE"
  }catch{$meta.status="ERROR";$meta.reason="EXECUTION_OR_PARSE_ERROR"}
  return [pscustomobject]@{meta=$meta;rows=@($rows)}
}
if($Synthetic){
  $l=$null
  try{
    $l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $l.Start();$port=[int]([System.Net.IPEndPoint]$l.LocalEndpoint).Port
    $ports=@($port)
    $a=Get-Day12NativeAllTcpInventory -WantedPorts $ports
    $b=Get-Day12NativeTcpInventory -WantedPorts $ports
    $c=CIMRows
    if($a.status -ne "CAPTURED" -or $b.status -ne "CAPTURED" -or
      @($a.rows|Where-Object{$_.port -eq $port}).Count -eq 0 -or
      @($c.rows|Where-Object{$_.port -eq $port}).Count -eq 0){
      throw "Controlled listener not observed by native ALL and CIM"
    }
    [ordered]@{schema=1;synthetic=$true;result="SYNTHETIC_PASS";read_only=$true
      all_listener_seen=$true;unfiltered_cim_seen=$true;mutation_performed=$false
    }|ConvertTo-Json|Set-Content -LiteralPath $out -Encoding UTF8
    exit 0
  }finally{if($null -ne $l){$l.Stop()}}
}
$listener=Get-Day12NativeTcpInventory -WantedPorts $ports
$all=Get-Day12NativeAllTcpInventory -WantedPorts $ports
$cim=CIMRows;$perPort=CIMRows -Filtered;$net=Netstat
$rows=@()
foreach($group in @($listener,$all)){
  foreach($item in @($group.rows)){$rows+=SafeRows @($item) ([string]$item.source)}
}
$rows+=@($cim.rows)+@($perPort.rows)+@($net.rows)
$portSummary=@()
foreach($p in $ports){
  $r=@($rows|Where-Object{$_.port -eq $p})
  $portSummary+= [pscustomobject]@{
    port=$p;observations=$r.Count
    sources=@($r|ForEach-Object{$_.provider}|Select-Object -Unique)
    scopes=@($r|ForEach-Object{$_.scope}|Select-Object -Unique)
    status=if($r.Count -eq 0){"NOT_OBSERVED"}elseif(@($r|Where-Object{$_.scope -ne "LOOPBACK"}).Count){ "NON_LOOPBACK_OR_UNKNOWN"}else{"LOOPBACK_OBSERVED"}
  }
}
[ordered]@{schema=1;phase="12.10-provider-diff";synthetic=$false;read_only=$true
  generated_at=(Get-Date).ToString("o");result="CAPTURED_REVIEW_REQUIRED"
  ports=$portSummary
  providers=[ordered]@{native_listener=$listener.providers;native_listener_status=$listener.status
    native_all=$all.providers;native_all_status=$all.status
    cim_unfiltered=$cim.details;cim_per_port=$perPort.details;netstat=$net.meta}
  notes=@("No network requests, local TCP client connections, firewall queries or GSC config changes.",
    "Only listener state, port numbers, coarse IP address scopes and error categories are emitted.",
    "Observed loopback LISTEN is scoped OS evidence; missing rows are inconclusive.",
    "This is NOT canonical Day12.10 PASS and never promotes Stable.")
  mutation_performed=$false;secrets_exported=$false
}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Saved 12.10 provider diagnostic: "+$out)
exit 0
