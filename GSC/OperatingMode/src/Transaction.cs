using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.Serialization.Json;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;

namespace GmsMode
{
    public class Entry
    {
        public string Kind, Id, Label, Proof, Before, After, Change, Details;
        public bool Eligible;
        public string Key()
        {
            // Compare Windows names, never case-fold a Base64 representation.
            if (Kind == "Run" || Kind == "Startup")
            {
                string[] parts = Id.Split('|');
                int count = Kind == "Run" ? 5 : 2;
                if (parts.Length != count) throw new InvalidDataException("시작 항목 식별자가 잘못되었습니다.");
                return Kind + "\0" + Decode(parts[Kind=="Run" ? 4 : 0]) + "\0" + Decode(parts[Kind=="Run" ? 3 : 1]);
            }
            return Kind + "\0" + Id;
        }
        static string Decode(string value) { return Encoding.Unicode.GetString(Convert.FromBase64String(value)); }
    }

    // Owned contains only the last committed baseline. Steps records the current operation.
    public class Journal
    {
        public int Schema = 3;
        public string Machine = Environment.MachineName, Sid = Disk.Sid(), Boot = "", Pending = "";
        public string[] Roots = new string[0];
        public List<Entry> Owned = new List<Entry>(), Steps = new List<Entry>(), Next = new List<Entry>();
        public int Intent;
        public string NextBoot = "";
    }

