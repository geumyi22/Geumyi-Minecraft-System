[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Targeted 12.10 Windows GetTcpTable2 IPv4 listener evidence.
# No GSC/API calls, TCP clients, process changes or firewall/ACL/config reads.
$targets=@(25570,25571,25573,25575,25576,25579)
if(-not $OutputDir){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-TcpTable2"}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$out=Join-Path $OutputDir ("Day12-TcpTable2-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$native=@'
using System;
using System.Collections.Generic;
using System.Net;
using System.Runtime.InteropServices;
public static class GeumyiDay12TcpTable2Reader {
  [DllImport("iphlpapi.dll",SetLastError=true)]
  private static extern uint GetTcpTable2(IntPtr data,ref uint size,bool order);
  public sealed class Row {
    public int Port {get;set;}
    public string Address {get;set;}
  }
  public static Row[] Read(){
    uint len=0;
    uint first=GetTcpTable2(IntPtr.Zero,ref len,true);
    if(first!=122 && first!=0) throw new InvalidOperationException("SIZE_PROBE_FAILED");
    if(len<4 || len>16777216) throw new InvalidOperationException("SIZE_OUT_OF_RANGE");
    IntPtr ptr=Marshal.AllocHGlobal(checked((int)len));
    try{
      uint result=GetTcpTable2(ptr,ref len,true);
      if(result!=0) throw new InvalidOperationException("TABLE_READ_FAILED");
      int n=Marshal.ReadInt32(ptr,0);
      const int stride=28; // MIB_TCPROW2: 7 consecutive 32-bit fields
      if(n<0 || ((long)n*stride+4)>len) throw new InvalidOperationException("ROW_BOUNDS");
      List<Row> list=new List<Row>();
      for(int i=0;i<n;i++){
        IntPtr row=IntPtr.Add(ptr,4+i*stride);
        int state=Marshal.ReadInt32(row,0);
        if(state!=2) continue; // MIB_TCP_STATE_LISTEN
        byte[] addr=new byte[4];
        byte[] portBytes=new byte[2];
        Marshal.Copy(IntPtr.Add(row,4),addr,0,4);
        Marshal.Copy(IntPtr.Add(row,8),portBytes,0,2);
        int port=(portBytes[0]<<8)|portBytes[1];
        list.Add(new Row{Port=port,Address=new IPAddress(addr).ToString()});
      }
      return list.ToArray();
    }finally{Marshal.FreeHGlobal(ptr);}
  }
}
'@
function AddressScope([string]$Address){
  $ip=$null
  if($Address -eq "0.0.0.0"){return "WILDCARD"}
  if([System.Net.IPAddress]::TryParse($Address,[ref]$ip)){
    if([System.Net.IPAddress]::IsLoopback($ip)){return "LOOPBACK"}
    return "NON_LOOPBACK_REDACTED"
  }
  return "UNKNOWN"
}
try{
  if(-not ("GeumyiDay12TcpTable2Reader" -as [type])){Add-Type -TypeDefinition $native -ErrorAction Stop}
}catch{throw "WIN32_INTEROP_COMPILE_FAILED"}
if($Synthetic){
  $listener=$null
  try{
    $listener=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $listener.Start()
    $ep=[System.Net.IPEndPoint]$listener.LocalEndpoint
    $rows=@([GeumyiDay12TcpTable2Reader]::Read())
    $matching=@($rows|Where-Object{$_.Port -eq $ep.Port -and (AddressScope $_.Address) -eq "LOOPBACK"})
    if($matching.Count -eq 0 -or (AddressScope "0.0.0.0") -ne "WILDCARD"){
      throw "TCP_TABLE2_LISTENER_CLASSIFIER_FAILED"
    }
    [ordered]@{schema=1;phase="12.10-tcptable2";synthetic=$true;read_only=$true
      result="SYNTHETIC_PASS";controlled_listener_observed=$true
      wildcard_classifier_verified=$true;mutation_performed=$false;secrets_exported=$false
    }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "GetTcpTable2 synthetic controlled listener PASS"
    exit 0
  }finally{if($null -ne $listener){$listener.Stop()}}
}
$rounds=@()
for($i=1;$i -le 3;$i++){
  $seen=@();$status="CAPTURED";$errorCategory="NONE"
  try{
    $all=@([GeumyiDay12TcpTable2Reader]::Read())
    foreach($e in $all){
      if($null -eq $e -or $targets -notcontains [int]$e.Port){continue}
      $seen+= [ordered]@{port=[int]$e.Port;scope=(AddressScope ([string]$e.Address))}
    }
  }catch{$status="ERROR";$errorCategory="NATIVE_TABLE_READ_OR_BOUNDS"}
  $rounds+= [ordered]@{round=$i;status=$status;error_category=$errorCategory;target_listeners=$seen}
  if($i -lt 3){Start-Sleep -Milliseconds 200}
}
$summary=@()
foreach($p in $targets){
  $hits=@($rounds|ForEach-Object{$_.target_listeners}|Where-Object{[int]$_.port -eq $p})
  $scopeList=@($hits|ForEach-Object{[string]$_.scope}|Select-Object -Unique)
  $summary+= [ordered]@{port=$p;observations=$hits.Count
    scopes=$scopeList;state=$(if($hits.Count -eq 0){"NOT_OBSERVED"}elseif(@($hits|Where-Object{$_.scope -ne "LOOPBACK"}).Count -gt 0){"NON_LOOPBACK_OR_UNKNOWN"}else{"LOOPBACK_OBSERVED"})}
}
$ok=@($rounds|Where-Object{$_.status -eq "CAPTURED"}).Count
$r=[ordered]@{
  schema=1;phase="12.10-tcptable2";generated_at=(Get-Date).ToString("o")
  result=$(if($ok -eq 3){"CAPTURED_REVIEW_REQUIRED"}else{"CHECK_REQUIRED"})
  synthetic=$false;read_only=$true
  provider="Windows GetTcpTable2 / MIB_TCPTABLE2 / IPv4 only"
  rounds=$rounds;summary=$summary
  notes=@(
    "Three scoped IPv4 native listener snapshots; no TCP packets are sent.",
    "IPv6 listener safety is not established by this IPv4-only tool.",
    "A port not observed is unknown, not verified private.",
    "Three observations are closely spaced, not continuous monitoring.",
    "No management API, firewall, ACL, Java service, server config, backup or world changes.",
    "This is targeted evidence, not the canonical Day12.10 PASS nor a Stable release approval."
  )
  mutation_performed=$false;secrets_exported=$false
}
$r|ConvertTo-Json -Depth 11|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("GetTcpTable2 scoped diagnosis: "+$r.result)
Write-Host ("Report: "+$out)
if($r.result -eq "CHECK_REQUIRED"){exit 2}
exit 0
