param(
    [string]$BackupRoot = "",
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Read-JsonUtf8 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    return $text | ConvertFrom-Json
}

function Write-JsonUtf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 30
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $json, $utf8)
}

function Json-Utf8Bytes {
    param($Value)
    $json = $Value | ConvertTo-Json -Depth 30 -Compress
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    return $utf8.GetBytes($json)
}

function Invoke-Gsc {
    param([string]$Method, [string]$Path, $Body = $null)
    $uri = "http://127.0.0.1:8787$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec 20
    }
    if ($Method -ne "POST") { throw "Body requests currently support POST only" }

    $bytes = Json-Utf8Bytes $Body
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = "POST"
    $request.ContentType = "application/json; charset=utf-8"
    $request.ContentLength = $bytes.Length
    $request.Timeout = 20000
    $request.ReadWriteTimeout = 20000

    $stream = $request.GetRequestStream()
    try {
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }

    try {
        $response = $request.GetResponse()
    } catch [System.Net.WebException] {
        $message = $_.Exception.Message
        if ($null -ne $_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            $reader = $null
            try {
                $reader = New-Object System.IO.StreamReader($errorResponse.GetResponseStream(), [Text.Encoding]::UTF8)
                $bodyText = $reader.ReadToEnd()
                if (-not [string]::IsNullOrWhiteSpace($bodyText)) { $message += ": " + $bodyText.Trim() }
            } finally {
                if ($null -ne $reader) { $reader.Dispose() }
                $errorResponse.Dispose()
            }
        }
        throw $message
    }

    $reader = $null
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return $text | ConvertFrom-Json
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $response.Dispose()
    }
}

function Wait-Gsc {
    param([int]$Seconds = 120)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            $h = Invoke-RestMethod -Method GET -Uri "http://127.0.0.1:8787/api/health" -TimeoutSec 5
            if ($h.ok) { return }
        } catch {}
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "GSC readiness timeout after service restart"
}

function Wait-Server {
    param([string]$Id, [bool]$WantOnline, [int]$Seconds = 240)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            $status = Invoke-Gsc "GET" "/api/status"
            $s = @($status.servers) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if ($null -ne $s -and [bool]$s.online -eq $WantOnline) { return }
        } catch {}
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "$Id online=$WantOnline timeout"
}

function Copy-ProfileWithAutoStart {
    param($Profile, [bool]$AutoStart)
    $h = [ordered]@{}
    foreach ($prop in $Profile.PSObject.Properties) {
        $h[$prop.Name] = $prop.Value
    }
    $h["auto_start"] = $AutoStart
    return [pscustomobject]$h
}

function Assert-State {
    param($State, [string]$Root)
    if ($State.schema -ne 1) { throw "Unexpected rollback state schema" }
    $entries = @($State.servers)
    if ($entries.Count -ne 3) { throw "Rollback state must contain exactly three backend servers" }
    $ids = @($entries | ForEach-Object { [string]$_.id } | Sort-Object)
    if (($ids -join ",") -ne "other,playground,wild") { throw "Rollback state server IDs are invalid: $($ids -join ',')" }

    foreach ($entry in $entries) {
        if ($null -eq $entry.profile) { throw "Missing original profile for $($entry.id)" }
        $live = [string]$entry.path
        if (-not (Test-Path -LiteralPath $live -PathType Container)) { throw "Original live server directory missing: $live" }
        if (-not (Test-Path -LiteralPath (Join-Path $live "server.properties") -PathType Leaf)) { throw "server.properties missing: $live" }

        $backup = Join-Path $Root ("servers\" + [string]$entry.id)
        $manifestPath = Join-Path $backup "backup-manifest.json"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Backup manifest missing: $($entry.id)" }
        $manifest = Read-JsonUtf8 $manifestPath
        foreach ($file in @($manifest.files)) {
            $candidate = Join-Path $live ([string]$file.relative)
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                throw "Live rollback file missing: $($entry.id) / $($file.relative)"
            }
            $hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
            if ($hash -ne [string]$file.sha256) {
                throw "Live rollback file hash mismatch: $($entry.id) / $($file.relative)"
            }
        }
    }
}

if ($SelfTest) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("Geumyi-Day10-Recovery-Test-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $cfgPath = Join-Path $tmp "server.json"
        $probe = [pscustomobject]@{
            bind = "127.0.0.1"
            servers = @(
                [pscustomobject]@{ id="wild"; name="금이 야생"; path="C:\테스트\야생"; auto_start=$true }
            )
        }
        Write-JsonUtf8NoBom $cfgPath $probe
        $round = Read-JsonUtf8 $cfgPath
        if ($round.servers[0].name -ne "금이 야생" -or $round.servers[0].path -ne "C:\테스트\야생") {
            throw "UTF-8 recovery round-trip failed"
        }
        $bytes = Json-Utf8Bytes @{ server=@{ name="금이 놀이터"; path="C:\테스트\놀이터" } }
        $decoded = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
        if ($decoded.server.name -ne "금이 놀이터") { throw "UTF-8 API body self-test failed" }
        Write-Host "DAY10 FAILED-CUTOVER RECOVERY SELFTEST PASS"
        exit 0
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$programData = $env:PROGRAMDATA
if ([string]::IsNullOrWhiteSpace($programData)) { $programData = "C:\ProgramData" }
$gscRoot = Join-Path $programData "GeumyiServerCenter"
$configPath = Join-Path $gscRoot "server.json"
$backupBase = Join-Path $gscRoot "Backups"

if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    $candidate = Get-ChildItem -LiteralPath $backupBase -Directory -Filter "Day10-Four-*" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "four-rollback-state.json") -PathType Leaf } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) { throw "No Day10-Four rollback backup was found" }
    $BackupRoot = $candidate.FullName
}

