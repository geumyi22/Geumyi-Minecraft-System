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

# Classifier is fail-closed: filtered administrators are not standard users.
function Get-Day12TokenClass {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $id -or -not $id.IsAuthenticated -or $null -eq $id.User) {
        return 'BLOCKED_UNVERIFIED_IDENTITY'
    }
    $disallowed = @(
        'S-1-5-18',        # SYSTEM
        'S-1-5-32-544',    # Administrators (including UAC deny-only group)
        'S-1-5-32-547',    # Power Users
        'S-1-5-32-548',    # Account Operators
        'S-1-5-32-549',    # Server Operators
        'S-1-5-32-550',    # Print Operators
        'S-1-5-32-551'     # Backup Operators
    )
    if ($disallowed -contains $id.User.Value) { return 'BLOCKED_PRIVILEGED_ACCOUNT' }
    $groups = $id.Groups
    if ($null -eq $groups) { return 'BLOCKED_UNVERIFIED_GROUPS' }
    foreach ($sid in $groups) {
        if ($disallowed -contains $sid.Value) {
            return 'BLOCKED_PRIVILEGED_OR_FILTERED_ADMIN_ACCOUNT'
        }
    }
    if ((New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return 'BLOCKED_PRIVILEGED_TOKEN'
    }
    return 'STANDARD_ACCOUNT_TOKEN'
}

