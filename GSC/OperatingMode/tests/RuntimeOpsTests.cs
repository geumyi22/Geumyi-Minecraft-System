using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;

namespace GmsMode
{
    // The fixture never registers a service or reads the real Host token.
    // Every network connection uses a random port reported by this test's own child.
    internal static class RuntimeOpsTests
    {
        const string FakeToken = "fixture-only-demo";
        static void Require(bool ok, string reason) { if (!ok) throw new Exception(reason); }

        static int Serve(string mode)
        {
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            try
            {
                Console.WriteLine(((IPEndPoint)listener.LocalEndpoint).Port);
                string[] routes = {"POST /api/shutdown", "GET /api/shutdown/status", "GET /api/shutdown/status", "POST /api/shutdown/finish"};
                for (int i = 0; i < routes.Length; i++)
                using (var client = listener.AcceptTcpClient())
                using (var stream = client.GetStream())
                {
                    client.ReceiveTimeout = 10000;
                    if (mode == "foreign")
                    {
                        int ch = stream.ReadByte();
                        if (ch == 'P') ch = stream.ReadByte();
                        Require(ch == -1, "foreign listener received an HTTP request or credential"); return 0;
                    }
                    var input = new StreamReader(stream, Encoding.ASCII, false, 1024, true);
                    Require(input.ReadLine() == routes[i] + " HTTP/1.0", "unexpected sequence");
                    bool auth = false;
                    string line;
                    while (!String.IsNullOrEmpty(line = input.ReadLine()))
                        if (line == "Authorization: Bearer " + FakeToken) auth = true;
                    Require(auth, "missing fixture bearer");
                    if (routes[i].StartsWith("POST")) Require(input.Read() == '{' && input.Read() == '}', "missing JSON body");
                    string status = mode == "redirect" ? "302 Found" : mode == "conflict" ? "409 Conflict" : "200 OK";
                    string body = i == 1 && mode == "failure" ? "{\"phase\":\"failed\"}" :
                        i == 2 ? "{\"phase\":\"ready\"}" : i == 3 ? "{\"ok\":true}" : "{\"phase\":\"stopping\"}";
                    string reply = "HTTP/1.0 " + status + "\r\nContent-Type: application/json\r\n" +
                        (mode == "redirect" ? "Location: http://127.0.0.1:1/not-followed\r\n" : "") +
                        "Content-Length: " + body.Length + "\r\n\r\n" + body;
                    byte[] bytes = Encoding.ASCII.GetBytes(reply);
                    stream.Write(bytes, 0, bytes.Length);
                    if (mode == "redirect" || mode == "conflict" || (mode == "failure" && i == 1)) return 0;
                }
                return 0;
            }
            finally { listener.Stop(); }
        }

        static void Run(string mode)
        {
            var info = new ProcessStartInfo(Assembly.GetExecutingAssembly().Location, "serve " + mode) {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true };
            using (var child = Process.Start(info))
            {
                try
                {
                    int port = Int32.Parse(child.StandardOutput.ReadLine());
                    int proofs = 0;
                    Action<int> verify = delegate(int pid) {
                        Require(pid == child.Id, "wrong TCP owner");
                        proofs++;
                        if (mode == "foreign")
                            typeof(RuntimeOps).GetMethod("VerifyProcess", BindingFlags.NonPublic | BindingFlags.Static)
                                .Invoke(null, new object[] {pid, new string[0]});
                    };
                    Exception problem = null;
                    try { RuntimeOps.ShutdownHost(port, FakeToken, verify, delegate { }); }
                    catch (Exception ex) { problem = ex.GetBaseException(); }
                    if (mode == "success") Require(problem == null && proofs == 4, "graceful success " + problem);
                    else
                    {
                        Require(problem != null, "unexpected success");
                        string expected = mode == "foreign" ? "리스너" : mode == "redirect" ? "302" : mode == "conflict" ? "409" : "실패";
                        Require(problem.Message.Contains(expected), "wrong failure stage: " + problem.Message);
                        Require(!problem.ToString().Contains(FakeToken), "credential in error");
                    }
                    Require(child.WaitForExit(5000) && child.ExitCode == 0, "invalid fixture behavior");
                    Console.WriteLine("PASS runtime loopback " + mode + " (OS peer PID checked " + proofs + " times)");
                }
                finally
                {
                    // Cleanup targets only the disposable fixture process we started.
                    if (!child.HasExited) { child.Kill(); child.WaitForExit(); }
                }
            }
        }

        public static int Main(string[] args)
        {
            try
            {
                if (args.Length == 2 && args[0] == "serve") return Serve(args[1]);
                foreach (bool machine in new[]{true,false})
                {
                    var scope = machine ? System.Security.Cryptography.DataProtectionScope.LocalMachine : System.Security.Cryptography.DataProtectionScope.CurrentUser;
                    byte[] encrypted = System.Security.Cryptography.ProtectedData.Protect(Encoding.UTF8.GetBytes(FakeToken),null,scope);
                    Require(RuntimeOps.HostToken((machine?"dpapi-m:":"dpapi-u:")+Convert.ToBase64String(encrypted).TrimEnd('='))==FakeToken,"synthetic GSC DPAPI token");
                }
                Require(RuntimeOps.HostToken(FakeToken)==FakeToken, "legacy Host token");
                bool refused=false;
                try { RuntimeOps.HostToken("dpapi-m:invalid"); } catch (InvalidOperationException) { refused=true; }
                Require(refused, "unreadable protected credential must stop before any request");
                Console.WriteLine("PASS GSC DPAPI user/machine, legacy and invalid token");
                foreach (string m in new[]{"success","foreign","redirect","conflict","failure"}) Run(m);
                var notes = new List<string>();
                string[] roots = RuntimeOps.Discover(notes);
                Require(roots.SequenceEqual(roots.OrderBy(p => p, StringComparer.OrdinalIgnoreCase)), "non-deterministic ordering");
                var processes = RuntimeOps.Inspect(roots, notes);
                Console.WriteLine("PASS read-only inventory (roots=" + roots.Length + ", observations=" + processes.Count + ", notes=" + notes.Count + ")");
                return 0;
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
        }
    }
}
