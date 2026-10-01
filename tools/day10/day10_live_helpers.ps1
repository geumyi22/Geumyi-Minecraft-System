Set-StrictMode -Version Latest

function Day10-Gsc {
    param([string]$Method, [string]$Path, $Body = $null)
    $uri = "http://127.0.0.1:8787$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec 20
    }
    $json = $Body | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec 20 -ContentType "application/json" -Body $json
}

function Day10-WaitGsc {
    param([int]$Seconds = 120)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            $h = Invoke-RestMethod -Method GET -Uri "http://127.0.0.1:8787/api/health" -TimeoutSec 5
            if ($h.ok) { return $h }
        } catch {}
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "GSC readiness timeout"
}

function Day10-State {
    param([string]$Id)
    $s = Day10-Gsc "GET" "/api/status"
    return @($s.servers) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Day10-WaitOnline {
    param([string]$Id, [bool]$Want, [int]$Seconds = 240)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $state = Day10-State $Id
        if ($null -ne $state -and [bool]$state.online -eq $Want) { return $state }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    throw "$Id online=$Want timeout"
}

function Day10-WaitTcp {
    param([int]$Port, [bool]$Want, [int]$Seconds = 90)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $open = $false
        $client = New-Object Net.Sockets.TcpClient
        try {
            $ar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(800)) {
                $client.EndConnect($ar)
                $open = $true
            }
        } catch {
            $open = $false
        } finally {
            $client.Close()
        }
        if ($open -eq $Want) { return }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "TCP port $Port open=$Want timeout"
}

function Day10-VerifySums {
    param([string]$Directory)
    $sumFile = Join-Path $Directory "SHA256SUMS.txt"
    if (-not (Test-Path -LiteralPath $sumFile)) { throw "SHA256SUMS.txt missing: $Directory" }
    foreach ($line in Get-Content -LiteralPath $sumFile) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { throw "bad checksum line: $line" }
        $expected = $Matches[1].ToLowerInvariant()
        $file = Join-Path $Directory $Matches[2].Trim()
        if (-not (Test-Path -LiteralPath $file)) { throw "artifact missing: $file" }
        $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "SHA256 mismatch: $file" }
    }
}

function Day10-SetServerProperty {
    param([string]$Path, [string]$Key, [string]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { throw "server.properties missing: $Path" }
    $lines = @(Get-Content -LiteralPath $Path)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trim = $lines[$i].Trim()
        if ($trim.StartsWith("#") -or -not $trim.Contains("=")) { continue }
        $parts = $trim.Split("=", 2)
        if ($parts[0].Trim() -eq $Key) {
            $lines[$i] = "$Key=$Value"
            $found = $true
            break
        }
    }
    if (-not $found) { $lines += "$Key=$Value" }
    [IO.File]::WriteAllLines($Path, $lines, (New-Object Text.UTF8Encoding($false)))
}

