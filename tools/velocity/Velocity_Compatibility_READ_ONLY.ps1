[CmdletBinding()]
param(
    [switch]$Synthetic,
    [string]$OutputDir = ''
)
# READ ONLY: collect only Velocity artifact version hints and SHA256 digests.
# NEVER inspect or export forwarding secrets, Floodgate keys, command lines,
# process IDs, players, network configurations or host credentials.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ids = @('wild','playground','other')
$report = [ordered]@{
    schema = 1
    collector = 'GSC-4.5.2-Velocity-Compatibility-READ-ONLY'
    collected_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    synthetic = [bool]$Synthetic
    host_state_changed = $false
    velocity_jar_or_config_changed = $false
    runtime_api_compatibility_verified = $false
    result = 'VERSION_UNVERIFIED'
    instances = @()
}
function VersionField([string]$manifest) {
    # JAR manifests may contain folded continuation lines; return only known
    # manifest metadata, never arbitrary lines or filesystem locations.
    if ([string]::IsNullOrWhiteSpace($manifest)) { return 'UNKNOWN' }
    $unfolded = ($manifest -replace '\r?\n ', '')
    foreach ($name in @('Implementation-Version','Bundle-Version','Specification-Version')) {
        $matches = [regex]::Matches($unfolded, '(?im)^' + [regex]::Escape($name) + ':\s*([^\r\n]+)$')
        if ($matches.Count -eq 1) {
            $value = $matches[0].Groups[1].Value.Trim()
            if ($value.Length -le 96 -and $value -match '^[a-zA-Z0-9+._\-]+$') { return $value }
        }
    }
    return 'UNKNOWN'
}
function JarVersionHint([string]$jar) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($jar)
        $manifestEntry = $zip.GetEntry('META-INF/MANIFEST.MF')
        if ($null -eq $manifestEntry) { return 'UNKNOWN' }
        if ($manifestEntry.Length -gt 32768) { return 'UNKNOWN' }
        $stream = $manifestEntry.Open()
        $reader = New-Object IO.StreamReader($stream)
        try {
            return VersionField ($reader.ReadToEnd())
        } finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    } catch {
        return 'UNKNOWN'
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
    }
}


# READ ONLY hint: the Java executable product version associated with the
# Bedrock UDP owner. It does not attest the actual loaded JVM or Task owner.
# No path, PID, command line, or credential is exported.
function JavaVersionHint([int]$udpPort) {
    try {
        $owners = @(Get-NetUDPEndpoint -LocalPort $udpPort -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.OwningProcess -gt 0 } |
            Select-Object -ExpandProperty OwningProcess -Unique)
        if ($owners.Count -ne 1) { return 'UNKNOWN' }
        $proc = @(Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$owners[0]) -ErrorAction SilentlyContinue)
        if ($proc.Count -ne 1 -or [string]$proc[0].Name -notin @('java.exe','javaw.exe')) {
            return 'UNKNOWN'
        }
        $path = [string]$proc[0].ExecutablePath
        if ([string]::IsNullOrWhiteSpace($path) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'UNKNOWN' }
        $version = [string][Diagnostics.FileVersionInfo]::GetVersionInfo($path).ProductVersion
        if ($version.Length -gt 0 -and $version.Length -le 64 -and
            $version -match '^[0-9][0-9a-zA-Z_.+ \-]*$') { return $version }
    } catch {}
    return 'UNKNOWN'
}

