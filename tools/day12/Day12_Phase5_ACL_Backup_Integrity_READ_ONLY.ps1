[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$CIFixture,
    [string]$CIFixtureRoot = '',
    [string]$BackupDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# On-host audit of PRIVATE Day12.5 ACL originals. Reads live GSC DACLs
# and local saved archive metadata; NEVER changes any production ACL.
# No private SDDL, account, SID, path, or archive hash enters the share JSON.
function Get-TargetRoles([string]$pd) {
    $root = Join-Path $pd 'GeumyiServerCenter'
    $runtime = Join-Path $root 'Runtime'
    $agent = Join-Path $runtime 'Agent'
    @(
        [pscustomobject]@{role='GSC_ROOT';path=$root},
        [pscustomobject]@{role='GSC_RUNTIME';path=$runtime},
        [pscustomobject]@{role='STATUSAGENT_RUNTIME';path=$agent},
        [pscustomobject]@{role='GSC_SERVER_JSON';path=(Join-Path $root 'server.json')},
        [pscustomobject]@{role='GSC_TRUSTED_DEVICES';path=(Join-Path $root 'trusted-devices.json')},
        [pscustomobject]@{role='GSC_UPDATES';path=(Join-Path $root 'Updates')},
        [pscustomobject]@{role='GSC_BACKUPS';path=(Join-Path $root 'Backups')},
        [pscustomobject]@{role='GSC_STAGING';path=(Join-Path $root 'Staging')},
        [pscustomobject]@{role='GSC_STAGING_CHILD';path=(Join-Path $root 'Staging\GSC')},
        [pscustomobject]@{role='STATUSAGENT_JAR';path=(Join-Path $agent 'GeumyiStatusAgent-0.5.4.jar')}
    )
}
function Same-Path([string]$a,[string]$b) {
    return [string]::Equals(
        [System.IO.Path]::GetFullPath($a).TrimEnd('\'),
        [System.IO.Path]::GetFullPath($b).TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)
}
function Assert-PlainItem([string]$path,[string]$label) {
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ('REPARSE_POINT_BLOCKED_'+$label)
    }
}
function Dacl([string]$path) {
    return (Get-Acl -LiteralPath $path -ErrorAction Stop).
        GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
}
$roles=@(Get-TargetRoles 'C:\SyntheticProgramData')
if ($SelfTest) {
    if ($roles.Count -ne 10 -or
        @($roles|Select-Object -ExpandProperty role -Unique).Count -ne 10 -or
        $roles[0].role -ne 'GSC_ROOT' -or
        $roles[9].role -ne 'STATUSAGENT_JAR') {
        throw 'INTEGRITY_FIXED_TARGET_CONTRACT_FAILED'
    }
    Write-Host 'INTEGRITY_SELFTEST_PASS: 10 fixed roles; source remains read-only'
    exit 0
}
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'LOCALAPPDATA_MISSING'
}
if ($CIFixture) {
    if ($env:GITHUB_ACTIONS -ne 'true' -or
        $env:GEUMYI_DAY12_ACL_BACKUP_CI -ne 'isolated_fixture' -or
        [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
        [string]::IsNullOrWhiteSpace($CIFixtureRoot)) {
        throw 'INTEGRITY_CI_FIXTURE_NOT_AUTHORIZED'
    }
    $runner=[System.IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\'
    $source=[System.IO.Path]::GetFullPath($CIFixtureRoot).TrimEnd('\')+'\'
    if (-not $source.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
        $source -notmatch 'ACL-Backup-Fixture-[0-9a-f]{32}\\$') {
        throw 'INTEGRITY_CI_FIXTURE_OUT_OF_SCOPE'
    }
    $pd=$CIFixtureRoot
    $manifestSource='ISOLATED_CI_FIXTURE'
} else {
    if (-not [string]::IsNullOrWhiteSpace($CIFixtureRoot)) {
        throw 'INTEGRITY_PRODUCTION_FIXTURE_OVERRIDE_BLOCKED'
    }
    if ([string]::IsNullOrWhiteSpace($env:ProgramData) -or
        [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
        throw 'PROGRAMDATA_MISSING'
    }
    $pd=$env:ProgramData
    if (-not (Same-Path $pd (Join-Path $env:SystemDrive 'ProgramData'))) {
        throw 'NONSTANDARD_PROGRAMDATA_REVIEW_REQUIRED'
    }
    $manifestSource='REAL_SERVER_WINDOWS_ACL'
}
Assert-PlainItem $pd 'PROGRAMDATA'
Assert-PlainItem $env:LOCALAPPDATA 'LOCALAPPDATA'

$base=Join-Path $env:LOCALAPPDATA 'Geumyi-Day12-ACL-Backup'
Assert-PlainItem $base 'BACKUP_BASE'
if ([string]::IsNullOrWhiteSpace($BackupDir)) {
    $matches=@(Get-ChildItem -LiteralPath $base -Directory -Filter 'backup-*' -ErrorAction Stop |
        Where-Object { $_.Name -match '^backup-\d{8}-\d{6}-[0-9a-fA-F]{8}$' } |
        Sort-Object Name -Descending)
    if ($matches.Count -lt 1) { throw 'PRIVATE_BACKUP_DIRECTORY_MISSING' }
    $BackupDir=$matches[0].FullName
}
Assert-PlainItem $BackupDir 'SELECTED_BACKUP'
if (-not (Same-Path (Split-Path -Path $BackupDir -Parent) $base) -or
    (Split-Path -Path $BackupDir -Leaf) -notmatch '^backup-\d{8}-\d{6}-[0-9a-fA-F]{8}$') {
    throw 'BACKUP_DIRECTORY_OUT_OF_SCOPE'
}
$backupAcl=Get-Acl -LiteralPath $BackupDir -ErrorAction Stop
if (-not $backupAcl.AreAccessRulesProtected) {
    throw 'PRIVATE_BACKUP_DIRECTORY_NOT_PROTECTED'
}
$me=[System.Security.Principal.WindowsIdentity]::GetCurrent().User
if ($null -eq $me) { throw 'CURRENT_USER_ID_MISSING' }
if (-not [string]::Equals(
    $backupAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value,
    $me.Value,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'PRIVATE_BACKUP_DIRECTORY_OWNER_MISMATCH'
}
foreach($ace in $backupAcl.Access) {
    $sid='UNRESOLVED'
    try { $sid=$ace.IdentityReference.Translate(
        [System.Security.Principal.SecurityIdentifier]).Value } catch {}
    if ($sid -notin @($me.Value,'S-1-5-18','S-1-5-32-544')) {
        throw 'PRIVATE_BACKUP_DIRECTORY_UNEXPECTED_ACE'
    }
}

$manifestPath=Join-Path $BackupDir 'PRIVATE-ACL-BACKUP-MANIFEST-DO-NOT-SHARE.json'
Assert-PlainItem $manifestPath 'PRIVATE_MANIFEST'
$m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($m.schema -ne 1 -or $m.kind -ne 'PRIVATE_LOCAL_DACL_BACKUP_METADATA' -or
    $m.source -ne $manifestSource -or -not (Same-Path $m.parent_programdata_path $pd) -or
    @($m.entries).Count -ne 10) {
    throw 'PRIVATE_MANIFEST_CONTRACT_MISMATCH'
}
if ((Dacl $pd) -cne [string]$m.parent_dacl_sddl) {
    throw 'PARENT_DACL_DRIFT_BLOCKED'
}

$verified=0
$summary=@()
$actualRoles=@(Get-TargetRoles $pd)
foreach ($expected in $actualRoles) {
    $entry=@($m.entries|Where-Object { $_.role -eq $expected.role })
    if ($entry.Count -ne 1 -or -not [bool]$entry[0].present) {
        throw ('EXPECTED_BACKUP_ROLE_MISSING_'+$expected.role)
    }
    $e=$entry[0]
    if (-not (Same-Path $e.actual_path $expected.path) -or
        -not (Same-Path $e.restore_parent (Split-Path -Path $expected.path -Parent)) -or
        $e.archive_name -cne ('PRIVATE-'+$expected.role+'.dacl') -or
        [string]$e.archive_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw ('BACKUP_ROLE_PATH_OR_ARCHIVE_MISMATCH_'+$expected.role)
    }
    Assert-PlainItem $expected.path ('TARGET_'+$expected.role)
    $archive=Join-Path $BackupDir $e.archive_name
    Assert-PlainItem $archive ('ARCHIVE_'+$expected.role)
    $info=Get-Item -LiteralPath $archive -Force -ErrorAction Stop
    $hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($hash -ine [string]$e.archive_sha256 -or $info.Length -ne [long]$e.archive_size) {
        throw ('BACKUP_ARCHIVE_INTEGRITY_BLOCKED_'+$expected.role)
    }
    $acl=Get-Acl -LiteralPath $expected.path -ErrorAction Stop
    if ($acl.GetSecurityDescriptorSddlForm(
        [System.Security.AccessControl.AccessControlSections]::Access) -cne
            [string]$e.original_dacl_sddl -or
        $acl.AreAccessRulesProtected -ne [bool]$e.original_inheritance_protected -or
        $acl.Owner -cne [string]$e.original_owner) {
        throw ('LIVE_ACL_DRIFT_BLOCKED_'+$expected.role)
    }
    $inherited=0; $explicit=0; $unresolved=0
    $create=[int]([System.Security.AccessControl.FileSystemRights]::CreateFiles -bor
                   [System.Security.AccessControl.FileSystemRights]::CreateDirectories)
    foreach ($ace in $acl.Access) {
        $sid='UNRESOLVED'
        try { $sid=$ace.IdentityReference.Translate(
            [System.Security.Principal.SecurityIdentifier]).Value } catch { $unresolved++ }
        if ($sid -eq 'S-1-5-32-545' -and
            $ace.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
            (([int]$ace.FileSystemRights -band $create) -ne 0)) {
            if ($ace.IsInherited) { $inherited++ } else { $explicit++ }
        }
    }
    $summary+= [ordered]@{
        role=$expected.role
        builtin_users_create_inherited_allow_ace_count=$inherited
        builtin_users_create_explicit_allow_ace_count=$explicit
        unresolved_principal_ace_count=$unresolved
    }
    $verified++
}
if ($verified -ne 10) { throw 'TEN_TARGET_INTEGRITY_CHECK_INCOMPLETE' }

# Store only redacted counts. Never write PRIVATE manifest/SDDL/hashes anywhere else.
$report=[ordered]@{
    schema=1
    phase='12.5-acl-backup-local-integrity'
    tool='DAY12_GSC_ACL_BACKUP_INTEGRITY_READ_ONLY'
    captured_at=(Get-Date).ToString('o')
    synthetic=[bool]$CIFixture
    archive_hashes_verified=$verified
    unchanged_live_target_acls=$verified
    parent_dacl_unchanged=$true
    private_backup_directory_protected=$true
    production_acl_modified=$false
    real_production_restore_performed=$false
    independent_standard_user_tested=$false
    exact_ace_delta_approved=$false
    raw_sddl_sid_paths_or_hashes_shared=$false
    strict_security_gate='NOT_PASSED'
    status='BACKUP_INTEGRITY_AND_CURRENT_DACL_VERIFIED_NOT_RESTORED'
    targets=$summary
    note='Local DACL and hashes match the private backup. This cannot certify production restoration, effective permissions, or an approved ACL change.'
}
$out=Join-Path $BackupDir ('DAY12-ACL-INTEGRITY-SHARE-ONLY-THIS-'+
                           [guid]::NewGuid().ToString('N')+'.json')
$shareText=$report|ConvertTo-Json -Depth 7
$utf8=[System.Text.UTF8Encoding]::new($false)
$bytes=$utf8.GetBytes($shareText)
$stream=[System.IO.FileStream]::new($out,[System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
Write-Host ('BACKUP_INTEGRITY: '+$report.status)
Write-Host ('Archives/hash/current DACL: '+$verified+'/10; strict gate: NOT_PASSED')
Write-Host ('SHARE ONLY: '+$out)
Write-Host 'PRIVATE-*.dacl and PRIVATE-*.json remain local. No production ACL changed.'
