using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.ServiceProcess;
using System.Text;
using Microsoft.Win32;

namespace GmsMode
{
    public sealed partial class WindowsEntries
    {
        readonly WindowsOwnership owner;
        internal const string RunBase = @"SOFTWARE\Microsoft\Windows\CurrentVersion\";
        internal WindowsEntries(string[] roots, string registryBase, string startup, string common)
        {
            owner = new WindowsOwnership(roots);
            runBase = registryBase;
            startupDirs = new[]{startup, common};
        }
        public WindowsEntries(string[] roots) : this(roots,RunBase,Environment.GetFolderPath(Environment.SpecialFolder.Startup),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup)) { }

        readonly string runBase;
        readonly string[] startupDirs;
        static readonly StringComparer CI = StringComparer.OrdinalIgnoreCase;
        static readonly UnicodeEncoding ArchiveEncoding = new UnicodeEncoding(false,false,true);
        static string Pack(params string[] values)
        {
            return String.Join("|",values.Select(x=>Convert.ToBase64String(ArchiveEncoding.GetBytes(x ?? ""))).ToArray());
        }
        static string[] Parts(string input, int count)
        {
            string[] parts = input.Split('|');
            if (parts.Length != count) throw Invalid();
            return parts.Select(x=>ArchiveEncoding.GetString(Convert.FromBase64String(x))).ToArray();
        }
        static Exception Invalid() { return new InvalidDataException("항목의 정의, 위치 또는 백업이 변경되었습니다. 재검사가 필요합니다."); }
        static bool Is(string s, params string[] names) { return names.Contains(s,CI); }
        static string Digest(byte[] hash) { return BitConverter.ToString(hash).Replace("-",""); }
        internal static string FileHash(string file)
        {
            using (var h = SHA256.Create())
            using (var f = File.Open(file,FileMode.Open,FileAccess.Read,FileShare.Read)) return Digest(h.ComputeHash(f));
        }
        static string TextHash(string input)
        {
            using (var h = SHA256.Create()) return Digest(h.ComputeHash(ArchiveEncoding.GetBytes(input)));
        }
        static void Note(List<string> notes, string area, Exception ex)
        {
            notes.Add(area + " 검사 제한 (" + ex.GetType().Name + " / 0x" + ex.HResult.ToString("X8") + ")");
        }
        static Entry Item(string kind,string id,string label,string proof,string before,string after,string change)
        {
            return new Entry { Kind=kind,Id=id,Label=label,Proof=proof,Before=before,After=after,Change=change,Eligible=true };
        }
        public List<Entry> Scan(List<string> notes)
        {
            var rows = new List<Entry>();
            ScanRun(rows,notes);
            ScanStartup(rows,notes);
            ScanTasks(rows,notes);
            ScanServices(rows,notes);
            notes.Add("현재 계정·전체 사용자 항목을 검사했습니다. 다른 계정의 Run/시작 폴더, 그룹 정책, WMI 구독, 타사 감독·컨테이너, 해석할 수 없는 스크립트는 별도 확인이 필요합니다.");
            return rows;
        }
        public string Read(Entry e) { return Access(e,null); }
        public void Write(Entry e,string state)
        {
            if (!e.Eligible || state == null || (state != e.Before && state != e.After)) throw Invalid();
            Access(e,state);
            if (Read(e) != state) throw Invalid();
        }
        string Access(Entry e,string next)
        {
            if (e.Kind == "Run") return RunAccess(e,next);
            if (e.Kind == "Startup") return StartupAccess(e,next);
            if (e.Kind == "Task") return TaskAccess(e,next);
            if (e.Kind == "Service") return ServiceAccess(e,next);
            throw Invalid();
        }

