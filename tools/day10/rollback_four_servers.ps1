param(
    [Parameter(Mandatory = $true)][string]$BackupRoot,
    [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "day10_live_helpers.ps1")

function Day10-FourRollbackAssert {
    param([string]$Root)
    $stateFile = Join-Path $Root "four-rollback-state.json"
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { throw "Missing four-server rollback state" }
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($state.schema -ne 1 -or @($state.servers).Count -ne 3) { throw "Incomplete rollback state" }
    foreach ($entry in $state.servers) {
        $original = Join-Path $Root ("servers\" + $entry.id)
        if (-not (Test-Path -LiteralPath (Join-Path $original "server.properties") -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $original "config\paper-global.yml") -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $original "backup-manifest.json") -PathType Leaf)) {
            throw "Incomplete original server backup for $($entry.id)"
        }
        $manifest = Get-Content -LiteralPath (Join-Path $original "backup-manifest.json") -Raw | ConvertFrom-Json
        foreach ($file in @($manifest.files)) {
            $candidate = Join-Path $original ([string]$file.relative)
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
                (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ne [string]$file.sha256) {
                throw "Rollback backup checksum mismatch: $($entry.id) / $($file.relative)"
            }
        }
    }
    return $state
}

function Day10-FourStopProxies {
    param($State)
    foreach ($p in @($State.proxy_pids)) {
        $id = [int]$p
        if ($id -le 0) { continue }
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
        if ($null -eq $proc) { continue }
        if ($proc.Name -notin @("java.exe","javaw.exe") -or
            [string]::IsNullOrWhiteSpace([string]$proc.CommandLine) -or
            $proc.CommandLine.IndexOf([string]$State.proxy_install_root,[StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw "PID $id is not the expected Day10 proxy; refusing to kill it"
        }
        Stop-Process -Id $id -Force -ErrorAction Stop
    }
    foreach ($port in @(25565,25566,25567)) {
        # Never terminate an unrelated port owner.
        $listener = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
        if ($listener.Count -gt 0) { throw "Public TCP port $port remains occupied; stop the unexpected process before rollback" }
    }
}

function Day10-FourRestore {
    param([string]$Root)
    $state = Day10-FourRollbackAssert $Root  # Pre-verify before touching the host.
    Write-Host "DAY10 FOUR-SERVER ROLLBACK START"
    foreach ($name in @("wild","playground","other")) {
        $current = Day10-State $name
        if ($null -eq $current) { throw "GSC server state missing: $name" }
        if ([bool]$current.online) {
            Day10-Gsc "POST" "/api/server/action" @{id=$name;action="stop"} | Out-Null
            Day10-WaitOnline $name $false 180 | Out-Null
        }
    }
    $lobby = Day10-State "lobby"
    if ($null -ne $lobby -and [bool]$lobby.online) {
        Day10-Gsc "POST" "/api/server/action" @{id="lobby";action="stop"} | Out-Null
        Day10-WaitOnline "lobby" $false 180 | Out-Null
    }
    Day10-FourStopProxies $state
    foreach ($entry in $state.servers) {
        $source = Join-Path $Root ("servers\" + $entry.id)
        $destination = [string]$entry.path
        if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
            throw "Original backend directory missing: $destination"
        }
        # Preserve any test-session changes in quarantine; never wipe them silently.
        $quarantine = Join-Path $Root ("quarantine\" + $entry.id)
        New-Item -ItemType Directory -Force -Path $quarantine | Out-Null
        foreach ($relative in @("server.properties","config","spigot.yml","plugins")) {
            $current = Join-Path $destination $relative
            if (Test-Path -LiteralPath $current) {
                $saved = Join-Path $quarantine $relative
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved) | Out-Null
                Copy-Item -LiteralPath $current -Destination $saved -Recurse -Force -ErrorAction Stop
            }
        }
        foreach ($relative in @("server.properties","config","spigot.yml","plugins")) {
            $target = Join-Path $destination $relative
            $original = Join-Path $source $relative
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
            }
            if (Test-Path -LiteralPath $original) {
                Copy-Item -LiteralPath $original -Destination $target -Recurse -Force -ErrorAction Stop
            }
        }
        foreach ($file in @((Get-Content -LiteralPath (Join-Path $source "backup-manifest.json") -Raw | ConvertFrom-Json).files)) {
            $restored = Join-Path $destination ([string]$file.relative)
            if ((Get-FileHash -LiteralPath $restored -Algorithm SHA256).Hash -ne [string]$file.sha256) {
                throw "Restored config/plugin hash mismatch: $($entry.id) / $($file.relative)"
            }
        }
    }
    if ($null -ne $lobby) {
        Day10-Gsc "POST" "/api/v4/server-profile" @{action="delete";server=@{id="lobby"}} | Out-Null
    }
    foreach ($entry in $state.servers) {
        Day10-Gsc "POST" "/api/v4/server-profile" @{action="update";server=$entry.profile} | Out-Null
    }
    foreach ($name in @("Geumyi Day10 Velocity Java","Geumyi Day10 Geyser UDP")) {
        Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
    }
    if (Test-Path -LiteralPath ([string]$state.proxy_install_root)) {
        # Quarantine new installation instead of deleting generated Floodgate keys or logs.
        $quarantine = Join-Path $Root "quarantine\deployed-proxies"
        if (Test-Path -LiteralPath $quarantine) { throw "Proxy rollback quarantine already exists" }
        Move-Item -LiteralPath ([string]$state.proxy_install_root) -Destination $quarantine -ErrorAction Stop
    }
    # Lobby is never deleted: its world and logs may contain valuable test data.
    if (Test-Path -LiteralPath ([string]$state.lobby_path)) {
        $quarantine = Join-Path $Root "quarantine\new-lobby"
        if (Test-Path -LiteralPath $quarantine) { throw "Lobby rollback quarantine already exists" }
        Move-Item -LiteralPath ([string]$state.lobby_path) -Destination $quarantine -ErrorAction Stop
    }
    foreach ($entry in $state.servers) {
        if ([bool]$entry.was_online) {
            Day10-Gsc "POST" "/api/server/action" @{id=$entry.id;action="start"} | Out-Null
            Day10-WaitOnline ([string]$entry.id) $true 240 | Out-Null
        }
    }
    Write-Host "DAY10 FOUR-SERVER ROLLBACK VERIFIED; backup and quarantine retained: $Root"
}

if ($SelfTest) {
    $a = $PSCommandPath
    if (-not (Test-Path -LiteralPath $a -PathType Leaf)) { throw "Rollback script missing" }
    if ($a -eq (Join-Path $PSScriptRoot "rollback_day10.ps1")) { throw "Retired rollback script chosen" }
    Write-Host "DAY10 FOUR-SERVER ROLLBACK SOURCE SELFTEST PASS"
    exit 0
}
Day10-FourRestore $BackupRoot
