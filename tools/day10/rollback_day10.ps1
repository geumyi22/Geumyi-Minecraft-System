param(
    [Parameter(Mandatory = $true)]
    [string]$BackupRoot
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$helpers = Join-Path $PSScriptRoot "day10_live_helpers.ps1"
if (Test-Path -LiteralPath $helpers) {
    . $helpers
}

$statePath = Join-Path $BackupRoot "rollback-state.json"
if (-not (Test-Path -LiteralPath $statePath)) {
    throw "rollback-state.json missing: $BackupRoot"
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

Write-Host "DAY 10 ROLLBACK START"
Write-Host "Backup: $BackupRoot"

try {
    $task = Get-ScheduledTask -TaskName "Geumyi Minecraft Velocity" -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName "Geumyi Minecraft Velocity" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "Geumyi Minecraft Velocity" -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {}

# Stop only the Java process running the Velocity JAR from this Day 10 install.
# Unregistering a Windows scheduled task alone does not stop its child Java process.
$velocityJar = Join-Path ([string]$state.velocity_root) "velocity.jar"
$velocityProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop |
    Where-Object {
        $_.Name -in @("java.exe", "javaw.exe") -and
        $null -ne $_.CommandLine -and
        $_.CommandLine.IndexOf($velocityJar, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
foreach ($proc in $velocityProcesses) {
    Write-Host ("Stopping Day 10 Velocity PID " + $proc.ProcessId)
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
}
$deadline = (Get-Date).AddSeconds(15)
do {
    $stillRunning = @(Get-CimInstance Win32_Process -ErrorAction Stop |
        Where-Object {
            $_.Name -in @("java.exe", "javaw.exe") -and
            $null -ne $_.CommandLine -and
            $_.CommandLine.IndexOf($velocityJar, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    if ($stillRunning.Count -eq 0) { break }
    Start-Sleep -Seconds 1
} while ((Get-Date) -lt $deadline)
if ($stillRunning.Count -gt 0) {
    throw "Velocity is still running; refusing to delete install files or restore old ports."
}

try { & netsh.exe interface portproxy delete v4tov4 listenport=25566 listenaddress=0.0.0.0 | Out-Null } catch {}
try { Remove-NetFirewallRule -DisplayName "Geumyi Velocity Java" -ErrorAction SilentlyContinue } catch {}
try { Remove-NetFirewallRule -DisplayName "Geumyi Geyser Bedrock" -ErrorAction SilentlyContinue } catch {}

foreach ($id in @("lobby", "wild", "playground")) {
    try {
        $s = Day10-State $id
        if ($null -ne $s -and [bool]$s.online) {
            Day10-Gsc "POST" "/api/server/action" @{ id = $id; action = "force-stop" } | Out-Null
            Start-Sleep -Seconds 3
        }
    } catch {}
}

$restorePairs = @(
    @("wild\server.properties", (Join-Path $state.wild_path "server.properties")),
    @("wild\paper-global.yml", (Join-Path $state.wild_path "config\paper-global.yml")),
    @("wild\spigot.yml", (Join-Path $state.wild_path "spigot.yml")),
    @("playground\server.properties", (Join-Path $state.playground_path "server.properties")),
    @("playground\paper-global.yml", (Join-Path $state.playground_path "config\paper-global.yml")),
    @("playground\spigot.yml", (Join-Path $state.playground_path "spigot.yml"))
)

foreach ($pair in $restorePairs) {
    $src = Join-Path $BackupRoot $pair[0]
    $dst = $pair[1]
    if (Test-Path -LiteralPath $src) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

foreach ($serverDir in @([string]$state.wild_path, [string]$state.playground_path)) {
    if ([string]::IsNullOrWhiteSpace($serverDir)) { continue }
    $pluginDir = Join-Path $serverDir "plugins"
    foreach ($name in @(
        "GeumyiNetwork-0.1.0-Paper26.3.jar",
        "ViaVersion-5.12.0.jar",
        "ViaBackwards-5.12.0.jar"
    )) {
        Remove-Item -LiteralPath (Join-Path $pluginDir $name) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath (Join-Path $pluginDir "GeumyiNetwork") -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $pluginDir) {
        Get-ChildItem -LiteralPath $pluginDir -File -Filter "*.day10-disabled" -ErrorAction SilentlyContinue | ForEach-Object {
            $suffix = ".day10-disabled"
            $original = $_.FullName.Substring(0, $_.FullName.Length - $suffix.Length)
            Move-Item -LiteralPath $_.FullName -Destination $original -Force
        }
    }
}

if ($state.lobby_created -and (Test-Path -LiteralPath $state.lobby_path)) {
    Remove-Item -LiteralPath $state.lobby_path -Recurse -Force -ErrorAction SilentlyContinue
}
if ($state.velocity_created -and (Test-Path -LiteralPath $state.velocity_root)) {
    Remove-Item -LiteralPath $state.velocity_root -Recurse -Force -ErrorAction SilentlyContinue
}
if ($state.bedrock_created -and (Test-Path -LiteralPath $state.bedrock_root)) {
    Remove-Item -LiteralPath $state.bedrock_root -Recurse -Force -ErrorAction SilentlyContinue
}

$gscBackup = Join-Path $BackupRoot "gsc\server.json"
if (Test-Path -LiteralPath $gscBackup) {
    Copy-Item -LiteralPath $gscBackup -Destination "$env:PROGRAMDATA\GeumyiServerCenter\server.json" -Force
    try {
        Restart-Service -Name "Geumyi Server Center Host" -Force
        Day10-WaitGsc 120 | Out-Null
    } catch {
        Write-Warning ("GSC restore/restart failed: " + $_.Exception.Message)
    }
}

foreach ($entry in @(
    @{ id = "wild"; want = [bool]$state.wild_initial_online },
    @{ id = "playground"; want = [bool]$state.playground_initial_online }
)) {
    try {
        $cur = Day10-State $entry.id
        if ($null -eq $cur) { continue }
        if ($entry.want -and -not [bool]$cur.online) {
            Day10-Gsc "POST" "/api/server/action" @{ id = $entry.id; action = "start" } | Out-Null
            Day10-WaitOnline $entry.id $true 240 | Out-Null
        } elseif (-not $entry.want -and [bool]$cur.online) {
            Day10-Gsc "POST" "/api/server/action" @{ id = $entry.id; action = "stop" } | Out-Null
            Day10-WaitOnline $entry.id $false 180 | Out-Null
        }
    } catch {
        Write-Warning ("state restore failed for " + $entry.id + ": " + $_.Exception.Message)
    }
}

Write-Host "DAY 10 ROLLBACK FINISHED"