        static RegistryKey BaseKey(string hive,string view)
        {
            if (!Is(hive,"HKCU","HKLM") || !Is(view,"32","64")) throw Invalid();
            return RegistryKey.OpenBaseKey(hive=="HKCU"? RegistryHive.CurrentUser : RegistryHive.LocalMachine,
                view=="32" ? RegistryView.Registry32 : RegistryView.Registry64);
        }
        [DllImport("ntdll.dll")] static extern int NtQueryKey(IntPtr handle,int info,IntPtr buffer,int length,out int needed);
        static string PhysicalKey(RegistryKey key)
        {
            int size;
            NtQueryKey(key.Handle.DangerousGetHandle(),3,IntPtr.Zero,0,out size);
            if (size <= 4 || size > 1024*1024) throw Invalid();
            IntPtr p = Marshal.AllocHGlobal(size);
            try
            {
                if (NtQueryKey(key.Handle.DangerousGetHandle(),3,p,size,out size)!=0) throw Invalid();
                return Marshal.PtrToStringUni(IntPtr.Add(p,4),Marshal.ReadInt32(p)/2);
            }
            finally { Marshal.FreeHGlobal(p); }
        }
        internal void ScanRun(List<Entry> rows,List<string> notes)
        {
            var visited = new HashSet<string>(CI);
            foreach (string hive in new[]{"HKCU","HKLM"})
            foreach (string view in new[]{"64","32"})
            foreach (string leaf in new[]{"Run","RunOnce"})
            {
                string area = hive + " " + view + "-bit " + leaf;
                try
                {
                    using (var b = BaseKey(hive,view))
                    using (var k = b.OpenSubKey(runBase + leaf,false))
                    {
                        if (k==null) continue;
                        string phys = PhysicalKey(k);
                        if (!visited.Add(phys)) continue; // Shared HKCU keys can surface in both views.
                        foreach (string n in k.GetValueNames())
                        {
                            try
                            {
                                var kind = k.GetValueKind(n);
                                string raw = k.GetValue(n,null,RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
                                string command = RunCommand(kind,raw);
                                string proof = command == null ? null : owner.Command(command);
                                if (proof == null)
                                {
                                    if (WindowsOwnership.Hint(n+" "+raw) || WindowsOwnership.IndirectCommand(raw))
                                        notes.Add("수동 확인 · "+area+" · "+n+" (실행 대상 미확인)");
                                    continue;
                                }
                                rows.Add(Item("Run",Pack(hive,view,leaf,n,phys),area+" · "+n,proof,Pack(kind.ToString(),raw),"absent","시작 값 백업 후 해제"));
                            }
                            catch (Exception ex) { Note(notes,area+" · "+n,ex); }
                        }
                    }
                }
                catch (Exception ex) { Note(notes,area,ex); }
            }
        }
        static string RunCommand(RegistryValueKind kind,string value)
        {
            if (kind == RegistryValueKind.String) return value;
            if (kind != RegistryValueKind.ExpandString || value==null) return null;
            // Own only stable machine directories. User-dependent variables can expand
            // differently for another logon to a machine-wide Run key.
            var vars = System.Text.RegularExpressions.Regex.Matches(value,"%([^%]+)%");
            foreach (System.Text.RegularExpressions.Match m in vars)
                if (!Is(m.Groups[1].Value,"ProgramData","ProgramFiles","SystemRoot","windir")) return null;
            return Environment.ExpandEnvironmentVariables(value);
        }
        string RunAccess(Entry e,string next)
        {
            string[] id=Parts(e.Id,5), before=Parts(e.Before,2);
            if (!Is(id[2],"Run","RunOnce") || !Is(before[0],"String","ExpandString") || e.After!="absent") throw Invalid();
            var kind = (RegistryValueKind)Enum.Parse(typeof(RegistryValueKind),before[0]);
            string proof = owner.Command(RunCommand(kind,before[1]));
            if (proof==null || !CI.Equals(proof,e.Proof)) throw Invalid();
            using (var b=BaseKey(id[0],id[1]))
            using (var k=b.OpenSubKey(runBase+id[2],next!=null))
            {
                if (k==null || !CI.Equals(PhysicalKey(k),id[4])) throw Invalid();
                bool exists = k.GetValueNames().Contains(id[3],CI);
                if (exists && (k.GetValueKind(id[3])!=kind || (k.GetValue(id[3],null,RegistryValueOptions.DoNotExpandEnvironmentNames) as string)!=before[1])) throw Invalid();
                string now=exists ? e.Before : e.After;
                if (next==null || next==now) return now;
                if (next==e.After) k.DeleteValue(id[3],true);
                else k.SetValue(id[3],before[1],kind);
                k.Flush();
                return next;
            }
        }

        static string SavedFile(string file)
        {
            string parent=Path.GetDirectoryName(Path.GetDirectoryName(file));
            return Path.Combine(parent,"GMS-OperatingMode-Backup",Path.GetFileName(file));
        }
        internal void ScanStartup(List<Entry> rows,List<string> notes)
        {
            for (int i=0;i<startupDirs.Length;i++)
            {
                string dir=startupDirs[i];
                try
                {
                    if (String.IsNullOrEmpty(dir) || !Directory.Exists(dir)) { notes.Add("시작 폴더 없음 · "+i); continue; }
                    if (!WindowsOwnership.PlainPath(dir)) { notes.Add("시작 폴더의 링크/권한 확인 필요 · "+i); continue; }
                    foreach (string file in Directory.GetFiles(dir))
                    {
                        string n=Path.GetFileName(file);
                        if (CI.Equals(n,"desktop.ini")) continue;
                        try
                        {
                            string proof=owner.StartupFile(file);
                            if (proof==null) { notes.Add("시작 폴더 자동 변경 제외 · "+n+" (대상 별도 확인)"); continue; }
                            if (File.Exists(SavedFile(file)) || Directory.Exists(SavedFile(file))) { notes.Add("백업 경로 충돌 · "+n); continue; }
                            rows.Add(Item("Startup",Pack(i.ToString(),n), (i==0?"사용자":"공용")+" 시작 폴더 · "+n,proof,FileHash(file),"parked","시작 폴더 밖에 원본 파일 보관"));
                        }
                        catch (Exception ex) { Note(notes,n,ex); }
                    }
                }
                catch (Exception ex) { Note(notes,"시작 폴더 "+i,ex); }
            }
        }
        string StartupAccess(Entry e,string next)
        {
            string[] id=Parts(e.Id,2);
            if (!Is(id[0],"0","1") || id[1]!=Path.GetFileName(id[1]) || String.IsNullOrEmpty(id[1]) ||
                id[1].IndexOfAny(Path.GetInvalidFileNameChars())>=0 || e.After!="parked") throw Invalid();
            string dir=startupDirs[int.Parse(id[0])], file=Path.Combine(dir,id[1]), saved=SavedFile(file), archive=Path.GetDirectoryName(saved);
            if (!WindowsOwnership.PlainPath(dir) || (Directory.Exists(archive) && !WindowsOwnership.PlainPath(archive))) throw Invalid();
            bool here=File.Exists(file), there=File.Exists(saved);
            if (here==there || Directory.Exists(file) || Directory.Exists(saved)) throw Invalid();
            string active=here?file:saved;
            if (!WindowsOwnership.PlainPath(active) || FileHash(active)!=e.Before || !CI.Equals(owner.StartupFile(active),e.Proof)) throw Invalid();
            string now=here?e.Before:e.After;
            if (next==null || next==now) return now;
            if (here)
            {
                Directory.CreateDirectory(archive);
                if (!WindowsOwnership.PlainPath(archive)) throw Invalid();
                File.Move(file,saved);
            }
            else File.Move(saved,file);
            return next;
        }
    }
}