if ($Synthetic) {
    $sampleManifest = 'Manifest-Version: 1.0' + [Environment]::NewLine + 'Implementation-Version: 4.2.1' + [Environment]::NewLine
    if ((VersionField $sampleManifest) -cne '4.2.1') { throw 'SYNTHETIC_MANIFEST_VERSION_PARSE_FAILED' }
    $foldedManifest = 'Implementation-Version: 4.2.' + [Environment]::NewLine + ' 1' + [Environment]::NewLine
    if ((VersionField $foldedManifest) -cne '4.2.1') { throw 'SYNTHETIC_MANIFEST_CONTINUATION_PARSE_FAILED' }

    foreach ($id in $ids) {
        $report.instances += [ordered]@{
            id=$id; task_present=$true; task_matches_expected_jar_path=$true
            velocity_jar_present=$true; velocity_jar_sha256=('0'*64)
            velocity_jar_bytes=123456
            manifest_version_hint='UNKNOWN'; java_binary_version_hint='UNKNOWN'
        }
    }
    $report.result = 'SYNTHETIC_STRUCTURE_PASS_NOT_LIVE'
    $report | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$proxyRoot = Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer'
foreach ($id in $ids) {
    $name = 'Geumyi Day10 Velocity ' + $id
    $expectedDir = Join-Path $proxyRoot $id
    $jar = Join-Path $expectedDir 'velocity.jar'
    $task = @(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)
    $singleTask = $task.Count -eq 1
    $taskMatches = $false
    if ($singleTask) {
        $actions = @($task[0].Actions)
        if ($actions.Count -eq 1) {
            $a = $actions[0]
            $taskMatches = (
                ([string]$task[0].TaskPath -eq '\') -and
                ([string]$a.WorkingDirectory).TrimEnd('\') -ieq $expectedDir.TrimEnd('\') -and
                ([IO.Path]::GetFileName([string]$a.Execute) -ieq 'java.exe') -and
                ([string]$a.Arguments -match '(?i)(?:^|\s)-jar\s+(?:"velocity\.jar"|velocity\.jar)(?:\s|$)')
            )
        }
    }
    $present = Test-Path -LiteralPath $jar -PathType Leaf
    $sha = ''
    $size = 0
    $hint = 'UNKNOWN'
    $javaHint = JavaVersionHint ([int](19132 + [array]::IndexOf($ids, $id)))
    if ($taskMatches -and $present) {
        try {
            $file = Get-Item -LiteralPath $jar -ErrorAction Stop
            if ($file.Length -gt 0 -and $file.Length -lt 1073741824) {
                $size = [int64]$file.Length
                $sha = (Get-FileHash -LiteralPath $jar -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                $hint = JarVersionHint $jar
            }
        } catch {
            # Fail closed without exporting Windows error messages or paths.
            $sha = ''; $size = 0; $hint = 'UNKNOWN'
        }
    }
    $report.instances += [ordered]@{
        id=$id
        task_present=[bool]$singleTask
        task_matches_expected_jar_path=[bool]$taskMatches
        velocity_jar_present=[bool]$present
        velocity_jar_sha256=[string]$sha
        velocity_jar_bytes=[int64]$size
        manifest_version_hint=[string]$hint
        java_binary_version_hint=[string]$javaHint
    }
}
if ($report.instances.Count -eq 3 -and
    @($report.instances | Where-Object { -not $_.task_matches_expected_jar_path -or -not $_.velocity_jar_sha256 }).Count -eq 0) {
    $report.result = 'ARTIFACT_FINGERPRINTS_CAPTURED_VERSION_UNVERIFIED'
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if ([string]::IsNullOrWhiteSpace($desktop)) { throw 'DESKTOP_UNAVAILABLE_NO_STATE_CHANGE' }
    $OutputDir = Join-Path $desktop 'Geumyi-Velocity-ReadOnly-Reports'
}
[void](New-Item -ItemType Directory -Path $OutputDir -Force)
$outFile = Join-Path $OutputDir ('Velocity-Compatibility-READ-ONLY-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outFile -Encoding UTF8
Write-Host 'READ ONLY completed; no Java, scheduled task, proxy, network or world modification.'
Write-Host ('Result: ' + $report.result)
Write-Host ('Sanitized report: ' + $outFile)
Write-Host 'Only share this JSON file. Do NOT share velocity.jar, forwarding secrets, or logs.'