function Day10-SetPaperVelocity {
    param([string]$Path, [string]$Secret)
    if (-not (Test-Path -LiteralPath $Path)) { throw "paper-global.yml missing: $Path" }
    $lines = @((Get-Content -LiteralPath $Path -Raw).Replace([Environment]::NewLine, "`n").Split([char]10))
    $proxies = -1
    $velocity = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $indent = $lines[$i].Length - $lines[$i].TrimStart().Length
        if ($indent -eq 0 -and $lines[$i].Trim() -eq "proxies:") {
            $proxies = $i
            break
        }
    }
    if ($proxies -lt 0) { throw "paper-global.yml proxies section missing" }
    for ($i = $proxies + 1; $i -lt $lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        $indent = $lines[$i].Length - $lines[$i].TrimStart().Length
        if ($indent -eq 0) { break }
        if ($indent -eq 2 -and $lines[$i].Trim() -eq "velocity:") {
            $velocity = $i
            break
        }
    }
    if ($velocity -lt 0) { throw "paper-global.yml proxies.velocity section missing" }
    $end = $lines.Count
    for ($i = $velocity + 1; $i -lt $lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        $indent = $lines[$i].Length - $lines[$i].TrimStart().Length
        if ($indent -le 2) {
            $end = $i
            break
        }
    }
    $wanted = @{
        "enabled" = "true"
        "online-mode" = "true"
        "secret" = ([char]34 + $Secret.Replace([string][char]34, [string]::Empty) + [char]34)
    }
    foreach ($key in @("enabled", "online-mode", "secret")) {
        $found = $false
        for ($i = $velocity + 1; $i -lt $end; $i++) {
            $indent = $lines[$i].Length - $lines[$i].TrimStart().Length
            if ($indent -eq 4 -and $lines[$i].Trim().StartsWith("${key}:")) {
                $lines[$i] = "    ${key}: " + $wanted[$key]
                $found = $true
                break
            }
        }
        if (-not $found) {
            $before = @($lines[0..($end - 1)])
            $after = @()
            if ($end -lt $lines.Count) { $after = @($lines[$end..($lines.Count - 1)]) }
            $lines = @($before + ("    ${key}: " + $wanted[$key]) + $after)
            $end++
        }
    }
    [IO.File]::WriteAllText($Path, ($lines -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}

function Day10-SetSpigotBungeeFalse {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = @(Get-Content -LiteralPath $Path)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s+bungeecord:\s*') {
            $indent = $lines[$i].Substring(0, $lines[$i].Length - $lines[$i].TrimStart().Length)
            $lines[$i] = $indent + "bungeecord: false"
            [IO.File]::WriteAllLines($Path, $lines, (New-Object Text.UTF8Encoding($false)))
            return
        }
    }
}

function Day10-SetYamlChild {
    param([string]$Text, [string]$Section, [string]$Key, [string]$Value)
    $lines = @($Text.Replace([Environment]::NewLine, "`n").Split([char]10))
    $sectionIndex = -1
    $sectionIndent = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq ($Section + ":")) {
            $sectionIndex = $i
            $sectionIndent = $lines[$i].Length - $lines[$i].TrimStart().Length
            break
        }
    }
    if ($sectionIndex -lt 0) { throw "YAML section missing: $Section" }
    $end = $lines.Count
    for ($i = $sectionIndex + 1; $i -lt $lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        $indent = $lines[$i].Length - $lines[$i].TrimStart().Length
        if ($indent -le $sectionIndent) {
            $end = $i
            break
        }
    }
    $childIndent = $sectionIndent + 2
    for ($i = $sectionIndex + 1; $i -lt $end; $i++) {
        $indent = $lines[$i].Length - $lines[$i].TrimStart().Length
        if ($indent -eq $childIndent -and $lines[$i].Trim().StartsWith($Key + ":")) {
            $lines[$i] = (" " * $childIndent) + $Key + ": " + $Value
            return ($lines -join [Environment]::NewLine)
        }
    }
    $before = @($lines[0..($end - 1)])
    $after = @()
    if ($end -lt $lines.Count) { $after = @($lines[$end..($lines.Count - 1)]) }
    return (@($before + ((" " * $childIndent) + $Key + ": " + $Value) + $after) -join [Environment]::NewLine)
}

