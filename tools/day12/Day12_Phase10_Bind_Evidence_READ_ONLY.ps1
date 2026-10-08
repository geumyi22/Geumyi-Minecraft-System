[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$wanted=@(25565,25566,25567,25570,25571,25572,25573,25575,25576,25577,25579,8787,8790)
$private=@(25570,25571,25572,25573,25575,25576,25577,25579)
$expected=@(
  [ordered]@{id="wild";java=25570;rcon=25575},
  [ordered]@{id="playground";java=25571;rcon=25576},
  [ordered]@{id="other";java=25572;rcon=25577},
  [ordered]@{id="lobby";java=25573;rcon=25579}
)
function Scope([string]$Address){
  $a=$Address.Trim('[',']').ToLowerInvariant()
  if($a -in @("127.0.0.1","::1","::ffff:127.0.0.1")){return "loopback"}
  if($a -in @("0.0.0.0","::","*")){return "wildcard"}
  if([string]::IsNullOrWhiteSpace($a)){return "unknown"}
  return "non-loopback"
}
function Safe-Listener([int]$Port,[string]$Address,[string]$Source,[int]$OwnerPid=0){
  $scope=Scope $Address
  [ordered]@{
    port=$Port
    address_scope=$scope
    address=$(if($scope -in @("loopback","wildcard")){$Address}else{"REDACTED_NON_LOOPBACK"})
    process_id=$OwnerPid
    source=$Source
  }
}
function Parse-Listeners([string[]]$Lines,[int[]]$Wanted){
  $records=New-Object System.Collections.ArrayList
  foreach($line in @($Lines)){
    if([string]$line -match '^\s*TCP\s+(\S+)\s+\S+\s+LISTENING\s+(\d+)\s*$'){
      $local=[string]$Matches[1]
      $ownerId=[int]$Matches[2]
      if($local -match '^(.+):(\d+)$'){
        $portNumber=[int]$Matches[2]
        if($Wanted -contains $portNumber){
          [void]$records.Add((Safe-Listener $portNumber ([string]$Matches[1]).Trim('[',']') "netstat" $ownerId))
        }
      }
    }
  }
  return $records.ToArray()
}
function Parse-Properties([string[]]$Lines){
  $values=@{}
  foreach($line in @($Lines)){
    if([string]$line -match '^\s*(server-ip|server-port|enable-rcon|rcon\.port)\s*=\s*(.*?)\s*$'){
      $values[[string]$Matches[1].ToLowerInvariant()]=[string]$Matches[2]
    }
  }
  $ip=if($values.ContainsKey("server-ip")){$values["server-ip"]}else{""}
  $scope=if(-not $values.ContainsKey("server-ip")){"missing"}elseif([string]::IsNullOrWhiteSpace($ip)){"wildcard_or_default"}else{Scope $ip}
  return [ordered]@{
    ip_scope=$scope
    ip_config=$(if($scope -eq "loopback"){$ip}else{"REDACTED_OR_EMPTY"})
    port=$(if($values.ContainsKey("server-port")){$values["server-port"]}else{"missing"})
    rcon_enabled=$(if($values.ContainsKey("enable-rcon")){$values["enable-rcon"]}else{"missing"})
    rcon_port=$(if($values.ContainsKey("rcon.port")){$values["rcon.port"]}else{"missing"})
  }
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Bind-Evidence"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-Bind-Evidence-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  $sample=@(
    ' TCP 127.0.0.1:25570 0.0.0.0:0 LISTENING 1234',
    ' TCP 0.0.0.0:25571 0.0.0.0:0 LISTENING 1235',
    ' TCP [::1]:25573 [::]:0 LISTENING 1236',
    ' TCP 127.0.0.1:52000 127.0.0.1:25570 TIME_WAIT 0'
  )
  $parsed=@(Parse-Listeners $sample @(25570,25571,25573))
  $p1=Parse-Properties @("server-ip=127.0.0.1","server-port=25570","enable-rcon=true","rcon.port=25575","rcon.password=DO_NOT_EXPORT")
  $p2=Parse-Properties @("server-ip=","server-port=25571")
  if($parsed.Count -ne 3 -or $parsed[0].address_scope -ne "loopback" -or
     $parsed[1].address_scope -ne "wildcard" -or $parsed[2].address_scope -ne "loopback" -or
     $parsed[0].process_id -ne 1234 -or $p1.ip_scope -ne "loopback" -or
     $p2.ip_scope -ne "wildcard_or_default" -or $p1.Contains("rcon.password")){
    throw "Phase 12.10 binding evidence regression"
  }
  [ordered]@{schema=1;phase="12.10-bind-evidence";synthetic=$true;read_only=$true;result="SYNTHETIC_PASS";mutation_performed=$false}|
    ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "SYNTHETIC PASS";exit 0
}
$base=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$cfgPath=Join-Path (Join-Path $base "GeumyiServerCenter") "server.json"
$cfg=$null
$configError=""
try{
  if(Test-Path -LiteralPath $cfgPath -PathType Leaf){
    $cfg=Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8|ConvertFrom-Json
  }else{$configError="server.json not found"}
}catch{$configError="server.json unreadable"}
$cfgById=@{}
if($null -ne $cfg){
  foreach($s in @($cfg.servers)){
    if($null -eq $s){continue}
    $id=([string]$s.id).ToLowerInvariant()
    $cfgById[$id]=$s
  }
}
$rows=@()
foreach($e in $expected){
  $pathPresent=$false
  $propsPresent=$false
  $props=[ordered]@{ip_scope="unavailable";ip_config="";port="unknown";rcon_enabled="unknown";rcon_port="unknown"}
  $hash=""
  if($cfgById.ContainsKey($e.id)){
    $s=$cfgById[$e.id]
    $serverDir=[string]$s.path
    if(-not [string]::IsNullOrWhiteSpace($serverDir)){
      $pathPresent=Test-Path -LiteralPath $serverDir -PathType Container
      $propFile=Join-Path $serverDir "server.properties"
      $propsPresent=Test-Path -LiteralPath $propFile -PathType Leaf
      if($propsPresent){
        try{
          $props=Parse-Properties @(Get-Content -LiteralPath $propFile -ErrorAction Stop)
          $hash=(Get-FileHash -LiteralPath $propFile -Algorithm SHA256).Hash.ToLowerInvariant()
        }catch{$props=[ordered]@{ip_scope="unreadable";ip_config="";port="unknown";rcon_enabled="unknown";rcon_port="unknown"}}
      }
    }
  }
  $rows+= [ordered]@{
    id=$e.id;expected_java=$e.java;expected_rcon=$e.rcon
    configured_in_gsc=$cfgById.ContainsKey($e.id)
    directory_present=$pathPresent;properties_present=$propsPresent
    properties_sha256=$hash;binding=$props
  }
}
function Get-FleetState {
  try{
    $response=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/v4/update/fleet" -Method GET -TimeoutSec 5 -ErrorAction Stop
    if($null -eq $response -or $null -eq $response.servers){
      return [ordered]@{status="NO_SERVER_ROWS";servers=@()}
    }
    $safe=@()
    foreach($entry in @($response.servers)){
      if($null -eq $entry){continue}
      $id=[string]$entry.server_id
      if($id -notin @("wild","playground","other","lobby")){continue}
      $onlineProp=$entry.PSObject.Properties["online"]
      $isOnline=($null -ne $onlineProp -and [bool]$onlineProp.Value)
      $safe+= [ordered]@{id=$id;online=$isOnline}
    }
    return [ordered]@{status="OK";servers=@($safe)}
  }catch{
    # Do not serialize API error messages: they may include local paths or tokens.
    return [ordered]@{status="UNAVAILABLE";servers=@()}
  }
}
function Probe-LoopbackTcp([int]$Port){
  $client=New-Object System.Net.Sockets.TcpClient
  $handle=$null
  try{
    $result=$client.BeginConnect("127.0.0.1",$Port,$null,$null)
    $handle=$result.AsyncWaitHandle
    if(-not $handle.WaitOne(450,$false)){return $false}
    $client.EndConnect($result)
    return [bool]$client.Connected
  }catch{return $false}finally{
    if($null -ne $handle){$handle.Close()}
    $client.Dispose()
  }
}
$fleetBefore=Get-FleetState
# Direct Windows IP Helper enumeration, redacted prior to report serialization.
$nativeSource=@'
using System;
using System.Collections.Generic;
using System.Net;
using System.Runtime.InteropServices;
public static class Day12BindNativeInspector {
  [DllImport("iphlpapi.dll", SetLastError=true)]
  private static extern uint GetExtendedTcpTable(
    IntPtr data, ref int size, bool order, uint family, uint klass, uint reserved);
  public sealed class Row {
    public int port {get;set;}
    public string address {get;set;}
    public int pid {get;set;}
    public string family {get;set;}
  }
  public static Row[] Read() {
    var found=new List<Row>();
    foreach(uint family in new uint[]{2,23}){
      int size=0;
      uint probe=GetExtendedTcpTable(IntPtr.Zero, ref size, true, family, 3, 0);
      if(probe!=122 && probe!=0) throw new Exception("GetExtendedTcpTable size probe error "+probe+" family "+family);
      if(size<4) continue;
      IntPtr buffer=Marshal.AllocHGlobal(size);
      try {
        uint err=GetExtendedTcpTable(buffer, ref size, true, family, 3, 0);
        if(err!=0) throw new Exception("GetExtendedTcpTable read error "+err+" family "+family);
        int count=Marshal.ReadInt32(buffer,0);
        int stride=family==2?24:56;
        if(count<0 || (long)count*stride+4>size) throw new Exception("Unexpected TCP table size");
        for(int i=0;i<count;i++){
          IntPtr row=IntPtr.Add(buffer,4+i*stride);
          int state=Marshal.ReadInt32(row,family==2?0:48);
          if(state!=2) continue;
          int portOffset=family==2?8:20;
          var portBytes=new byte[2];
          Marshal.Copy(IntPtr.Add(row,portOffset),portBytes,0,2);
          int port=(portBytes[0]<<8)|portBytes[1];
          int pid=Marshal.ReadInt32(row,family==2?20:52);
          string addr;
          if(family==2){
            var bytes=new byte[4]; Marshal.Copy(IntPtr.Add(row,4),bytes,0,4);
            addr=new IPAddress(bytes).ToString();
          } else {
            var bytes=new byte[16]; Marshal.Copy(row,bytes,0,16);
            long scope=(long)(uint)Marshal.ReadInt32(row,16);
            addr=new IPAddress(bytes,scope).ToString();
          }
          found.Add(new Row{port=port,address=addr,pid=pid,family=family==2?"IPv4":"IPv6"});
        }
      } finally {Marshal.FreeHGlobal(buffer);}
    }
    return found.ToArray();
  }
}
'@
$nativeReady=$false
try{
  if(-not ('Day12BindNativeInspector' -as [type])){
    Add-Type -TypeDefinition $nativeSource -ErrorAction Stop
  }
  $nativeReady=$true
}catch{}
$isElevated=$false
try{
  $principal=New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
  $isElevated=$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}catch{}
