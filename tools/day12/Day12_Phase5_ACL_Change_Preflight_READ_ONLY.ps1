[CmdletBinding()]
param([switch]$SelfTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Production read-only: reads only GSC ACLs and Host service identity class.
# Writes ONLY two evidence files inside a newly created private LOCALAPPDATA folder.
# It never changes ACLs on GSC, ProgramData, services, firewall or Minecraft.
# PRIVATE-ACL-SDDL-SNAPSHOT-DO-NOT-SHARE.json must stay on the operator PC.

function Target-Definitions([string]$pd) {
    $gsc = Join-Path $pd 'GeumyiServerCenter'
    $runtime = Join-Path $gsc 'Runtime'
    $agent = Join-Path $runtime 'Agent'
    @(
        [pscustomobject]@{Role='PROGRAMDATA_PARENT'; Path=$pd; Required=$true},
        [pscustomobject]@{Role='GSC_ROOT'; Path=$gsc; Required=$true},
        [pscustomobject]@{Role='GSC_RUNTIME'; Path=$runtime; Required=$true},
        [pscustomobject]@{Role='STATUSAGENT_RUNTIME'; Path=$agent; Required=$true},
        [pscustomobject]@{Role='GSC_SERVER_JSON'; Path=(Join-Path $gsc 'server.json'); Required=$true},
        [pscustomobject]@{Role='GSC_TRUSTED_DEVICES'; Path=(Join-Path $gsc 'trusted-devices.json'); Required=$false},
        [pscustomobject]@{Role='GSC_UPDATES'; Path=(Join-Path $gsc 'Updates'); Required=$false},
        [pscustomobject]@{Role='GSC_BACKUPS'; Path=(Join-Path $gsc 'Backups'); Required=$false},
        [pscustomobject]@{Role='GSC_STAGING'; Path=(Join-Path $gsc 'Staging'); Required=$false},
        [pscustomobject]@{Role='GSC_STAGING_CHILD'; Path=(Join-Path $gsc 'Staging\GSC'); Required=$false},
        [pscustomobject]@{Role='STATUSAGENT_JAR'; Path=(Join-Path $agent 'GeumyiStatusAgent-0.5.4.jar'); Required=$false}
    )
}

function Principal-Sid($rule) {
    try {
        return $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        return 'UNRESOLVED'
    }
}

function Read-Target([object]$target) {
    $public = [ordered]@{
        role = [string]$target.Role
        required = [bool]$target.Required
        exists = $false
        reparse_point = $false
        result = 'NOT_PRESENT'
        inherited_ace_source_review = $false
        users_create_allow_ace_count = 0
        users_inherited_create_allow_ace_count = 0
        users_direct_write_allow_ace_count = 0
        unknown_sid_ace_count = 0
        acl_inheritance_enabled = $null
    }
    $private = [ordered]@{
        role = [string]$target.Role
        path = [string]$target.Path
        exists = $false
        acl_sddl = $null
        owner = $null
        access_rules = @()
    }
    try {
        $item = Get-Item -LiteralPath $target.Path -Force -ErrorAction Stop
        $public.exists = $true
        $private.exists = $true
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $public.reparse_point = $true
            $public.result = 'REPARSE_POINT_REVIEW_REQUIRED'
            return [pscustomobject]@{Public=$public; Private=$private}
        }
        $acl = Get-Acl -LiteralPath $target.Path -ErrorAction Stop
        $public.result = 'DACL_CAPTURED_REVIEW_ONLY'
        $public.acl_inheritance_enabled = -not [bool]$acl.AreAccessRulesProtected
        $private.acl_sddl = [string]$acl.Sddl
        $private.owner = [string]$acl.Owner
        $rules = @()
        foreach ($ace in @($acl.Access)) {
            $sid = Principal-Sid $ace
            $rights = [int]$ace.FileSystemRights
            $rule = [ordered]@{
                principal_sid = $sid
                rights = [string]$ace.FileSystemRights
                rights_mask = $rights
                type = [string]$ace.AccessControlType
                inherited = [bool]$ace.IsInherited
                inheritance_flags = [string]$ace.InheritanceFlags
                propagation_flags = [string]$ace.PropagationFlags
            }
            $rules += $rule
            if ($sid -eq 'UNRESOLVED') { $public.unknown_sid_ace_count++ }
            if ($sid -ne 'S-1-5-32-545' -or $rule.type -ne 'Allow') { continue }
            $addFile = [int][System.Security.AccessControl.FileSystemRights]::CreateFiles
            $addDir = [int][System.Security.AccessControl.FileSystemRights]::CreateDirectories
            $writeData = [int][System.Security.AccessControl.FileSystemRights]::WriteData
            $canCreate = ((($rights -band $addFile) -ne 0) -or (($rights -band $addDir) -ne 0))
            if ($canCreate) {
                $public.users_create_allow_ace_count++
                if ($rule.inherited) { $public.users_inherited_create_allow_ace_count++ }
            }
            if (($rights -band $writeData) -ne 0) { $public.users_direct_write_allow_ace_count++ }
        }
        $private.access_rules = @($rules)
        $public.inherited_ace_source_review = [bool]($public.users_inherited_create_allow_ace_count -gt 0)
    } catch {
        $public.result = 'ACL_READ_OR_OBJECT_ERROR'
    }
    return [pscustomobject]@{Public=$public;Private=$private}
}