$statePath = Join-Path $BackupRoot "four-rollback-state.json"
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "Rollback state file missing: $statePath" }
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "GSC server.json missing: $configPath" }

$state = Read-JsonUtf8 $statePath
Assert-State $state $BackupRoot

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$recoveryDir = Join-Path $BackupRoot ("manual-recovery-" + $stamp)
New-Item -ItemType Directory -Force -Path $recoveryDir | Out-Null
$log = Join-Path $recoveryDir "recovery.log"

function Log {
    param([string]$Text)
    $line = ("{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text)
    Write-Host $line
    [IO.File]::AppendAllText($log, $line + [Environment]::NewLine, [Text.Encoding]::UTF8)
}

Log "Recovery backup: $BackupRoot"
Log "All restored backend files match the Day10 backup manifests."

$currentBackup = Join-Path $recoveryDir "server.json.before-recovery"
Copy-Item -LiteralPath $configPath -Destination $currentBackup -Force
Log "Current GSC config preserved: $currentBackup"

$serviceName = "Geumyi Server Center Host"
$svc = Get-Service -Name $serviceName -ErrorAction Stop
if ($svc.Status -ne "Stopped") {
    Log "Stopping GSC Host service..."
    Stop-Service -Name $serviceName -Force -ErrorAction Stop
    $svc.WaitForStatus("Stopped", (New-TimeSpan -Seconds 30))
}

$current = Read-JsonUtf8 $configPath
$temporaryProfiles = @()
foreach ($entry in @($state.servers)) {
    $temporaryProfiles += Copy-ProfileWithAutoStart $entry.profile $false
}
$current.servers = $temporaryProfiles
Write-JsonUtf8NoBom $configPath $current

$verifyDisk = Read-JsonUtf8 $configPath
foreach ($entry in @($state.servers)) {
    $disk = @($verifyDisk.servers | Where-Object { $_.id -eq $entry.id }) | Select-Object -First 1
    if ($null -eq $disk) { throw "Recovered config missing profile: $($entry.id)" }
    if ([string]$disk.path -ne [string]$entry.profile.path) { throw "Recovered path mismatch: $($entry.id)" }
    if ([string]$disk.name -ne [string]$entry.profile.name) { throw "Recovered name mismatch: $($entry.id)" }
    if ([string]$disk.path -match "\?\?\?" -or [string]$disk.name -match "\?\?\?") { throw "Question-mark corruption remains in recovered profile: $($entry.id)" }
}
Log "Original three GSC profiles restored on disk with auto_start temporarily disabled."

Start-Service -Name $serviceName -ErrorAction Stop
Wait-Gsc 120
Log "GSC Host service is healthy."

$settings = Invoke-Gsc "GET" "/api/settings"
foreach ($entry in @($state.servers)) {
    $api = @($settings.servers | Where-Object { $_.id -eq $entry.id }) | Select-Object -First 1
    if ($null -eq $api) { throw "GSC API missing recovered profile: $($entry.id)" }
    if ([string]$api.path -ne [string]$entry.profile.path) { throw "GSC API path mismatch: $($entry.id)" }
    if ([string]$api.name -ne [string]$entry.profile.name) { throw "GSC API name mismatch: $($entry.id)" }
}
Log "GSC API reports the original Unicode names and paths."

foreach ($entry in @($state.servers)) {
    if ([bool]$entry.was_online) {
        Log "Starting originally-online server: $($entry.id)"
        Invoke-Gsc "POST" "/api/server/action" @{ id=[string]$entry.id; action="start" } | Out-Null
        Wait-Server ([string]$entry.id) $true 240
        Log "Server online: $($entry.id)"
    } else {
        Log "Leaving originally-offline server stopped: $($entry.id)"
    }
}

foreach ($entry in @($state.servers)) {
    Invoke-Gsc "POST" "/api/v4/server-profile" @{ action="update"; server=$entry.profile } | Out-Null
}
Log "Original auto_start/profile flags restored through explicit UTF-8 API bodies."

$finalSettings = Invoke-Gsc "GET" "/api/settings"
foreach ($entry in @($state.servers)) {
    $api = @($finalSettings.servers | Where-Object { $_.id -eq $entry.id }) | Select-Object -First 1
    if ($null -eq $api) { throw "Final profile missing: $($entry.id)" }
    if ([string]$api.path -ne [string]$entry.profile.path -or [string]$api.name -ne [string]$entry.profile.name) {
        throw "Final profile verification failed: $($entry.id)"
    }
}

Log "DAY10 FAILED-CUTOVER RECOVERY PASS"
Write-Host ""
Write-Host "============================================================"
Write-Host " DAY10 FAILED-CUTOVER RECOVERY PASS"
Write-Host " Backup retained: $BackupRoot"
Write-Host " Recovery log:   $log"
Write-Host "============================================================"
