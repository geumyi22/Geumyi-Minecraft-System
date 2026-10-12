[CmdletBinding()]
param([switch]$Synthetic)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Same no-write native directory probe used by the real-host operator kit.
. (Join-Path $PSScriptRoot '..\Day12_GSC_NoWrite_AccessCore.ps1')

# =============================================================================
# Day12.5 ACL NEGATIVE TEST (GitHub Actions Windows runner ONLY).
#
# Goal: prove with a REAL standard-user security token that the GSC ACL model
# behaves as claimed:
#   A) while BUILTIN\Users holds create/write ACEs on a directory, an
#      unprivileged user CAN create a file there  -> the risky state the
#      least-privilege change is meant to remove is actually DETECTED;
#   B) after those Users ACEs are removed (inheritance broken, only RX kept),
#      the same unprivileged user is DENIED create / modify / replace;
#   C) SYSTEM / Administrators / the current runner account keep write access.
#
# Everything happens on a brand-new GUID directory under RUNNER_TEMP and on a
# disposable local account. NEVER touches %ProgramData%, a real GSC install,
# services, worlds, backups or firewall.
#
# Fail-closed: if a real standard-user token cannot be created or the checks
# cannot run, the script exits BLOCKED/UNVERIFIED (non-zero) and NEVER reports
# PASS. A result JSON with status is written for the PR record.
# =============================================================================

$ExitPass = 0; $ExitFail = 1; $ExitBlocked = 42

function Write-Result([string]$status, [hashtable]$facts, [string]$reason) {
    $out = [ordered]@{
        schema      = 1
        phase       = '12.5-acl-negative-test'
        tool        = 'DAY12_ACL_NEGATIVE_TEST_WINDOWS_CI'
        captured_at = (Get-Date).ToString('o')
        synthetic   = $true
        status      = $status
        reason      = $reason
        production_acl_modified = $false
        ran_on_github_actions   = ($env:GITHUB_ACTIONS -eq 'true')
    }
    foreach ($k in $facts.Keys) { $out[$k] = $facts[$k] }
    $json = $out | ConvertTo-Json -Depth 6
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ("``````json`n" + $json + "`n``````")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
        $p = Join-Path $env:RUNNER_TEMP 'DAY12-ACL-NEGATIVE-TEST-RESULT.json'
        [IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ('RESULT JSON: ' + $p)
    }
    Write-Host ('NEGATIVE TEST STATUS: ' + $status + ' (' + $reason + ')')
}

function Block([string]$reason) {
    Write-Result 'BLOCKED_UNVERIFIED' @{} $reason
    exit $ExitBlocked
}

# ---- Guard: disposable CI fixture only -------------------------------------
if (-not $Synthetic -or $env:GITHUB_ACTIONS -ne 'true' -or
    $env:GEUMYI_DAY12_ACL_NEGTEST_CI -ne 'isolated_fixture' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'CI_ONLY_DISPOSABLE_ACL_NEGATIVE_TEST_REFUSED'
}
$runnerRoot = (Resolve-Path -LiteralPath $env:RUNNER_TEMP -ErrorAction Stop).Path
if (-not [System.IO.Path]::IsPathRooted($runnerRoot) -or ($runnerRoot -match '^[A-Za-z]:\\?$')) {
    throw 'RUNNER_TEMP_IS_UNSAFE'
}

# ---- P/Invoke: LogonUser + impersonation -----------------------------------
# A standard-user *primary* token is obtained with LogonUser; file operations
# run inside WindowsIdentity.RunImpersonated so the kernel enforces the real
# account's DACL check (NOT a manual AccessCheck, NOT the admin runner token).
$signature = @'
using System;
using System.Runtime.InteropServices;
public static class GeumyiLogon {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out IntPtr token);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr h);
}
'@

$adminSid  = 'S-1-5-32-544'
$systemSid = 'S-1-5-18'
$usersSid  = 'S-1-5-32-545'

function New-DisposableStandardUser {
    $name = 'gscneg' + ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    # Random 24+ char password meeting local complexity policy. Built without
    # ConvertTo-SecureString -AsPlainText (which PSSA flags); the SecureString is
    # assembled char-by-char. The plaintext is needed only for LogonUser below.
    $upper = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = [char[]]'abcdefghijkmnpqrstuvwxyz'
    $pw = ([string]$upper[(Get-Random -Maximum $upper.Length)]) +
          ([string]$lower[(Get-Random -Maximum $lower.Length)]) +
          ((Get-Random -Maximum 900000) + 100000).ToString() +
          '!' + [Guid]::NewGuid().ToString('N').Substring(0, 14)
    $sb = New-Object System.Security.SecureString
    foreach ($ch in $pw.ToCharArray()) { $sb.AppendChar($ch) }
    $sb.MakeReadOnly()
    New-LocalUser -Name $name -Password $sb -AccountNeverExpires -ErrorAction Stop | Out-Null
    # Ensure membership is ONLY Users (standard), never Administrators.
    try { Add-LocalGroupMember -Group 'Users' -Member $name -ErrorAction Stop } catch { $null = $_ }
    foreach ($g in @('Administrators')) {
        try { Remove-LocalGroupMember -Group $g -Member $name -ErrorAction SilentlyContinue } catch { $null = $_ }
    }
    return [pscustomobject]@{ Name = $name; Password = $pw }
}