function Test-Contract {
    $defs = @(Target-Definitions 'C:\SyntheticProgramData')
    $names = @($defs | ForEach-Object { $_.Role })
    $expected = @('PROGRAMDATA_PARENT','GSC_ROOT','GSC_RUNTIME',
                  'STATUSAGENT_RUNTIME','GSC_SERVER_JSON','GSC_TRUSTED_DEVICES',
                  'GSC_UPDATES','GSC_BACKUPS','GSC_STAGING','GSC_STAGING_CHILD',
                  'STATUSAGENT_JAR')
    if ($names.Count -ne $expected.Count -or (($names -join '|') -ne ($expected -join '|'))) {
        throw 'ACL_ROLE_MAPPING_SELFTEST_FAILED'
    }
    $synthetic = [ordered]@{role='GSC_ROOT';result='DACL_CAPTURED_REVIEW_ONLY';users_create_allow_ace_count=1}
    $text = $synthetic | ConvertTo-Json -Compress
    if ($text -match 'C:\\|S-1-5-' -or $text -notmatch 'DACL_CAPTURED_REVIEW_ONLY') {
        throw 'SANITIZED_SUMMARY_SELFTEST_FAILED'
    }
    Write-Host 'SELFTEST_PASS: ACL role contract and sanitized summary shape'
}

if ($SelfTest) { Test-Contract; exit 0 }

