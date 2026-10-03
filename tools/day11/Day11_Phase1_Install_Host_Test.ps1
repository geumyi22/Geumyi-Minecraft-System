[CmdletBinding()]
param(
    [string]$PackageDir = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ServiceName = "Geumyi Server Center Host"
$ProgramDataRoot = if ($env:PROGRAMDATA) { $env:PROGRAMDATA } else { "C:\ProgramData" }
$StateRoot = Join-Path $ProgramDataRoot "GeumyiServerCenter"
$BackupRoot = Join-Path $StateRoot "Backups"
$ManifestPath = Join-Path $PackageDir "host-test-manifest.json"
$NewHost = Join-Path $PackageDir "GeumyiServerHost.exe"
$NewClient = Join-Path $PackageDir "GeumyiServerCenter.exe"

function Write-Step([string]$Message) {
    Write-Host ("[DAY11] " + $Message) -ForegroundColor Cyan
}

function Is-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Health {
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/health" -Method Get -TimeoutSec 3
    } catch {
        return $null
    }
}

function Wait-Health([int]$Seconds = 45) {
    $end = (Get-Date).AddSeconds($Seconds)
    do {
        $h = Get-Health
        if ($null -ne $h -and $h.ok -eq $true) { return $h }
        Start-Sleep -Milliseconds 800
    } while ((Get-Date) -lt $end)
    return $null
}

function Test-Tcp([int]$Port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $ar = $c.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne(400)) { $c.Close(); return $false }
        $c.EndConnect($ar)
        $c.Close()
        return $true
    } catch { return $false }
}

