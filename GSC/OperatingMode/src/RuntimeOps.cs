using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.ServiceProcess;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace GmsMode
{
    public static class RuntimeOps
    {
        const string HostExe = "GeumyiServerHost.exe";
        const string ClientExe = "GeumyiServerCenter.exe";
        const string HostService = "Geumyi Server Center Host";
        static readonly StringComparer Paths = StringComparer.OrdinalIgnoreCase;
        static string DataDir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GeumyiServerCenter"); } }
        static string ConfigPath { get { return Path.Combine(DataDir, "server.json"); } }

        static void Note(List<string> notes, string message)
        {
            if (!notes.Contains(message)) notes.Add(message);
        }

        // All operands are local fully qualified Windows paths. Check the entire chain,
        // including the file itself, before reading markers or following path files.
        static string Existing(string input, bool directory)
        {
            try
            {
                string path = WindowsOwnership.Local(input, null);
                if (path == null || path.Length < 4 || new DriveInfo(path.Substring(0, 3)).DriveType != DriveType.Fixed) return null;
                if (directory ? !Directory.Exists(path) : !File.Exists(path)) return null;
                return LocalAssetPath.Available(path) ? path : null;
            }
            catch (Exception) { return null; }
        }

        static bool Broad(string path)
        {
            // Never trust a drive root, an OS tree, a program container or a user profile
            // as a GMS launch directory, even if corrupt config points to an existing marker.
            var dirs = new[] { Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86,
                Environment.SpecialFolder.CommonApplicationData, Environment.SpecialFolder.UserProfile,
                Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolder.ApplicationData,
                Environment.SpecialFolder.MyDocuments, Environment.SpecialFolder.DesktopDirectory };
            foreach (var d in dirs)
            {
                string standard = Environment.GetFolderPath(d);
                if (Paths.Equals(path, standard) || standard.StartsWith(path + "\\", StringComparison.OrdinalIgnoreCase)) return true;
            }
            string win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            return Paths.Equals(win, path) || path.StartsWith(win + "\\", StringComparison.OrdinalIgnoreCase) ||
                Regex.IsMatch(path, @"(?i)^[a-z]:\\Users(?:\\[^\\]+(?:\\(?:Desktop|Documents|Downloads|Pictures|Videos|Music|OneDrive|AppData))?)?$");
        }

        static bool Marker(string dir, string name)
        {
            return dir != null && Existing(Path.Combine(dir, name), false) != null;
        }

        static string ReadSmall(string path, int max)
        {
            if (Existing(path, false) == null) throw new IOException("로컬 파일 경로를 확인할 수 없습니다.");
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                if (stream.Length > max) throw new IOException("구성 파일 크기가 검사 범위를 벗어났습니다.");
                using (var reader = new StreamReader(stream, Encoding.UTF8, true)) return reader.ReadToEnd();
            }
        }

        static Dictionary<string, object> Json(string s)
        {
            var obj = new JavaScriptSerializer { MaxJsonLength = 2097152, RecursionLimit = 48 }
                .DeserializeObject(s) as Dictionary<string, object>;
            if (obj == null) throw new IOException("JSON 개체 형식을 확인할 수 없습니다.");
            return obj;
        }
        static string Value(Dictionary<string, object> obj, string key)
        {
            object v;
            return obj != null && obj.TryGetValue(key, out v) && v is string ? (string)v : "";
        }
        static int Number(Dictionary<string, object> obj, string key)
        {
            object v;
            return obj != null && obj.TryGetValue(key, out v) && v is int ? (int)v : 0;
        }
        static Dictionary<string, object> Child(Dictionary<string, object> obj, string key)
        {
            object v;
            return obj != null && obj.TryGetValue(key, out v) ? v as Dictionary<string, object> : null;
        }
        static IEnumerable<Dictionary<string, object>> Entries(Dictionary<string, object> obj, string key)
        {
            object v;
            if (!obj.TryGetValue(key, out v) || v == null) yield break;
            var rows = v as object[];
            if (rows == null) throw new IOException("등록 목록 형식을 확인할 수 없습니다.");
            foreach (object entry in rows)
            {
                var row = entry as Dictionary<string, object>;
                if (row == null) throw new IOException("등록 항목 형식을 확인할 수 없습니다.");
                yield return row;
            }
        }

        static List<string> Installs()
        {
            var dirs = new List<string>();
            foreach (var folder in new[] {Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86})
            {
                string pf = Environment.GetFolderPath(folder);
                if (pf.Length != 0) dirs.Add(Path.Combine(pf, "Geumyi Server Center"));
            }
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
                using (var hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
                using (var key = hive.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter"))
                    if (key != null) dirs.Add(key.GetValue("InstallLocation") as string);
            return dirs.Select(d => Existing(d, true)).Where(d => d != null && !Broad(d) &&
                (Marker(d, HostExe) || Marker(d, ClientExe))).Distinct(Paths).ToList();
        }

        static string ServerDir(Dictionary<string, object> server)
        {
            string path = Value(server, "path").Trim();
            if (path.Length == 0)
            {
                string pf = Existing(Value(server, "path_file"), false);
                if (pf != null && Paths.Equals(Path.GetFileName(pf), "server_path.txt"))
                    path = ReadSmall(pf, 8192).Trim().TrimStart('\uFEFF');
            }
            return Existing(path, true);
        }

        sealed class Catalog
        {
            public readonly SortedSet<string> Roots = new SortedSet<string>(Paths);
            public readonly Dictionary<int,string> Ports = new Dictionary<int,string>();
            public void Port(int port, string dir)
            {
                if (port > 0 && port <= 65535 && dir != null) Ports[port] = dir;
            }
        }

        static Catalog CatalogOf(List<string> notes)
        {
            var cat = new Catalog();
            foreach (string install in Installs()) cat.Roots.Add(install);
            string programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            foreach (string name in new[] { "MinecraftServer", "MinecraftPlaygroundServer" })
            {
                string legacy = Existing(Path.Combine(programData, name), true);
                if (Marker(legacy, "BootStart.ps1") && Marker(legacy, "server_path.txt") && Marker(legacy, "launch_server.cmd"))
                    cat.Roots.Add(legacy);
            }
            if (Marker(DataDir, "server.json") || Marker(DataDir, "role.json") || Marker(DataDir, "instances.json")) cat.Roots.Add(DataDir);
            if (File.Exists(ConfigPath))
            {
                try
                {
                    var cfg = Json(ReadSmall(ConfigPath, 2097152));
                    foreach (var s in Entries(cfg, "servers"))
                    {
                        string dir = ServerDir(s);
                        if (dir == null || Broad(dir) || !Marker(dir, "server.properties"))
                        { Note(notes, "GSC 등록 서버 중 로컬 전용 경로와 server.properties를 확인하지 못한 항목이 있습니다."); continue; }
                        cat.Roots.Add(dir);
                        cat.Port(Number(s, "java_port"), dir);
                    }
                    var agent = Child(cfg, "agent");
                    string ad = Existing(Value(agent, "working_dir"), true), jar = Value(agent, "jar_name");
                    if (ad != null && !Broad(ad) && Regex.IsMatch(jar, @"(?i)^GeumyiStatusAgent(?:-[0-9.]+)?\.jar$") && Marker(ad, jar))
                    {
                        cat.Roots.Add(ad);
                        Uri health;
                        if (Uri.TryCreate(Value(agent, "health_url"), UriKind.Absolute, out health) && health.IsLoopback)
                            cat.Port(health.Port, ad);
                    }
                }
                catch (Exception) { Note(notes, "GSC server.json의 전체 등록 경로를 읽지 못했습니다."); }
            }
            string instances = Path.Combine(DataDir, "instances.json");
            if (File.Exists(instances))
            {
                try
                {
                    var catalog = Json(ReadSmall(instances, 2097152));
                    if (Number(catalog, "schema") != 1) throw new IOException();
                    foreach (var s in Entries(catalog, "instances"))
                    {
                        string dir = Existing(Value(s, "dir"), true);
                        bool proxy = Paths.Equals(Value(s, "kind"), "velocity");
                        if (dir == null || Broad(dir) || !Marker(dir, proxy ? "velocity.toml" : "server.properties"))
                        { Note(notes, "GSC 인스턴스 중 폴더 또는 구성 파일을 확인하지 못한 항목이 있습니다."); continue; }
                        cat.Roots.Add(dir);
                        cat.Port(Number(s, "java_port"), dir);
                        if (proxy) cat.Port(Number(s, "bridge_port"), dir);
                    }
                }
                catch (Exception) { Note(notes, "GSC instances.json의 전체 등록 경로를 읽지 못했습니다."); }
            }
            var proxyPorts = new Dictionary<string,int> { { @"FourServer\wild",25565 }, { @"FourServer\playground",25566 }, { @"FourServer\other",25567 }, { "Velocity",25565 } };
            foreach (var proxy in proxyPorts)
            {
                string dir = Existing(Path.Combine(DataDir, "Network", proxy.Key), true);
                if (Marker(dir, "velocity.toml") && Marker(dir, "velocity.jar"))
                { cat.Roots.Add(dir); cat.Port(proxy.Value, dir); }
            }
            return cat;
        }

        public static string[] Discover(List<string> notes)
        {
            var cat = CatalogOf(notes);
            if (cat.Roots.Count == 0) Note(notes, "기본 설치 위치와 등록 정보에서 GSC 전용 폴더를 확인하지 못했습니다.");
            return cat.Roots.ToArray();
        }

        static bool Accepted(string dir, string[] roots)
        {
            return dir != null && (roots ?? new string[0]).Contains(dir, Paths);
        }

        // TCP_TABLE_OWNER_PID_ALL also contains established connections. IPv6 dual-stack
        // Go listeners may expose a v4 mapped server socket through the IPv6 table.
        [DllImport("iphlpapi.dll")]
        static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool order, int family, int tableClass, uint reserved);
        sealed class TcpRow
        {
            public int State, Pid, Port, PeerPort;
            public IPAddress Address, Peer;
        }
        static int PortAt(IntPtr row, int offset)
        { return 256 * Marshal.ReadByte(row, offset) + Marshal.ReadByte(row, offset + 1); }
        static IPAddress IpAt(IntPtr row, int offset, int bytes)
        {
            var address = new byte[bytes];
            Marshal.Copy(IntPtr.Add(row, offset), address, 0, bytes);
            var ip = new IPAddress(address);
            return ip.IsIPv4MappedToIPv6 ? ip.MapToIPv4() : ip;
        }
        static List<TcpRow> Table()
        {
            var result = new List<TcpRow>();
            foreach (int family in new[] {2, 23})
            {
                int size = 0;
                uint status = GetExtendedTcpTable(IntPtr.Zero, ref size, false, family, 5, 0);
                if (family == 23 && (status == 50 || status == 232)) continue;
                if (status != 122 && status != 0) throw new Win32Exception((int)status);
                for (int attempt = 0; attempt < 4; attempt++)
                {
                    if (size < 4 || size > 64 * 1024 * 1024) throw new IOException("TCP 테이블 크기를 확인하지 못했습니다.");
                    int capacity = size;
                    IntPtr block = Marshal.AllocHGlobal(capacity);
                    try
                    {
                        status = GetExtendedTcpTable(block, ref size, false, family, 5, 0);
                        if (status == 122 && attempt < 3) continue;
                        if (status != 0) throw new Win32Exception((int)status);
                        int n = Marshal.ReadInt32(block), bytes = family == 2 ? 24 : 56;
                        if (n < 0 || n > (capacity - 4) / bytes) throw new IOException("TCP 소유권 테이블이 변경되었습니다.");
                        for (int i = 0; i < n; i++)
                        {
                            IntPtr r = IntPtr.Add(block, 4 + bytes * i);
                            result.Add(new TcpRow { State = Marshal.ReadInt32(r, family == 2 ? 0 : 48),
                                Pid = Marshal.ReadInt32(r, bytes - 4), Address = IpAt(r, family == 2 ? 4 : 0, family == 2 ? 4 : 16),
                                Peer = IpAt(r, family == 2 ? 12 : 24, family == 2 ? 4 : 16),
                                Port = PortAt(r, family == 2 ? 8 : 20), PeerPort = PortAt(r, family == 2 ? 16 : 44) });
                        }
                        break;
                    }
                    finally { Marshal.FreeHGlobal(block); }
                }
            }
            return result;
        }

        static bool ProvenJar(string jar, string[] roots)
        {
            string path = Existing(jar, false);
            if (path == null || !Paths.Equals(Path.GetExtension(path), ".jar")) return false;
            string dir = Path.GetDirectoryName(path);
            if (!Accepted(dir, roots)) return false;
            return Marker(dir, "server.properties") || Marker(dir, "velocity.toml") ||
                Regex.IsMatch(Path.GetFileName(path), @"(?i)^GeumyiStatusAgent(?:-[0-9.]+)?\.jar$");
        }

        static bool LegacyWebProcess(string[] args, string[] roots)
        {
            if (args.Length < 2) return false;
            // The legacy launch_web.cmd calls Manager\Web\Run.cmd which passes
            // its absolute app.py to Python. Do not infer ownership from app.py alone.
            int firstScript = 1;
            while (firstScript < args.Length && (args[firstScript] == "-u" || args[firstScript] == "-B")) firstScript++;
            if (firstScript >= args.Length) return false;
            string script = Existing(args[firstScript], false);
            if (script == null) return false;
            string pd = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            foreach (string name in new[] {"MinecraftServer", "MinecraftPlaygroundServer"})
            {
                string root = Path.Combine(pd, name);
                if (Accepted(root, roots) && Paths.Equals(script, Path.Combine(root, @"Manager\Web\app.py")) &&
                    Marker(root, "BootStart.ps1") && Marker(root, "launch_web.cmd")) return true;
            }
            return false;
        }

        public static List<string> Inspect(string[] roots, List<string> notes)
        {
            var result = new List<string>();
            var known = CatalogOf(notes);
            List<TcpRow> sockets;
            try { sockets = Table(); }
            catch (Exception) { sockets = new List<TcpRow>(); Note(notes, "TCP 소유 PID를 조회하지 못해 포트 기반 관찰이 일부 누락될 수 있습니다."); }
            var owner = new WindowsOwnership(roots);
            using (var search = new ManagementObjectSearcher("SELECT Name,ProcessId,ExecutablePath,CommandLine FROM Win32_Process WHERE Name='GeumyiServerHost.exe' OR Name='GeumyiServerCenter.exe' OR Name='java.exe' OR Name='javaw.exe' OR Name='cmd.exe' OR Name='powershell.exe' OR Name='pwsh.exe' OR Name='python.exe' OR Name='pythonw.exe'"))
            using (var rows = search.Get())
                foreach (ManagementObject p in rows) using (p)
                {
                    string name = p["Name"] as string ?? "";
                    int pid = Convert.ToInt32(p["ProcessId"], CultureInfo.InvariantCulture);
                    if (Paths.Equals(name, HostExe) || Paths.Equals(name, ClientExe))
                    {
                        string exe = Existing(p["ExecutablePath"] as string, false);
                        string where = exe != null && Accepted(Path.GetDirectoryName(exe), roots) ? "등록 폴더에서 실행" : "설치 경로 미확인";
                        result.Add(name + " · PID " + pid + " · " + where);
                        continue;
                    }
                    string raw = p["CommandLine"] as string;
                    if (Paths.Equals(name, "python.exe") || Paths.Equals(name, "pythonw.exe"))
                    {
                        if (LegacyWebProcess(WindowsOwnership.Args(raw), roots))
                            result.Add("구형 GMS Web Manager · PID " + pid + " · 등록된 app.py 인수 확인");
                        continue;
                    }
                    if (!(Paths.Equals(name, "java.exe") || Paths.Equals(name, "javaw.exe")))
                    {
                        if (owner.Command(raw) != null) result.Add(name + " · PID " + pid + " · 등록된 실행 대상 인수 확인");
                        continue;
                    }
                    string[] args = WindowsOwnership.Args(raw);
                    string jar = "";
                    for (int i = 1; i + 1 < args.Length; ++i) if (args[i] == "-jar") { jar = args[i + 1]; break; }
                    if (ProvenJar(jar, roots))
                    { result.Add("Java · PID " + pid + " · 등록 폴더의 JAR 실행 인수 확인"); continue; }
                    if (sockets.Any(t => t.State == 2 && t.Pid == pid && known.Ports.ContainsKey(t.Port) && Accepted(known.Ports[t.Port], roots)))
                    { result.Add("Java · PID " + pid + " · 등록 포트 사용 중, 소유권 미확인"); continue; }
                    if (!String.IsNullOrEmpty(jar) && !Path.IsPathRooted(jar) &&
                        Regex.IsMatch(jar, @"(?i)^(?:velocity|paper|purpur|spigot|minecraft_server|server|GeumyiStatusAgent)(?:[-.][a-z0-9._-]+)?\.jar$"))
                        result.Add("Java · PID " + pid + " · 상대 게임 JAR 경로, GMS 소유권 미확인");
                }
            result.Sort(StringComparer.Ordinal);
            return result;
        }

        static string HostPath(string exe, string[] roots)
        {
            string full = Existing(exe, false);
            if (full == null || !Paths.Equals(Path.GetFileName(full), HostExe)) return null;
            string dir = Path.GetDirectoryName(full);
            return Accepted(dir, roots) && Installs().Contains(dir, Paths) ? full : null;
        }
        static bool HostArguments(string[] args, string exe, bool service)
        {
            if (args.Length < 3 || !Paths.Equals(Existing(args[0], false), exe)) return false;
            int i = 1;
            bool isService = i < args.Length && args[i] == "--service";
            if (isService) i++;
            return (!service || isService) && args.Length == i + 2 && args[i] == "--config" &&
                Paths.Equals(Existing(args[i + 1], false), ConfigPath);
        }

        static void VerifyProcess(int pid, string[] roots)
        {
            using (var search = new ManagementObjectSearcher("SELECT ExecutablePath,CommandLine FROM Win32_Process WHERE ProcessId=" + pid.ToString(CultureInfo.InvariantCulture)))
            using (var rows = search.Get())
                foreach (ManagementObject row in rows) using (row)
                {
                    string exe = HostPath(row["ExecutablePath"] as string, roots);
                    if (exe != null && HostArguments(WindowsOwnership.Args(row["CommandLine"] as string), exe, false)) return;
                }
            throw new InvalidOperationException("리스너의 GSC Host 설치 경로와 --config 인수를 검증하지 못했습니다. GSC에서 정상 종료하세요.");
        }

        // Open a direct IPv4 socket. Identify the *connected* server endpoint before
        // sending HTTP headers. No proxy, redirects or connection pooling can redirect a token.
        static Dictionary<string,object> Request(int port, Action<int> verifyHost, string token, string method, string route, ref int hostPid)
        {
            using (var socket = new TcpClient(AddressFamily.InterNetwork))
            {
                socket.ReceiveTimeout = 6000; socket.SendTimeout = 5000;
                socket.Connect(IPAddress.Loopback, port);
                int localPort = ((IPEndPoint)socket.Client.LocalEndPoint).Port;
                int[] owners = new int[0];
                int callerPid;
                using (var self = Process.GetCurrentProcess()) callerPid = self.Id;
                Stopwatch wait = Stopwatch.StartNew();
                do
                {
                    var connected = Table().Where(t => t.Address.Equals(IPAddress.Loopback) && t.Peer.Equals(IPAddress.Loopback)).ToList();
                    // Require the exact reverse 4-tuple, our client PID and the peer PID.
                    // IP Helper can report a transient state on one side even while
                    // the socket is live. The connection itself binds both endpoints.
                    if (connected.Any(t => t.Pid == callerPid && t.Port == localPort && t.PeerPort == port) &&
                        !(socket.Client.Poll(0, SelectMode.SelectRead) && socket.Available == 0))
                        owners = connected.Where(t => t.Port == port && t.PeerPort == localPort && t.Pid > 0)
                            .Select(t => t.Pid).Distinct().ToArray();
                    if (owners.Length > 0) break;
                    Thread.Sleep(40);
                } while (wait.ElapsedMilliseconds < 1500);
                if (owners.Length != 1 || (hostPid != 0 && owners[0] != hostPid))
                    throw new IOException("연결된 서버 PID가 일치하지 않습니다. GSC에서 상태를 확인하세요.");
                verifyHost(owners[0]);
                hostPid = owners[0];
                using (NetworkStream stream = socket.GetStream())
                {
                    string bearer = token.Length == 0 ? "" : "Authorization: Bearer " + token + "\r\n";
                    string post = method == "POST" ? "Content-Type: application/json\r\nContent-Length: 2\r\n\r\n{}" : "\r\n";
                    byte[] request = Encoding.ASCII.GetBytes(method + " " + route + " HTTP/1.0\r\nHost: 127.0.0.1:" + port + "\r\nConnection: close\r\n" + bearer + post);
                    stream.Write(request, 0, request.Length);
                    using (var memory = new MemoryStream())
                    {
                        byte[] buffer = new byte[4096];
                        int n;
                        while ((n = stream.Read(buffer, 0, buffer.Length)) != 0)
                        {
                            if (memory.Length + n > 65536) throw new IOException("GSC 상태 응답이 허용 크기를 넘었습니다.");
                            memory.Write(buffer, 0, n);
                        }
                        string reply = Encoding.UTF8.GetString(memory.ToArray());
                        int separator = reply.IndexOf("\r\n\r\n", StringComparison.Ordinal);
                        var status = Regex.Match(reply, @"^HTTP/1\.[01] (\d{3}) ");
                        if (status.Success && status.Groups[1].Value == "409")
                            throw new InvalidOperationException("GSC가 409를 반환했습니다. 개인 서버·프록시 또는 진행 중인 설치를 GSC에서 확인하고 해당 인스턴스를 정상 종료하세요.");
                        if (separator < 0 || !status.Success || status.Groups[1].Value[0] != '2')
                            throw new IOException("GSC API 요청이 거절되었습니다. HTTP " + (status.Success ? status.Groups[1].Value : "상태 미확인"));
                        try { return Json(reply.Substring(separator + 4)); }
                        catch (Exception) { throw new IOException("GSC JSON 상태 응답을 해석할 수 없습니다."); }
                    }
                }
            }
        }

        // GSC writes machine-scoped DPAPI ciphertext using raw (unpadded) Base64.
        // Older installs can still contain a plaintext token. Do not write either form back.
        internal static string HostToken(string stored)
        {
            bool machine = stored.StartsWith("dpapi-m:", StringComparison.Ordinal);
            if (!machine && !stored.StartsWith("dpapi-u:", StringComparison.Ordinal)) return stored;
            byte[] plain = null;
            try
            {
                string raw = stored.Substring(8);
                if (raw.Length == 0 || raw.Length > 16384) throw new FormatException();
                byte[] encrypted = Convert.FromBase64String(raw.PadRight((raw.Length + 3) / 4 * 4, '='));
                plain = System.Security.Cryptography.ProtectedData.Unprotect(encrypted, null, machine ?
                    System.Security.Cryptography.DataProtectionScope.LocalMachine : System.Security.Cryptography.DataProtectionScope.CurrentUser);
                if (plain.Length == 0) throw new FormatException();
                return new UTF8Encoding(false,true).GetString(plain);
            }
            catch (Exception)
            {
                throw new InvalidOperationException("저장된 GSC Host 인증 정보를 현재 Windows 계정에서 확인할 수 없습니다. GSC에서 정상 종료하세요.");
            }
            finally { if (plain != null) Array.Clear(plain,0,plain.Length); }
        }

        public static void Shutdown(string[] roots, Action<string> progress)
        {
            if (!Accepted(DataDir, roots)) throw new InvalidOperationException("검증된 GSC 데이터 폴더가 필요합니다.");
            Dictionary<string,object> cfg;
            try { cfg = Json(ReadSmall(ConfigPath, 2097152)); }
            catch (Exception) { throw new IOException("server.json을 읽지 못했습니다. GSC에서 정상 종료하세요."); }
            int port = Number(cfg, "port");
            string token = HostToken(Value(cfg, "api_token"));
            if (port < 1 || port > 65535 || token.Length > 4096 || token.Any(c => c < 33 || c > 126))
                throw new InvalidOperationException("Host 포트 또는 인증 설정을 확인할 수 없습니다.");
            Uri health;
            string target = Value(Child(cfg, "agent"), "health_url");
            if (target.Length > 0 && (!Uri.TryCreate(target, UriKind.Absolute, out health) || !health.IsLoopback || health.Scheme != "http"))
                throw new InvalidOperationException("로컬 Agent 구성이 아닙니다. GSC에서 정상 종료하세요.");
            ShutdownHost(port, token, candidate => VerifyProcess(candidate, roots), progress);
            progress("GSC Host 종료를 확인했습니다. 별도 개인 인스턴스와 Velocity는 각 관리 화면 또는 원래 콘솔에서 정상 종료하세요.");
            var notes = new List<string>();
            foreach (string row in Inspect(roots, notes)) progress("종료 후 관찰 · " + row);
            foreach (string note in notes) progress(note);
        }

        // The public entry point binds verifyHost to the installed binary and exact config.
        // The protocol test binds it to the PID of its own disposable loopback child.
        internal static void ShutdownHost(int port, string token, Action<int> verifyHost, Action<string> progress)
        {
            int pid = 0;
            Request(port, verifyHost, token, "POST", "/api/shutdown", ref pid);
            using (var host = Process.GetProcessById(pid))
            {
                // Hold the same process handle during every poll and the final exit.
                IntPtr handle = host.Handle;
                progress("GSC가 백엔드 저장과 Agent 종료를 진행 중입니다.");
                Stopwatch timer = Stopwatch.StartNew();
                while (true)
                {
                    Thread.Sleep(800);
                    string phase = Value(Request(port, verifyHost, token, "GET", "/api/shutdown/status", ref pid), "phase");
                    if (phase == "ready") break;
                    if (phase == "failed") throw new InvalidOperationException("GSC 정상 종료 실패. GSC 서버 로그와 현재 실행 상태를 확인하세요.");
                    if (phase != "stopping" || timer.Elapsed > TimeSpan.FromMinutes(5))
                        throw new InvalidOperationException("GSC 종료 완료를 확인할 수 없습니다. GSC에서 현재 상태를 확인하세요.");
                }
                Request(port, verifyHost, token, "POST", "/api/shutdown/finish", ref pid);
                if (!host.WaitForExit(20000)) throw new InvalidOperationException("Host 프로세스 종료 대기 시간이 지났습니다.");
            }
        }

        public static void StartHost(string[] roots)
        {
            bool valid = false;
            using (var search = new ManagementObjectSearcher("SELECT PathName FROM Win32_Service WHERE Name='Geumyi Server Center Host'"))
            using (var rows = search.Get())
                foreach (ManagementObject service in rows) using (service)
                {
                    string[] args = WindowsOwnership.Args(service["PathName"] as string);
                    string exe = args.Length == 0 ? null : HostPath(args[0], roots);
                    valid = exe != null && Accepted(DataDir, roots) && HostArguments(args, exe, true);
                }
            if (!valid) throw new InvalidOperationException("공식 GSC 서비스 실행 파일과 server.json 경로를 확인하지 못했습니다.");
            using (var service = new ServiceController(HostService))
            {
                if (service.Status != ServiceControllerStatus.Running)
                {
                    if (service.Status != ServiceControllerStatus.StartPending) service.Start();
                    service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
                }
            }
        }
    }
}