$javaProcesses=@()
try{
  $javaProcesses=@(Get-Process -ErrorAction SilentlyContinue|
    Where-Object {$_.ProcessName -in @("java","javaw")}|
    ForEach-Object {[ordered]@{name=[string]$_.ProcessName;process_id=[int]$_.Id}})
}catch{}
# Only list port numbers mentioned in the Windows portproxy configuration.
# No raw addresses, hostnames or process commands are exported.
$portProxy=[ordered]@{status="UNAVAILABLE";mentioned_target_ports=@()}
try{
  $netsh=Join-Path $env:WINDIR "System32\netsh.exe"
  if(Test-Path -LiteralPath $netsh -PathType Leaf){
    $lines=@(& $netsh interface portproxy show all 2>$null)
    $exitCode=$LASTEXITCODE
    $portMentions=@()
    if($exitCode -eq 0){
      foreach($portNumber in $wanted){
        $needle='(?<!\d)'+[string]$portNumber+'(?!\d)'
        if(@($lines|Where-Object{[string]$_ -match $needle}).Count -gt 0){$portMentions+=$portNumber}
      }
    }
    $portProxy=[ordered]@{status=$(if($exitCode -eq 0){"OK"}else{"ERROR"});mentioned_target_ports=@($portMentions)}
  }
}catch{}
$providers=New-Object System.Collections.ArrayList
for($round=1;$round -le 2;$round++){
  if($nativeReady){
    try{
      $nativeRows=@([Day12BindNativeInspector]::Read())
      $matches=@()
      foreach($item in $nativeRows){
        if($null -ne $item -and $wanted -contains [int]$item.port){
          $matches+=Safe-Listener ([int]$item.port) ([string]$item.address) "GetExtendedTcpTable" ([int]$item.pid)
        }
      }
      [void]$providers.Add([ordered]@{round=$round;source="GetExtendedTcpTable";status="OK";total=$nativeRows.Count;rows=@($matches)})
    }catch{
      [void]$providers.Add([ordered]@{round=$round;source="GetExtendedTcpTable";status="ERROR";rows=@()})
    }
  }else{
    [void]$providers.Add([ordered]@{round=$round;source="GetExtendedTcpTable";status="ERROR";rows=@()})
  }
  try{
    $all=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
    $match=@()
    foreach($item in $all){
      if($null -ne $item -and $wanted -contains [int]$item.LocalPort){
        $match+=Safe-Listener ([int]$item.LocalPort) ([string]$item.LocalAddress) "Get-NetTCPConnection" ([int]$item.OwningProcess)
      }
    }
    [void]$providers.Add([ordered]@{round=$round;source="Get-NetTCPConnection";status="OK";total=$all.Count;rows=@($match)})
  }catch{
    [void]$providers.Add([ordered]@{round=$round;source="Get-NetTCPConnection";status="ERROR";rows=@()})
  }
  try{
    $all=@([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners())
    $match=@()
    foreach($item in $all){
      if($null -ne $item -and $wanted -contains [int]$item.Port){
        $match+=Safe-Listener ([int]$item.Port) ([string]$item.Address) "IPGlobalProperties"
      }
    }
    [void]$providers.Add([ordered]@{round=$round;source="IPGlobalProperties";status="OK";total=$all.Count;rows=@($match)})
  }catch{
    [void]$providers.Add([ordered]@{round=$round;source="IPGlobalProperties";status="ERROR";rows=@()})
  }
  try{
    $netstat=Join-Path $env:WINDIR "System32\netstat.exe"
    $all=@(& $netstat -ano -p TCP 2>$null)
    $code=$LASTEXITCODE
    $match=@(Parse-Listeners $all $wanted)
    [void]$providers.Add([ordered]@{round=$round;source="netstat";status=$(if($code -eq 0){"OK"}else{"ERROR"});line_count=$all.Count;rows=@($match)})
  }catch{
    [void]$providers.Add([ordered]@{round=$round;source="netstat";status="ERROR";rows=@()})
  }
}
$fleetAfter=Get-FleetState
$tcpLoopback=@($expected|ForEach-Object{
  [ordered]@{id=$_.id;port=[int]$_.java;connects=(Probe-LoopbackTcp ([int]$_.java))}
})
$observed=@($providers|ForEach-Object{$_.rows}|Where-Object{$null -ne $_})
$potentialExposure=@($observed|Where-Object{$private -contains [int]$_.port -and $_.address_scope -ne "loopback"})
$configRisks=@($rows|Where-Object{$_.binding.ip_scope -ne "loopback"})
$report=[ordered]@{
  schema=1;phase="12.10-bind-evidence";generated_at=(Get-Date).ToString("o")
  synthetic=$false;read_only=$true;result="CAPTURED_REVIEW_REQUIRED"
  machine_role_hint=$(try{[string](Get-Service "Geumyi Server Center Host" -ErrorAction Stop).Status}catch{"UNKNOWN"})
  gsc_config_available=($null -ne $cfg);gsc_config_error=$configError
  servers=$rows;providers=@($providers.ToArray())
  fleet_before=$fleetBefore;fleet_after=$fleetAfter;java_loopback_connect=$tcpLoopback
  process_context=[ordered]@{elevated=$isElevated;java_processes=$javaProcesses}
  portproxy_summary=$portProxy
  nonloopback_private_listener_evidence_count=$potentialExposure.Count
  nonloopback_or_missing_server_ip_config_count=$configRisks.Count
  interpretation="Configured server-ip, actual TCP socket bind, GSC online state, loopback connect, and RCON bind are independent evidence. Missing listeners are never treated as PASS. No production settings are modified."
  secrets_exported=$false;mutation_performed=$false
}
$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "DAY12 BIND EVIDENCE: CAPTURED - REVIEW REQUIRED"
Write-Host ("Config scope warnings: "+$configRisks.Count+"; observed public/wildcard private listeners: "+$potentialExposure.Count)
Write-Host ("Report: "+$out)
exit 0