function Day10-SetGeyserConfig {
    param([string]$Path, [int]$BedrockPort)
    $text = Get-Content -LiteralPath $Path -Raw
    $text = Day10-SetYamlChild $text "bedrock" "address" "0.0.0.0"
    $text = Day10-SetYamlChild $text "bedrock" "port" ([string]$BedrockPort)
    $text = Day10-SetYamlChild $text "bedrock" "clone-remote-port" "false"
    $text = Day10-SetYamlChild $text "remote" "address" "auto"
    $text = Day10-SetYamlChild $text "remote" "auth-type" "floodgate"
    [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Day10-ConfigureLobbyGds {
    param([string]$TemplatePath, [string]$DestinationPath)
    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        throw "GDS config template missing: $TemplatePath"
    }
    $text = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
    $text = Day10-SetYamlChild $text "server" "id" "lobby"
    $text = Day10-SetYamlChild $text "server" "name" '"Geumyi Lobby"'
    $text = Day10-SetYamlChild $text "bridge" "enabled" "false"
    $text = Day10-SetYamlChild $text "agent" "enabled" "false"
    $text = Day10-SetYamlChild $text "api" "enabled" "true"
    $text = Day10-SetYamlChild $text "api" "bind" '"127.0.0.1"'
    $text = Day10-SetYamlChild $text "api" "port" "8767"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DestinationPath) | Out-Null
    [IO.File]::WriteAllText($DestinationPath, $text, (New-Object Text.UTF8Encoding($false)))
}