function Get-StandardUserToken([string]$user, [string]$pass) {
    if (-not ('GeumyiLogon' -as [type])) {
        Add-Type -TypeDefinition $signature -Language CSharp -ErrorAction Stop
    }
    $tok = [IntPtr]::Zero
    # LOGON32_LOGON_INTERACTIVE = 2, LOGON32_PROVIDER_DEFAULT = 0.
    foreach ($logonType in @(2, 3, 4)) {   # interactive, network, batch
        if ([GeumyiLogon]::LogonUser($user, '.', $pass, $logonType, 0, [ref]$tok)) {
            return $tok
        }
    }
    return [IntPtr]::Zero
}

function Invoke-AsUser([IntPtr]$token, [scriptblock]$action) {
    $id = New-Object System.Security.Principal.WindowsIdentity($token)
    return [System.Security.Principal.WindowsIdentity]::RunImpersonated(
        $id.AccessToken, [Func[object]] { & $action })
}

# A create attempt that returns $true only if a NEW file was really written.
function Test-CanCreate([string]$dir, [string]$leaf) {
    $p = Join-Path $dir $leaf
    try {
        [IO.File]::WriteAllText($p, 'x', (New-Object System.Text.UTF8Encoding($false)))
        $ok = [IO.File]::Exists($p)
        return $ok
    } catch [System.UnauthorizedAccessException] { return $false }
      catch [System.IO.IOException] { return $false }
}

function Test-CanModify([string]$path) {
    try {
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
        try { $b = [byte[]](1); $fs.Write($b, 0, 1) } finally { $fs.Dispose() }
        return $true
    } catch [System.UnauthorizedAccessException] { return $false }
      catch [System.IO.IOException] { return $false }
}

