[CmdletBinding()]
param(
    [string]$OutputDir = "",
    [switch]$NoNetworkProbe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ProgramDataRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:PROGRAMDATA)) { return $env:PROGRAMDATA }
    return "C:\ProgramData"
}

function Safe-FileHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { return $null }
}

function Try-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Test-Tcp([int]$Port) {
    if ($Port -le 0) { return $false }
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $ar = $c.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne(350)) { $c.Close(); return $false }
        $c.EndConnect($ar)
        $c.Close()
        return $true
    } catch { return $false }
}

function Test-UdpBound([int]$Port) {
    if ($Port -le 0) { return $false }
    try {
        if (Get-Command Get-NetUDPEndpoint -ErrorAction SilentlyContinue) {
            return [bool](Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
    } catch {}
    try {
        $match = & netstat.exe -ano -p udp 2>$null | Select-String -SimpleMatch (":" + $Port)
        return [bool]$match
    } catch { return $false }
}

function Get-DirectorySize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return [int64]0 }
    try {
        return [int64]((Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum)
    } catch { return [int64]0 }
}

function Get-JarInventory([string]$Plugins) {
    if (-not (Test-Path -LiteralPath $Plugins -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $Plugins -Filter *.jar -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                name = $_.Name
                size = [int64]$_.Length
                modified = $_.LastWriteTime.ToString("o")
                sha256 = Safe-FileHash $_.FullName
            }
        }
    )
}

$programData = Get-ProgramDataRoot
$gscRoot = Join-Path $programData "GeumyiServerCenter"
$configPath = Join-Path $gscRoot "server.json"
$networkRoot = Join-Path $gscRoot "Network\FourServer"
$backupRoot = Join-Path $gscRoot "Backups"
$checkpointRoot = Join-Path $gscRoot "Checkpoints"
$updatesRoot = Join-Path $gscRoot "Updates"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $env:TEMP "Geumyi-Day11-Preflight"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonPath = Join-Path $OutputDir ("Geumyi-Day11-Phase0-" + $stamp + ".json")
$txtPath = Join-Path $OutputDir ("Geumyi-Day11-Phase0-" + $stamp + ".txt")

$config = Try-JsonFile $configPath
$serverRows = @()

if ($null -ne $config -and $null -ne $config.servers) {
    foreach ($s in @($config.servers)) {
        $dir = [string]$s.path
        $props = $null
        $propPath = if ([string]::IsNullOrWhiteSpace($dir)) { "" } else { Join-Path $dir "server.properties" }
        $safeProps = @{}
        if ($propPath -and (Test-Path -LiteralPath $propPath -PathType Leaf)) {
            foreach ($line in Get-Content -LiteralPath $propPath -ErrorAction SilentlyContinue) {
                if ($line -match "^\s*#" -or $line -notmatch "=") { continue }
                $kv = $line -split "=",2
                $k = $kv[0].Trim()
                $v = $kv[1].Trim()
                if ($k -in @("server-port","rcon.port","enable-rcon","online-mode","accepts-transfers","max-players")) {
                    $safeProps[$k] = $v
                }
            }
        }
        $serverRows += [pscustomobject]@{
            id = [string]$s.id
            name = [string]$s.name
            role = [string]$s.role
            path_exists = (-not [string]::IsNullOrWhiteSpace($dir)) -and (Test-Path -LiteralPath $dir -PathType Container)
            java_port = [int]$s.java_port
            java_listening = Test-Tcp ([int]$s.java_port)
            rcon_port = [int]$s.rcon_port
            rcon_listening = Test-Tcp ([int]$s.rcon_port)
            bedrock_port = [int]$s.bedrock_port
            gds_api_port = [int]$s.gds_api_port
            gds_listening = Test-Tcp ([int]$s.gds_api_port)
            auto_start = [bool]$s.auto_start
            restart_on_crash = [bool]$s.restart_on_crash
            update_policy = [string]$s.update_policy
            safe_properties = $safeProps
            plugin_jars = if ($dir) { Get-JarInventory (Join-Path $dir "plugins") } else { @() }
        }
    }
}

$proxyRows = @()
foreach ($id in @("wild","playground","other")) {
    $root = Join-Path $networkRoot $id
    $plugins = Join-Path $root "plugins"
    $proxyRows += [pscustomobject]@{
        id = $id
        root_exists = Test-Path -LiteralPath $root -PathType Container
        velocity_toml = Test-Path -LiteralPath (Join-Path $root "velocity.toml") -PathType Leaf
        forwarding_secret_present = Test-Path -LiteralPath (Join-Path $root "forwarding.secret") -PathType Leaf
        floodgate_key_present = @(
            Join-Path $plugins "floodgate\key.pem"
            Join-Path $plugins "floodgate-velocity\key.pem"
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Measure-Object | Select-Object -ExpandProperty Count
        jars = Get-JarInventory $plugins
    }
}

$tasks = @()
try {
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like "Geumyi*" } |
            ForEach-Object {
                [pscustomobject]@{
                    name = $_.TaskName
                    state = [string]$_.State
                    path = $_.TaskPath
                }
            })
    }
} catch {}

