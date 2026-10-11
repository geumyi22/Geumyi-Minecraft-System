[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$CIFixture,
    [string]$CIFixtureRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Day12.5: PRODUCTION GSC ACL *READ-ONLY* BACKUP.
# Never calls Set-Acl on ProgramData/GSC, never calls icacls /restore,
# /grant, /deny, /reset or inheritance modification on the server.
# Output is a NEW user-profile directory, where only that NEW folder's
# ACL is set to private. Never share the PRIVATE originals or SID/path data.

function Get-TargetRoles([string]$pd) {
    $root = Join-Path $pd 'GeumyiServerCenter'
    $runtime = Join-Path $root 'Runtime'
    $agent = Join-Path $runtime 'Agent'
    @(
        [pscustomobject]@{role='GSC_ROOT';path=$root;required=$true},
        [pscustomobject]@{role='GSC_RUNTIME';path=$runtime;required=$true},
        [pscustomobject]@{role='STATUSAGENT_RUNTIME';path=$agent;required=$true},
        [pscustomobject]@{role='GSC_SERVER_JSON';path=(Join-Path $root 'server.json');required=$true},
        [pscustomobject]@{role='GSC_TRUSTED_DEVICES';path=(Join-Path $root 'trusted-devices.json');required=$false},
        [pscustomobject]@{role='GSC_UPDATES';path=(Join-Path $root 'Updates');required=$false},
        [pscustomobject]@{role='GSC_BACKUPS';path=(Join-Path $root 'Backups');required=$false},
        [pscustomobject]@{role='GSC_STAGING';path=(Join-Path $root 'Staging');required=$false},
        [pscustomobject]@{role='GSC_STAGING_CHILD';path=(Join-Path $root 'Staging\GSC');required=$false},
        [pscustomobject]@{role='STATUSAGENT_JAR';path=(Join-Path $agent 'GeumyiStatusAgent-0.5.4.jar');required=$false}
    )
}

function Test-Contract {
    $roles = @(Get-TargetRoles 'C:\SyntheticProgramData')
    if ($roles.Count -ne 10 -or $roles[0].role -ne 'GSC_ROOT' -or
        $roles[9].role -ne 'STATUSAGENT_JAR' -or
        @($roles | Where-Object { $_.required }).Count -ne 4) {
        throw 'FIXED_TARGET_ROLE_CONTRACT_FAILED'
    }
    if (-not ([System.Security.AccessControl.AccessControlSections]::Access)) {
        throw 'DACL_READ_CONTRACT_FAILED'
    }
    Write-Host 'SELFTEST_PASS: fixed 10-target ACL backup scope and DACL-only metadata'
}

if ($SelfTest) { Test-Contract; exit 0 }

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'LOCALAPPDATA_MISSING'
}
if (-not $CIFixture -and -not [string]::IsNullOrWhiteSpace($CIFixtureRoot)) {
    throw 'FIXTURE_ROOT_NOT_ALLOWED_FOR_REAL_CAPTURE'
}
if ($CIFixture) {
    if ($env:GITHUB_ACTIONS -ne 'true' -or
        $env:GEUMYI_DAY12_ACL_BACKUP_CI -ne 'isolated_fixture' -or
        [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
        [string]::IsNullOrWhiteSpace($CIFixtureRoot)) {
        throw 'CI_FIXTURE_MODE_NOT_AUTHORIZED'
    }
    $runner = [System.IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
    $source = [System.IO.Path]::GetFullPath($CIFixtureRoot).TrimEnd('\') + '\'
    if (-not $source.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
        $source -notmatch 'ACL-Backup-Fixture-[0-9a-f]{32}\\$') {
        throw 'CI_FIXTURE_PATH_NOT_IN_RUNNER_TEMP'
    }
    $pd = $CIFixtureRoot
} else {
    $pd = $env:ProgramData
    if ([string]::IsNullOrWhiteSpace($pd)) {
        throw 'PROGRAMDATA_MISSING'
    }
    # Production cannot be redirected by caller supplied ProgramData path.
    $expected = Join-Path $env:SystemDrive 'ProgramData'
    if (-not [string]::Equals(
        [System.IO.Path]::GetFullPath($pd).TrimEnd('\'),
        [System.IO.Path]::GetFullPath($expected).TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'NONSTANDARD_PROGRAMDATA_ROOT_REQUIRES_MANUAL_REVIEW'
    }
}

$pdItem = Get-Item -LiteralPath $pd -Force -ErrorAction Stop
if (($pdItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'PROGRAMDATA_REPARSE_POINT_REVIEW_REQUIRED'
}
$localItem = Get-Item -LiteralPath $env:LOCALAPPDATA -Force -ErrorAction Stop
if (($localItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'LOCALAPPDATA_REPARSE_POINT_REVIEW_REQUIRED'
}
$icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
if (-not (Test-Path -LiteralPath $icacls -PathType Leaf)) {
    throw 'WINDOWS_ICACLS_NOT_FOUND'
}

# Inspect the exact fixed targets before creating any backup.
$targets = @()
foreach ($row in @(Get-TargetRoles $pd)) {
    $exists = Test-Path -LiteralPath $row.path
    if (-not $exists) {
        if ($row.required) { throw ('REQUIRED_GSC_ACL_TARGET_NOT_FOUND: ' + $row.role) }
        $targets += [pscustomobject]@{role=$row.role;path=$row.path;present=$false}
        continue
    }
    $item = Get-Item -LiteralPath $row.path -Force -ErrorAction Stop
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ('REPARSE_POINT_NOT_SUPPORTED: ' + $row.role)
    }
    $acl = Get-Acl -LiteralPath $row.path -ErrorAction Stop
    $targets += [pscustomobject]@{
        role = $row.role
        path = $row.path
        present = $true
        dacl_before = $acl.GetSecurityDescriptorSddlForm(
            [System.Security.AccessControl.AccessControlSections]::Access)
        sddl_before = $acl.Sddl
        owner_before = $acl.Owner
        inheritance_protected = [bool]$acl.AreAccessRulesProtected
    }
}
$programDataParent = Get-Acl -LiteralPath $pd -ErrorAction Stop
$parentDaclBefore = $programDataParent.GetSecurityDescriptorSddlForm(
    [System.Security.AccessControl.AccessControlSections]::Access)

# PRIVATE originals: new random folder under LOCALAPPDATA, never in GSC.
$outBase = Join-Path $env:LOCALAPPDATA 'Geumyi-Day12-ACL-Backup'
if (Test-Path -LiteralPath $outBase) {
    $existing = Get-Item -LiteralPath $outBase -Force -ErrorAction Stop
    if (($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BACKUP_BASE_REPARSE_POINT_REFUSED'
    }
} else {
    [void](New-Item -ItemType Directory -Path $outBase -ErrorAction Stop)
}
$outDir = Join-Path $outBase ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') +
                            '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[void](New-Item -ItemType Directory -Path $outDir -ErrorAction Stop)

# Restrict ONLY the newly created backup-output folder ACL.
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
if ($null -eq $me) { throw 'USER_IDENTITY_UNAVAILABLE' }
$privateAcl = [System.Security.AccessControl.DirectorySecurity]::new()
$privateAcl.SetAccessRuleProtection($true,$false)
$privateAcl.SetOwner($me)
foreach ($id in @($me.Value,'S-1-5-18','S-1-5-32-544')) {
    $sid=[System.Security.Principal.SecurityIdentifier]::new($id)
    $ace=[System.Security.AccessControl.FileSystemAccessRule]::new(
        $sid,[System.Security.AccessControl.FileSystemRights]::FullControl,
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
         [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow)
    $privateAcl.AddAccessRule($ace)
}
Set-Acl -LiteralPath $outDir -AclObject $privateAcl -ErrorAction Stop
if (-not (Get-Acl -LiteralPath $outDir).AreAccessRulesProtected) {
    throw 'BACKUP_OUTPUT_FOLDER_NOT_PROTECTED'
}

$entries=@()
$success=0
$absent=0
foreach ($row in $targets) {
    if (-not $row.present) {
        $absent++
        $entries += [ordered]@{role=$row.role;present=$false;archive=$null}
        continue
    }
    # Save precisely ONE target DACL per archive, with NO /T recursive scan.
    # This does not preserve owner/SACL; private manifest keeps original SDDL.
    $archive = Join-Path $outDir ('PRIVATE-' + $row.role + '.dacl')
    & $icacls $row.path /save $archive | Out-Null
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        throw ('ICACLS_DACL_SAVE_FAILED: ' + $row.role)
    }
    $archiveItem = Get-Item -LiteralPath $archive
    if ($archiveItem.Length -lt 10) {
        throw ('ICACLS_EMPTY_DACL_ARCHIVE: ' + $row.role)
    }
    $savedHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $after = (Get-Acl -LiteralPath $row.path -ErrorAction Stop).
        GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
    if ($after -ne $row.dacl_before) {
        throw ('GSC_DACL_CHANGED_DURING_READONLY_SNAPSHOT: ' + $row.role)
    }
    $entries += [ordered]@{
        role=$row.role
        present=$true
        actual_path=$row.path
        restore_parent=([System.IO.Directory]::GetParent($row.path)).FullName
        archive_name=[System.IO.Path]::GetFileName($archive)
        archive_sha256=$savedHash
        archive_size=$archiveItem.Length
        original_dacl_sddl=$row.dacl_before
        original_sddl=$row.sddl_before
        original_owner=$row.owner_before
        original_inheritance_protected=$row.inheritance_protected
    }
    $success++
}
$parentDaclAfter = (Get-Acl -LiteralPath $pd -ErrorAction Stop).
    GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
if ($parentDaclAfter -ne $parentDaclBefore) {
    throw 'PARENT_DACL_CHANGED_DURING_READONLY_SNAPSHOT'
}

$privateManifest = [ordered]@{
    schema=1
    kind='PRIVATE_LOCAL_DACL_BACKUP_METADATA'
    captured_at=(Get-Date).ToString('o')
    source=if($CIFixture){'ISOLATED_CI_FIXTURE'}else{'REAL_SERVER_WINDOWS_ACL'}
    parent_programdata_path=$pd
    parent_dacl_sddl=$parentDaclBefore
    entries=$entries
    warning='Do not share. DACL archives are not full security-descriptor backups. No live restore performed. Restoring any production ACL requires separate explicit approval and verified target/parent path.'
}
$privateManifestPath=Join-Path $outDir 'PRIVATE-ACL-BACKUP-MANIFEST-DO-NOT-SHARE.json'
$privateManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $privateManifestPath -Encoding UTF8

$share = [ordered]@{
    schema=1
    phase='12.5-production-acl-original-backup'
    tool='DAY12_GSC_ACL_ORIGINAL_BACKUP_READ_ONLY'
    captured_at=(Get-Date).ToString('o')
    synthetic=[bool]$CIFixture
    production_acl_modified=$false
    gsc_service_restarted=$false
    firewall_modified=$false
    server_or_world_or_golden_backup_modified=$false
    private_archive_files_created_under_localappdata=$true
    backup_output_directory_acl_restricted=$true
    private_sddl_paths_or_sids_shared=$false
    scoped_role_count=$targets.Count
    captured_archive_count=$success
    optional_missing_count=$absent
    parent_acl_unchanged_during_backup=$true
    target_acls_unchanged_during_backup=$true
    real_production_restore_performed=$false
    snapshot_contains_dacl_only=$true
    independent_standard_user_tested=$false
    strict_security_gate='NOT_PASSED'
    status=if($CIFixture){'CI_FIXTURE_BACKUP_PASS'}else{'LOCAL_BACKUP_CAPTURED_NOT_RESTORED'}
    note='Do not upload the PRIVATE manifest or *.dacl. Before any ACL change, exact live parent/ACE mapping and safe rollback acceptance remain mandatory.'
}
$sharePath=Join-Path $outDir 'DAY12-ACL-BACKUP-SHARE-ONLY-THIS.json'
$share | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sharePath -Encoding UTF8

Write-Host ('ACL_BACKUP: '+$share.status)
Write-Host ('Targets: '+$targets.Count+'; backup archives: '+$success+'; optional missing: '+$absent)
Write-Host ('SHARE ONLY: '+$sharePath)
Write-Host 'PRIVATE files (*.dacl, PRIVATE-*.json) must remain on this PC.'
