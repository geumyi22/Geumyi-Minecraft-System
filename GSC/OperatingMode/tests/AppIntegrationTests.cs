using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using GmsMode;

internal static class AppIntegrationTests
{
    static int count;
    static void Check(bool ok,string title)
    { if (!ok) throw new Exception(title); Console.WriteLine("PASS " + (++count) + "  " + title); }
    [STAThread] static int Main(string[] args)
    {
        try
        {
            if (args.Length == 1 && args[0]=="--inventory")
            {
                var result=Snapshot.Scan(new string[0],new Disk(Disk.Production,true),false);
                Console.WriteLine("Read-only discovery: {0} roots, {1} process observations, {2} notes",
                    result.Roots.Length,result.Processes.Count,result.Notes.Count);
                foreach (var group in result.Entries.Where(e=>e.Eligible).GroupBy(e=>e.Kind))
                    Console.WriteLine("Eligible " + group.Key + " = " + group.Count());
                foreach (var g in result.Notes.GroupBy(n => n.Split('·')[0].Split('(')[0].Trim()).OrderByDescending(x=>x.Count()).Take(10))
                    Console.WriteLine("Review group: " + (g.Key.Length>35 ? g.Key.Substring(0,35) : g.Key) + " (" + g.Count() + ")");
                return 0;
            }
            Integration(); return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }
    static void Integration()
    {
        string identity=Disk.Sid(), path=System.Windows.Forms.Application.ExecutablePath;
        bool requested=false;
        Check(Program.RequestElevation(path,identity,delegate(ProcessStartInfo info) {
            requested=info.Verb=="runas" && info.FileName==path && info.Arguments=="--elevated-for "+identity && info.UseShellExecute;
        }) && requested,"production elevation builds same-user runas request without a mutation command");
        Check(!Program.RequestElevation(path,identity,delegate { throw new Win32Exception(1223); }),"UAC cancellation leaves standard session open (test double)");
        bool failed=false;
        try { Program.RequestElevation(path,identity,delegate { throw new Win32Exception(5); }); }
        catch (Win32Exception ex) { failed=ex.NativeErrorCode==5; }
        Check(failed,"unexpected launch error reaches UI error boundary");
        foreach (string view in new[]{"--review-manual","--review-restore"})
        {
            Check(Program.StartupReview(new[]{view},identity,false)==view &&
                Program.StartupReview(new[]{"--elevated-for",identity,view},identity,true)==view,
                "review opens in normal and same-account elevated windows " + view);
        }
        bool rejected=false;
        try { Program.StartupReview(new[]{"--elevated-for","different-account","--review-restore"},identity,true); }
        catch (InvalidOperationException) { rejected=true; }
        Check(rejected,"review intent cannot change elevation identity");
        rejected=false;
        try { Program.StartupReview(new[]{"--apply"},identity,false); }
        catch (InvalidOperationException) { rejected=true; }
        Check(rejected,"startup cannot directly apply a change");
        Check(LocalAssetPath.Accept(0x400,0x9000601a) && LocalAssetPath.Accept(0x400,0x9000e01a),"locally resident Microsoft cloud tag variants");
        Check(!LocalAssetPath.Accept(0x400,0xa000000c) && !LocalAssetPath.Accept(0x400,0xa0000003),"directory junction and symbolic link excluded");
        Check(!LocalAssetPath.Accept(0x401000,0) && !LocalAssetPath.Accept(0x40400,0x9000601a) &&
            !LocalAssetPath.Accept(0x400400,0x9000001a),"offline and recall-on-access assets excluded");
        string id=Guid.NewGuid().ToString("N"), box=Path.Combine(Path.GetTempPath(),"gms-app-"+id);
        string reg=@"Software\GmsMode-Integration-"+id;
        string start=Directory.CreateDirectory(Path.Combine(box,"profile","fixture-startup")).FullName;
        string shared=Directory.CreateDirectory(Path.Combine(box,"shared","fixture-startup")).FullName;
        string install=Directory.CreateDirectory(Path.Combine(box,"install")).FullName;
        var disk=new Disk(Path.Combine(box,"snapshot"),false);
        var roots=new[]{install};
        var system=new WindowsEntries(roots,reg+"\\",start,shared);
        string exe=Path.Combine(install,"GeumyiServerCenter.exe");
        File.WriteAllText(exe,"inert fixture"); string lnk=Path.Combine(start,"GSC fixture.lnk");
        try
        {
            using (var key=Registry.CurrentUser.CreateSubKey(reg+@"\RunOnce"))
            {
                string original="\""+exe+"\" --background";
                key.SetValue("GSC fixture",original,RegistryValueKind.String);
                key.SetValue("unrelated","notepad.exe");
                dynamic sh=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell",true));
                dynamic shortcut=sh.CreateShortcut(lnk);
                try { shortcut.TargetPath=exe; shortcut.Arguments="--background"; shortcut.Save(); }
                finally { Marshal.ReleaseComObject(shortcut); Marshal.ReleaseComObject(sh); }
                string sha=WindowsEntries.FileHash(lnk);
                var notes=new List<string>(); var rows=new List<Entry>();
                system.ScanRun(rows,notes); system.ScanStartup(rows,notes);
                Check(rows.Count==2,"preview contains approved RunOnce and shortcut fixtures");
                using (disk.Lock()) new Engine(disk,system.Read,system.Write).Run(disk.Load(),rows,roots,true,"fixture-boot");
                Check(key.GetValue("GSC fixture")==null && !File.Exists(lnk) && (string)key.GetValue("unrelated")=="notepad.exe",
                    "transaction reconciles two real Windows adapters on isolated targets");
                var reopen=new WindowsEntries(disk.Load().Roots,reg+"\\",start,shared);
                using (disk.Lock()) new Engine(disk,reopen.Read,reopen.Write).Run(disk.Load(),new List<Entry>(),roots,false,"fixture-boot");
                Check((string)key.GetValue("GSC fixture")==original && WindowsEntries.FileHash(lnk)==sha && disk.Load().Owned.Count==0,
                    "a newly opened manager restores byte-identical settings and launch shortcut");
                key.DeleteValue("GSC fixture");
                key.SetValue(" @",original); rows.Clear(); system.ScanRun(rows,notes);
                using (disk.Lock()) new Engine(disk,system.Read,system.Write).Run(disk.Load(),rows,roots,true,"fixture-boot");
                key.SetValue(" Z",original); rows.Clear(); system.ScanRun(rows,notes);
                using (disk.Lock()) new Engine(disk,system.Read,system.Write).Run(disk.Load(),rows,roots,true,"fixture-boot");
                using (disk.Lock()) new Engine(disk,system.Read,system.Write).Run(disk.Load(),new List<Entry>(),roots,false,"fixture-boot");
                Check((string)key.GetValue(" @")==original && (string)key.GetValue(" Z")==original,
                    "distinct Windows names whose Base64 differs only by case retain both backups");
            }
        }
        finally { Registry.CurrentUser.DeleteSubKeyTree(reg,false); Directory.Delete(box,true); }
    }
}