function Day10-CopyArtifactJar {
    param([string]$ArtifactDir, [string]$Destination, [string]$Pattern = "*.jar")
    $jar = Get-ChildItem -LiteralPath $ArtifactDir -File | Where-Object { $_.Name -like $Pattern } | Select-Object -First 1
    if ($null -eq $jar) { throw "JAR not found: $ArtifactDir pattern=$Pattern" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $jar.FullName -Destination $Destination -Force
}

function Day10-FindPaperJar {
    param([string]$ServerDir)
    $start = Join-Path $ServerDir "start.bat"
    if (Test-Path -LiteralPath $start) {
        $text = Get-Content -LiteralPath $start -Raw
        $match = [regex]::Match($text, '(?i)-jar\s+(?:"([^"]+[.]jar)"|([^\s"]+[.]jar))')
        if ($match.Success) {
            $name = $match.Groups[1].Value
            if ([string]::IsNullOrWhiteSpace($name)) { $name = $match.Groups[2].Value }
            $candidate = Join-Path $ServerDir $name
            if (Test-Path -LiteralPath $candidate) { return (Resolve-Path $candidate).Path }
        }
    }
    $fallback = Get-ChildItem -LiteralPath $ServerDir -File -Filter "*.jar" |
        Where-Object { $_.Name -match '(?i)paper' } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if ($null -eq $fallback) { throw "Paper JAR not found: $ServerDir" }
    return $fallback.FullName
}

function Day10-DisableBackendProxyPlugins {
    param([string]$ServerDir)
    $pluginDir = Join-Path $ServerDir "plugins"
    if (-not (Test-Path -LiteralPath $pluginDir)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $pluginDir -File) {
        if ($file.Name -match '(?i)^(Geyser-Spigot|floodgate-spigot).*[.]jar$') {
            Move-Item -LiteralPath $file.FullName -Destination ($file.FullName + ".day10-disabled") -Force
        }
    }
}

function Day10-WriteNetworkConfig {
    param([string]$ServerDir, [string]$ServerId)
    $dir = Join-Path $ServerDir "plugins\GeumyiNetwork"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lines = @(
        "server-id: $ServerId",
        "lobby-server: lobby",
        "location-api: http://127.0.0.1:8787/api/v4/network/player-location",
        "restore-on-join: true",
        "save-on-quit: true",
        "save-interval-seconds: 60",
        "request-timeout-millis: 2500"
    )
    [IO.File]::WriteAllLines((Join-Path $dir "config.yml"), $lines, (New-Object Text.UTF8Encoding($false)))
}

function Day10-ProfileFromSettings {
    param($Server, [int]$JavaPort, [int]$BedrockPort, [bool]$AutoStart)
    return @{
        id = [string]$Server.id
        name = [string]$Server.name
        role = [string]$Server.role
        update_policy = [string]$Server.update_policy
        java_port = $JavaPort
        rcon_port = [int]$Server.rcon_port
        bedrock_port = $BedrockPort
        gds_api_port = [int]$Server.gds_api_port
        path = [string]$Server.path
        path_file = [string]$Server.path_file
        start_command = [string]$Server.start_command
        auto_start = $AutoStart
        restart_on_crash = [bool]$Server.restart_on_crash
    }
}


# The existing 5.12.1-SNAPSHOT pair is already deployed by this host.
# Retain it on Wild/Playground. ViaVersionStatus is a separate plugin, not ViaVersion.
function Day10-GetViaBaseline {
    param([string]$ServerDir)
    $pluginDir = Join-Path $ServerDir "plugins"
    if (-not (Test-Path -LiteralPath $pluginDir -PathType Container)) {
        throw "Plugin directory missing: $pluginDir"
    }
    $files = @(Get-ChildItem -LiteralPath $pluginDir -File)
    $via = @($files | Where-Object { $_.Name -match '^ViaVersion-(.+)[.]jar$' })
    $back = @($files | Where-Object { $_.Name -match '^ViaBackwards-(.+)[.]jar$' })
    $net = @($files | Where-Object { $_.Name -match '^GeumyiNetwork.*[.]jar$' })
    if ($net.Count -ne 0 -or (Test-Path -LiteralPath (Join-Path $pluginDir "GeumyiNetwork"))) {
        throw "Existing GeumyiNetwork installation needs manual reconciliation: $ServerDir"
    }
    if ($via.Count -gt 1 -or $back.Count -gt 1) {
        throw "Multiple ViaVersion/ViaBackwards JARs found: $ServerDir"
    }
    if ($via.Count -ne $back.Count) {
        throw "Incomplete ViaVersion/ViaBackwards pair: $ServerDir"
    }
    if ($via.Count -eq 0) {
        return [pscustomobject]@{ Installed = $false; Version = ""; ViaName = ""; BackName = "" }
    }
    $viaVersion = [regex]::Match($via[0].Name, '^ViaVersion-(.+)[.]jar$').Groups[1].Value
    $backVersion = [regex]::Match($back[0].Name, '^ViaBackwards-(.+)[.]jar$').Groups[1].Value
    if ($viaVersion -ne $backVersion) {
        throw "Via pair versions differ: $viaVersion vs $backVersion in $ServerDir"
    }
    if ($viaVersion -notin @("5.12.1-SNAPSHOT", "5.12.0")) {
        throw "Via pair $viaVersion not reviewed for Day 10: $ServerDir"
    }
    return [pscustomobject]@{
        Installed = $true
        Version = $viaVersion
        ViaName = $via[0].Name
        BackName = $back[0].Name
    }
}

function Day10-BackupBackendPlugins {
    param([string]$ServerDir, [string]$BackupRoot, [string]$Id)
    $pluginDir = Join-Path $ServerDir "plugins"
    $dest = Join-Path $BackupRoot ($Id + "\plugins-original")
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $names = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $pluginDir -File)) {
        if ($file.Name -match '^(ViaVersion-|ViaBackwards-|ViaVersionStatus-|Geyser-Spigot|floodgate-spigot).*([.]jar)$') {
            $copy = Join-Path $dest $file.Name
            Copy-Item -LiteralPath $file.FullName -Destination $copy -ErrorAction Stop
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $hash) {
                throw "Plugin backup hash mismatch: $($file.FullName)"
            }
            $names += $file.Name
        }
    }
    $dataFolders = @("ViaVersion", "ViaBackwards", "ViaVersionStatus", "Geyser-Spigot", "floodgate")
    foreach ($name in $dataFolders) {
        $source = Join-Path $pluginDir $name
        if (Test-Path -LiteralPath $source -PathType Container) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $dest $name) -Recurse -ErrorAction Stop
        }
    }
    return @($names)
}

