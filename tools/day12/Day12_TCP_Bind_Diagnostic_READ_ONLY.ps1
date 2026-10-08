[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$ports=@(25565,25566,25567,25570,25571,25572,25573,25575,25576,25577,25579,8790)
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Port-Diagnostic"
}
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
$out=Join-Path $OutputDir ("Day12-TCP-Diagnostic-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
# This call reads the system IPv4/IPv6 TCP tables only. No network
# configuration, firewall rule or process is changed.
$nativeSource=@'
using System;
using System.Collections.Generic;
using System.Net;
using System.Runtime.InteropServices;
public static class Day12TcpTableInspector {
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
$results=[ordered]@{}
try{
  Add-Type -TypeDefinition $nativeSource -ErrorAction Stop
  $results.native=[ordered]@{status="OK";rows=@([Day12TcpTableInspector]::Read() | Where-Object {$ports -contains $_.port})}
}catch{
  $results.native=[ordered]@{status="ERROR";error=[string]$_.Exception.Message;rows=@()}
}
if(-not $Synthetic){
  try{
    $data=@(Get-NetTCPConnection -State Listen -ErrorAction Stop)
    $results.powershell=[ordered]@{
      status="OK";total_listeners=$data.Count
      rows=@($data | Where-Object {$ports -contains [int]$_.LocalPort} | ForEach-Object {
        [ordered]@{port=[int]$_.LocalPort;address=[string]$_.LocalAddress;pid=[int]$_.OwningProcess}
      })
    }
  }catch{
    $results.powershell=[ordered]@{status="ERROR";error=[string]$_.Exception.Message;rows=@()}
  }
  try{
    $data=@([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners())
    $results.dotnet=[ordered]@{
      status="OK";total_listeners=$data.Count
      rows=@($data | Where-Object {$ports -contains [int]$_.Port} | ForEach-Object {
        [ordered]@{port=[int]$_.Port;address=$_.Address.ToString()}
      })
    }
  }catch{
    $results.dotnet=[ordered]@{status="ERROR";error=[string]$_.Exception.Message;rows=@()}
  }
  try{
    $netstat=Join-Path $env:WINDIR "System32\netstat.exe"
    if(-not(Test-Path -LiteralPath $netstat -PathType Leaf)){throw "netstat.exe missing: $netstat"}
    $all=@(& $netstat -ano -p TCP 2>&1)
    $code=$LASTEXITCODE
    $rows=@()
    foreach($line in $all){
      if([string]$line -match '^\s*TCP\s+(\S+)\s+(\S+)\s+LISTENING\s+(\d+)\s*$'){
        $addressPort=[string]$Matches[1];$pid=[int]$Matches[3]
        if($addressPort -match '^(.+):(\d+)$'){
          $port=[int]$Matches[2]
          if($ports -contains $port){
            $rows+=([ordered]@{port=$port;address=([string]$Matches[1]).Trim('[',']');pid=$pid})
          }
        }
      }
    }
    $results.netstat=[ordered]@{
      status=$(if($code -eq 0){"OK"}else{"ERROR"});exit_code=$code
      line_count=$all.Count;rows=@($rows)
      sample_nonsecret_lines=@($all | Where-Object {[string]$_ -match '^\s*TCP\s+' -and [string]$_ -match ':(2556[567]|2557[0-9]|8790)\s+'} | Select-Object -First 24)
    }
  }catch{
    $results.netstat=[ordered]@{status="ERROR";error=[string]$_.Exception.Message;rows=@()}
  }
  $connect=@()
  foreach($p in @(25570,25571,25573)){
    $client=New-Object System.Net.Sockets.TcpClient
    try{
      $pending=$client.BeginConnect("127.0.0.1",$p,$null,$null)
      $ok=$pending.AsyncWaitHandle.WaitOne(400)
      if($ok){try{$client.EndConnect($pending)}catch{$ok=$false}}
      $connect+=([ordered]@{port=$p;loopback_connect=$ok})
    }catch{
      $connect+=([ordered]@{port=$p;loopback_connect=$false})
    }finally{$client.Close()}
  }
  $results.loopback=$connect
}
$nativeRows=@($results.native.rows)
$report=[ordered]@{
  schema=1;phase="12.10-TCP-Diagnostic";read_only=$true
  synthetic=[bool]$Synthetic;generated_at=(Get-Date).ToString("o")
  result=$(if($Synthetic){"SYNTHETIC_CAPTURED"}else{"CAPTURED"})
  expected_ports=$ports;providers=$results
  security_note="Loopback response alone cannot prove bind address. Public backend binds remain a FAIL until verified."
  mutation_performed=$false
}
$report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("TCP DIAGNOSTIC: "+$report.result)
Write-Host ("Native rows: "+$nativeRows.Count)
Write-Host ("Report: "+$out)
if(-not $Synthetic -and $nativeRows.Count -eq 0){
  Write-Host "[CHECK] Native TCP inspection found no matching listener. Inspect the JSON; do not mark private bind safe."
}
exit 0
