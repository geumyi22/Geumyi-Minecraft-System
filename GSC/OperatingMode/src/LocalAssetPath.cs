using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace GmsMode
{
    // Read-only asset discovery. Recovery storage and files moved out of Startup use stricter checks.
    internal static class LocalAssetPath
    {
        const uint Unavailable = 0x1000 | 0x40000 | 0x400000; // offline / recall on open / on data access
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct FindData
        {
            internal uint Attributes;
            internal System.Runtime.InteropServices.ComTypes.FILETIME Created, Accessed, Written;
            internal uint SizeHigh, SizeLow, Tag, Reserved;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] internal string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=14)] internal string ShortName;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr FindFirstFile(string path, out FindData data);
        [DllImport("kernel32.dll")] static extern bool FindClose(IntPtr handle);

        internal static bool Accept(uint flags, uint tag)
        {
            return (flags & Unavailable) == 0 && ((flags & 0x400) == 0 || (tag & 0xFFFF0FFFu) == 0x9000001Au);
        }
        internal static bool Available(string path)
        {
            if (String.IsNullOrWhiteSpace(path) || !Regex.IsMatch(path,@"^[A-Za-z]:[\\/]") ||
                path.IndexOf(':',2) >= 0 || path.IndexOfAny(new[]{'*','?','\0'}) >= 0) return false;
            try
            {
                string full = Path.GetFullPath(path);
                if (new DriveInfo(Path.GetPathRoot(full)).DriveType != DriveType.Fixed) return false;
                for (string part = full; part != null && part.Length > 3; part = Path.GetDirectoryName(part))
                {
                    // Fetch tag and availability from directory metadata without reading file contents.
                    FindData data;
                    IntPtr handle = FindFirstFile(part,out data);
                    if (handle == new IntPtr(-1)) return false;
                    try { if (!Accept(data.Attributes,data.Tag)) return false; }
                    finally { FindClose(handle); }
                }
                return true;
            }
            catch (Exception) { return false; }
        }
    }
}