$health = $null
if (-not $NoNetworkProbe) {
    try {
        $health = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8787/api/health" -TimeoutSec 3
    } catch {
        $health = [pscustomobject]@{ ok = $false; error = $_.Exception.Message }
    }
}

$drive = $null
try {
    $root = [System.IO.Path]::GetPathRoot($gscRoot)
    $d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $root.TrimEnd("\") + "'") -ErrorAction Stop
    if ($null -ne $d) {
        $drive = [pscustomobject]@{
            device = $d.DeviceID
            free_bytes = [int64]$d.FreeSpace
            size_bytes = [int64]$d.Size
        }
    }
} catch {}

$pending = @()
if (Test-Path -LiteralPath $updatesRoot -PathType Container) {
    $pending = @(Get-ChildItem -LiteralPath $updatesRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "pending|journal|transaction|rejected" } |
        Select-Object -First 200 |
        ForEach-Object {
            [pscustomobject]@{
                relative = $_.FullName.Substring($updatesRoot.Length).TrimStart("\")
                size = [int64]$_.Length
                modified = $_.LastWriteTime.ToString("o")
            }
        })
}

$result = [ordered]@{
    schema = 1
    phase = "Day11-Phase0-READ-ONLY"
    generated_at = (Get-Date).ToString("o")
    safety = [ordered]@{
        mutates_server_config = $false
        stops_minecraft = $false
        stops_velocity = $false
        changes_firewall = $false
        reads_secrets = $false
        note = "This script only reads host/runtime state and writes this report under the selected output directory."
    }
    host = [ordered]@{
        computer_name = $env:COMPUTERNAME
        windows = [Environment]::OSVersion.VersionString
        powershell = $PSVersionTable.PSVersion.ToString()
        java = try { (& java.exe -version 2>&1 | Select-Object -First 1).ToString() } catch { "" }
        gsc_root_exists = Test-Path -LiteralPath $gscRoot -PathType Container
        config_exists = Test-Path -LiteralPath $configPath -PathType Leaf
        config_sha256 = Safe-FileHash $configPath
        gsc_health = $health
        drive = $drive
    }
    servers = $serverRows
    public_entry = @(
        [pscustomobject]@{ id="wild"; java_port=25565; java_tcp=(Test-Tcp 25565); bedrock_port=19132; bedrock_udp_bound=(Test-UdpBound 19132) }
        [pscustomobject]@{ id="playground"; java_port=25566; java_tcp=(Test-Tcp 25566); bedrock_port=19133; bedrock_udp_bound=(Test-UdpBound 19133) }
        [pscustomobject]@{ id="other"; java_port=25567; java_tcp=(Test-Tcp 25567); bedrock_port=19134; bedrock_udp_bound=(Test-UdpBound 19134) }
    )
    proxies = $proxyRows
    scheduled_tasks = $tasks
    protection = [ordered]@{
        backup_root_exists = Test-Path -LiteralPath $backupRoot -PathType Container
        backup_bytes = Get-DirectorySize $backupRoot
        checkpoint_root_exists = Test-Path -LiteralPath $checkpointRoot -PathType Container
        checkpoint_bytes = Get-DirectorySize $checkpointRoot
        updates_root_exists = Test-Path -LiteralPath $updatesRoot -PathType Container
        pending_artifacts = $pending
    }
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$summary = @()
$summary += "============================================================"
$summary += " Geumyi Minecraft System - Day 11 Phase 0 / READ ONLY"
$summary += "============================================================"
$summary += "Generated: " + $result.generated_at
$summary += "GSC health: " + ($(if ($health -and $health.ok) { "OK v" + $health.version } else { "UNAVAILABLE" }))
$summary += ""
$summary += "Servers:"
foreach ($s in $serverRows) {
    $summary += ("- {0}: java={1} rcon={2} gds={3} role={4} bedrock_profile={5}" -f $s.id,$s.java_listening,$s.rcon_listening,$s.gds_listening,$s.role,$s.bedrock_port)
}
$summary += ""
$summary += "Public entry:"
foreach ($p in @($result.public_entry)) {
    $summary += ("- {0}: Java {1}={2}, Bedrock UDP {3} bound={4}" -f $p.id,$p.java_port,$p.java_tcp,$p.bedrock_port,$p.bedrock_udp_bound)
}
$summary += ""
$summary += "Backup bytes: " + $result.protection.backup_bytes
$summary += "Checkpoint bytes: " + $result.protection.checkpoint_bytes
$summary += "Pending update artifacts: " + @($pending).Count
$summary += ""
$summary += "JSON: " + $jsonPath
$summary += "This preflight made no server/config/firewall/process changes."
$summary -join [Environment]::NewLine | Set-Content -LiteralPath $txtPath -Encoding UTF8
$summary -join [Environment]::NewLine | Write-Host

Write-Host ""
Write-Host "DAY 11 PHASE 0 READ-ONLY COMPLETE"
Write-Host "Send the JSON report to continue:"
Write-Host $jsonPath
