[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$CIFixture,
    [string]$CIFixtureRoot = '',
    [int]$MaxObjects = 300000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Day12.5 READ-ONLY subtree inventory for %ProgramData%\GeumyiServerCenter.
# Purpose: evidence that the fixed 10-target DACL backup cannot provide before
# any GSC-root inheritance change:
#   * objects NOT owned by SYSTEM / Administrators / TrustedInstaller
#     (a pre-created, user-owned object keeps owner rights after the parent
#     ACL is narrowed, so it must be found and reviewed first);
#   * reparse points (junctions/symlinks) - never followed;
#   * legacy predictable temp names (*.tmp, *.gsc.tmp, *.new, *.part,
#     *.gsc-restore, *.gsc-new) that pre-fix GSC builds could open;
#   * objects with explicit ACEs or a protected DACL (not re-propagated by an
#     inheritance change and not covered by the 10-object backup).
# Never calls Set-Acl / icacls; never opens file contents; never follows a
# reparse point. Share JSON contains counts only (no names, paths, SIDs).

$script:LegacyTempRegex = '(?i)(\.gsc\.tmp|\.json\.tmp|\.tmp|\.new|\.part|\.gsc-restore|\.gsc-new)$'
$script:NewTempRegex = '(?i)^\..+\.gsc-\d+\.tmp$'   # internal/atomicfile pattern (Go CreateTemp digits)
$script:KnownTop = @('Backups','Checkpoints','PluginBackups','Runtime','Updates','Staging','logs','events','metrics','jobs','audit','ManagedPlugins')

function Get-OwnerClass([string]$sid, [string]$currentSid) {
    if ([string]::IsNullOrWhiteSpace($sid)) { return 'UNREADABLE' }
    if ($sid -eq 'S-1-5-18') { return 'SYSTEM' }
    if ($sid -eq 'S-1-5-32-544') { return 'ADMINISTRATORS' }
    if ($sid -like 'S-1-5-80-*') { return 'SERVICE_SID' }          # e.g. TrustedInstaller
    if ($sid -eq $currentSid) { return 'CURRENT_OPERATOR_ACCOUNT' }
    return 'OTHER_ACCOUNT'
}

function Get-NameClass([string]$name) {
    if ($name -match $script:NewTempRegex) { return 'NEW_RANDOM_TEMP' }
    if ($name -match $script:LegacyTempRegex) { return 'LEGACY_PREDICTABLE_TEMP' }
    return 'NORMAL'
}

function Get-TopBucket([string]$root, [string]$full) {
    $rel = $full.Substring($root.Length).TrimStart('\','/')
    if ($rel -eq '') { return 'ROOT' }
    $first = ($rel -split '[\\/]')[0]
    foreach ($k in $script:KnownTop) { if ($first -ieq $k) { return $k } }
    if ($rel -notmatch '[\\/]') { return 'ROOT_CHILD' }
    return 'OTHER_TOP'
}

# Walks without following reparse points. $AclProvider returns
# @{ owner_sid=...; protected=[bool]; explicit_aces=[int] } or $null.
function Invoke-Walk([string]$root, [scriptblock]$AclProvider, [string]$currentSid, [int]$max) {
    $agg = [ordered]@{
        objects = 0; directories = 0; files = 0; reparse_points = 0; unreadable = 0; truncated = $false
        owner = [ordered]@{}; legacy_temp = [ordered]@{}; new_random_temp = 0
        explicit_or_protected = 0; non_admin_owned_by_bucket = [ordered]@{}; reparse_by_bucket = [ordered]@{}
    }
    $stack = New-Object System.Collections.Stack
    $stack.Push([System.IO.DirectoryInfo]::new($root))
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $children = @()
        try { $children = @($dir.GetFileSystemInfos()) } catch { $agg.unreadable++; continue }
        foreach ($c in $children) {
            if ($agg.objects -ge $max) { $agg.truncated = $true; break }
            $agg.objects++
            $bucket = Get-TopBucket $root $c.FullName
            $isReparse = (($c.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
            $isDir = (($c.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0)
            if ($isDir) { $agg.directories++ } else { $agg.files++ }
            $a = $null
            try { $a = & $AclProvider $c } catch { $a = $null }
            $ownerClass = if ($null -eq $a) { 'UNREADABLE' } else { Get-OwnerClass ([string]$a.owner_sid) $currentSid }
            if (-not $agg.owner.Contains($ownerClass)) { $agg.owner[$ownerClass] = 0 }
            $agg.owner[$ownerClass]++
            if ($ownerClass -in @('CURRENT_OPERATOR_ACCOUNT','OTHER_ACCOUNT','UNREADABLE')) {
                if (-not $agg.non_admin_owned_by_bucket.Contains($bucket)) { $agg.non_admin_owned_by_bucket[$bucket] = 0 }
                $agg.non_admin_owned_by_bucket[$bucket]++
            }
            if ($null -ne $a -and ([bool]$a.protected -or [int]$a.explicit_aces -gt 0)) { $agg.explicit_or_protected++ }
            $nc = Get-NameClass $c.Name
            if ($nc -eq 'NEW_RANDOM_TEMP') { $agg.new_random_temp++ }
            elseif ($nc -eq 'LEGACY_PREDICTABLE_TEMP') {
                $k = 'owner_' + $ownerClass
                if (-not $agg.legacy_temp.Contains($k)) { $agg.legacy_temp[$k] = 0 }
                $agg.legacy_temp[$k]++
            }
            if ($isReparse) {
                $agg.reparse_points++
                if (-not $agg.reparse_by_bucket.Contains($bucket)) { $agg.reparse_by_bucket[$bucket] = 0 }
                $agg.reparse_by_bucket[$bucket]++
                continue   # never descend into a junction / symlink
            }
            if ($isDir) { $stack.Push([System.IO.DirectoryInfo]$c) }
        }
        if ($agg.truncated) { break }
    }
    return $agg
}

$windowsAclProvider = {
    param($info)
    $sec = $info.GetAccessControl([System.Security.AccessControl.AccessControlSections]'Owner, Access')
    $explicit = @($sec.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])).Count
    return @{
        owner_sid = $sec.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        protected = [bool]$sec.AreAccessRulesProtected
        explicit_aces = $explicit
    }
}

if ($SelfTest) {
    if ((Get-OwnerClass 'S-1-5-18' 'X') -ne 'SYSTEM' -or (Get-OwnerClass 'S-1-5-32-544' 'X') -ne 'ADMINISTRATORS' -or
        (Get-OwnerClass 'S-1-5-80-956008885-1' 'X') -ne 'SERVICE_SID' -or (Get-OwnerClass 'S-1-5-21-9-1001' 'S-1-5-21-9-1001') -ne 'CURRENT_OPERATOR_ACCOUNT' -or
        (Get-OwnerClass 'S-1-5-21-9-1002' 'S-1-5-21-9-1001') -ne 'OTHER_ACCOUNT' -or (Get-OwnerClass '' 'X') -ne 'UNREADABLE') {
        throw 'OWNER_CLASS_SELFTEST_FAILED'
    }
    foreach ($n in @('agent.properties.gsc.tmp','server.json.tmp','x.jar.new','a.part','w.dat.gsc-restore','h.exe.gsc-new','wild.json.tmp')) {
        if ((Get-NameClass $n) -ne 'LEGACY_PREDICTABLE_TEMP') { throw ('LEGACY_NAME_SELFTEST_FAILED_' + $n) }
    }
    if ((Get-NameClass '.server.json.gsc-123456789.tmp') -ne 'NEW_RANDOM_TEMP' -or (Get-NameClass 'server.json') -ne 'NORMAL') {
        throw 'NAME_CLASS_SELFTEST_FAILED'
    }
    # Walker on a disposable tree with a stub ACL provider (portable).
    $t = Join-Path ([System.IO.Path]::GetTempPath()) ('gsc-inv-selftest-' + [guid]::NewGuid().ToString('N'))
    $outside = $t + '-outside'
    try {
        [void](New-Item -ItemType Directory -Path (Join-Path $t 'Runtime\Agent') -Force)
        [void](New-Item -ItemType Directory -Path $outside -Force)
        Set-Content -LiteralPath (Join-Path $outside 'must-not-be-walked.txt') -Value 'x'
        Set-Content -LiteralPath (Join-Path $t 'Runtime\Agent\agent.properties.gsc.tmp') -Value 'x'
        Set-Content -LiteralPath (Join-Path $t 'server.json') -Value 'x'
        $linked = $false
        try { [void](New-Item -ItemType SymbolicLink -Path (Join-Path $t 'Staging') -Target $outside -ErrorAction Stop); $linked = $true } catch {
            try { [void](New-Item -ItemType Junction -Path (Join-Path $t 'Staging') -Target $outside -ErrorAction Stop); $linked = $true } catch { $linked = $false }
        }
        $stub = { param($i) if ($i.Name -like '*.gsc.tmp') { @{owner_sid='S-1-5-21-1-2-3-1002';protected=$false;explicit_aces=0} } else { @{owner_sid='S-1-5-18';protected=$false;explicit_aces=0} } }
        $r = Invoke-Walk $t $stub 'S-1-5-21-1-2-3-1001' 1000
        if ($r.legacy_temp['owner_OTHER_ACCOUNT'] -ne 1 -or $r.non_admin_owned_by_bucket['Runtime'] -ne 1) { throw 'WALK_CLASSIFY_SELFTEST_FAILED' }
        if ($linked -and ($r.reparse_points -ne 1 -or $r.objects -ne 5)) { throw ('WALK_REPARSE_SELFTEST_FAILED objects=' + $r.objects + ' reparse=' + $r.reparse_points) }
        $cap = Invoke-Walk $t $stub 'X' 2
        if (-not $cap.truncated) { throw 'WALK_CAP_SELFTEST_FAILED' }
        Write-Host ('INVENTORY_SELFTEST_PASS (owner/name classes, walker, reparse not followed=' + $linked + ', cap)')
    } finally {
        # Self-test ONLY cleanup. Scope is restricted to two fresh GUID-named
        # temporary directories and never reaches the production GSC tree.
        $tempPrefix = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::GetTempPath()).TrimEnd('\\','/') +
            [System.IO.Path]::DirectorySeparatorChar
        foreach ($candidate in @($t,$outside)) {
            $full = [System.IO.Path]::GetFullPath($candidate)
            $leaf = [System.IO.Path]::GetFileName($full)
            if (-not $full.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or
                $leaf -notmatch '^gsc-inv-selftest-[0-9a-f]{32}(-outside)?
    exit 0
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'WINDOWS_ONLY' }
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA_MISSING' }
if ($CIFixture) {
    if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or [string]::IsNullOrWhiteSpace($CIFixtureRoot)) {
        throw 'CI_FIXTURE_MODE_NOT_AUTHORIZED'
    }
    $runner = [System.IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
    if (-not ([System.IO.Path]::GetFullPath($CIFixtureRoot)).StartsWith($runner, [StringComparison]::OrdinalIgnoreCase)) { throw 'CI_FIXTURE_OUT_OF_SCOPE' }
    $root = [System.IO.Path]::GetFullPath($CIFixtureRoot).TrimEnd('\')
} else {
    if (-not [string]::IsNullOrWhiteSpace($CIFixtureRoot)) { throw 'FIXTURE_ROOT_NOT_ALLOWED_FOR_REAL_CAPTURE' }
    $pd = $env:ProgramData
    if ([string]::IsNullOrWhiteSpace($pd) -or -not [string]::Equals([System.IO.Path]::GetFullPath($pd).TrimEnd('\'),
        [System.IO.Path]::GetFullPath((Join-Path $env:SystemDrive 'ProgramData')).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'NONSTANDARD_PROGRAMDATA_REVIEW_REQUIRED'
    }
    $root = Join-Path $pd 'GeumyiServerCenter'
}
$rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'GSC_ROOT_IS_REPARSE_POINT_REVIEW_REQUIRED' }

$me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([System.Security.Principal.WindowsPrincipal]$me).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
$started = Get-Date
$agg = Invoke-Walk $root $windowsAclProvider $me.User.Value $MaxObjects
$rootOwner = Get-OwnerClass ((& $windowsAclProvider $rootItem).owner_sid) $me.User.Value

$share = [ordered]@{
    schema = 1
    phase = '12.5-gsc-subtree-owner-reparse-inventory'
    tool = 'DAY12_GSC_SUBTREE_OWNER_INVENTORY_READ_ONLY'
    captured_at = (Get-Date).ToString('o')
    synthetic = [bool]$CIFixture
    elevated = [bool]$elevated
    duration_seconds = [int]((Get-Date) - $started).TotalSeconds
    root_owner_class = $rootOwner
    objects = $agg.objects; directories = $agg.directories; files = $agg.files
    truncated_at_cap = [bool]$agg.truncated; unreadable_directories = $agg.unreadable
    owner_class_counts = $agg.owner
    non_admin_or_unreadable_owner_by_top_bucket = $agg.non_admin_owned_by_bucket
    reparse_points = $agg.reparse_points; reparse_points_by_top_bucket = $agg.reparse_by_bucket
    legacy_predictable_temp_by_owner_class = $agg.legacy_temp
    new_random_temp_files = $agg.new_random_temp
    objects_with_explicit_ace_or_protected_dacl = $agg.explicit_or_protected
    production_acl_modified = $false
    reparse_points_followed = $false
    names_paths_sids_shared = $false
    strict_security_gate = 'NOT_PASSED'
    note = 'Counts only. Any OTHER_ACCOUNT/CURRENT_OPERATOR_ACCOUNT owner, reparse point or legacy temp inside the GSC tree must be reviewed privately before narrowing ACLs; do not delete automatically.'
}
$outBase = Join-Path $env:LOCALAPPDATA 'Geumyi-Day12-ACL-Inventory'
if (Test-Path -LiteralPath $outBase) {
    if (((Get-Item -LiteralPath $outBase -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'OUTPUT_BASE_REPARSE_POINT_REFUSED' }
} else { [void](New-Item -ItemType Directory -Path $outBase) }
$out = Join-Path $outBase ('DAY12-GSC-SUBTREE-INVENTORY-SHARE-ONLY-THIS-' + [guid]::NewGuid().ToString('N') + '.json')
$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($share | ConvertTo-Json -Depth 6))
$fs = [System.IO.FileStream]::new($out, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
Write-Host ('INVENTORY: objects=' + $agg.objects + ' reparse=' + $agg.reparse_points + ' legacy_temp=' + (@($agg.legacy_temp.Values | Measure-Object -Sum).Sum) + ' truncated=' + $agg.truncated)
Write-Host ('SHARE ONLY: ' + $out)
 -or
                -not [string]::Equals([System.IO.Path]::GetDirectoryName($full).TrimEnd('\\'),
                                      $tempPrefix.TrimEnd('\\'),
                                      [StringComparison]::OrdinalIgnoreCase)) {
                throw 'SELFTEST_CLEANUP_OUTSIDE_DISPOSABLE_TEMP_BLOCKED'
            }
        }
        $linkPath = Join-Path $t 'Staging'
        if ($linked -and [System.IO.Directory]::Exists($linkPath)) {
            $attrs = [System.IO.File]::GetAttributes($linkPath)
            if (($attrs -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                throw 'SELFTEST_EXPECTED_REPARSE_LINK_MISSING'
            }
            # Delete just the junction/symlink, never the linked directory.
            [System.IO.Directory]::Delete($linkPath,$false)
        }
        if ([System.IO.Directory]::Exists($t)) {
            [System.IO.Directory]::Delete($t,$true)
        }
        if ([System.IO.Directory]::Exists($outside)) {
            [System.IO.Directory]::Delete($outside,$true)
        }
    }
    exit 0
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'WINDOWS_ONLY' }
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA_MISSING' }
if ($CIFixture) {
    if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or [string]::IsNullOrWhiteSpace($CIFixtureRoot)) {
        throw 'CI_FIXTURE_MODE_NOT_AUTHORIZED'
    }
    $runner = [System.IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
    if (-not ([System.IO.Path]::GetFullPath($CIFixtureRoot)).StartsWith($runner, [StringComparison]::OrdinalIgnoreCase)) { throw 'CI_FIXTURE_OUT_OF_SCOPE' }
    $root = [System.IO.Path]::GetFullPath($CIFixtureRoot).TrimEnd('\')
} else {
    if (-not [string]::IsNullOrWhiteSpace($CIFixtureRoot)) { throw 'FIXTURE_ROOT_NOT_ALLOWED_FOR_REAL_CAPTURE' }
    $pd = $env:ProgramData
    if ([string]::IsNullOrWhiteSpace($pd) -or -not [string]::Equals([System.IO.Path]::GetFullPath($pd).TrimEnd('\'),
        [System.IO.Path]::GetFullPath((Join-Path $env:SystemDrive 'ProgramData')).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'NONSTANDARD_PROGRAMDATA_REVIEW_REQUIRED'
    }
    $root = Join-Path $pd 'GeumyiServerCenter'
}
$rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'GSC_ROOT_IS_REPARSE_POINT_REVIEW_REQUIRED' }

$me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([System.Security.Principal.WindowsPrincipal]$me).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
$started = Get-Date
$agg = Invoke-Walk $root $windowsAclProvider $me.User.Value $MaxObjects
$rootOwner = Get-OwnerClass ((& $windowsAclProvider $rootItem).owner_sid) $me.User.Value

$share = [ordered]@{
    schema = 1
    phase = '12.5-gsc-subtree-owner-reparse-inventory'
    tool = 'DAY12_GSC_SUBTREE_OWNER_INVENTORY_READ_ONLY'
    captured_at = (Get-Date).ToString('o')
    synthetic = [bool]$CIFixture
    elevated = [bool]$elevated
    duration_seconds = [int]((Get-Date) - $started).TotalSeconds
    root_owner_class = $rootOwner
    objects = $agg.objects; directories = $agg.directories; files = $agg.files
    truncated_at_cap = [bool]$agg.truncated; unreadable_directories = $agg.unreadable
    owner_class_counts = $agg.owner
    non_admin_or_unreadable_owner_by_top_bucket = $agg.non_admin_owned_by_bucket
    reparse_points = $agg.reparse_points; reparse_points_by_top_bucket = $agg.reparse_by_bucket
    legacy_predictable_temp_by_owner_class = $agg.legacy_temp
    new_random_temp_files = $agg.new_random_temp
    objects_with_explicit_ace_or_protected_dacl = $agg.explicit_or_protected
    production_acl_modified = $false
    reparse_points_followed = $false
    names_paths_sids_shared = $false
    strict_security_gate = 'NOT_PASSED'
    note = 'Counts only. Any OTHER_ACCOUNT/CURRENT_OPERATOR_ACCOUNT owner, reparse point or legacy temp inside the GSC tree must be reviewed privately before narrowing ACLs; do not delete automatically.'
}
$outBase = Join-Path $env:LOCALAPPDATA 'Geumyi-Day12-ACL-Inventory'
if (Test-Path -LiteralPath $outBase) {
    if (((Get-Item -LiteralPath $outBase -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'OUTPUT_BASE_REPARSE_POINT_REFUSED' }
} else { [void](New-Item -ItemType Directory -Path $outBase) }
$out = Join-Path $outBase ('DAY12-GSC-SUBTREE-INVENTORY-SHARE-ONLY-THIS-' + [guid]::NewGuid().ToString('N') + '.json')
$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($share | ConvertTo-Json -Depth 6))
$fs = [System.IO.FileStream]::new($out, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
Write-Host ('INVENTORY: objects=' + $agg.objects + ' reparse=' + $agg.reparse_points + ' legacy_temp=' + (@($agg.legacy_temp.Values | Measure-Object -Sum).Sum) + ' truncated=' + $agg.truncated)
Write-Host ('SHARE ONLY: ' + $out)
