[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$CIFixture,
    [string]$CIFixtureRoot = '',
    [ValidateRange(1,300000)][int]$MaxObjects = 300000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Day12.5 defensive DACL review. Production: READ ONLY. The only production-mode
# write is a new counts-only JSON under the operator's LOCALAPPDATA.
# No ACL apply/restore/delete, no services, world, backup, firewall or credentials.
# No path, filename, SID, trustee, raw DACL/SDDL, token or owner name is serialized.
# A trustee ACE is NOT an Effective Access decision; security gate is never PASS.
# Reparse points are counted but never opened or descended into.

$script:TopBuckets = @('Backups','Checkpoints','PluginBackups','Runtime','Updates','Staging','logs','events','metrics','jobs','audit','ManagedPlugins')
$script:BroadSids = @('S-1-5-32-545','S-1-1-0','S-1-5-11','S-1-5-32-546')  # Users, Everyone, Authenticated Users, Guests
$script:WriteMask = [int][System.Security.AccessControl.FileSystemRights]::Write -bor
                    [int][System.Security.AccessControl.FileSystemRights]::Modify -bor
                    [int][System.Security.AccessControl.FileSystemRights]::Delete -bor
                    [int][System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
                    [int][System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
                    [int][System.Security.AccessControl.FileSystemRights]::TakeOwnership

function Get-TopBucket([string]$root,[string]$full) {
    $relative = $full.Substring($root.Length).TrimStart('\','/')
    if ($relative -eq '') { return 'ROOT' }
    $first = ($relative -split '[\/\\]')[0]
    foreach($bucket in $script:TopBuckets) {
        if ([string]::Equals($first,$bucket,[StringComparison]::OrdinalIgnoreCase)) { return $bucket }
    }
    if ($relative -notmatch '[\/\\]') { return 'ROOT_CHILD' }
    return 'OTHER_TOP'
}

function Convert-ToAclFacts([System.Security.AccessControl.FileSystemSecurity]$acl) {
    # Reads only the access section. Neither raw SDDL nor trustee identities leave
    # this function, which returns booleans and integer counts only.
    $access = @($acl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier]))
    $facts = @{
        protected = [bool]$acl.AreAccessRulesProtected
        explicit = 0
        broad_write_allow_explicit = $false
        broad_write_allow_inherited = $false
        broad_write_deny = $false
        other_write_allow_explicit = $false
        unmapped_access_rules = 0
    }
    foreach ($ace in $access) {
        if (-not $ace.IsInherited) { $facts.explicit++ }
        $sid = ''
        try { $sid = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
        catch { $facts.unmapped_access_rules++; continue }
        $canWrite = (([int]$ace.FileSystemRights -band $script:WriteMask) -ne 0)
        if (-not $canWrite) { continue }
        $broad = $script:BroadSids -contains $sid
        if ($broad -and $ace.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
            if ($ace.IsInherited) { $facts.broad_write_allow_inherited = $true }
            else { $facts.broad_write_allow_explicit = $true }
        }
        if ($broad -and $ace.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny) {
            $facts.broad_write_deny = $true
        }
        if (-not $broad -and -not $ace.IsInherited -and
            $ace.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
            $facts.other_write_allow_explicit = $true
        }
    }
    return $facts
}

function Read-ObjectAclFacts([System.IO.FileSystemInfo]$item) {
    $sec = $item.GetAccessControl([System.Security.AccessControl.AccessControlSections]'Access')
    return (Convert-ToAclFacts $sec)
}

function New-Aggregate {
    return @{
        objects = 0; files = 0; directories = 0; reparse_points = 0
        unreadable_objects = 0; unreadable_directories = 0; truncated = $false
        candidate_count = 0; candidate_files = 0; candidate_directories = 0
        protected_dacl_objects = 0; explicit_ace_objects = 0
        broad_write_allow_explicit_objects = 0
        broad_write_allow_inherited_objects = 0
        broad_write_deny_objects = 0
        other_write_allow_explicit_objects = 0
        unmapped_rule_objects = 0
        candidate_by_bucket = [ordered]@{}
        protected_by_bucket = [ordered]@{}
        broad_write_allow_explicit_by_bucket = [ordered]@{}
    }
}

function Add-Count([System.Collections.Specialized.OrderedDictionary]$map,[string]$bucket) {
    if (-not $map.Contains($bucket)) { $map[$bucket] = 0 }
    $map[$bucket] = [int]$map[$bucket] + 1
}

function Measure-GscTree([string]$root,[int]$max) {
    $result = New-Aggregate
    $stack = New-Object System.Collections.Stack
    $stack.Push([System.IO.DirectoryInfo]::new($root))
    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()
        $children = @()
        try { $children = @($directory.GetFileSystemInfos()) }
        catch { $result.unreadable_directories++; continue }
        foreach($item in $children) {
            if ($result.objects -ge $max) { $result.truncated = $true; break }
            $result.objects++
            $isDir = (($item.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0)
            $isReparse = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
            if($isDir) { $result.directories++ } else { $result.files++ }
            if($isReparse) {
                $result.reparse_points++
                continue # no GetAccessControl or traversal of links/junctions
            }
            $bucket = Get-TopBucket $root $item.FullName
            $facts = $null
            try { $facts = Read-ObjectAclFacts $item }
            catch { $result.unreadable_objects++ }
            if($null -ne $facts) {
                if($facts.unmapped_access_rules -gt 0) { $result.unmapped_rule_objects++ }
                if($facts.protected -or $facts.explicit -gt 0) {
                    $result.candidate_count++
                    if($isDir) { $result.candidate_directories++ } else { $result.candidate_files++ }
                    Add-Count $result.candidate_by_bucket $bucket
                    if($facts.protected) {
                        $result.protected_dacl_objects++
                        Add-Count $result.protected_by_bucket $bucket
                    }
                    if($facts.explicit -gt 0) { $result.explicit_ace_objects++ }
                    if($facts.broad_write_allow_explicit) {
                        $result.broad_write_allow_explicit_objects++
                        Add-Count $result.broad_write_allow_explicit_by_bucket $bucket
                    }
                    if($facts.broad_write_allow_inherited) { $result.broad_write_allow_inherited_objects++ }
                    if($facts.broad_write_deny) { $result.broad_write_deny_objects++ }
                    if($facts.other_write_allow_explicit) { $result.other_write_allow_explicit_objects++ }
                }
            }
            if($isDir) { $stack.Push([System.IO.DirectoryInfo]$item) }
        }
        if($result.truncated) { break }
    }
    return $result
}

function Test-Contract {
    $users = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $users,'Read','Allow')
    $acl.AddAccessRule($readRule)
    $readFacts = Convert-ToAclFacts $acl
    if($readFacts.broad_write_allow_explicit) { throw 'READ_RULE_CLASSIFIED_AS_WRITE' }
    $writeRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $users,'Write','Allow')
    $acl.AddAccessRule($writeRule)
    $writeFacts = Convert-ToAclFacts $acl
    if(-not $writeFacts.broad_write_allow_explicit -or $writeFacts.explicit -lt 1) {
        throw 'WRITE_RULE_NOT_IDENTIFIED'
    }
    $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $users,'Write','Deny')
    $acl.AddAccessRule($denyRule)
    if(-not (Convert-ToAclFacts $acl).broad_write_deny) {
        throw 'DENY_RULE_NOT_IDENTIFIED'
    }
    $sample = @{
        schema=1; candidate_count=6; broad_write_allow_explicit_objects=1
        candidate_by_bucket=[ordered]@{Runtime=2;ROOT_CHILD=4}
        final_acl_security_pass=$false; effective_access_verified=$false
    } | ConvertTo-Json -Depth 6 -Compress
    if ($sample -match 'S-1-5-|[a-zA-Z]:\\|agent.properties|\\.json.tmp') {
        throw 'SANITIZED_SHAPE_CONTRACT_FAILED'
    }
    if ((Get-TopBucket 'C:\ProgramData\GeumyiServerCenter' 'C:\ProgramData\GeumyiServerCenter\Runtime\Agent\a.bin') -ne 'Runtime') {
        throw 'BUCKET_SELFTEST_FAILED'
    }
    Write-Host 'EXPLICIT_ACL_REVIEW_SELFTEST_PASS (ACE allow/deny, sanitized counts, buckets)'
}