if ([string]::IsNullOrWhiteSpace($env:ProgramData) -or
    [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'PROGRAMDATA_OR_LOCALAPPDATA_MISSING'
}
$rootInfo = Get-Item -LiteralPath $env:LOCALAPPDATA -Force -ErrorAction Stop
if (($rootInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'LOCALAPPDATA_REPARSE_POINT_REVIEW_REQUIRED'
}

# Private metadata is created only in a newly created output folder.
$time = Get-Date
$stamp = $time.ToString('yyyyMMdd-HHmmss')
$outBase = Join-Path $env:LOCALAPPDATA 'Geumyi-Day12-ACL-Preflight'
if (-not (Test-Path -LiteralPath $outBase -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $outBase -ErrorAction Stop)
}
$outDir = Join-Path $outBase ($stamp + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
[void](New-Item -ItemType Directory -Path $outDir -ErrorAction Stop)

# Restrict the NEW evidence directory only. GSC/ProgramData ACLs are never edited.
$currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
if ($null -eq $currentSid) { throw 'CURRENT_USER_SID_UNAVAILABLE' }
$privateAcl = New-Object System.Security.AccessControl.DirectorySecurity
$privateAcl.SetAccessRuleProtection($true, $false)
$privateAcl.SetOwner($currentSid)
foreach ($sidString in @($currentSid.Value, 'S-1-5-18', 'S-1-5-32-544')) {
    $sid = [System.Security.Principal.SecurityIdentifier]::new($sidString)
    $entry = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $sid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $privateAcl.AddAccessRule($entry)
}
Set-Acl -LiteralPath $outDir -AclObject $privateAcl -ErrorAction Stop
if (-not ((Get-Acl -LiteralPath $outDir).AreAccessRulesProtected)) {
    throw 'EVIDENCE_DIRECTORY_NOT_PROTECTED'
}

$serviceResult = 'SERVICE_QUERY_UNAVAILABLE'
try {
    $s = Get-CimInstance -ClassName Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
    if ($null -eq $s) { $serviceResult = 'SERVICE_NOT_FOUND' }
    elseif ([string]$s.StartName -match '^(LocalSystem|NT AUTHORITY\\SYSTEM)$') {
        $serviceResult = 'LOCAL_SYSTEM'
    } else { $serviceResult = 'NON_SYSTEM_ACCOUNT_REVIEW' }
} catch { $serviceResult = 'SERVICE_QUERY_UNAVAILABLE' }

$summary = @()
$privateTargets = @()
foreach ($item in @(Target-Definitions $env:ProgramData)) {
    $rec = Read-Target $item
    $summary += $rec.Public
    $privateTargets += $rec.Private
}
$missingRequired = @($summary | Where-Object { $_.required -and $_.result -ne 'DACL_CAPTURED_REVIEW_ONLY' }).Count
$reparse = @($summary | Where-Object { $_.reparse_point }).Count
$unresolved = @($summary | Where-Object { $_.unknown_sid_ace_count -gt 0 }).Count

$privateReport = [ordered]@{
    schema=1
    kind='LOCAL_ONLY_SDDL_PREDEPLOY_EVIDENCE_NOT_RESTORE_ARCHIVE'
    captured_at=$time.ToString('o')
    service_name='Geumyi Server Center Host'
    service_account_class=$serviceResult
    targets=$privateTargets
}
$privatePath = Join-Path $outDir 'PRIVATE-ACL-SDDL-SNAPSHOT-DO-NOT-SHARE.json'
$privateReport | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $privatePath -Encoding UTF8 -ErrorAction Stop

$share = [ordered]@{
    schema=1
    phase='12.5-acl-change-preflight'
    tool='DAY12_GSC_ACL_PREDEPLOY_READONLY'
    captured_at=$time.ToString('o')
    synthetic=$false
    production_acl_modified=$false
    gsc_service_modified=$false
    firewall_modified=$false
    worlds_or_backups_modified=$false
    output_directory_created_under_localappdata=$true
    output_directory_acl_restricted=$true
    raw_sddl_or_paths_shared=$false
    independent_standard_user_proven=$false
    mandatory_integrity_and_actual_file_create_not_tested=$true
    service_account_class=$serviceResult
    targets=$summary
    required_targets_unverified=$missingRequired
    reparse_targets=$reparse
    unresolved_sid_targets=$unresolved
    evidence_state=if($missingRequired -eq 0 -and $reparse -eq 0 -and $unresolved -eq 0 -and
                      $serviceResult -eq 'LOCAL_SYSTEM') { 'PREDEPLOY_ACL_EVIDENCE_CAPTURED' }
                   else { 'REVIEW_REQUIRED' }
    final_acl_security_pass=$false
    exact_ace_mutation_approved=$false
    note='Local SDDL evidence is NOT an icacls restore archive. Backup/restore rehearsal and separate explicit approval are mandatory before production ACL modifications.'
}
$sharePath = Join-Path $outDir 'DAY12-ACL-CHANGE-PREFLIGHT-SHARE-ONLY-THIS.json'
$share | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sharePath -Encoding UTF8 -ErrorAction Stop
Write-Host ('PREDEPLOY_ACL_EVIDENCE: ' + $share.evidence_state)
Write-Host ('Required target gaps: ' + $missingRequired + '; reparse targets: ' + $reparse)
Write-Host ('SHARE ONLY: ' + $sharePath)
Write-Host ('PRIVATE: PRIVATE-ACL-SDDL-SNAPSHOT-DO-NOT-SHARE.json (DO NOT SHARE)')
