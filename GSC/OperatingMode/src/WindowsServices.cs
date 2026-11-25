using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;
using System.ServiceProcess;
using Microsoft.Win32;

namespace GmsMode
{
    public sealed partial class WindowsEntries
    {
        const string ServicesKey=@"SYSTEM\CurrentControlSet\Services";
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
        static extern IntPtr OpenSCManager(string machine,string database,uint access);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
        static extern IntPtr OpenService(IntPtr scm,string name,uint access);
        [DllImport("advapi32.dll",SetLastError=true)] static extern bool CloseServiceHandle(IntPtr h);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
        static extern bool ChangeServiceConfig(IntPtr service,uint type,uint start,uint error,string path,string group,IntPtr tag,string deps,string account,string password,string display);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
        static extern bool ChangeServiceConfig2(IntPtr service,uint level,ref int value);

        static int Number(RegistryKey key,string name,int orElse)
        {
            object v=key.GetValue(name);
            return v is int ? (int)v : orElse;
        }
        static string Image(RegistryKey k) { return k.GetValue("ImagePath",null,RegistryValueOptions.DoNotExpandEnvironmentNames) as string; }
        static bool Delayed(RegistryKey k) { return Number(k,"DelayedAutoStart",0)!=0; }
        static bool IndirectStart(string name,RegistryKey k)
        {
            using (var triggers=k.OpenSubKey("TriggerInfo"))
                if (triggers!=null && triggers.SubKeyCount>0) return true;
            // Demand-start services can still be launched as dependencies, including
            // by other demand-start services whose own trigger is unknown.
            using (var svc=new ServiceController(name))
            {
                var dependents=svc.DependentServices;
                try { return dependents.Length!=0; }
                finally { foreach (var d in dependents) d.Dispose(); }
            }
        }
        static string ServiceSignature(RegistryKey k)
        {
            return TextHash(Pack(Image(k),Number(k,"Type",0).ToString(),k.GetValue("ObjectName","") as string,
                        k.GetValue("DisplayName","") as string));
        }
        static string ServiceState(RegistryKey k)
        {
            int start=Number(k,"Start",-1);
            // SCM ignores DelayedAutoStart when start=demand. On restore it is
            // explicitly set back to the saved automatic/delayed configuration.
            return Pack(start.ToString(), start==2 && Delayed(k) ? "1" : "0",ServiceSignature(k));
        }
        void ScanServices(List<Entry> rows,List<string> notes)
        {
            try
            {
                using (var b=BaseKey("HKLM","64"))
                using (var list=b.OpenSubKey(ServicesKey))
                {
                    foreach (string name in list.GetSubKeyNames())
                    {
                        try
                        {
                            using (var k=list.OpenSubKey(name))
                            {
                                if (k==null) continue;
                                int type=Number(k,"Type",0);
                                if ((type & 0x30)==0) continue;
                                string img=Image(k);
                                string proof=owner.Command(img);
                                if (proof==null || type!=0x10)
                                {
                                    if (WindowsOwnership.Hint(name+" "+img) || WindowsOwnership.IndirectCommand(img))
                                        notes.Add("서비스 수동 확인 · "+name+" (공유 서비스 또는 실행 대상 미확인)");
                                    continue;
                                }
                                int start=Number(k,"Start",-1);
                                if (start==4) { notes.Add("이미 사용 안 함 · 서비스 "+name); continue; }
                                if (IndirectStart(name,k)) { notes.Add("서비스 종속성 또는 트리거 시작 수동 확인 · "+name); continue; }
                                if (start!=2) { notes.Add("자동 시작 유형 아님 · 서비스 "+name); continue; }
                                rows.Add(Item("Service",name,"서비스 · "+name,proof,ServiceState(k),Pack("3","0",ServiceSignature(k)),
                                    Delayed(k)?"지연된 자동 시작 → 수동":"자동 시작 → 수동"));
                            }
                        }
                        catch (Exception ex) { Note(notes,"서비스 "+name,ex); }
                    }
                }
            }
            catch (Exception ex) { Note(notes,"서비스 목록",ex); }
        }
        string ServiceAccess(Entry e,string next)
        {
            string[] before=Parts(e.Before,3), after=Parts(e.After,3);
            if (e.Id=="" || e.Id.Contains("\\") || e.Id.Contains("/") || e.Id.Contains("\0") ||
                before[0]!="2" || !Is(before[1],"0","1") || after[0]!="3" || after[1]!="0" || before[2]!=after[2]) throw Invalid();
            using (var b=BaseKey("HKLM","64"))
            using (var k=b.OpenSubKey(ServicesKey+"\\"+e.Id))
            {
                if (k==null || Number(k,"Type",0)!=0x10 || IndirectStart(e.Id,k)) throw Invalid();
                string proof=owner.Command(Image(k));
                string now=ServiceState(k);
                if (proof==null || !CI.Equals(proof,e.Proof) || (now!=e.Before && now!=e.After)) throw Invalid();
                if (next==null || now==next) return now;
                IntPtr scm=OpenSCManager(null,null,1);
                if (scm==IntPtr.Zero) throw new Win32Exception();
                try
                {
                    IntPtr service=OpenService(scm,e.Id,2);
                    if (service==IntPtr.Zero) throw new Win32Exception();
                    try
                    {
                        uint start=next==e.After ? 3u : 2u;
                        if (!ChangeServiceConfig(service,uint.MaxValue,start,uint.MaxValue,null,null,IntPtr.Zero,null,null,null,null)) throw new Win32Exception();
                        if (start==2 && Delayed(k)!=(before[1]=="1"))
                        {
                            int value=before[1]=="1"?1:0;
                            if (!ChangeServiceConfig2(service,3,ref value))
                            {
                                int error=Marshal.GetLastWin32Error();
                                // Restore the exact pre-call demand state before reporting failure.
                                if (!ChangeServiceConfig(service,uint.MaxValue,3,uint.MaxValue,null,null,IntPtr.Zero,null,null,null,null)) throw Invalid();
                                throw new Win32Exception(error);
                            }
                        }
                    }
                    finally { CloseServiceHandle(service); }
                }
                finally { CloseServiceHandle(scm); }
                return next;
            }
        }
    }
}
