param([switch]$SelfTest)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "day10_live_helpers.ps1")

function Day10-FourPortMap {
    return [ordered]@{ wild=25570; playground=25571; other=25572; lobby=25573 }
}

function Day10-ValidateFourPaths {
    param([System.Collections.IDictionary]$Paths)
    $unique = @()
    foreach ($id in @("wild","playground","other","lobby")) {
        if (-not $Paths.Contains($id)) { throw "Missing path: $id" }
        $root = [string]$Paths[$id]
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Missing folder: $id" }
        foreach ($relative in @("server.properties","config\paper-global.yml")) {
            if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
                throw "Missing required config: $id/$relative"
            }
        }
        $unique += (Resolve-Path -LiteralPath $root).Path.ToLowerInvariant()
    }
    if (@($unique | Select-Object -Unique).Count -ne 4) { throw "Duplicate backend paths" }
}

function Day10-RequireAllOffline {
    # The finalizer must first gracefully stop each existing backend in GSC.
    foreach ($id in @("wild","playground","other")) {
        $status = Day10-State $id
        if ($null -eq $status -or [bool]$status.online) {
            throw "Cannot verify backend is offline: $id"
        }
    }
    $map = Day10-FourPortMap
    foreach ($id in @("wild","playground","other","lobby")) {
        $port = [int]$map[$id]
        if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
            throw "Target private port in use: $port"
        }
    }
}

function Day10-SnapshotFourConfig {
    param([System.Collections.IDictionary]$Paths, [string]$BackupRoot)
    Day10-ValidateFourPaths $Paths
    if (Test-Path -LiteralPath $BackupRoot) { throw "Refusing to overwrite backup: $BackupRoot" }
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $files = @()
    try {
        foreach ($id in @("wild","playground","other","lobby")) {
            foreach ($relative in @("server.properties","config\paper-global.yml")) {
                $src = Join-Path ([string]$Paths[$id]) $relative
                $saved = Join-Path (Join-Path $BackupRoot $id) $relative
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved) | Out-Null
                Copy-Item -LiteralPath $src -Destination $saved -ErrorAction Stop
                $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
                if ((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ne $hash) {
                    throw "Backup hash mismatch for $id/$relative"
                }
                $files += [ordered]@{id=$id;relative=$relative;sha256=$hash}
            }
        }
        $manifest = [ordered]@{schema=1;created=(Get-Date).ToString("o");paths=$Paths;files=$files}
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $BackupRoot "manifest.json") -Encoding UTF8
    } catch {
        Remove-Item -LiteralPath $BackupRoot -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Day10-RestoreFourConfig {
    param([string]$BackupRoot)
    $manifestPath = Join-Path $BackupRoot "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Port rollback manifest is missing"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([int]$manifest.schema -ne 1 -or @($manifest.files).Count -ne 8) {
        throw "Incomplete port rollback manifest"
    }
    # Verify every backup file before changing any destination.
    foreach ($entry in @($manifest.files)) {
        $source = Join-Path (Join-Path $BackupRoot ([string]$entry.id)) ([string]$entry.relative)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
            (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne [string]$entry.sha256) {
            throw "Damaged rollback source: $source"
        }
    }
    foreach ($entry in @($manifest.files)) {
        $source = Join-Path (Join-Path $BackupRoot ([string]$entry.id)) ([string]$entry.relative)
        $destRoot = [string]$manifest.paths.([string]$entry.id)
        $dest = Join-Path $destRoot ([string]$entry.relative)
        Copy-Item -LiteralPath $source -Destination $dest -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne [string]$entry.sha256) {
            throw "Rollback verification failed: $dest"
        }
    }
    Write-Host "DAY10 FOUR-SERVER CONFIG ROLLBACK VERIFIED"
}

