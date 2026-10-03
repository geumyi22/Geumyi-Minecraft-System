Set-StrictMode -Version Latest

function Day10-NewPlainRconPassword {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (-join ($bytes | ForEach-Object { $_.ToString("x2") }))
}

function Day10-GeyserConfigComplete {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $text = Day10-ReadUtf8Strict $Path
        Day10-AssertYamlTextSafe $text $Path
        if ((Get-Item -LiteralPath $Path).Length -le 128) { return $false }
        return ($text -match "(?m)^bedrock:\s*")
    } catch {
        return $false
    }
}
function Day10-FourRequireSuccess {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE" }
}
function Day10-FourSaveState {
    param([string]$Path, $State)
    $tmp = $Path + ".tmp"
    $State | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Day10-FourTrackProcess {
    param([string]$Path, $State, [int]$ProcessId)
    $State.proxy_pids = @($State.proxy_pids) + @($ProcessId)
    Day10-FourSaveState $Path $State
}
function Day10-FourManifest {
    param([string]$Root)
    $files = @()
    foreach ($relative in @("server.properties","config\paper-global.yml","spigot.yml")) {
        $src = Join-Path $Root $relative
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            $files += [ordered]@{relative=$relative;sha256=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash}
        }
    }
    foreach ($jar in @(Get-ChildItem -LiteralPath (Join-Path $Root "plugins") -File -Filter "*.jar" -ErrorAction Stop)) {
        $files += [ordered]@{relative=("plugins\" + $jar.Name);sha256=(Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256).Hash}
    }
    return [ordered]@{schema=1;files=$files}
}
function Day10-FourBackupServer {
    param([string]$From,[string]$To)
    if (Test-Path -LiteralPath $To) { throw "Backup destination exists: $To" }
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    & robocopy.exe $From $To /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NP /NFL /NDL
    if ($LASTEXITCODE -ge 4) { throw "Full server backup returned a mismatch/error: $From code=$LASTEXITCODE" }
    $sourceFiles=@(Get-ChildItem -LiteralPath $From -File -Recurse -Force -ErrorAction Stop)
    $copiedFiles=@(Get-ChildItem -LiteralPath $To -File -Recurse -Force -ErrorAction Stop)
    if($sourceFiles.Count -ne $copiedFiles.Count){throw "Full backup file count mismatch: $From"}
    $sourceBytes=[long]0; $copiedBytes=[long]0
    foreach($file in $sourceFiles){$sourceBytes += [long]$file.Length}
    foreach($file in $copiedFiles){$copiedBytes += [long]$file.Length}
    if($sourceBytes -ne $copiedBytes){throw "Full backup size mismatch: $From"}
    $manifest = Day10-FourManifest $From
    foreach ($file in $manifest.files) {
        $saved = Join-Path $To ([string]$file.relative)
        if (-not (Test-Path -LiteralPath $saved -PathType Leaf) -or
            (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ne [string]$file.sha256) {
            throw "Backup hash mismatch: $saved"
        }
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $To "backup-manifest.json") -Encoding UTF8
}
function Day10-FourCheckBackupSpace {
    param([string[]]$Paths,[string]$BackupRoot)
    $bytes = [long]0
    foreach ($p in $Paths) {
        foreach ($file in @(Get-ChildItem -LiteralPath $p -File -Recurse -Force -ErrorAction Stop)) {
            $bytes += [long]$file.Length
        }
    }
    $parent = Split-Path -Parent $BackupRoot
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $drive = (Get-Item -LiteralPath $parent).PSDrive
    if ($null -eq $drive.Free -or [long]$drive.Free -lt ($bytes + 4GB)) {
        throw "Backup needs at least $(($bytes + 4GB) / 1GB) GiB free on $($drive.Name)"
    }
}
function Day10-FourGetArtifacts {
    param([string]$Destination,[string]$Repository)
    $gh = (Get-Command gh.exe -ErrorAction Stop).Source
    & $gh auth status *> $null
    Day10-FourRequireSuccess "GitHub authentication (run gh auth login first)"
    $mainSHA = ((& $gh api "repos/$Repository/commits/main" --jq .sha) -join "").Trim()
    Day10-FourRequireSuccess "Resolve main SHA"
    if ($mainSHA -notmatch '^[0-9a-f]{40}$') { throw "Invalid main SHA" }
    $runs = (& $gh run list --repo $Repository --workflow system-ci.yml --branch main --limit 30 --json databaseId,headSha,conclusion,status | ConvertFrom-Json)
    Day10-FourRequireSuccess "List main System CI runs"
    $selected = @($runs | Where-Object { $_.headSha -eq $mainSHA -and $_.conclusion -eq "success" -and $_.status -eq "completed" }) | Select-Object -First 1
    if ($null -eq $selected) { throw "Current main has no passing System CI. Do not deploy." }
    foreach ($name in @("lobby-0.1.0","network-0.1.0","gst-1.1.1-hotfix","gds-1.1.1")) {
        $folder = Join-Path $Destination $name
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        & $gh run download $selected.databaseId --repo $Repository --name $name --dir $folder
        Day10-FourRequireSuccess "Download CI artifact $name"
        $jar = @(Get-ChildItem -LiteralPath $folder -File -Filter "*.jar")
        if ($jar.Count -ne 1 -or $jar[0].Length -lt 10000) {
            throw "Unexpected JAR artifact contents: $name"
        }
    }
    $gsc = Join-Path $Destination "gsc-4.2.4-ci"
    New-Item -ItemType Directory -Path $gsc -Force | Out-Null
    & $gh run download $selected.databaseId --repo $Repository --name "gsc-4.2.4-ci" --dir $gsc
    Day10-FourRequireSuccess "Download current-main GSC CI artifact"
    Day10-VerifySums $gsc
    $setup = Join-Path $gsc "GeumyiServerCenter-v4.2.4-Setup.exe"
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf) -or
        (Get-Item -LiteralPath $setup).Length -lt 100000) {
        throw "Verified GSC setup is missing from current-main CI artifact"
    }
    return [pscustomobject]@{Commit=$mainSHA;Run=$selected.databaseId;Setup=$setup}
}
function Day10-FourCreateLobby {
    param([string]$Path,[string]$Wild,[string]$Artifacts,[string]$Bedrock,[int]$GdsPort)
    if (Test-Path -LiteralPath $Path) { throw "Lobby folder already exists" }
    New-Item -ItemType Directory -Path (Join-Path $Path "plugins") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Path "config") -Force | Out-Null
    Copy-Item -LiteralPath (Day10-FindPaperJar $Wild) -Destination (Join-Path $Path "paper.jar")
    $tpl = Join-Path $PSScriptRoot "..\..\Servers\Lobby"
    Copy-Item -LiteralPath (Join-Path $tpl "server.properties.template") -Destination (Join-Path $Path "server.properties")
    Copy-Item -LiteralPath (Join-Path $tpl "start.bat.template") -Destination (Join-Path $Path "start.bat")
    Copy-Item -LiteralPath (Join-Path $Wild "config\paper-global.yml") -Destination (Join-Path $Path "config\paper-global.yml")
    foreach ($jar in @("ViaVersion-5.12.0.jar","ViaBackwards-5.12.0.jar")) {
        Copy-Item -LiteralPath (Join-Path $Bedrock ("backend-plugins\" + $jar)) -Destination (Join-Path $Path ("plugins\" + $jar))
    }
    Day10-CopyArtifactJar (Join-Path $Artifacts "lobby-0.1.0") (Join-Path $Path "plugins\GeumyiLobby-0.1.0.jar")
    Day10-CopyArtifactJar (Join-Path $Artifacts "gst-1.1.1-hotfix") (Join-Path $Path "plugins\GeumyiServerTools-1.1.1.jar")
    Day10-CopyArtifactJar (Join-Path $Artifacts "gds-1.1.1") (Join-Path $Path "plugins\GeumyiDiscordStatus-1.1.1.jar")
    Day10-ConfigureLobbyGds (Join-Path $PSScriptRoot "..\..\Plugins\GeumyiDiscordStatus\src\main\resources\config.yml") (Join-Path $Path "plugins\GeumyiDiscordStatus\config.yml") $GdsPort
    # Plain hexadecimal avoids Java Properties escaping '=' or ':'.
    Day10-SetServerProperty (Join-Path $Path "server.properties") "rcon.password" (Day10-NewPlainRconPassword)
    [IO.File]::WriteAllText((Join-Path $Path "eula.txt"),("eula=true" + [Environment]::NewLine),[Text.Encoding]::ASCII)
}
function Day10-FourBootstrapProxy {
    param([string]$Dir,[string]$Java,[int]$BedrockPort,[string]$SharedKey,$State,[string]$StatePath)
    $geyser = Join-Path $Dir "plugins\Geyser-Velocity\config.yml"
    $key = Join-Path $Dir "plugins\floodgate\key.pem"
    if ($SharedKey -ne "") {
        New-Item -ItemType Directory -Path (Split-Path -Parent $key) -Force | Out-Null
        Copy-Item -LiteralPath $SharedKey -Destination $key
    }
    $process = Start-Process -FilePath $Java -ArgumentList @("-Xms256M","-Xmx512M","-jar",(Join-Path $Dir "velocity.jar")) -WorkingDirectory $Dir -PassThru
    Day10-FourTrackProcess $StatePath $State $process.Id
    $end = (Get-Date).AddSeconds(90)
    $stableLength = -1L
    $stableCount = 0
    $configReady = $false
    do {
        if ($process.HasExited) { throw "Velocity exited early during bootstrap: $Dir" }
        if ((Test-Path -LiteralPath $geyser -PathType Leaf) -and
            (Test-Path -LiteralPath $key -PathType Leaf)) {
            $length = (Get-Item -LiteralPath $geyser).Length
            if (Day10-GeyserConfigComplete $geyser) {
                if ($length -eq $stableLength) {
                    $stableCount++
                } else {
                    $stableLength = $length
                    $stableCount = 1
                }
                if ($stableCount -ge 2) {
                    $configReady = $true
                    break
                }
            } else {
                $stableCount = 0
                $stableLength = $length
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $end)
    if (-not $configReady) {
        throw "Velocity/Geyser/Floodgate configuration generation did not reach a complete stable config: $Dir"
    }
    Stop-Process -Id $process.Id -Force
    $process.WaitForExit(20000) | Out-Null
    Day10-SetGeyserConfig $geyser $BedrockPort
    $geyserText=Day10-ReadUtf8Strict $geyser
    $bedrockBlock=[regex]::Match($geyserText,'(?ms)^bedrock:\s*\r?\n(?<body>(?:[ \t]+.*(?:\r?\n|$))*)')
    if(-not $bedrockBlock.Success){throw "Geyser bedrock section missing after configuration: $Dir"}
    $portMatch=[regex]::Match($bedrockBlock.Groups["body"].Value,'(?m)^\s+port:\s*(\d+)\s*
}
function Day10-FourCheckPorts {
    foreach ($port in @(25570,25571,25572,25573)) { Day10-AssertLoopbackListener $port }
    foreach ($port in @(25565,25566,25567)) { Day10-WaitTcp $port $true 60 }

    foreach ($port in @(19132,19133,19134)) {
        $deadline=(Get-Date).AddSeconds(90)
        $ready=$false
        do {
            if (@(Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue).Count -gt 0) {
                $ready=$true
                break
            }
            Start-Sleep -Seconds 2
        } while ((Get-Date) -lt $deadline)
        if (-not $ready) { throw "Bedrock UDP listener missing after 90s: $port" }
    }

    # A bound UDP socket is not proof that Geyser can answer RakNet.
    # Poll the GSC network probe because Velocity TCP commonly becomes ready
    # before Geyser has completed RakNet startup.
    $deadline=(Get-Date).AddSeconds(90)
    $last=$null
    do {
        try {
            $last=Invoke-RestMethod -Method GET -Uri "http://127.0.0.1:8787/api/v4/network/entry-status" -TimeoutSec 12
            $points=@($last.endpoints)
            if($points.Count -eq 3){
                $bad=@($points | Where-Object { -not [bool]$_.java_responding -or -not [bool]$_.bedrock_raknet_pong })
                if($bad.Count -eq 0){ return }
            }
        } catch {}
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    if($null -eq $last){throw "Java/RakNet network probe unavailable after 90s"}
    $points=@($last.endpoints)
    if($points.Count -ne 3){throw "Missing Java/Bedrock network endpoint results after 90s"}
    $bad=@($points | Where-Object { -not [bool]$_.java_responding -or -not [bool]$_.bedrock_raknet_pong })
    $detail=($bad | ForEach-Object { "$($_.id):TCP=$($_.java_tcp)/$($_.java_responding),UDP=$($_.bedrock_udp)/$($_.bedrock_raknet_pong)" }) -join "; "
    throw "Java/RakNet response failed after 90s: $detail"
}

function Day10-FourProtectProxySecrets {
    param([string]$ProxyRoot)
    foreach($id in @("wild","playground","other")){
        foreach($relative in @("forwarding.secret","plugins\floodgate\key.pem")){
            $path=Join-Path (Join-Path $ProxyRoot $id) $relative
            if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing proxy secret: $id/$relative"}
            & icacls.exe $path /inheritance:r /grant:r "*S-1-5-18:(F)" "*S-1-5-32-544:(F)" | Out-Null
            if($LASTEXITCODE -ne 0){throw "Could not restrict local secret ACL: $id/$relative"}
        }
    }
}
)
    if(-not $portMatch.Success -or [int]$portMatch.Groups[1].Value -ne $BedrockPort){
        throw "Geyser UDP port verification failed for $Dir; expected $BedrockPort"
    }
    Write-Host "Configured Geyser UDP $BedrockPort for $Dir"
    return $key
}
function Day10-FourCheckPorts {
    foreach ($port in @(25570,25571,25572,25573)) { Day10-AssertLoopbackListener $port }
    foreach ($port in @(25565,25566,25567)) { Day10-WaitTcp $port $true 60 }

    foreach ($port in @(19132,19133,19134)) {
        $deadline=(Get-Date).AddSeconds(90)
        $ready=$false
        do {
            if (@(Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue).Count -gt 0) {
                $ready=$true
                break
            }
            Start-Sleep -Seconds 2
        } while ((Get-Date) -lt $deadline)
        if (-not $ready) { throw "Bedrock UDP listener missing after 90s: $port" }
    }

    # A bound UDP socket is not proof that Geyser can answer RakNet.
    # Poll the GSC network probe because Velocity TCP commonly becomes ready
    # before Geyser has completed RakNet startup.
    $deadline=(Get-Date).AddSeconds(90)
    $last=$null
    do {
        try {
            $last=Invoke-RestMethod -Method GET -Uri "http://127.0.0.1:8787/api/v4/network/entry-status" -TimeoutSec 12
            $points=@($last.endpoints)
            if($points.Count -eq 3){
                $bad=@($points | Where-Object { -not [bool]$_.java_responding -or -not [bool]$_.bedrock_raknet_pong })
                if($bad.Count -eq 0){ return }
            }
        } catch {}
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    if($null -eq $last){throw "Java/RakNet network probe unavailable after 90s"}
    $points=@($last.endpoints)
    if($points.Count -ne 3){throw "Missing Java/Bedrock network endpoint results after 90s"}
    $bad=@($points | Where-Object { -not [bool]$_.java_responding -or -not [bool]$_.bedrock_raknet_pong })
    $detail=($bad | ForEach-Object { "$($_.id):TCP=$($_.java_tcp)/$($_.java_responding),UDP=$($_.bedrock_udp)/$($_.bedrock_raknet_pong)" }) -join "; "
    throw "Java/RakNet response failed after 90s: $detail"
}

function Day10-FourProtectProxySecrets {
    param([string]$ProxyRoot)
    foreach($id in @("wild","playground","other")){
        foreach($relative in @("forwarding.secret","plugins\floodgate\key.pem")){
            $path=Join-Path (Join-Path $ProxyRoot $id) $relative
            if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing proxy secret: $id/$relative"}
            & icacls.exe $path /inheritance:r /grant:r "*S-1-5-18:(F)" "*S-1-5-32-544:(F)" | Out-Null
            if($LASTEXITCODE -ne 0){throw "Could not restrict local secret ACL: $id/$relative"}
        }
    }
}
