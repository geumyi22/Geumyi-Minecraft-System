using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using GmsMode;

internal static class TransactionTests
{
    static int count;
    static readonly string[] NoRoots = new string[0];
    static void Check(bool ok,string test)
    { if (!ok) throw new Exception(test); Console.WriteLine("PASS " + (++count) + "  " + test); }
    static Entry Sample(string name) { return new Entry { Kind="fixture", Id=name, Label=name, Before="automatic", After="manual", Eligible=true }; }
    static bool Blocked(Action act) { try { act(); return false; } catch (IOException) { return true; } }
    static string Digest(string path)
    { using (var h = SHA256.Create()) using (var f = File.OpenRead(path)) return Convert.ToBase64String(h.ComputeHash(f)); }
    sealed class Box
    {
        internal readonly string Folder;
        internal readonly Disk Disk;
        internal Box(string folder) { Folder=folder; Disk=new Disk(Path.Combine(folder,"state"),false); Disk.Prepare(); }
        internal string Read(Entry e) { return File.ReadAllText(Path.Combine(Folder,e.Id)); }
        internal void Write(Entry e,string value) { File.WriteAllText(Path.Combine(Folder,e.Id),value); }
        internal Engine Engine() { return new Engine(Disk,Read,Write); }
        internal int Run(bool apply,params Entry[] list) { return Engine().Run(Disk.Load(),list,NoRoots,apply,"boot-1"); }
    }
    static int Main(string[] args)
    {
        try
        {
            if (args.Length == 2 && args[0] == "crash")
            {
                // Only operates inside the fixture created by our parent process.
                if (!File.Exists(Path.Combine(args[1],"qa-owned"))) return 4;
                var b = new Box(args[1]);
                var engine = new Engine(b.Disk,b.Read,delegate(Entry e,string state) { b.Write(e,state); Environment.Exit(87); });
                engine.Run(b.Disk.Load(),new[]{Sample("A"),Sample("B")},NoRoots,true,"boot-1");
                return 3;
            }
            string dir=Path.Combine(Path.GetTempPath(),"gms-txn-"+Guid.NewGuid().ToString("N"));
            var box=new Box(dir);
            try { Suite(box); }
            finally { Directory.Delete(dir,true); }
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }
    static void Suite(Box b)
    {
        Entry a=Sample("A"), c=Sample("B"), d=Sample("C");
        foreach (var e in new[]{a,c,d}) b.Write(e,e.Before);
        var excluded=Sample("unrelated-java"); excluded.Eligible=false; b.Write(excluded,"original-unrelated");
        string world=Path.Combine(b.Folder,"level.dat");
        File.WriteAllBytes(world,new byte[]{0,5,90,201,240,19});
        string initial=Digest(world);
        using (b.Disk.Lock()) Check(Blocked(delegate { using (b.Disk.Lock()) {} }),"concurrent writer is refused");
        Check(b.Run(true,a,c,excluded)==2 && b.Read(a)==a.After && b.Read(c)==c.After,"apply selected fixture entries");
        string[] saved=Directory.GetFiles(b.Disk.Folder,"before-*.json");
        Check(saved.Length==1 && File.ReadAllText(saved[0]).Contains("automatic"),"before-image backup recorded");
        Check(b.Run(true,excluded)==0 && b.Disk.Load().Owned.Count==2,"repeat preview is a no-op");
        b.Write(a,a.Before); Check(b.Run(true,a,d)==2 && b.Disk.Load().Owned.Count==3,"re-registration and new entry preserve the first baseline");
        b.Write(c,"externally-edited");
        Check(Blocked(()=>b.Run(false)) && b.Read(c)=="externally-edited" && b.Read(d)==d.After,"external drift blocks restore before writes");
        b.Write(c,c.After);
        Check(b.Run(false)==3 && b.Read(a)==a.Before && b.Read(d)==d.Before && b.Disk.Load().Owned.Count==0,"restore all three entries");
        Check(b.Run(false)==0,"repeat restore is a no-op");
        var failAfterWrite=new Engine(b.Disk,b.Read,delegate(Entry e,string state) {
            b.Write(e,state); if (e.Id=="B" && state==e.After) throw new IOException("injected post-write failure");
        });
        Check(Blocked(()=>failAfterWrite.Run(b.Disk.Load(),new[]{a,c},NoRoots,true,"b")) &&
            b.Read(a)==a.Before && b.Read(c)==c.Before && b.Disk.Load().Pending=="","post-write failure rolls back all attempted changes");
        b.Run(true,a,c);
        var failRestore=new Engine(b.Disk,b.Read,delegate(Entry e,string state) {
            b.Write(e,state); if (e.Id=="A" && state==e.Before) throw new IOException("injected restore failure");
        });
        Check(Blocked(()=>failRestore.Run(b.Disk.Load(),new Entry[0],NoRoots,false,"b")) &&
            b.Read(a)==a.After && b.Read(c)==c.After && b.Disk.Load().Owned.Count==2,"failed restore returns to manual baseline");
        b.Run(false);
        File.WriteAllText(Path.Combine(b.Folder,"qa-owned"),"fixture");
        var info=new ProcessStartInfo(Assembly.GetExecutingAssembly().Location,"crash \""+b.Folder+"\"") { UseShellExecute=false };
        using (var proc=Process.Start(info)) { proc.WaitForExit(); Check(proc.ExitCode==87,"isolated child exits after OS write before commit"); }
        var dropped=b.Disk.Load();
        Check(dropped.Intent==1 && dropped.Pending=="apply" && b.Read(a)==a.After && b.Read(c)==c.Before,"durable journal records only attempted entries after process death");
        b.Engine().Recover(dropped);
        Check(b.Read(a)==a.Before && b.Disk.Load().Pending=="","new transaction engine recovers interrupted process");
        var conflict=new Engine(b.Disk,b.Read,delegate(Entry e,string state) {
            if (e.Id=="B") { b.Write(e,"foreign"); throw new IOException("external edit"); } b.Write(e,state);
        });
        Check(Blocked(()=>conflict.Run(b.Disk.Load(),new[]{a,c},NoRoots,true,"b")) && b.Read(a)==a.Before &&
            b.Read(c)=="foreign" && b.Disk.Load().Intent==1,"rollback restores unaffected entries and retains conflicting entry");
        b.Write(c,c.After); b.Engine().Recover(b.Disk.Load());
        Check(b.Read(c)==c.Before && b.Disk.Load().Pending=="","unresolved recovery resumes after identity is restored");
        var duplicate=new[]{a,a};
        Check(Blocked(()=>b.Run(true,duplicate)) && b.Read(a)==a.Before,"duplicate keys fail in preflight");
        Check(Digest(world)==initial && b.Read(excluded)=="original-unrelated","world sentinel and unrelated Java fixture preserved");
        var foreign=b.Disk.Load(); foreign.Machine="other-machine"; b.Disk.Save(foreign);
        Check(Blocked(()=>b.Disk.Load()),"foreign-machine journal rejected");
    }
}
