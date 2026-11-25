using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("GMS Operating Mode")]
[assembly: AssemblyProduct("GMS Operating Mode")]
[assembly: AssemblyDescription("GMS 수동 운영 전환 및 복원")]
[assembly: AssemblyVersion("3.0.1.0")]
[assembly: AssemblyFileVersion("3.0.1.0")]
[assembly: ComVisible(false)]

namespace GmsMode
{
    internal static class Log
    {
        static readonly object Gate = new object();
        public static string Location = "";
        public static void Message(string message)
        {
            lock (Gate)
            {
                try
                {
                    if (Location == "")
                    {
                        string folder;
                        if (Disk.Admin())
                        {
                            var disk = new Disk(Disk.Production, true);
                            disk.Prepare(); folder = disk.Folder;
                        }
                        else
                        {
                            folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                "GMS Operating Mode", "Logs");
                            Directory.CreateDirectory(folder);
                        }
                        string path = Path.Combine(folder, "session-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") +
                            "-" + Guid.NewGuid().ToString("N") + ".log");
                        using (File.Open(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read)) { }
                        Location = path;
                    }
                    File.AppendAllText(Location, DateTime.Now.ToString("O") + "  " + message + Environment.NewLine, Encoding.UTF8);
                }
                catch { /* Error dialogs remain available if the log location cannot be written. */ }
            }
        }
        public static void Failure(string stage, Exception ex)
        {
            Message(stage + " | " + ex.GetType().Name + " | " + ex.Message + Environment.NewLine + ex.StackTrace);
            MessageBox.Show(stage + Environment.NewLine + ex.Message + Environment.NewLine + Environment.NewLine +
                (Location == "" ? "로그를 저장할 수 없습니다." : "진단 로그  " + Location), "GMS Operating Mode 3.0.1",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
    internal static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            try
            {
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException += delegate(object s, ThreadExceptionEventArgs e) { Log.Failure("화면 처리 오류", e.Exception); };
                AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e)
                { Log.Failure("프로그램 오류", e.ExceptionObject as Exception ?? new Exception("알 수 없는 예외")); };
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                bool elevated = Disk.Admin();
                string review = StartupReview(args, Disk.Sid(), elevated);
                string name = elevated ? @"Global\Geumyi.GMS.OperatingMode.3.Admin" :
                    @"Local\Geumyi.GMS.OperatingMode.3." + Disk.Sid();
                bool primary;
                using (var mutex = new Mutex(true, name, out primary))
                {
                    if (!primary)
                    {
                        MessageBox.Show("이미 실행 중인 운영 모드 관리자 창을 사용해 주세요.", "GMS Operating Mode 3.0.1");
                        return 2;
                    }
                    try
                    {
                        Log.Message("시작 / 3.0.1 / x64 / 관리자 " + elevated);
                        Application.Run(new Dashboard(elevated, review));
                    }
                    finally { mutex.ReleaseMutex(); }
                }
                return 0;
            }
            catch (Exception ex) { Log.Failure("시작 실패", ex); return 1; }
        }
        // A launch argument may select a confirmation screen. There is no apply command.
        internal static string StartupReview(string[] args, string sid, bool elevated)
        {
            int offset = 0;
            if (args.Length > 0 && args[0] == "--elevated-for")
            {
                if (args.Length < 2 || args[1] != sid || !elevated)
                    throw new InvalidOperationException("처음 실행한 Windows 계정으로 관리자 권한을 승인해 주세요.");
                offset = 2;
            }
            if (args.Length == offset) return "";
            if (args.Length == offset + 1 && (args[offset] == "--review-manual" || args[offset] == "--review-restore"))
                return args[offset];
            throw new InvalidOperationException("지원하지 않는 시작 옵션입니다. EXE에서 직접 열어 주세요.");
        }
        public static bool Elevate(string review = "")
        {
            return RequestElevation(Application.ExecutablePath, Disk.Sid(), delegate(ProcessStartInfo info) {
                using (Process child = Process.Start(info)) { }
            }, review);
        }
        internal static bool RequestElevation(string executable, string sid, Action<ProcessStartInfo> launch, string review = "")
        {
            try
            {
                string args = "--elevated-for " + sid;
                if (review != "") args += " " + StartupReview(new[]{review},sid,false);
                var info = new ProcessStartInfo(executable, args);
                info.UseShellExecute = true; info.Verb = "runas";
                launch(info);
                return true;
            }
            catch (Win32Exception ex)
            {
                if (ex.NativeErrorCode != 1223) throw;
                Log.Message("사용자가 권한 요청을 취소했습니다.");
                return false;
            }
        }
    }
}
