[CmdletBinding()]
param([switch]$Synthetic)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ONLY a disposable Windows GitHub Actions fixture. NEVER use on an operator PC.
# The script changes ACLs only on a new GUID directory in RUNNER_TEMP.
if (-not $Synthetic -or $env:GITHUB_ACTIONS -ne 'true' -or
    $env:GEUMYI_DAY12_ACL_REHEARSAL_CI -ne 'isolated_fixture' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'CI_ONLY_DISPOSABLE_ACL_REHEARSAL_REFUSED'
}
$runnerRoot = (Resolve-Path -LiteralPath $env:RUNNER_TEMP -ErrorAction Stop).Path
if (-not [System.IO.Path]::IsPathRooted($runnerRoot) -or
    ($runnerRoot -match '^[A-Za-z]:\\?$')) {
    throw 'RUNNER_TEMP_IS_UNSAFE'
}

$base = Join-Path $runnerRoot ('Geumyi-ACL-Isolated-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $base -ErrorAction Stop | Out-Null
$parent = Join-Path $base 'SyntheticProgramData'
$gsc = Join-Path $parent 'GeumyiServerCenter'
$runtime = Join-Path $gsc 'Runtime'
$agent = Join-Path $runtime 'Agent'
$updates = Join-Path $gsc 'Updates'
$backups = Join-Path $gsc 'Backups'
$staging = Join-Path $gsc 'Staging'
$stageChild = Join-Path $staging 'GSC'
$targets = @($gsc,$runtime,$agent,$updates,$backups,$staging,$stageChild)
$usersSID = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
$systemSID = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$adminsSID = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$currentSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
           [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$propagate = [System.Security.AccessControl.PropagationFlags]::None
$allow = [System.Security.AccessControl.AccessControlType]::Allow
$full = [System.Security.AccessControl.FileSystemRights]::FullControl
$read = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
$create = ([System.Security.AccessControl.FileSystemRights]::CreateFiles -bor
           [System.Security.AccessControl.FileSystemRights]::CreateDirectories)
$fixtureRight = [System.Security.AccessControl.FileSystemRights]([int]$read -bor [int]$create)

function Find-UsersAllows([string]$path) {
    $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
    return @($acl.Access | Where-Object {
        $sid='UNRESOLVED'
        try { $sid=$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch {}
        $sid -eq 'S-1-5-32-545' -and $_.AccessControlType -eq
             [System.Security.AccessControl.AccessControlType]::Allow
    })
}

function Get-DaclSddl([string]$path) {
    $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
    return $acl.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
}

function Assert-Fixture-SafePath([string]$path) {
    $fullPath = [System.IO.Path]::GetFullPath($path)
    $basePrefix = [System.IO.Path]::GetFullPath($base).TrimEnd('\')+'\'
    if (-not $fullPath.StartsWith($basePrefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'OUT_OF_DISPOSABLE_FIXTURE_PATH'
    }
}

try {
    foreach ($dir in @($parent) + $targets) {
        Assert-Fixture-SafePath $dir
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    }

    # Synthesize the specific inherited Users create-write condition from the
    # real report. Explicitly control this NEW parent, not actual ProgramData.
    $parentAcl = [System.Security.AccessControl.DirectorySecurity]::new()
    $parentAcl.SetAccessRuleProtection($true,$false)
    foreach ($pair in @(
        [pscustomobject]@{Sid=$currentSID;Rights=$full},
        [pscustomobject]@{Sid=$systemSID;Rights=$full},
        [pscustomobject]@{Sid=$adminsSID;Rights=$full},
        [pscustomobject]@{Sid=$usersSID;Rights=$fixtureRight}
    )) {
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $pair.Sid,$pair.Rights,$inherit,$propagate,$allow)
        $parentAcl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $parent -AclObject $parentAcl -ErrorAction Stop

    $initialParent = Get-DaclSddl $parent
    $before = @{}
    foreach ($p in $targets) {
        $before[$p]=Get-DaclSddl $p
        $u = @(Find-UsersAllows $p)
        if ($u.Count -ne 1 -or -not $u[0].IsInherited -or
            (([int]$u[0].FileSystemRights -band [int]$create) -ne [int]$create)) {
            throw ('EXPECTED_SINGLE_INHERITED_USERS_CREATE_ALLOW_NOT_FOUND: '+$p)
        }
    }

    # Real icacls backup/restore rehearsal; only disposable fixture paths.
    $backupPath=Join-Path $base 'acl-fixture-original.dat'
    & icacls.exe $gsc /save $backupPath /T
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw 'ISOLATED_ICACLS_SAVE_FAILED'
    }
    $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash

    # PROPOSAL REHEARSAL (NOT operator ACL apply):
    # Stop inheriting root rights but preserve other existing ACEs and modify
    # ONLY the single known Users allow; keep all Users read/execute bits.
    $a = Get-Acl -LiteralPath $gsc -ErrorAction Stop
    $a.SetAccessRuleProtection($true,$true)
    $eligible = @($a.Access | Where-Object {
        $sid='UNRESOLVED'
        try { $sid=$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch {}
        $sid -eq 'S-1-5-32-545' -and $_.AccessControlType -eq $allow -and
        (([int]$_.FileSystemRights -band [int]$create) -eq [int]$create)
    })
    if ($eligible.Count -ne 1) { throw 'UNEXPECTED_USERS_RIGHTS_SHAPE' }
    $oldRule=$eligible[0]
    $newMask = ([int]$oldRule.FileSystemRights -band (-bnot [int]$create))
    # RemoveAccessRuleSpecific returns void; validate the post-change ACL below.
    $a.RemoveAccessRuleSpecific($oldRule)
    if ($newMask -ne 0) {
        $replacement = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $oldRule.IdentityReference,
            [System.Security.AccessControl.FileSystemRights]$newMask,
            $oldRule.InheritanceFlags,
            $oldRule.PropagationFlags,
            $allow)
        $a.AddAccessRule($replacement)
    }
    Set-Acl -LiteralPath $gsc -AclObject $a -ErrorAction Stop

    if ((Get-DaclSddl $parent) -ne $initialParent) {
        throw 'PARENT_PROGRAMDATA_FIXTURE_CHANGED'
    }
    $gscACL = Get-Acl -LiteralPath $gsc -ErrorAction Stop
    if (-not $gscACL.AreAccessRulesProtected) {
        throw 'GSC_ROOT_INHERITANCE_STILL_ENABLED'
    }
    foreach ($p in $targets) {
        $u=@(Find-UsersAllows $p)
        if (@($u|Where-Object {
            (([int]$_.FileSystemRights -band [int]$create) -ne 0)
        }).Count -ne 0) {
            throw ('USERS_CREATE_RIGHT_STILL_PRESENT_IN_STAGING: '+$p)
        }
        if (@($u|Where-Object {
            (([int]$_.FileSystemRights -band [int]$read) -ne [int]$read)
        }).Count -ne 0 -or $u.Count -eq 0) {
            throw ('USERS_READ_AND_TRAVERSE_LOST_IN_STAGING: '+$p)
        }
    }

    # Restore ONLY disposable fixture. Always compare exact DACL-only SDDL
    # and parent scope after OS restore; do not trust exit-code alone.
    & icacls.exe $parent /restore $backupPath
    if ($LASTEXITCODE -ne 0) { throw 'ISOLATED_ICACLS_RESTORE_FAILED' }
    foreach ($p in $targets) {
        if ((Get-DaclSddl $p) -ne $before[$p]) {
            throw ('ISOLATED_ROLLBACK_SDDL_MISMATCH: '+$p)
        }
    }
    if ((Get-DaclSddl $parent) -ne $initialParent) {
        throw 'PARENT_DACL_CHANGED_AFTER_ISOLATED_RESTORE'
    }
    Write-Host 'DAY12_ACL_LEAST_PRIVILEGE_DISPOSABLE_REHEARSAL_PASS'
    Write-Host ('Fixture paths checked: '+$targets.Count+
                '; original archive SHA256: '+$backupHash.ToLowerInvariant())
    Write-Host 'NO production ACL or Windows service was touched.'
} finally {
    # Cleanup is permitted ONLY inside a new GUID directory under RUNNER_TEMP.
    if (Test-Path -LiteralPath $base) {
        $verified = [System.IO.Path]::GetFullPath($base)
        $runnerPrefix = $runnerRoot.TrimEnd('\')+'\'
        if ($verified.StartsWith($runnerPrefix,[StringComparison]::OrdinalIgnoreCase) -and
            $verified -match 'Geumyi-ACL-Isolated-[0-9a-f]{32}$') {
            Remove-Item -LiteralPath $verified -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