if ($SelfTest) { Test-Contract; exit 0 }

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'WINDOWS_ONLY' }
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA_MISSING' }
if ($CIFixture) {
    if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GEUMYI_DAY12_EXPLICIT_ACL_CI -ne 'isolated_fixture' -or
        [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or [string]::IsNullOrWhiteSpace($CIFixtureRoot)) {
        throw 'CI_FIXTURE_MODE_REQUIRES_GITHUB_RUNNER'
    }
    $runner = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
    $candidate = [IO.Path]::GetFullPath($CIFixtureRoot)
    if (-not $candidate.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'FIXTURE_OUTSIDE_RUNNER_TEMP_REFUSED'
    }
    $root = $candidate.TrimEnd('\')
} else {
    if (-not [string]::IsNullOrWhiteSpace($CIFixtureRoot)) { throw 'PRODUCTION_ROOT_OVERRIDE_REFUSED' }
    $pd = $env:ProgramData
    if([string]::IsNullOrWhiteSpace($pd) -or [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
        throw 'PROGRAMDATA_OR_SYSTEMDRIVE_MISSING'
    }
    $expectedPD = [IO.Path]::GetFullPath((Join-Path $env:SystemDrive 'ProgramData')).TrimEnd('\')
    if(-not [string]::Equals([IO.Path]::GetFullPath($pd).TrimEnd('\'),$expectedPD,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'NONSTANDARD_PROGRAMDATA_REVIEW_REQUIRED'
    }
    $root = Join-Path $pd 'GeumyiServerCenter'
}

$rootInfo = Get-Item -LiteralPath $root -Force -ErrorAction Stop
if (($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    ($rootInfo.Attributes -band [IO.FileAttributes]::Directory) -eq 0) {
    throw 'GSC_ROOT_UNSAFE_REPARSE_OR_NOT_DIRECTORY'
}
$rootFacts = $null
try { $rootFacts = Convert-ToAclFacts (Get-Acl -LiteralPath $root -ErrorAction Stop) }
catch { throw 'GSC_ROOT_ACL_READ_FAILED' }
$start = Get-Date
$r = Measure-GscTree $root $MaxObjects
$quality = if($r.truncated -or $r.unreadable_objects -gt 0 -or $r.unreadable_directories -gt 0 -or
              $r.unmapped_rule_objects -gt 0 -or $r.reparse_points -gt 0) {
    'BLOCKED_UNVERIFIED'
} else { 'CAPTURED_REVIEW_REQUIRED' }

# IMPORTANT: the output is an allowlist, not an object dump.
$share = [ordered]@{
    schema=1
    phase='12.5-gsc-explicit-acl-review'
    tool='DAY12_GSC_EXPLICIT_ACL_REVIEW_READ_ONLY'
    captured_at=(Get-Date).ToString('o')
    synthetic=[bool]$CIFixture
    duration_seconds=[int]((Get-Date)-$start).TotalSeconds
    objects=$r.objects
    directories=$r.directories
    files=$r.files
    truncated_at_cap=[bool]$r.truncated
    unreadable_objects=$r.unreadable_objects
    unreadable_directories=$r.unreadable_directories
    reparse_points=$r.reparse_points
    unmapped_rule_objects=$r.unmapped_rule_objects
    root_protected_dacl=[bool]$rootFacts.protected
    root_explicit_ace_count=[int]$rootFacts.explicit
    root_broad_write_allow_explicit=[bool]$rootFacts.broad_write_allow_explicit
    root_broad_write_allow_inherited=[bool]$rootFacts.broad_write_allow_inherited
    candidate_count=$r.candidate_count
    candidate_files=$r.candidate_files
    candidate_directories=$r.candidate_directories
    protected_dacl_objects=$r.protected_dacl_objects
    explicit_ace_objects=$r.explicit_ace_objects
    broad_write_allow_explicit_objects=$r.broad_write_allow_explicit_objects
    broad_write_allow_inherited_objects=$r.broad_write_allow_inherited_objects
    broad_write_deny_objects=$r.broad_write_deny_objects
    other_write_allow_explicit_objects=$r.other_write_allow_explicit_objects
    candidate_by_bucket=$r.candidate_by_bucket
    protected_by_bucket=$r.protected_by_bucket
    broad_write_allow_explicit_by_bucket=$r.broad_write_allow_explicit_by_bucket
    effective_access_verified=$false
    effective_standard_user_write_denial_proven=$false
    production_acl_modified=$false
    reparse_points_followed=$false
    names_paths_sids_or_raw_sddl_shared=$false
    evidence_state=$quality
    strict_security_gate='NOT_PASSED'
    note='ACE presence is NOT effective access. No live standard-user create/modify probe was performed. Share counts-only JSON; no production ACL apply is authorized.'
}
$dstDir = Join-Path $env:LOCALAPPDATA 'Geumyi-Day12-ACL-ExplicitReview'
$localRoot = Get-Item -LiteralPath $env:LOCALAPPDATA -Force -ErrorAction Stop
if (($localRoot.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'OUTPUT_PARENT_REPARSE_REFUSED'
}
if (Test-Path -LiteralPath $dstDir) {
    $outItem=Get-Item -LiteralPath $dstDir -Force -ErrorAction Stop
    if (($outItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        ($outItem.Attributes -band [IO.FileAttributes]::Directory) -eq 0) {
        throw 'OUTPUT_DIRECTORY_REPARSE_REFUSED'
    }
} else { [void](New-Item -ItemType Directory -Path $dstDir -ErrorAction Stop) }
$dest = Join-Path $dstDir ('DAY12-GSC-EXPLICIT-ACL-SHARE-ONLY-THIS-' + [guid]::NewGuid().ToString('N') + '.json')
$json = $share | ConvertTo-Json -Depth 8
# Fail before writing any accidental unsanitized evidence.
if($json -match 'S-1-5-|[A-Za-z]:\\|agent.properties|server.json|PRIVATE-|acl_sddl|principal_sid') {
    throw 'SANITIZED_OUTPUT_CONTRACT_REFUSED'
}
$bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
$f = New-Object System.IO.FileStream($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $f.Write($bytes,0,$bytes.Length) } finally { $f.Dispose() }
Write-Host ('EXPLICIT_ACL_REVIEW: ' + $quality + ' objects=' + $r.objects +
            ' candidates=' + $r.candidate_count + ' broad_explicit_write=' +
            $r.broad_write_allow_explicit_objects)
Write-Host ('SHARE ONLY: ' + $dest)
