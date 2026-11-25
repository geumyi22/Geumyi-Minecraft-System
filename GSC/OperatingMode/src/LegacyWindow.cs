using System;
using System.Collections.Generic;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace GmsMode
{
    public static class LegacyWindow
    {
        const string LegacyTitle = "GMS 운영 모드 관리자 2.0.0";
        const string LegacyHash = "CF330677FDC1F477151217FF6B3B13B8D98F394E02F35FC3086D6C3FBD184FB7";
        const uint QueryLimited = 0x1000;
        const uint Synchronize = 0x100000;
        const uint StillRunning = 258; // WAIT_TIMEOUT from a zero-timeout process wait
        const int ShowNormal = 1;

        public static bool Found() { return Locate(false); }
        public static bool Reveal() { return Locate(true); }

        static bool Locate(bool show)
        {
            try
            {
                var candidates = new List<IntPtr>();
                EnumWindows(delegate(IntPtr window, IntPtr unused)
                {
                    if (MatchesTitle(window)) candidates.Add(window);
                    return true;
                }, IntPtr.Zero);
                foreach (IntPtr window in candidates)
                    if (CheckProcess(window, show)) return true;
            }
            catch (Exception) { /* Access to elevated processes or WMI can be unavailable. */ }
            return false;
        }

        static bool MatchesTitle(IntPtr window)
        {
            var title = new StringBuilder(256);
            if (GetWindowText(window, title, title.Capacity) != LegacyTitle.Length || title.ToString() != LegacyTitle) return false;
            var className = new StringBuilder(128);
            return GetClassName(window, className, className.Capacity) > 0 &&
                className.ToString().StartsWith("WindowsForms10.Window.", StringComparison.Ordinal);
        }

        static bool CheckProcess(IntPtr window, bool show)
        {
            uint childId;
            if (GetWindowThreadProcessId(window, out childId) == 0) return false;
            using (SafeProcessHandle child = OpenProcess(QueryLimited | Synchronize, false, childId))
            {
                if (child.IsInvalid || WaitForSingleObject(child, 0) != StillRunning) return false;
                string expected = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
                if (!String.Equals(ImagePath(child), expected, StringComparison.OrdinalIgnoreCase)) return false;

                uint parentId = ReadParent(childId);
                if (parentId == 0) return false;
                using (SafeProcessHandle parent = OpenProcess(QueryLimited | Synchronize, false, parentId))
                {
                    if (parent.IsInvalid || WaitForSingleObject(parent, 0) != StillRunning) return false;
                    string path = ImagePath(parent);
                    if (String.IsNullOrEmpty(path) || path.Length < 3 || path[1] != ':' || path[2] != '\\' ||
                        new DriveInfo(Path.GetPathRoot(path)).DriveType == DriveType.Network || !IsKnownBinary(path)) return false;
                    long parentCreated, childCreated, exit, kernel, user;
                    if (!GetProcessTimes(parent, out parentCreated, out exit, out kernel, out user) ||
                        !GetProcessTimes(child, out childCreated, out exit, out kernel, out user) || parentCreated > childCreated) return false;
                    uint currentId;
                    if (!MatchesTitle(window) || GetWindowThreadProcessId(window, out currentId) == 0 || currentId != childId ||
                        WaitForSingleObject(parent, 0) != StillRunning || WaitForSingleObject(child, 0) != StillRunning) return false;
                    return !show || ShowWindowAsync(window, ShowNormal);
                }
            }
        }

        static uint ReadParent(uint childId)
        {
            // A standard account may read the parent PID while WMI masks ExecutablePath on an elevated process.
            // Query the actual image name from the open process handle in both modes.
            string sql = "SELECT ParentProcessId FROM Win32_Process WHERE Name='powershell.exe' AND ProcessId=" +
                childId.ToString(System.Globalization.CultureInfo.InvariantCulture);
            using (var search = new ManagementObjectSearcher(sql))
            using (var rows = search.Get())
                foreach (ManagementObject row in rows)
                    using (row) return Convert.ToUInt32(row["ParentProcessId"]);
            return 0;
        }

        static string ImagePath(SafeProcessHandle process)
        {
            var path = new StringBuilder(32768);
            uint length = (uint)path.Capacity;
            return QueryFullProcessImageName(process, 0, path, ref length) ? path.ToString() : null;
        }

        static bool IsKnownBinary(string path)
        {
            using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                if (file.Length != 1860608) return false;
                using (var sha = SHA256.Create())
                    return BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "") == LegacyHash;
            }
        }

        delegate bool WindowCallback(IntPtr window, IntPtr unused);
        [DllImport("user32.dll")] static extern bool EnumWindows(WindowCallback callback, IntPtr unused);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int length);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder text, int length);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
        [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window, int command);
        [DllImport("kernel32.dll")] static extern SafeProcessHandle OpenProcess(uint desired, bool inherit, uint processId);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(SafeProcessHandle process, uint flags, StringBuilder name, ref uint length);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(SafeProcessHandle process,uint timeout);
        [DllImport("kernel32.dll")] static extern bool GetProcessTimes(SafeProcessHandle process, out long created, out long exit, out long kernel, out long user);
    }
}