function Day10-InstallViaIfMissing {
    param([string]$ServerDir, [string]$ViaSource, [string]$BackSource)
    $baseline = Day10-GetViaBaseline $ServerDir
    if ($baseline.Installed) {
        Write-Host ("Keeping existing Via pair " + $baseline.Version + " in " + $ServerDir)
        return
    }
    $pluginDir = Join-Path $ServerDir "plugins"
    $viaDest = Join-Path $pluginDir "ViaVersion-5.12.0.jar"
    $backDest = Join-Path $pluginDir "ViaBackwards-5.12.0.jar"
    if ((Test-Path -LiteralPath $viaDest) -or (Test-Path -LiteralPath $backDest)) {
        throw "Via installation target already exists: $ServerDir"
    }
    Copy-Item -LiteralPath $ViaSource -Destination $viaDest -ErrorAction Stop
    Copy-Item -LiteralPath $BackSource -Destination $backDest -ErrorAction Stop
}

function Day10-RestoreBackendPlugins {
    param([string]$ServerDir, [string]$BackupRoot, [string]$Id)
    if ([string]::IsNullOrWhiteSpace($serverDir)) { throw "Missing rollback server path" }
    $pluginDir = Join-Path $serverDir "plugins"
    $originalDir = Join-Path $BackupRoot ($Id + "\plugins-original")
    if (-not (Test-Path -LiteralPath $originalDir -PathType Container)) {
        throw "Original plugin backup is missing: $originalDir"
    }

    # Remove only artifacts that the finalizer added and that were not
    # present in the original backup. Never remove an existing Via pair.
    foreach ($name in @(
        "GeumyiNetwork-0.1.0-Paper26.3.jar",
        "ViaVersion-5.12.0.jar",
        "ViaBackwards-5.12.0.jar"
    )) {
        $original = Join-Path $originalDir $name
        $installed = Join-Path $pluginDir $name
        if (-not (Test-Path -LiteralPath $original) -and (Test-Path -LiteralPath $installed)) {
            Remove-Item -LiteralPath $installed -Force -ErrorAction Stop
        }
    }
    Remove-Item -LiteralPath (Join-Path $pluginDir "GeumyiNetwork") -Recurse -Force -ErrorAction SilentlyContinue

    # On cutover Geyser/Floodgate JARs are renamed to .day10-disabled.
    # Copy the verified original JAR bytes back, then remove the disabled copy.
    if (Test-Path -LiteralPath $pluginDir) {
        foreach ($disabled in @(Get-ChildItem -LiteralPath $pluginDir -File -Filter "*.day10-disabled")) {
            $suffix = ".day10-disabled"
            $name = $disabled.Name.Substring(0, $disabled.Name.Length - $suffix.Length)
            $original = Join-Path $originalDir $name
            $target = Join-Path $pluginDir $name
            if (Test-Path -LiteralPath $original) {
                Copy-Item -LiteralPath $original -Destination $target -Force -ErrorAction Stop
                if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne
                    (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash) {
                    throw "Original plugin restoration failed: $target"
                }
                Remove-Item -LiteralPath $disabled.FullName -Force -ErrorAction Stop
            } else {
                if (Test-Path -LiteralPath $target) {
                    throw "Plugin rollback name collision: $target"
                }
                Move-Item -LiteralPath $disabled.FullName -Destination $target -ErrorAction Stop
            }
        }
    }
    # Restore all original Via/Status/Geyser/Floodgate JARs by exact filename
    # and verify the resulting SHA-256 rather than guessing file versions.
    foreach ($file in @(Get-ChildItem -LiteralPath $originalDir -File)) {
        $target = Join-Path $pluginDir $file.Name
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) {
            throw "Plugin hash mismatch after rollback: $target"
        }
    }
}

function Day10-AssertLoopbackListener {
    param([int]$Port)
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) { throw "backend port not listening: $Port" }
    foreach ($listener in $listeners) {
        if ($listener.LocalAddress -notin @("127.0.0.1", "::1")) {
            throw "backend port $Port exposed on $($listener.LocalAddress)"
        }
    }
}