function Day10-ApplyFourConfig {
    param(
        [System.Collections.IDictionary]$Paths,
        [string]$BackupRoot,
        [string]$SecretFile,
        [switch]$SyntheticTestOnly
    )
    if (-not $SyntheticTestOnly) { Day10-RequireAllOffline }
    if (-not (Test-Path -LiteralPath $SecretFile -PathType Leaf)) {
        throw "Forwarding secret file is missing"
    }
    $secret = (Get-Content -LiteralPath $SecretFile -Raw).Trim()
    if ($secret.Length -lt 32 -or $secret.Contains([char]34) -or $secret.Contains([char]10)) {
        throw "Invalid Velocity forwarding secret"
    }
    Day10-SnapshotFourConfig $Paths $BackupRoot
    $map = Day10-FourPortMap
    try {
        foreach ($id in @("wild","playground","other","lobby")) {
            $root = [string]$Paths[$id]
            $props = Join-Path $root "server.properties"
            Day10-SetServerProperty $props "server-ip" "127.0.0.1"
            Day10-SetServerProperty $props "server-port" ([string]$map[$id])
            Day10-SetServerProperty $props "online-mode" "false"
            Day10-SetServerProperty $props "enforce-secure-profile" "false"
            Day10-SetPaperVelocity (Join-Path $root "config\paper-global.yml") $secret
            $text = Get-Content -LiteralPath $props -Raw
            if (-not $text.Contains("server-port=$($map[$id])") -or
                -not $text.Contains("server-ip=127.0.0.1")) {
                throw "Private port verification failed: $id"
            }
        }
        Write-Host "DAY10 FOUR BACKEND CONFIGS UPDATED"
    } catch {
        $reason = $_.Exception.Message
        Day10-RestoreFourConfig $BackupRoot
        throw "Port transaction failed and configuration was restored: $reason"
    }
}

function Day10-TestFourConfig {
    $root = Join-Path $env:TEMP ("Geumyi-FourPortTest-" + [guid]::NewGuid().ToString("N"))
    $paths = [ordered]@{}
    try {
        $list = @(
            @{id="wild";port=25565;rcon=25575},
            @{id="playground";port=25566;rcon=25576},
            @{id="other";port=25567;rcon=25577},
            @{id="lobby";port=25573;rcon=25579}
        )
        foreach ($entry in $list) {
            $dir = Join-Path $root ([string]$entry.id)
            New-Item -ItemType Directory -Path (Join-Path $dir "config") -Force | Out-Null
            [IO.File]::WriteAllLines((Join-Path $dir "server.properties"),
                @("server-port=$($entry.port)","rcon.port=$($entry.rcon)","online-mode=true","server-ip="),
                [Text.Encoding]::ASCII)
            $paper = @("proxies:","  velocity:","    enabled: false","    online-mode: true","    secret: empty") -join [Environment]::NewLine
            [IO.File]::WriteAllText((Join-Path $dir "config\paper-global.yml"),
                $paper, (New-Object Text.UTF8Encoding($false)))
            $paths[[string]$entry.id] = $dir
        }
        $secret = Join-Path $root "forwarding.secret"
        [IO.File]::WriteAllText($secret, "abcdefghijklmnopqrstuvwx12345678")
        $backup = Join-Path $root "backup"
        Day10-ApplyFourConfig $paths $backup $secret -SyntheticTestOnly
        $map = Day10-FourPortMap
        foreach ($entry in $list) {
            $id = [string]$entry.id
            $props = Get-Content -LiteralPath (Join-Path $paths[$id] "server.properties") -Raw
            if (-not $props.Contains("server-port=$($map[$id])") -or
                -not $props.Contains("rcon.port=$($entry.rcon)")) {
                throw "Port or RCON changed unexpectedly: $id"
            }
        }
        Day10-RestoreFourConfig $backup
        $manifest = Get-Content -LiteralPath (Join-Path $backup "manifest.json") -Raw | ConvertFrom-Json
        foreach ($entry in @($manifest.files)) {
            $dest = Join-Path ([string]$paths[[string]$entry.id]) ([string]$entry.relative)
            if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne [string]$entry.sha256) {
                throw "Byte-exact rollback regression: $dest"
            }
        }
        Write-Host "DAY10 FOUR-SERVER PORT TRANSACTION SELFTEST PASS"
    } finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($SelfTest) { Day10-TestFourConfig; exit 0 }
