# Day12 Native TCP read-only helper. Dot-source this file; it does not
# execute any network query until Get-Day12NativeTcpInventory is called.
# Evidence is read via the documented Windows IP Helper API only.
function Get-Day12NativeTcpInventory {
  [CmdletBinding()]
  param([int[]]$WantedPorts)
  if(-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core"){
    return [pscustomobject]@{status="UNSUPPORTED";rows=@();providers=@();error_categories=@("NON_WINDOWS")}
  }
  $source=@'
using System;
using System.Collections.Generic;
using System.Net;
using System.Runtime.InteropServices;
public static class GeumyiDay12TcpListenerV2 {
  [DllImport("iphlpapi.dll", SetLastError=true)]
  private static extern uint GetExtendedTcpTable(
    IntPtr table, ref int size, bool sorted, uint family, uint tableClass, uint reserved);
  public sealed class Row {
    public int port {get;set;}
    public string address {get;set;}
    public int pid {get;set;}
  }
  private static IntPtr Load(uint family,uint tableClass,ref int size) {
    uint first=GetExtendedTcpTable(IntPtr.Zero,ref size,true,family,tableClass,0);
    if(first!=122 && first!=0) throw new InvalidOperationException("NATIVE_SIZE_PROBE");
    if(size<4) throw new InvalidOperationException("NATIVE_EMPTY_TABLE_HEADER");
    IntPtr ptr=Marshal.AllocHGlobal(size);
    uint second=GetExtendedTcpTable(ptr,ref size,true,family,tableClass,0);
    if(second!=0){Marshal.FreeHGlobal(ptr);throw new InvalidOperationException("NATIVE_TABLE_READ");}
    return ptr;
  }
  private static Row[] ReadTable(uint family, uint tableClass) {
    int size=0;
    IntPtr table=Load(family,tableClass,ref size);
    try {
      int n=Marshal.ReadInt32(table,0);
      int stride=tableClass==0?20:(family==2?24:56);
      if(n<0 || (long)n*stride+4>size) throw new InvalidOperationException("NATIVE_ROW_BOUNDS");
      var rows=new List<Row>();
      for(int i=0;i<n;i++){
        IntPtr r=IntPtr.Add(table,4+i*stride);
        int state=Marshal.ReadInt32(r, family==23?48:0);
        if(state!=2) continue; // MIB_TCP_STATE_LISTEN
        int portOffset=family==23?20:8;
        byte[] b=new byte[2];
        Marshal.Copy(IntPtr.Add(r,portOffset),b,0,2);
        int port=(b[0]<<8)|b[1];
        string ip;
        if(family==2){
          byte[] addr=new byte[4];
          Marshal.Copy(IntPtr.Add(r,4),addr,0,4);
          ip=new IPAddress(addr).ToString();
        } else {
          byte[] addr=new byte[16];
          Marshal.Copy(r,addr,0,16);
          long scope=(long)(uint)Marshal.ReadInt32(r,16);
          ip=new IPAddress(addr,scope).ToString();
        }
        int pid=tableClass==0?0:Marshal.ReadInt32(r,family==23?52:20);
        rows.Add(new Row{port=port,address=ip,pid=pid});
      }
      return rows.ToArray();
    } finally {Marshal.FreeHGlobal(table);}
  }
  public static Row[] ReadOwnerV4(){return ReadTable(2,3);} // TCP_TABLE_OWNER_PID_LISTENER
  public static Row[] ReadOwnerV6(){return ReadTable(23,3);}
  public static Row[] ReadBasicV4(){return ReadTable(2,0);} // TCP_TABLE_BASIC_LISTENER
}
'@
  $providers=New-Object System.Collections.ArrayList
  $found=New-Object System.Collections.ArrayList
  try {
    if(-not ('GeumyiDay12TcpListenerV2' -as [type])){Add-Type -TypeDefinition $source -ErrorAction Stop}
  }catch {
    return [pscustomobject]@{
      status="ERROR";rows=@();providers=@();error_categories=@("NATIVE_TYPE_UNAVAILABLE")
    }
  }
  $methods=@(
    [pscustomobject]@{name="GetExtendedTcpTable_OWNER_PID_IPv4";method="ReadOwnerV4"},
    [pscustomobject]@{name="GetExtendedTcpTable_OWNER_PID_IPv6";method="ReadOwnerV6"},
    [pscustomobject]@{name="GetExtendedTcpTable_BASIC_LISTENER_IPv4";method="ReadBasicV4"}
  )
  $errors=@()
  foreach($item in $methods){
    try{
      $raw=@([GeumyiDay12TcpListenerV2]::($item.method)())
      $matches=0
      foreach($row in $raw){
        if($null -eq $row){continue}
        $port=[int]$row.port
        if($WantedPorts -notcontains $port){continue}
        $matches++
        [void]$found.Add([pscustomobject]@{
          port=$port;address=[string]$row.address;pid=[int]$row.pid;source=$item.name
        })
      }
      [void]$providers.Add([pscustomobject]@{source=$item.name;status="CAPTURED";total=$raw.Count;matched=$matches})
    }catch{
      [void]$providers.Add([pscustomobject]@{source=$item.name;status="ERROR";total=0;matched=0})
      $errors+=("NATIVE_"+$item.method.ToUpperInvariant()+"_ERROR")
    }
  }
  $passCount=@($providers|Where-Object{$_.status -eq "CAPTURED"}).Count
  $status=if($passCount -eq $providers.Count){"CAPTURED"}elseif($passCount -gt 0){"PARTIAL"}else{"ERROR"}
  return [pscustomobject]@{status=$status;rows=@($found.ToArray());providers=@($providers.ToArray());error_categories=@($errors)}
}
