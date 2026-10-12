# Windows native directory access query for Day12.
# Opening an EXISTING directory with FILE_ADD_FILE or FILE_ADD_SUBDIRECTORY
# checks the caller's actual token against the DACL without creating a child.
# Used on DISPOSABLE CI fixtures and by opt-in READ-ONLY real host probe.
# Do NOT substitute this test for a real standard-user account/token.
Set-StrictMode -Version Latest

if (-not ('GeumyiDay12DirectoryOpenCheck' -as [type])) {
    $nativeSignature = @'
using System;
using System.Runtime.InteropServices;
public static class GeumyiDay12DirectoryOpenCheck {
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", ExactSpelling = true,
      CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateFile(
      string path, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
      uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
    Add-Type -TypeDefinition $nativeSignature -Language CSharp -ErrorAction Stop
}

function Invoke-Day12DirectoryAccessCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Directory,
        [Parameter(Mandatory=$true)]
        [ValidateSet('CreateFiles','CreateDirectories')][string]$Right
    )

    # FILE_ADD_FILE = 0x2; FILE_ADD_SUBDIRECTORY = 0x4. Neither API call
    # creates anything; OPEN_EXISTING is mandatory. Opening a handle is
    # a live NTFS access check with the *current* caller's security token.
    $desired = if ($Right -eq 'CreateFiles') { [uint32]0x2 } else { [uint32]0x4 }
    $shareMode = [uint32]0x7 # FILE_SHARE_READ | WRITE | DELETE
    $openExisting = [uint32]0x3
    $directorySemantics = [uint32]0x02000000 # FILE_FLAG_BACKUP_SEMANTICS
    $handle = [GeumyiDay12DirectoryOpenCheck]::CreateFile(
        $Directory, $desired, $shareMode, [IntPtr]::Zero, $openExisting,
        $directorySemantics, [IntPtr]::Zero)
    if ($handle -eq [IntPtr]::new(-1)) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($errorCode -eq 5) { return 'DENIED' }
        # Any unexpected I/O/share/permission error is not a proof of denial.
        return 'UNVERIFIED'
    }
    try { return 'ALLOWED' }
    finally { [void][GeumyiDay12DirectoryOpenCheck]::CloseHandle($handle) }
}