function Test-UdpBound([int]$Port) {
    try {
        if (Get-Command Get-NetUDPEndpoint -ErrorAction SilentlyContinue) {
            return [bool](Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        return [bool](& netstat.exe -ano -p udp 2>$null | Select-String -SimpleMatch (":" + $Port) | Select-Object -First 1)
    } catch { return $false }
}

function Capture-NetworkState {
    $tcpPorts = @(25565,25566,25567,25570,25571,25572,25573)
    $udpPorts = @(19132,19133,19134)
    $tcp = @{}
    $udp = @{}
    foreach ($p in $tcpPorts) { $tcp["$p"] = Test-Tcp $p }
    foreach ($p in $udpPorts) { $udp["$p"] = Test-UdpBound $p }
    return [pscustomobject]@{ tcp = $tcp; udp = $udp }
}

function Assert-PreviouslyOpenPorts([object]$Before) {
    foreach ($k in $Before.tcp.Keys) {
        if ([bool]$Before.tcp[$k] -and -not (Test-Tcp ([int]$k))) {
            throw "Minecraft/Proxy TCP port $k was open before GSC update but is not open now."
        }
    }
    foreach ($k in $Before.udp.Keys) {
        if ([bool]$Before.udp[$k] -and -not (Test-UdpBound ([int]$k))) {
            throw "Bedrock UDP port $k was bound before GSC update but is not bound now."
        }
    }
}

function Resolve-ServiceExe {
    $svc = Get-CimInstance Win32_Service -Filter ("Name='" + $ServiceName.Replace("'","''") + "'") -ErrorAction Stop
    if ($null -eq $svc) { throw "GSC Host service was not found." }
    $raw = [string]$svc.PathName
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "GSC Host service executable path is empty." }
    if ($raw.StartsWith('"')) {
        $end = $raw.IndexOf('"', 1)
        if ($end -le 1) { throw "Cannot parse GSC Host service path: $raw" }
        return $raw.Substring(1, $end - 1)
    }
    $candidate = $raw
    $argIndex = $raw.IndexOf(" --")
    if ($argIndex -gt 0) { $candidate = $raw.Substring(0, $argIndex) }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    $fallback = "C:\Program Files\Geumyi Server Center\GeumyiServerHost.exe"
    if (Test-Path -LiteralPath $fallback -PathType Leaf) { return $fallback }
    throw "Cannot resolve GSC Host executable from service path: $raw"
}

function Test-ClientClosed([string]$ClientPath) {
    $target = [IO.Path]::GetFullPath($ClientPath)
    try {
        $running = Get-CimInstance Win32_Process -Filter "Name='GeumyiServerCenter.exe'" -ErrorAction SilentlyContinue
        foreach ($p in @($running)) {
            if ([string]::IsNullOrWhiteSpace([string]$p.ExecutablePath)) { continue }
            if ([IO.Path]::GetFullPath([string]$p.ExecutablePath).Equals($target, [StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
        }
    } catch {}
    return $true
}

function Verify-Package {
    foreach ($p in @($ManifestPath,$NewHost,$NewClient)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Package file missing: $p" }
    }
    $m = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @(
        @{ path=$NewHost; expected=[string]$m.host_sha256; name="GeumyiServerHost.exe" },
        @{ path=$NewClient; expected=[string]$m.client_sha256; name="GeumyiServerCenter.exe" }
    )) {
        $actual = (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $entry.expected.ToLowerInvariant()) {
            throw ("Package SHA-256 mismatch: " + $entry.name)
        }
    }
    return $m
}

function Stop-GscServiceSafe {
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($svc.Status -ne "Stopped") {
        Stop-Service -Name $ServiceName -ErrorAction Stop
        $svc.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(30))
    }
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($svc.Status -ne "Stopped") { throw "GSC Host service did not stop normally." }
}

function Start-GscServiceSafe {
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($svc.Status -ne "Running") {
        Start-Service -Name $ServiceName -ErrorAction Stop
    }
    $h = Wait-Health 60
    if ($null -eq $h) { throw "GSC Host health did not recover after start." }
    return $h
}

if (-not (Is-Administrator)) {
    throw "Administrator privileges are required. Run Day11_Phase1_INSTALL_HOST_TEST.cmd and accept UAC."
}

$manifest = Verify-Package
$beforeHealth = Get-Health
if ($null -eq $beforeHealth -or $beforeHealth.ok -ne $true) {
    throw "Existing GSC Host health is not OK. No files were changed."
}

$hostPath = Resolve-ServiceExe
$installDir = Split-Path -Parent $hostPath
$clientPath = Join-Path $installDir "GeumyiServerCenter.exe"
if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { throw "Installed Host executable missing: $hostPath" }
if (-not (Test-ClientClosed $clientPath)) {
    throw "Geumyi Server Center desktop app is still open. Close the GSC window and run this package again. Minecraft servers were not touched."
}

$beforeNetwork = Capture-NetworkState
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $BackupRoot ("Day11-GSCHostTest-" + $stamp)
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $hostPath -Destination (Join-Path $backup "GeumyiServerHost.exe") -Force
if (Test-Path -LiteralPath $clientPath -PathType Leaf) {
    Copy-Item -LiteralPath $clientPath -Destination (Join-Path $backup "GeumyiServerCenter.exe") -Force
}
$config = Join-Path $StateRoot "server.json"
if (Test-Path -LiteralPath $config -PathType Leaf) {
    Copy-Item -LiteralPath $config -Destination (Join-Path $backup "server.json") -Force
}
$oldClientHash = ""
if (Test-Path -LiteralPath $clientPath -PathType Leaf) {
    $oldClientHash = (Get-FileHash -LiteralPath $clientPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$beforeRecord = [ordered]@{
    time = (Get-Date).ToString("o")
    source_sha = [string]$manifest.source_sha
    old_host_sha256 = (Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToLowerInvariant()
    old_client_sha256 = $oldClientHash
    new_host_sha256 = [string]$manifest.host_sha256
    new_client_sha256 = [string]$manifest.client_sha256
    install_dir = $installDir
    old_health_version = [string]$beforeHealth.version
    network_before = $beforeNetwork
}
$beforeRecord | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backup "deployment.json") -Encoding UTF8

Write-Step "Backup created: $backup"
Write-Step "Stopping GSC Host service only. Minecraft/Paper/Velocity processes are not stopped."

$rollbackNeeded = $false
try {
    Stop-GscServiceSafe
    Assert-PreviouslyOpenPorts $beforeNetwork

    Copy-Item -LiteralPath $NewHost -Destination $hostPath -Force
    Copy-Item -LiteralPath $NewClient -Destination $clientPath -Force
    $rollbackNeeded = $true

    $afterHealth = Start-GscServiceSafe
    Assert-PreviouslyOpenPorts $beforeNetwork

    $installedHostHash = (Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $installedClientHash = (Get-FileHash -LiteralPath $clientPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($installedHostHash -ne ([string]$manifest.host_sha256).ToLowerInvariant()) { throw "Installed Host hash mismatch." }
    if ($installedClientHash -ne ([string]$manifest.client_sha256).ToLowerInvariant()) { throw "Installed Client hash mismatch." }

    $result = [ordered]@{
        ok = $true
        time = (Get-Date).ToString("o")
        source_sha = [string]$manifest.source_sha
        gsc_health_version = [string]$afterHealth.version
        backup = $backup
        minecraft_processes_stopped = $false
        velocity_processes_stopped = $false
        rollback_used = $false
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backup "result.json") -Encoding UTF8
    Write-Host ""
    Write-Host "DAY 11 PHASE 1 HOST TEST DEPLOY PASS" -ForegroundColor Green
    Write-Host "GSC-only update completed. Minecraft/Velocity were not stopped."
    Write-Host "Backup: $backup"
    Write-Host "Open Geumyi Server Center again, then continue the Day 11 runtime checks."
    exit 0
}
catch {
    $failure = $_.Exception.Message
    Write-Warning ("Day 11 host-test deployment failed: " + $failure)
    if ($rollbackNeeded) {
        Write-Step "Attempting automatic GSC-only rollback..."
        try {
            Stop-GscServiceSafe
            Copy-Item -LiteralPath (Join-Path $backup "GeumyiServerHost.exe") -Destination $hostPath -Force
            $oldClient = Join-Path $backup "GeumyiServerCenter.exe"
            if (Test-Path -LiteralPath $oldClient -PathType Leaf) {
                Copy-Item -LiteralPath $oldClient -Destination $clientPath -Force
            }
            $rollbackHealth = Start-GscServiceSafe
            Assert-PreviouslyOpenPorts $beforeNetwork
            [ordered]@{
                ok = $false
                error = $failure
                rollback_used = $true
                rollback_health = [string]$rollbackHealth.version
                time = (Get-Date).ToString("o")
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup "result.json") -Encoding UTF8
            Write-Host "DAY 11 HOST TEST ROLLBACK PASS" -ForegroundColor Yellow
            Write-Host "Old GSC binaries restored. Minecraft/Velocity were not stopped."
        } catch {
            Write-Host "ROLLBACK FAILED: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Do not change Minecraft servers. Preserve this backup and report the log immediately:"
            Write-Host $backup
        }
    }
    throw
}