    public sealed class Disk
    {
        public static readonly string Production = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "GMS Operating Mode Recovery v3");
        public readonly string Folder;
        private readonly bool protect;
        public Disk(string folder, bool secure) { Folder = folder; protect = secure; }
        public static string Sid() { return WindowsIdentity.GetCurrent().User.Value; }
        public static bool Admin()
        {
            return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
        }
        static SecurityIdentifier Principal(WellKnownSidType value) { return new SecurityIdentifier(value, null); }
        static bool Trusted(string sid) { return sid == "S-1-5-18" || sid == "S-1-5-32-544"; }
        public void Prepare()
        {
            if (!protect) { Directory.CreateDirectory(Folder); return; }
            if (!Admin() || !String.Equals(Folder, Production, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("관리자 권한으로 복구 저장소를 열어 주세요.");
            if (!Directory.Exists(Folder))
            {
                var security = new DirectorySecurity();
                security.SetAccessRuleProtection(true, false);
                var admins = Principal(WellKnownSidType.BuiltinAdministratorsSid);
                security.SetOwner(admins);
                foreach (var id in new[] { admins, Principal(WellKnownSidType.LocalSystemSid) })
                    security.AddAccessRule(new FileSystemAccessRule(id, FileSystemRights.FullControl,
                        InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                        PropagationFlags.None, AccessControlType.Allow));
                Directory.CreateDirectory(Folder, security);
            }
            ValidateFolder();
        }
        void ValidateFolder()
        {
            if ((File.GetAttributes(Folder) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("복구 저장소가 다른 경로로 연결되어 있습니다.");
            var acl = Directory.GetAccessControl(Folder);
            if (!acl.AreAccessRulesProtected || !Trusted(acl.GetOwner(typeof(SecurityIdentifier)).Value))
                throw new IOException("복구 폴더의 소유자 또는 권한이 예상과 다릅니다.");
            foreach (FileSystemAccessRule rule in acl.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                if (rule.AccessControlType == AccessControlType.Allow && !Trusted(rule.IdentityReference.Value))
                    throw new IOException("복구 폴더 접근 권한을 확인해 주세요.");
        }
        string Current { get { return Path.Combine(Folder, "current.json"); } }
        static DataContractJsonSerializer Codec() { return new DataContractJsonSerializer(typeof(Journal)); }
        const long MaxJournalBytes = 64L * 1024 * 1024;
        public Journal Load()
        {
            if (!Directory.Exists(Folder)) return new Journal();
            if (protect) ValidateFolder();
            try
            {
                if ((File.GetAttributes(Current) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("복구 기록의 경로를 확인해 주세요.");
            }
            catch (FileNotFoundException) { return new Journal(); }
            using (var stream = File.OpenRead(Current))
            {
                if (stream.Length > MaxJournalBytes) throw new IOException("복구 기록이 너무 큽니다.");
                var j = (Journal)Codec().ReadObject(stream);
                if (j == null || j.Schema != 3 || j.Machine != Environment.MachineName || j.Roots == null ||
                    j.Steps == null || j.Next == null || j.Owned == null || j.Intent < 0 || j.Intent > j.Steps.Count ||
                    (j.Pending != "" && j.Pending != "apply" && j.Pending != "restore"))
                    throw new IOException("복구 기록의 버전, PC 또는 트랜잭션 정보가 일치하지 않습니다.");
                if (j.Sid != Sid() && (j.Owned.Count != 0 || j.Pending != ""))
                    throw new IOException("원래 적용한 Windows 계정으로 열어 주세요. 사용자별 시작 항목을 보호합니다.");
                return j;
            }
        }
        void WriteNew(string path, Journal value)
        {
            using (var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                Codec().WriteObject(file, value);
                if (file.Length > MaxJournalBytes) throw new IOException("복구 기록의 안전한 크기 한도를 넘었습니다.");
                file.Flush(true);
            }
        }
        public void Save(Journal journal)
        {
            string tmp = Path.Combine(Folder, Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                WriteNew(tmp, journal);
                if (File.Exists(Current)) File.Replace(tmp, Current, null);
                else File.Move(tmp, Current);
            }
            finally { if (File.Exists(tmp)) File.Delete(tmp); }
        }
        public void Backup(Journal journal)
        {
            string name = "before-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N") + ".json";
            string temporary = Path.Combine(Folder, Guid.NewGuid().ToString("N") + ".tmp");
            try { WriteNew(temporary,journal); File.Move(temporary,Path.Combine(Folder,name)); }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        public IDisposable Lock()
        {
            Prepare();
            return new FileStream(Path.Combine(Folder, "operation.lock"), FileMode.OpenOrCreate,
                FileAccess.ReadWrite, FileShare.None);
        }
    }

    public class Engine
    {
        readonly Disk disk;
        readonly Func<Entry,string> read;
        readonly Action<Entry,string> write;
        public Engine(Disk store, Func<Entry,string> reader, Action<Entry,string> writer)
        { disk = store; read = reader; write = writer; }
        void Check(Entry e, string expected)
        {
            if (read(e) != expected) throw new IOException("미리보기와 현재 상태가 다릅니다. 다시 검사하세요. " + e.Label);
        }
        void Transition(Entry e, string from, string to)
        {
            Check(e, from);
            write(e, to);
            Check(e, to);
        }
        static void Clear(Journal j)
        {
            j.Steps = new List<Entry>(); j.Next = new List<Entry>(); j.Pending = ""; j.Intent = 0; j.NextBoot = "";
        }
        public void Recover(Journal j)
        {
            if (j.Pending == "") return;
            bool applying = j.Pending == "apply";
            // An intent is flushed before the OS call, so an interrupted OS write can be inspected.
            var conflicts = new List<string>();
            for (int i = j.Intent - 1; i >= 0; --i)
            {
                var e = j.Steps[i];
                string original = applying ? e.Before : e.After;
                string target = applying ? e.After : e.Before;
                try { if (read(e) != original) Transition(e, target, original); }
                catch (Exception) { conflicts.Add(e.Label); continue; }
                j.Steps.RemoveAt(i);
                j.Intent--;
                disk.Save(j);
            }
            if (conflicts.Count != 0)
                throw new IOException("복구 보류 " + conflicts.Count + "건 · " + String.Join(", ", conflicts));
            Clear(j); disk.Save(j);
        }
        public int Run(Journal j, IList<Entry> preview, string[] roots, bool applying, string boot)
        {
            if (j.Pending != "") throw new InvalidOperationException("중단된 작업을 먼저 복구하세요.");
            var next = j.Owned.ToDictionary(e => e.Key(), StringComparer.OrdinalIgnoreCase);
            var steps = new List<Entry>();
            if (applying)
            {
                var planned = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var e in preview.Where(item => item.Eligible))
                {
                    if (String.IsNullOrEmpty(e.Id) || e.Before == e.After || !planned.Add(e.Key()))
                        throw new IOException("중복되거나 올바르지 않은 변경 항목입니다.");
                    Entry existing;
                    if (next.TryGetValue(e.Key(), out existing) &&
                        (existing.Before != e.Before || existing.After != e.After))
                        throw new IOException("기존 백업과 재등록된 항목의 정의가 다릅니다. " + e.Label);
                    Check(e, e.Before); steps.Add(e); next[e.Key()] = e;
                }
                foreach (var owned in j.Owned.Where(e => !planned.Contains(e.Key()))) Check(owned, owned.After);
            }
            else
            {
                foreach (var e in j.Owned.AsEnumerable().Reverse())
                {
                    string state = read(e);
                    if (state == e.Before) continue;
                    if (state != e.After) throw new IOException("기존 설정과 충돌하여 복원을 보류합니다. " + e.Label);
                    steps.Add(e);
                }
                next.Clear();
            }
            if (steps.Count == 0 && (applying || j.Owned.Count == 0)) return 0;
            j.Sid = Disk.Sid(); j.Roots = roots; j.Pending = applying ? "apply" : "restore";
            j.NextBoot = applying ? boot : ""; j.Steps = steps; j.Intent = 0; j.Next = next.Values.ToList();
            disk.Backup(j); disk.Save(j);
            try
            {
                foreach (var e in steps)
                {
                    Check(e, applying ? e.Before : e.After);
                    j.Intent++; disk.Save(j);
                    Transition(e, applying ? e.Before : e.After, applying ? e.After : e.Before);
                }
                // Re-read all tracked entries, including those unchanged during this operation.
                foreach (var e in (applying ? j.Next : j.Owned)) Check(e, applying ? e.After : e.Before);
                j.Owned = j.Next; j.Boot = j.NextBoot;
                if (!applying) j.Roots = new string[0];
                Clear(j); disk.Save(j);
            }
            catch (Exception ex)
            {
                try { Recover(disk.Load()); }
                catch (Exception rollback) { throw new IOException("자동 롤백이 중단되었습니다. 복구 기록을 보존했습니다. " + rollback.Message, ex); }
                throw new IOException("전환을 중단하고 이번 작업의 시작 상태로 롤백했습니다. " + ex.Message, ex);
            }
            return steps.Count;
        }
    }
}