# ---- ACL helpers (fixture directory only) ----------------------------------
function Set-UsersCreateAllowed([string]$dir) {
    $acl = Get-Acl -LiteralPath $dir
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($systemSid, $adminSid, [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier($sid)),
            'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    }
    # BUILTIN\Users: read + CREATE (the risky state).
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        (New-Object System.Security.Principal.SecurityIdentifier($usersSid)),
        'ReadAndExecute,CreateFiles,CreateDirectories,AppendData,Write',
        'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $dir -AclObject $acl
}

function Set-UsersReadOnly([string]$dir) {
    $acl = Get-Acl -LiteralPath $dir
    $acl.SetAccessRuleProtection($true, $false)
    $acl.PurgeAccessRules((New-Object System.Security.Principal.SecurityIdentifier($usersSid)))
    # Keep only read/traverse for Users (legitimate read must survive).
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        (New-Object System.Security.Principal.SecurityIdentifier($usersSid)),
        'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $dir -AclObject $acl
}

# ---- Run -------------------------------------------------------------------
$base = Join-Path $runnerRoot ('Geumyi-ACL-Neg-' + [Guid]::NewGuid().ToString('N'))
$user = $null
$token = [IntPtr]::Zero
$facts = @{}
try {
    New-Item -ItemType Directory -Path $base -ErrorAction Stop | Out-Null
    $dir = Join-Path $base 'GeumyiServerCenter'
    New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null

    try { $user = New-DisposableStandardUser }
    catch { Block ('CANNOT_CREATE_STANDARD_USER: ' + $_.Exception.Message) }

    $token = Get-StandardUserToken $user.Name $user.Password
    if ($token -eq [IntPtr]::Zero) {
        Block ('LOGONUSER_FAILED_err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }

    # Sanity: the impersonated identity must be the standard user and NOT admin.
    $imp = Invoke-AsUser $token {
        $i = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        [pscustomobject]@{
            Name    = $i.Name
            IsAdmin = (New-Object System.Security.Principal.WindowsPrincipal($i)).IsInRole(
                        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
        }
    }
    $facts['impersonated_is_admin'] = [bool]$imp.IsAdmin
    if ($imp.IsAdmin) { Block 'IMPERSONATED_TOKEN_IS_ADMIN_NOT_STANDARD' }
    $tokenClass = Invoke-AsUser $token { Get-Day12TokenClass }
    $facts['real_standard_token_class_confirmed'] = ($tokenClass -eq 'STANDARD_ACCOUNT_TOKEN')
    if (-not $facts['real_standard_token_class_confirmed']) { Block 'TOKEN_CLASSIFIER_DID_NOT_ACCEPT_REAL_STANDARD_USER' }

    # Case A: Users create allowed -> standard user CAN create (risk detected).
    Set-UsersCreateAllowed $dir
    $script:__d = $dir
    $aCreate = Invoke-AsUser $token { Test-CanCreate $script:__d 'std-created-A.txt' }
    $facts['caseA_users_create_allowed_detected'] = [bool]$aCreate
    $facts['caseA_nowrite_addfile_handle_allowed'] = (
        (Invoke-AsUser $token { Invoke-Day12DirectoryAccessCheck -Directory $script:__d -Right CreateFiles }) -eq 'ALLOWED')
    $facts['caseA_nowrite_adddirectory_handle_allowed'] = (
        (Invoke-AsUser $token { Invoke-Day12DirectoryAccessCheck -Directory $script:__d -Right CreateDirectories }) -eq 'ALLOWED')

    # Current (admin) account preserves write under the same ACL.
    $facts['caseA_admin_can_create'] = (Test-CanCreate $dir 'admin-created-A.txt')

    # Case B: remove Users create -> standard user DENIED create/modify/replace.
    $keep = Join-Path $dir 'keep-B.txt'
    [IO.File]::WriteAllText($keep, 'original', (New-Object System.Text.UTF8Encoding($false)))
    Set-UsersReadOnly $dir
    $script:__d = $dir; $script:__keep = $keep
    $bCreate  = Invoke-AsUser $token { Test-CanCreate $script:__d 'std-created-B.txt' }
    $bModify  = Invoke-AsUser $token { Test-CanModify $script:__keep }
    $bReplace = Invoke-AsUser $token {
        try {
            $tmp = $script:__keep + '.att'
            [IO.File]::WriteAllText($tmp, 'evil', (New-Object System.Text.UTF8Encoding($false)))
            [IO.File]::Replace($tmp, $script:__keep, $null); return $true
        } catch { return $false }
    }
    $facts['caseB_std_create_denied']  = (-not $bCreate)
    $facts['caseB_nowrite_addfile_handle_denied'] = (
        (Invoke-AsUser $token { Invoke-Day12DirectoryAccessCheck -Directory $script:__d -Right CreateFiles }) -eq 'DENIED')
    $facts['caseB_nowrite_adddirectory_handle_denied'] = (
        (Invoke-AsUser $token { Invoke-Day12DirectoryAccessCheck -Directory $script:__d -Right CreateDirectories }) -eq 'DENIED')
    $facts['caseB_std_modify_denied']  = (-not $bModify)
    $facts['caseB_std_replace_denied'] = (-not $bReplace)
    # Standard user must still READ (legitimate read preserved).
    $script:__keep2 = $keep
    $bRead = Invoke-AsUser $token { try { [IO.File]::ReadAllText($script:__keep2) -eq 'original' } catch { $false } }
    $facts['caseB_std_read_preserved'] = [bool]$bRead
    # Admin/SYSTEM still write after narrowing.
    $facts['caseB_admin_can_create'] = (Test-CanCreate $dir 'admin-created-B.txt')
    $keepUnchanged = ([IO.File]::ReadAllText($keep) -eq 'original')
    $facts['caseB_existing_file_unchanged'] = $keepUnchanged

    # Verdict: every expected condition must hold, else FAIL (never silent pass).
    $pass = $facts['real_standard_token_class_confirmed'] -and
            $facts['caseA_nowrite_addfile_handle_allowed'] -and
            $facts['caseA_nowrite_adddirectory_handle_allowed'] -and
            $facts['caseB_nowrite_addfile_handle_denied'] -and
            $facts['caseB_nowrite_adddirectory_handle_denied'] -and
            $facts['caseA_users_create_allowed_detected'] -and
            $facts['caseA_admin_can_create'] -and
            $facts['caseB_std_create_denied'] -and
            $facts['caseB_std_modify_denied'] -and
            $facts['caseB_std_replace_denied'] -and
            $facts['caseB_std_read_preserved'] -and
            $facts['caseB_admin_can_create'] -and
            $facts['caseB_existing_file_unchanged']
    if ($pass) {
        Write-Result 'PASS' $facts 'Users create detected; denied after removal; admin/read preserved'
        $exit = $ExitPass
    } else {
        Write-Result 'FAIL' $facts 'One or more ACL negative-test conditions did not hold'
        $exit = $ExitFail
    }
} catch {
    Write-Result 'BLOCKED_UNVERIFIED' $facts ('EXCEPTION: ' + $_.Exception.Message)
    $exit = $ExitBlocked
} finally {
    if ($token -ne [IntPtr]::Zero) { [void][GeumyiLogon]::CloseHandle($token) }
    if ($null -ne $user) {
        try { Remove-LocalUser -Name $user.Name -ErrorAction SilentlyContinue } catch { $null = $_ }
    }
    if (Test-Path -LiteralPath $base) {
        try {
            $bAcl = Get-Acl -LiteralPath $base
            $bAcl.SetAccessRuleProtection($true, $false)
            Set-Acl -LiteralPath $base -AclObject $bAcl
        } catch { $null = $_ }
        Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit $exit
