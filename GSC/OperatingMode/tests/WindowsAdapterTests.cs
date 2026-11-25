using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Xml;
using Microsoft.Win32;

namespace GmsMode
{
    // These tests use a fresh, non-startup registry key and sandbox directories.
    // Scheduler definitions are edited in memory and never registered with Windows.
    internal static class WindowsAdapterTests
    {
        static int checkedCases;
        static void Check(bool ok,string description)
        {
            if (!ok) throw new Exception(description);
            ++checkedCases; Console.WriteLine("PASS "+description);
        }
        static bool Refused(Action action) { try { action(); return false; } catch (InvalidDataException) { return true; } }
        static string Q(string value) { return "\""+value+"\""; }
        [STAThread] public static int Main(string[] args)
        {
            if (args.Length!=1 || !Directory.Exists(args[0])) return 2;
            string box=Path.Combine(Path.GetFullPath(args[0]),"windows-adapters-"+Guid.NewGuid().ToString("N"));
            string baseKey=@"Software\GmsOperatingModeTest-"+Guid.NewGuid().ToString("N");
            Directory.CreateDirectory(box);
            try
            {
                string install=Directory.CreateDirectory(Path.Combine(box,"Program Files","GSC")).FullName;
                string host=Path.Combine(install,"GeumyiServerHost.exe");
                File.WriteAllText(host,"inert QA file"); // never executed
                string startup=Directory.CreateDirectory(Path.Combine(box,"menuA","test-startup")).FullName;
                string common=Directory.CreateDirectory(Path.Combine(box,"menuB","test-startup")).FullName;
                var adapters=new WindowsEntries(new[]{install},baseKey+"\\",startup,common);
                var notes=new List<string>();
                var entries=new List<Entry>();
                string cmd=Q(host)+" --service";
                using (RegistryKey k=Registry.CurrentUser.CreateSubKey(baseKey+"\\Run"))
                {
                    k.SetValue("fixture",cmd,RegistryValueKind.ExpandString);
                    k.SetValue("unrelated","notepad.exe "+Q(host),RegistryValueKind.String);
                    k.SetValue("fake cmd","cmd.exe /c echo "+Q(host),RegistryValueKind.String);
                    k.SetValue("opaque","cmd.exe /c C:\\Ops\\launch.cmd",RegistryValueKind.String);
                    adapters.ScanRun(entries,notes);
                    Check(entries.Count==1 && entries[0].Kind=="Run","Run parser filters misleading arguments and deduplicates shared HKCU views");
                    Check(notes.Any(x=>x.Contains("opaque")),"unnamed opaque script launcher flagged in review notes without exposing arguments");
                    Entry e=entries.Single();
                    Check(adapters.Read(e)==e.Before,"Run baseline read");
                    adapters.Write(e,e.After);
                    Check(k.GetValue("fixture")==null && k.GetValue("unrelated")!=null,"only the approved value is removed");
                    adapters.Write(e,e.After);
                    k.SetValue("fixture","foreign executable");
                    Check(Refused(()=>adapters.Write(e,e.Before)) && (string)k.GetValue("fixture")=="foreign executable","foreign replacement blocks restore");
                    k.DeleteValue("fixture");
                    adapters.Write(e,e.Before);
                    Check(k.GetValueKind("fixture")==RegistryValueKind.ExpandString && (string)k.GetValue("fixture",null,RegistryValueOptions.DoNotExpandEnvironmentNames)==cmd,"exact data and registry type restored");
                }
                string lnk=Path.Combine(startup,"fixture.lnk");
                dynamic shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell",true));
                dynamic shortcut=shell.CreateShortcut(lnk);
                try { shortcut.TargetPath=host; shortcut.Arguments="--service"; shortcut.Save(); }
                finally { Marshal.ReleaseComObject(shortcut); Marshal.ReleaseComObject(shell); }
                string original=WindowsEntries.FileHash(lnk);
                string foreign=Path.Combine(startup,"foreign.cmd"); File.WriteAllText(foreign,"rem inert");
                entries.Clear(); adapters.ScanStartup(entries,notes);
                Check(entries.Count==1 && entries[0].Kind=="Startup","shortcut identity and unknown startup file exclusion");
                var entry=entries.Single();
                adapters.Write(entry,entry.After); adapters.Write(entry,entry.After);
                Check(!File.Exists(lnk) && File.Exists(foreign),"startup file parked outside startup folder");
                File.WriteAllText(lnk,"another file");
                Check(Refused(()=>adapters.Write(entry,entry.Before)) && File.ReadAllText(lnk)=="another file","startup filename collision blocks restore");
                File.Delete(lnk);
                adapters.Write(entry,entry.Before);
                Check(WindowsEntries.FileHash(lnk)==original,"startup .lnk restores byte-for-byte");
                string proxy=Directory.CreateDirectory(Path.Combine(box,"proxy")).FullName;
                string java=Path.Combine(box,"java.exe"); File.WriteAllText(java,"inert");
                File.WriteAllText(Path.Combine(proxy,"velocity.jar"),"inert");
                File.WriteAllText(Path.Combine(proxy,"velocity.toml"),"inert");
                var owner=new WindowsOwnership(new[]{proxy});
                Check(owner.Target(java,new[]{"-jar","velocity.jar"},proxy)==null,"unrelated executable named java.exe excluded");
                string jdir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Java");
                string jvm=Directory.Exists(jdir)?Directory.GetFiles(jdir,"java.exe",SearchOption.AllDirectories).FirstOrDefault():null;
                if (jvm!=null)
                {
                    Check(owner.Target(jvm,new[]{"-Xms256M","-Xmx512M","-jar","velocity.jar"},proxy)==Path.Combine(proxy,"velocity.jar"),"Day10 jar resolved with scheduler working directory");
                    Check(owner.Target(jvm,new[]{"-jar","velocity.jar"},box)==null,"java outside supported proxy directory excluded");
                    Check(owner.Target(jvm,new[]{"-javaagent:other","-jar","velocity.jar"},proxy)==null,"ambiguous java agent excluded");
                }
                else Console.WriteLine("SKIP positive JDK identity case (JDK not installed in Program Files/Java)");
                string start=Path.Combine(proxy,"start.bat"); File.WriteAllText(start,"@echo off\r\nsetlocal\r\ncd /d \"%~dp0\"\r\njava -Xms256M -Xmx512M -jar \"%~dp0velocity.jar\"\r\n");
                Check(owner.Command("cmd.exe /c "+Q(start))==start && owner.Command("cmd.exe /c "+Q(start)+" & calc.exe")==null,"stock proxy launcher allowed, compound command refused");
                File.AppendAllText(start,"notepad.exe\r\n");
                Check(owner.Command("cmd.exe /c "+Q(start))==null,"modified mixed-purpose launcher refused despite approved directory");
                TestLegacyCopies(box);
                TestTaskMemory(adapters,host);
                Console.WriteLine("Total: "+checkedCases);
                return 0;
            }
            catch(Exception ex) { Console.Error.WriteLine(ex); return 1; }
            finally
            {
                Registry.CurrentUser.DeleteSubKeyTree(baseKey,false);
                // box is newly created under the supplied QA directory, never a live GMS root.
                Directory.Delete(box,true);
            }
        }
        static void TestLegacyCopies(string box)
        {
            string pd=Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            string copyRoot=Directory.CreateDirectory(Path.Combine(box,"pd")).FullName;
            string ps=Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe");
            foreach (string name in new[]{"MinecraftServer","MinecraftPlaygroundServer"})
            {
                string src=Path.Combine(pd,name);
                if (!File.Exists(Path.Combine(src,"BootStart.ps1"))) { Console.WriteLine("SKIP legacy positive copy "+name+" (profile unavailable)"); continue; }
                string dest=Directory.CreateDirectory(Path.Combine(copyRoot,name)).FullName;
                Directory.CreateDirectory(Path.Combine(dest,"Manager"));
                File.WriteAllText(Path.Combine(dest,"server_path.txt"),"inert");
                var o=new WindowsOwnership(new[]{dest},copyRoot);
                foreach(string n in new[]{"BootStart.ps1","StartServer.ps1","launch_console.cmd","launch_server.cmd","launch_web.cmd"})
                {
                    string path=Path.Combine(dest,n);
                    if (!File.Exists(Path.Combine(src,n))) continue;
                    File.Copy(Path.Combine(src,n),path);
                    string raw=Path.GetExtension(n)==".ps1" ? Q(ps)+" -NoProfile -ExecutionPolicy Bypass -File "+Q(path) : "cmd.exe /d /c "+Q(path);
                    Check(o.Command(raw)==path,"legacy fingerprint and exact invocation "+name+"/"+n);
                    Check(o.Command(Q(ps)+" -Command "+Q(path))==null && o.Command(raw+" -extra")==null,"unexpected shell/args rejected "+name+"/"+n);
                    File.AppendAllText(path," ");
                    Check(o.Command(raw)==null,"edited legacy content rejected "+name+"/"+n);
                }
            }
        }
        static void TestTaskMemory(WindowsEntries a,string host)
        {
            dynamic svc=Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service",true));
            svc.Connect();
            dynamic d=svc.NewTask(0);
            try
            {
                dynamic tr=d.Triggers.Create(8); dynamic off=d.Triggers.Create(9); off.Enabled=false;
                dynamic action=d.Actions.Create(0); action.Path=host;
                var doc=new XmlDocument(); doc.LoadXml((string)d.XmlText);
                Check(a.TaskProof(doc)==host,"detached Windows Task Scheduler definition matches Host action");
                string before=doc.OuterXml;
                var method=typeof(WindowsEntries).GetMethod("DisabledTriggers",System.Reflection.BindingFlags.Static|System.Reflection.BindingFlags.NonPublic);
                string after=(string)method.Invoke(null,new object[]{svc,before});
                dynamic afterDef=svc.NewTask(0); afterDef.XmlText=after;
                Check(after!=before && !(bool)afterDef.Triggers.Item(1).Enabled && !(bool)afterDef.Triggers.Item(2).Enabled && (bool)afterDef.Settings.Enabled,"disables active trigger, preserves disabled trigger and task-wide enabled state");
                var reread=new XmlDocument(); reread.LoadXml((string)afterDef.XmlText);
                Check(reread.OuterXml==after,"disabled XML matches Windows COM reparse and serialization byte-for-byte");
                afterDef.XmlText=before;
                reread.LoadXml((string)afterDef.XmlText);
                Check(reread.OuterXml==before && (bool)afterDef.Triggers.Item(1).Enabled && !(bool)afterDef.Triggers.Item(2).Enabled,"restore COM XML matches exact original definition and mixed trigger states");
                dynamic extra=d.Actions.Create(0); extra.Path="notepad.exe"; doc.LoadXml((string)d.XmlText);
                Check(a.TaskProof(doc)==null,"mixed task with unrelated second action excluded");
                Marshal.ReleaseComObject(extra); Marshal.ReleaseComObject(afterDef);
                Marshal.ReleaseComObject(off); Marshal.ReleaseComObject(tr); Marshal.ReleaseComObject(action);
            }
            finally { Marshal.ReleaseComObject(d); Marshal.ReleaseComObject(svc); }
        }
    }
}
