using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace GmsMode
{
    // A filename, display name or string in an argument is never proof on its own.
    internal sealed class WindowsOwnership
    {
        readonly HashSet<string> roots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        static readonly StringComparer CI = StringComparer.OrdinalIgnoreCase;
        readonly string programData;
        internal WindowsOwnership(IEnumerable<string> input) : this(input,Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData)) { }
        internal WindowsOwnership(IEnumerable<string> input,string dataDir)
        {
            programData=dataDir;
            foreach (string item in input ?? new string[0])
            {
                string path = Local(item, null);
                if (path == null || !Directory.Exists(path) || Shared(path) || !LocalAssetPath.Available(path)) continue;
                roots.Add(path);
            }
        }

        internal static string Local(string value, string directory)
        {
            if (String.IsNullOrWhiteSpace(value)) return null;
            string s = value.Trim().Replace('/', '\\');
            if (s.Contains("%") || s.Contains("\"") || s.StartsWith(@"\\") || s.IndexOfAny(new[]{'\0','\r','\n','*','?'}) >= 0) return null;
            if (!Regex.IsMatch(s, @"^[A-Za-z]:\\"))
            {
                if (directory == null || s.StartsWith(@"\") || s.Contains(":")) return null;
                s = Path.Combine(directory, s);
            }
            if (s.Substring(2).Contains(":") || s.Split('\\').Any(x => x == ".." || x.EndsWith(".") || x.EndsWith(" "))) return null;
            try { return Path.GetFullPath(s).TrimEnd('\\'); } catch (Exception) { return null; }
        }

        internal static bool PlainPath(string path)
        {
            try
            {
                for (string cur = path; cur != null; cur = Path.GetDirectoryName(cur))
                    if ((File.GetAttributes(cur) & FileAttributes.ReparsePoint) != 0) return false;
                return true;
            }
            catch (Exception) { return false; }
        }

        static bool Shared(string p)
        {
            if (p.Length <= 3 || p.IndexOf('\\', 3) < 0 && Path.GetFileName(p).Equals("Users", StringComparison.OrdinalIgnoreCase)) return true;
            var shared = new[]{Environment.SpecialFolder.Windows, Environment.SpecialFolder.ProgramFiles,
                Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.CommonApplicationData,
                Environment.SpecialFolder.UserProfile, Environment.SpecialFolder.DesktopDirectory, Environment.SpecialFolder.MyDocuments,
                Environment.SpecialFolder.ApplicationData, Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolder.System,
                Environment.SpecialFolder.Startup, Environment.SpecialFolder.CommonStartup};
            return shared.Any(x => CI.Equals(Environment.GetFolderPath(x), p)) ||
                CI.Equals(p, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")) ||
                CI.Equals(p, Path.GetTempPath().TrimEnd('\\'));
        }

        internal static bool Hint(string value)
        {
            return Regex.IsMatch(value ?? "", @"Geumyi|Minecraft|\bGSCM?\b|Velocity|StatusAgent|MC (?:Playground |Server |Web )", RegexOptions.IgnoreCase);
        }
        internal static bool IndirectProgram(string value)
        {
            if (String.IsNullOrWhiteSpace(value)) return false;
            // A generic launcher may hide the GMS path inside a private script.
            // Report it without inspecting its payload or changing the registration.
            string name=Path.GetFileName(value.Trim().Trim('"'));
            return Regex.IsMatch(name,@"^(?:cmd|powershell|pwsh|wscript|cscript|javaw?|pythonw?|node|nssm|winsw)(?:\.exe)?$|\.(?:bat|cmd|ps1|vbs|js|py|jar)$",
                RegexOptions.IgnoreCase);
        }
        internal static bool IndirectCommand(string raw)
        {
            var args=Args(raw); return args.Length!=0 && IndirectProgram(args[0]);
        }

        internal static string[] Args(string raw)
        {
            if (String.IsNullOrWhiteSpace(raw)) return new string[0];
            if (raw.IndexOfAny(new[]{'\0','\r','\n'}) >= 0) return new string[0];
            int count;
            IntPtr p = CommandLineToArgvW(raw.TrimStart(), out count);
            if (p == IntPtr.Zero) return new string[0];
            try
            {
                var result = new string[count];
                for (int i = 0; i < count; ++i) result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(p, i * IntPtr.Size));
                return result;
            }
            finally { LocalFree(p); }
        }
        [DllImport("shell32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CommandLineToArgvW(string raw, out int count);
        [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);

        internal string Command(string raw)
        {
            string[] a = Args(raw);
            return a.Length == 0 ? null : Target(a[0], a.Skip(1).ToArray(), null);
        }

        bool Approved(string directory)
        {
            if (roots.Contains(directory)) return true;
            foreach (string r in roots)
            {
                if (!CI.Equals(Path.GetFileName(r), "GeumyiServerCenter")) continue;
                foreach (string suffix in new[]{@"Network\Velocity",@"Network\FourServer\wild",@"Network\FourServer\playground",@"Network\FourServer\other",@"Runtime\Agent"})
                    if (CI.Equals(directory, Path.Combine(r, suffix))) return true;
            }
            return false;
        }

        string Asset(string file, string wd, bool launcher)
        {
            string p = Local(file, wd);
            if (p == null || !File.Exists(p) || !LocalAssetPath.Available(p)) return null;
            string dir = Path.GetDirectoryName(p), n = Path.GetFileName(p);
            if (!Approved(dir)) return null;
            bool proxy = File.Exists(Path.Combine(dir,"velocity.toml")) && LocalAssetPath.Available(Path.Combine(dir,"velocity.toml"));
            bool server = File.Exists(Path.Combine(dir,"server.properties")) && LocalAssetPath.Available(Path.Combine(dir,"server.properties"));
            if (launcher)
            {
                if ((server || proxy) && Regex.IsMatch(n, @"^(?:start|run|server)\.(?:bat|cmd)$", RegexOptions.IgnoreCase) &&
                    SimpleServerLauncher(p)) return p;
            }
            else if ((proxy && CI.Equals(n, "velocity.jar")) ||
                     (server && Regex.IsMatch(n, @"^(?:server|paper|purpur|spigot|fabric-server-launch|forge|neoforge)(?:[-._][\w.+-]+)?\.jar$", RegexOptions.IgnoreCase)) ||
                     Regex.IsMatch(n, @"^GeumyiStatusAgent(?:-[0-9]+(?:\.[0-9]+)*)?\.jar$", RegexOptions.IgnoreCase)) return p;
            return null;
        }

        static bool JarArgs(string[] args,out string jar)
        {
            jar=null;
            int j=Array.IndexOf(args,"-jar");
            if (j<0 || j+1>=args.Length || args.Take(j).Any(x=>!Regex.IsMatch(x,@"^-Xm[sx]\d+[kKmMgG]?$")) ||
                args.Skip(j+2).Any(x=>!CI.Equals(x,"nogui") && !CI.Equals(x,"--nogui"))) return false;
            jar=args[j+1]; return true;
        }
        static bool JavaExecutable(string path)
        {
            if (path==null || !File.Exists(path) || !PlainPath(path)) return false;
            var v=FileVersionInfo.GetVersionInfo(path);
            return Regex.IsMatch(v.FileDescription ?? "",@"Java|OpenJDK",RegexOptions.IgnoreCase) &&
                Regex.IsMatch(v.OriginalFilename ?? "",@"^(javaw?|shimconsole|shimwindow)\.exe$",RegexOptions.IgnoreCase);
        }
        bool SimpleServerLauncher(string file)
        {
            if (new FileInfo(file).Length>65536) return false;
            string dir=Path.GetDirectoryName(file);
            bool launched=false, directorySet=false;
            foreach (string source in File.ReadAllLines(file))
            {
                string s=source.Trim();
                if (s.Length==0 || CI.Equals(s,"@echo off") || CI.Equals(s,"setlocal") || CI.Equals(s,"endlocal")) continue;
                if (CI.Equals(s,"cd /d \"%~dp0\"")) { directorySet=true; continue; }
                if (s.IndexOfAny("&|<>^!()".ToCharArray())>=0 || launched) return false;
                string[] cmd=Args(s);
                if (cmd.Length==0 || !(CI.Equals(cmd[0],"java") || CI.Equals(cmd[0],"java.exe") || JavaExecutable(Local(cmd[0],null)))) return false;
                string jar;
                if (!JarArgs(cmd.Skip(1).ToArray(),out jar)) return false;
                if (jar.StartsWith("%~dp0",StringComparison.OrdinalIgnoreCase)) jar=dir+"\\"+jar.Substring(5);
                if (Asset(jar,directorySet?dir:null,false)==null) return false;
                launched=true;
            }
            return launched;
        }

        // Legacy launchers had generic names and, in two cases, embed PowerShell
        // -Command. Only the actual files reviewed on the operator PC are recognized.
        // Custom or edited scripts remain visible as manual-review items.
        static readonly Dictionary<string,string> LegacyHashes=new Dictionary<string,string>(CI)
        {
            {@"MinecraftServer\BootStart.ps1","377101C5DE86B18C017F4BFFAE383ACA2D0ECC5FE6704BF140B7D81B10494F37"},
            {@"MinecraftServer\StartServer.ps1","6ED19D34F9FB44EFBFD9AC6DB919C18DC4D2E4A09F77F3A70E5EEF819FCCF4BD"},
            {@"MinecraftServer\launch_console.cmd","0081280E9FAD508A80BDF976C70B8697B61B953DC2C6B1C2FDE947DBE2370AA5"},
            {@"MinecraftServer\launch_server.cmd","BCC872DD131B8F82D2477E92955A987526336C28C7FEC0451A854206A00965B0"},
            {@"MinecraftServer\launch_web.cmd","348EE501607B0EFD7804E9E049CB01B0CE79DEBE61C832392AC220C42B5973FC"},
            {@"MinecraftPlaygroundServer\BootStart.ps1","5BD71A085D65ABF54A6740081AC7C4F30C231FDA6D9D7D07D13B282D9FD5E3D3"},
            {@"MinecraftPlaygroundServer\launch_console.cmd","BC38B99B40CF4EF40D6AFDAEA20B774E0869EFD4625AF414B6DC141A955BDDB6"},
            {@"MinecraftPlaygroundServer\launch_server.cmd","D0B741734B44B62E9D8ED96C288F7E01B763B1DEDCBC6A59E3474519D3ECA357"},
            {@"MinecraftPlaygroundServer\launch_web.cmd","F6586A4EC59CF5452145FD9FF17EE3E925ACD68D7337B3AAD14FBBB04F4E1752"}
        };
        string Legacy(string path)
        {
            string p=Local(path,null);
            if (p==null) return null;
            string dir=Path.GetDirectoryName(p), expected;
            if (!roots.Contains(dir) || !CI.Equals(Path.GetDirectoryName(dir),programData) ||
                !LegacyHashes.TryGetValue(Path.GetFileName(dir)+"\\"+Path.GetFileName(p),out expected) ||
                !PlainPath(p) || !PlainPath(Path.Combine(dir,"server_path.txt")) ||
                !Directory.Exists(Path.Combine(dir,"Manager")) || !PlainPath(Path.Combine(dir,"Manager")) ||
                new FileInfo(p).Length>65536) return null;
            return WindowsEntries.FileHash(p)==expected?p:null;
        }
        static bool LegacyPowerShellArgs(string[] args)
        {
            if (args.Length<2 || !CI.Equals(args[args.Length-2],"-File") || !CI.Equals(Path.GetExtension(args[args.Length-1]),".ps1")) return false;
            for (int i=0;i<args.Length-2;i++)
            {
                if (CI.Equals(args[i],"-NoLogo") || CI.Equals(args[i],"-NoProfile") || CI.Equals(args[i],"-NonInteractive")) continue;
                if (++i>=args.Length-2) return false;
                if (CI.Equals(args[i-1],"-ExecutionPolicy") && CI.Equals(args[i],"Bypass")) continue;
                if (CI.Equals(args[i-1],"-WindowStyle") && CI.Equals(args[i],"Hidden")) continue;
                return false;
            }
            return true;
        }

        internal string Target(string program, string[] args, string wd)
        {
            if (String.IsNullOrWhiteSpace(program)) return null;
            wd = Local(wd, null);
            string exe = Local(program, null);
            string n = Path.GetFileName(program);
            if (CI.Equals(n, "GeumyiServerHost.exe") || CI.Equals(n, "GeumyiServerCenter.exe") || CI.Equals(n, "GeumyiStatusAgent.exe"))
                return exe != null && Approved(Path.GetDirectoryName(exe)) && File.Exists(exe) && LocalAssetPath.Available(exe) ? exe : null;
            if (CI.Equals(n, "cmd.exe"))
            {
                if (!(CI.Equals(program,"cmd.exe") || CI.Equals(exe, Path.Combine(Environment.SystemDirectory,"cmd.exe")))) return null;
                int i=args.Length==3 && CI.Equals(args[0],"/d")?1:0;
                if (args.Length != i+2 || !CI.Equals(args[i],"/c") || args[i+1].IndexOfAny("&|<>^%!()".ToCharArray()) >= 0) return null;
                string launcher=args[i+1];
                return (CI.Equals(Path.GetExtension(launcher),".cmd")?Legacy(launcher):null) ?? Asset(launcher, null, true);
            }
            if (CI.Equals(n,"powershell.exe"))
            {
                string systemPs=Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe");
                if (CI.Equals(exe,systemPs) && LegacyPowerShellArgs(args)) return Legacy(args[args.Length-1]);
                return null;
            }
            if (CI.Equals(n, "java.exe") || CI.Equals(n, "javaw.exe"))
            {
                string jar;
                return JavaExecutable(exe) && JarArgs(args,out jar)?Asset(jar,wd,false):null;
            }
            if (args.Length == 0) return (CI.Equals(Path.GetExtension(program),".cmd")?Legacy(program):null) ?? Asset(program,null,true);
            return null;
        }

        internal string StartupFile(string file)
        {
            if (!PlainPath(file)) return null;
            if (CI.Equals(Path.GetExtension(file), ".lnk"))
            {
                dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell", true));
                try
                {
                    dynamic link = shell.CreateShortcut(file);
                    try
                    {
                        string target = (string)link.TargetPath;
                        string[] args = Args("x " + (string)link.Arguments).Skip(1).ToArray();
                        return Target(target,args,(string)link.WorkingDirectory);
                    }
                    finally { Marshal.ReleaseComObject(link); }
                }
                finally { Marshal.ReleaseComObject(shell); }
            }
            string name = Path.GetFileName(file);
            // A directly copied product EXE is eligible only if an approved original is byte-identical.
            if (!CI.Equals(name,"GeumyiServerHost.exe") && !CI.Equals(name,"GeumyiServerCenter.exe") && !CI.Equals(name,"GeumyiStatusAgent.exe")) return null;
            foreach (string r in roots)
            {
                string candidate = Path.Combine(r,name);
                if (File.Exists(candidate) && PlainPath(candidate) && WindowsEntries.FileHash(candidate) == WindowsEntries.FileHash(file)) return candidate;
            }
            return null;
        }
    }
}
