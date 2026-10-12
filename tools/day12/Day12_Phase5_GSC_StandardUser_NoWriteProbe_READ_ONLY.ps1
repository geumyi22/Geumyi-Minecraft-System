[CmdletBinding()]
param([switch]$SelfTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Day12.5 exact live-token read-only access probe.
# ONLY tests existing %ProgramData%\GeumyiServerCenter root directory.
# NEVER creates, edits or deletes any production file or folder.
# Uses CreateFileW(OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS) with requested
# FILE_ADD_FILE / FILE_ADD_SUBDIRECTORY access under the *actual* caller token.
# A filtered admin token, elevated admin, SYSTEM, service or unknown identity
# is NOT a standard-user observation. Refuse (BLOCKED_UNVERIFIED).
# Emits no identities, full paths, SIDs, SDDL, ACL dumps, or credentials.
# Output is a counts-only / categorical JSON under LOCALAPPDATA.

$core = Join-Path $PSScriptRoot 'Day12_GSC_NoWrite_AccessCore.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
    throw 'ACCESS_CORE_MISSING'
}
. $core

function Get-EligibleTokenClass {
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

function Write-SanitizedResult([hashtable]$facts) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA_UNAVAILABLE'
    }
    $local = Get-Item -LiteralPath $env:LOCALAPPDATA -Force -ErrorAction Stop
    if (($local.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'LOCALAPPDATA_REPARSE_PARENT_BLOCKED'
    }
    $outDir = Join-Path $env:LOCALAPPDATA 'Geumyi-Day12-StandardUser-AccessProbe'
    if (Test-Path -LiteralPath $outDir) {
        $item = Get-Item -LiteralPath $outDir -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($item.Attributes -band [IO.FileAttributes]::Directory) -eq 0) {
            throw 'OUTPUT_DIRECTORY_NOT_SAFE'
        }
    } else {
        [void](New-Item -ItemType Directory -Path $outDir -ErrorAction Stop)
    }
    $out = Join-Path $outDir ('DAY12-GSC-STANDARD-USER-NOWRITE-SHARE-ONLY-THIS-' +
        [Guid]::NewGuid().ToString('N') + '.json')
    $data = [ordered]@{
        schema = 1
        phase = '12.5-live-standard-user-directory-access'
        tool = 'DAY12_GSC_NO_WRITE_STANDARD_USER_PROBE'
        captured_at = (Get-Date).ToString('o')
        synthetic = $false
        token_class = [string]$facts.token_class
        root_checked = [bool]$facts.root_checked
        create_files_access = [string]$facts.create_files_access
        create_directories_access = [string]$facts.create_directories_access
        actual_file_created = $false
        actual_directory_created = $false
        production_acl_modified = $false
        service_firewall_backup_world_modified = $false
        raw_sids_paths_credentials_or_sddl_shared = $false
        result = [string]$facts.result
        strict_security_gate = 'NOT_PASSED'
        note = 'An actual non-admin token has been used only when token_class=STANDARD_ACCOUNT_TOKEN. No file creation occurred. Other production targets, owner, MIC and rollback are not verified.'
    }
    $json = $data | ConvertTo-Json -Depth 4
    if ($json -match 'S-1-5-|[A-Za-z]:\\|principal_sid|acl_sddl|agent.properties|server.json') {
        throw 'OUTPUT_DISCLOSURE_CONTRACT_FAILED'
    }
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
    $stream = New-Object IO.FileStream($out,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    Write-Host ('ACCESS_PROBE_STATE: ' + [string]$facts.result)
    Write-Host ('SHARE ONLY NEW JSON IN: ' + 'LOCALAPPDATA/Geumyi-Day12-StandardUser-AccessProbe')
}

if ($SelfTest) {
    # Only the machine's *disposable temp* directory is created and removed.
    # This is a native call smoke test and NOT a standard-user proof.
    $tmpRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)
    $scratch = Join-Path $tmpRoot ('gsc-access-smoke-' + [Guid]::NewGuid().ToString('N'))
    try {
        [void][IO.Directory]::CreateDirectory($scratch)
        if ((Invoke-Day12DirectoryAccessCheck -Directory $scratch -Right CreateFiles) -ne 'ALLOWED' -or
            (Invoke-Day12DirectoryAccessCheck -Directory $scratch -Right CreateDirectories) -ne 'ALLOWED') {
            throw 'NATIVE_DIRECTORY_PROBE_SELFTEST_FAILED'
        }
        Write-Host 'STANDARD_USER_ACCESS_PROBE_SELFTEST_PASS (scratch only)'
    } finally {
        $target = [IO.Path]::GetFullPath($scratch)
        if ([IO.Path]::GetDirectoryName($target).TrimEnd([char]92,[char]47) -ne $tmpRoot -or
            [IO.Path]::GetFileName($target) -notmatch '^gsc-access-smoke-[0-9a-f]{32}$') {
            throw 'SCRATCH_SCOPE_MISMATCH'
        }
        if ([IO.Directory]::Exists($target)) {
            [IO.Directory]::Delete($target,$false)
        }
    }
    exit 0
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'WINDOWS_ONLY'
}
$class = Get-EligibleTokenClass
$state = @{
    token_class = $class
    root_checked = $false
    create_files_access = 'UNVERIFIED'
    create_directories_access = 'UNVERIFIED'
    result = 'BLOCKED_UNVERIFIED'
}
if ($class -ne 'STANDARD_ACCOUNT_TOKEN') {
    Write-SanitizedResult $state
    Write-Host 'BLOCKED: Run only from an existing real standard-user Windows account.'
    Write-Host 'Do NOT create or change a Windows account or production ACL for this probe.'
    exit 42
}

if ([string]::IsNullOrWhiteSpace($env:ProgramData) -or
    [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
    Write-SanitizedResult $state
    exit 42
}
$canonicalParent = [IO.Path]::GetFullPath((Join-Path $env:SystemDrive 'ProgramData')).TrimEnd('\')
if (-not [string]::Equals([IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\'),
                          $canonicalParent,[StringComparison]::OrdinalIgnoreCase)) {
    Write-SanitizedResult $state
    Write-Host 'BLOCKED: Nonstandard ProgramData path'
    exit 42
}
$targetRoot = Join-Path $canonicalParent 'GeumyiServerCenter'
$root = $null
try { $root = Get-Item -LiteralPath $targetRoot -Force -ErrorAction Stop } catch { $root = $null }
if ($null -eq $root -or ($root.Attributes -band [IO.FileAttributes]::Directory) -eq 0 -or
    ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    Write-SanitizedResult $state
    Write-Host 'BLOCKED: GSC root missing, inaccessible or reparse point'
    exit 42
}
$state.root_checked = $true
$state.create_files_access = Invoke-Day12DirectoryAccessCheck -Directory $targetRoot -Right CreateFiles
$state.create_directories_access = Invoke-Day12DirectoryAccessCheck -Directory $targetRoot -Right CreateDirectories

if ($state.create_files_access -eq 'ALLOWED' -or $state.create_directories_access -eq 'ALLOWED') {
    $state.result = 'WRITE_ACCESS_DETECTED_REVIEW_REQUIRED'
} elseif ($state.create_files_access -eq 'DENIED' -and $state.create_directories_access -eq 'DENIED') {
    $state.result = 'STANDARD_TOKEN_DENIAL_OBSERVED_SCOPE_LIMITED'
} else {
    $state.result = 'BLOCKED_UNVERIFIED'
}
Write-SanitizedResult $state
if ($state.result -eq 'BLOCKED_UNVERIFIED') { exit 42 }
Write-Host 'No GSC files or directories were created, modified or deleted.'
exit 0
