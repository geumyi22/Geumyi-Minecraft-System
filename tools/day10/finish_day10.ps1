param(
    [string]$Repository = "geumyi22/Geumyi-Minecraft-System",
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

# Initialize rollback guards before SelfTest so the script-level trap is safe
# even when a self-test assertion throws under StrictMode.
$backupRoot = ""
$cutover = $false
$finished = $false
$logPath = ""

$helpers = Join-Path $PSScriptRoot "day10_live_helpers.ps1"
if (-not (Test-Path -LiteralPath $helpers)) {
    throw "helper library missing: $helpers"
}
. $helpers

function Day10-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Day10-Need {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw "$Name not found" }
    return $command.Source
}

function Day10-SelfTest {
    $root = Join-Path $env:TEMP ("Geumyi-Day10-SelfTest-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path (Join-Path $root "config") | Out-Null
    try {
        $props = Join-Path $root "server.properties"
        [IO.File]::WriteAllLines($props, @("server-port=25565","online-mode=true","server-ip="), [Text.Encoding]::ASCII)
        Day10-SetServerProperty $props "server-port" "25567"
        Day10-SetServerProperty $props "online-mode" "false"
        Day10-SetServerProperty $props "server-ip" "127.0.0.1"
        $p = Get-Content -LiteralPath $props -Raw
        if ($p -notmatch 'server-port=25567' -or $p -notmatch 'online-mode=false' -or $p -notmatch 'server-ip=127[.]0[.]0[.]1') {
            throw "server.properties mutation regression"
        }

        $paper = Join-Path $root "config\paper-global.yml"
        $paperText = @"
_version: 31
proxies:
  bungee-cord:
    online-mode: true
  proxy-protocol: false
  velocity:
    enabled: false
    online-mode: true
    secret: ""
scoreboards:
  save-empty-scoreboard-teams: false
"@
        [IO.File]::WriteAllText($paper, $paperText, (New-Object Text.UTF8Encoding($false)))
        Day10-SetPaperVelocity $paper "test-secret-1234567890"
        $after = Get-Content -LiteralPath $paper -Raw
        if ($after -notmatch 'enabled:\s*true' -or $after -notmatch 'secret:\s*"test-secret-1234567890"') {
            throw "paper-global Velocity mutation regression"
        }

        $geyser = Join-Path $root "geyser.yml"
        $geyserText = @"
bedrock:
  address: 127.0.0.1
  port: 19133
  clone-remote-port: true
remote:
  address: 127.0.0.1
  auth-type: online
"@
        [IO.File]::WriteAllText($geyser, $geyserText, (New-Object Text.UTF8Encoding($false)))
        Day10-SetGeyserConfig $geyser 19132
        $g = Get-Content -LiteralPath $geyser -Raw
        if ($g -notmatch 'address:\s*0[.]0[.]0[.]0' -or $g -notmatch 'port:\s*19132' -or $g -notmatch 'auth-type:\s*floodgate') {
            throw "Geyser mutation regression"
        }

        $gdsTemplate = Join-Path $root "gds-template.yml"
        $gdsConfig = @"
server:
  id: survival
  name: "Wild"
bridge:
  enabled: true
agent:
  enabled: true
api:
  enabled: true
  bind: "127.0.0.1"
  port: 8766
"@
        [IO.File]::WriteAllText($gdsTemplate, $gdsConfig, (New-Object Text.UTF8Encoding($false)))
        $gdsDest = Join-Path $root "plugins\GeumyiDiscordStatus\config.yml"
        Day10-ConfigureLobbyGds $gdsTemplate $gdsDest
        $gc = Get-Content -LiteralPath $gdsDest -Raw
        if ($gc -notmatch '(?m)^\s+id:\s+lobby\s*$' -or
            $gc -notmatch '(?m)^\s+port:\s+8767\s*$' -or
            $gc -notmatch '(?m)^\s+enabled:\s+false\s*$') {
            throw "Lobby GDS config isolation regression"
        }

        Write-Host "DAY10 FINALIZER SELFTEST PASS"
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($SelfTest) {
    try {
        Day10-SelfTest
        exit 0
    } catch {
        Write-Host ("DAY10 FINALIZER SELFTEST FAIL: " + $_.Exception.ToString())
        exit 2
    }
}

if (-not (Day10-IsAdmin)) {
    throw "Run from Administrator PowerShell."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$work = Join-Path $env:TEMP "Geumyi-Day10-$stamp"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$logPath = Join-Path $work "day10-e2e.log"
$backupRoot = ""
$cutover = $false
$finished = $false

function Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    if (-not [string]::IsNullOrWhiteSpace($logPath)) {
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    }
}

function Fail {
    param([string]$Message)
    Log "FAIL: $Message"
    throw $Message
}

trap {
    Write-Host ("DAY10 ERROR: " + $_.Exception.ToString())
    try { Log ("UNHANDLED: " + $_.Exception.Message) } catch {}
    if ($cutover -and -not $finished -and -not [string]::IsNullOrWhiteSpace($backupRoot)) {
        try {
            Write-Host ""
            Write-Host "Automatic rollback starting..."
            & (Join-Path $PSScriptRoot "rollback_day10.ps1") -BackupRoot $backupRoot
        } catch {
            Write-Warning ("automatic rollback failed: " + $_.Exception.Message)
        }
    }
    Write-Host ""
    Write-Host "DAY 10 FINALIZER STOPPED"
    if (-not [string]::IsNullOrWhiteSpace($logPath)) { Write-Host "Log: $logPath" }
    if (-not [string]::IsNullOrWhiteSpace($backupRoot)) {
        Write-Host "Backup: $backupRoot"
    }
    exit 1
}

Log "Day 10 finalizer start"
$gh = Day10-Need "gh"
$java = Day10-Need "java"
foreach ($cmd in @("Get-NetTCPConnection","Get-NetUDPEndpoint","New-NetFirewallRule","New-ScheduledTaskAction","Register-ScheduledTask")) {
    if ($null -eq (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Fail "Windows command unavailable: $cmd"
    }
}

& $gh auth status
if ($LASTEXITCODE -ne 0) { Fail "gh auth login required" }

Log "dispatching fresh System CI for current main"
$mainSha = ((& $gh api "repos/$Repository/commits/main" --jq .sha) -join "").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($mainSha)) { Fail "cannot resolve main SHA" }

$dispatchLines = @(& $gh workflow run system-ci.yml --repo $Repository --ref main 2>&1)
$dispatchCode = $LASTEXITCODE
$dispatchLines | ForEach-Object { Write-Host $_ }
if ($dispatchCode -ne 0) { Fail "cannot dispatch System CI" }
$dispatchText = $dispatchLines -join [Environment]::NewLine
$match = [regex]::Match($dispatchText, 'actions/runs/(?<id>[0-9]+)')
if (-not $match.Success) { Fail "workflow dispatch did not return run URL" }
$runId = [string]$match.Groups["id"].Value

$viewText = @(& $gh run view $runId --repo $Repository --json databaseId,headSha,event,status,conclusion,url,workflowName)
if ($LASTEXITCODE -ne 0) { Fail "cannot inspect run $runId" }
$view = ($viewText -join [Environment]::NewLine) | ConvertFrom-Json
if ([string]$view.headSha -ne $mainSha) { Fail "fresh CI SHA mismatch" }
if ([string]$view.workflowName -ne "System CI") { Fail "unexpected workflow name" }

Log "watching fresh System CI run $runId"
& $gh run watch $runId --repo $Repository --exit-status
if ($LASTEXITCODE -ne 0) { Fail "fresh System CI failed" }
Log "fresh System CI PASS"

$artifactRoot = Join-Path $work "artifacts"
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
foreach ($name in @("gsc-4.2.4-ci","lobby-0.1.0","network-0.1.0","gst-1.1.1-hotfix","gds-1.1.1")) {
    $dest = Join-Path $artifactRoot $name
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    & $gh run download $runId --repo $Repository -n $name -D $dest
    if ($LASTEXITCODE -ne 0) { Fail "artifact download failed: $name" }
}
Day10-VerifySums (Join-Path $artifactRoot "gsc-4.2.4-ci")

$hostExe = Join-Path $artifactRoot "gsc-4.2.4-ci\GeumyiServerHost.exe"
$setupExe = Join-Path $artifactRoot "gsc-4.2.4-ci\GeumyiServerCenter-v4.2.4-Setup.exe"
if (-not (Test-Path -LiteralPath $hostExe) -or -not (Test-Path -LiteralPath $setupExe)) {
    Fail "GSC CI package incomplete"
}

Log "running built Host Day 10 self-test"
$selfProc = Start-Process -FilePath $hostExe -ArgumentList "--day10-selftest" -PassThru -Wait -NoNewWindow
if ($selfProc.ExitCode -ne 0) { Fail "Host Day 10 self-test failed: $($selfProc.ExitCode)" }

Log "installing latest main GSC build"
Write-Host "If Setup opens, keep the existing server role and Wild/Playground paths."
$setupProc = Start-Process -FilePath $setupExe -PassThru
if (-not $setupProc.WaitForExit(900000)) { Fail "GSC Setup timeout" }
if ($setupProc.ExitCode -ne 0) { Fail "GSC Setup exit=$($setupProc.ExitCode)" }
Day10-WaitGsc 120 | Out-Null

$settings = Day10-Gsc "GET" "/api/settings"
$wild = @($settings.servers) | Where-Object { $_.id -eq "wild" } | Select-Object -First 1
$play = @($settings.servers) | Where-Object { $_.id -eq "playground" } | Select-Object -First 1
$lobbyExisting = @($settings.servers) | Where-Object { $_.id -eq "lobby" } | Select-Object -First 1
if ($null -eq $wild -or $null -eq $play) { Fail "Wild/Playground profiles missing" }
if ($null -ne $lobbyExisting) { Fail "Lobby profile already exists; refusing first-deploy finalizer" }

$wildPath = [string]$wild.path
$playPath = [string]$play.path
$lobbyPath = Join-Path $env:PROGRAMDATA "GeumyiLobbyServer"
$velocityRoot = Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Network\Velocity"
$bedrockRoot = Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Network\Bedrock"

foreach ($dir in @($wildPath,$playPath)) {
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath (Join-Path $dir "server.properties"))) {
        Fail "invalid backend path: $dir"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dir "config\paper-global.yml"))) {
        Fail "paper-global.yml missing: $dir"
    }
}
foreach ($newDir in @($lobbyPath,$velocityRoot,$bedrockRoot)) {
    if (Test-Path -LiteralPath $newDir) { Fail "first-deploy target already exists: $newDir" }
}
if (Get-ScheduledTask -TaskName "Geumyi Minecraft Velocity" -ErrorAction SilentlyContinue) {
    Fail "Velocity scheduled task already exists"
}

foreach ($serverDir in @($wildPath,$playPath)) {
    $pluginDir = Join-Path $serverDir "plugins"
    if (Get-ChildItem -LiteralPath $pluginDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^GeumyiNetwork.*[.]jar$|^ViaVersion.*[.]jar$|^ViaBackwards.*[.]jar$' }) {
        Fail "Network/Via plugin already exists in $serverDir; manual reconciliation required"
    }
}

$wildState = Day10-State "wild"
$playState = Day10-State "playground"
if ($null -eq $wildState -or $null -eq $playState) { Fail "cannot read backend status" }
$wildPlayers = 0
$playPlayers = 0
if ($wildState.minecraft -and $null -ne $wildState.minecraft.online) { $wildPlayers = [int]$wildState.minecraft.online }
if ($playState.minecraft -and $null -ne $playState.minecraft.online) { $playPlayers = [int]$playState.minecraft.online }
if ($wildPlayers -gt 0 -or $playPlayers -gt 0) { Fail "players online: wild=$wildPlayers playground=$playPlayers" }

foreach ($port in @(25567,25568,25569)) {
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        Fail "candidate backend port already in use: $port"
    }
}

$paperJar = Day10-FindPaperJar $wildPath
Log "Lobby will reuse Paper runtime: $paperJar"

Write-Host ""
Write-Host "============================================================"
Write-Host " DAY 10 LIVE NETWORK CUTOVER"
Write-Host "============================================================"
Write-Host "World folders are not modified."
Write-Host "Wild -> 127.0.0.1:25567"
Write-Host "Playground -> 127.0.0.1:25568"
Write-Host "Lobby -> 127.0.0.1:25569"
Write-Host "Velocity public Java -> 25565"
Write-Host "Geyser public Bedrock -> UDP 19132"
Write-Host "Old Java Playground port 25566 -> Velocity alias"
Write-Host "A configuration backup and rollback state will be created first."
$confirm = Read-Host "Type DEPLOY to continue"
if ($confirm -ne "DEPLOY") { Fail "deployment cancelled" }

$backupRoot = Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Backups\Day10-$stamp"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $backupRoot "gsc") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $backupRoot "wild") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $backupRoot "playground") | Out-Null
Copy-Item -LiteralPath "$env:PROGRAMDATA\GeumyiServerCenter\server.json" -Destination (Join-Path $backupRoot "gsc\server.json") -Force
foreach ($entry in @(
    @($wildPath,"wild"),
    @($playPath,"playground")
)) {
    $srcDir = $entry[0]
    $name = $entry[1]
    Copy-Item -LiteralPath (Join-Path $srcDir "server.properties") -Destination (Join-Path $backupRoot "$name\server.properties") -Force
    Copy-Item -LiteralPath (Join-Path $srcDir "config\paper-global.yml") -Destination (Join-Path $backupRoot "$name\paper-global.yml") -Force
    if (Test-Path -LiteralPath (Join-Path $srcDir "spigot.yml")) {
        Copy-Item -LiteralPath (Join-Path $srcDir "spigot.yml") -Destination (Join-Path $backupRoot "$name\spigot.yml") -Force
    }
}

$rollbackState = [ordered]@{
    wild_path = $wildPath
    playground_path = $playPath
    lobby_path = $lobbyPath
    velocity_root = $velocityRoot
    bedrock_root = $bedrockRoot
    wild_initial_online = [bool]$wildState.online
    playground_initial_online = [bool]$playState.online
    lobby_created = $true
    velocity_created = $true
    bedrock_created = $true
}
$rollbackState | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backupRoot "rollback-state.json") -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "rollback_day10.ps1") -Destination (Join-Path $backupRoot "rollback_day10.ps1") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "day10_live_helpers.ps1") -Destination (Join-Path $backupRoot "day10_live_helpers.ps1") -Force
Log "backup ready: $backupRoot"

$cutover = $true

foreach ($id in @("wild","playground")) {
    $s = Day10-State $id
    if ($null -ne $s -and [bool]$s.online) {
        Log "gracefully stopping $id"
        Day10-Gsc "POST" "/api/server/action" @{ id = $id; action = "stop" } | Out-Null
        Day10-WaitOnline $id $false 180 | Out-Null
    }
}

Log "staging Velocity"
& (Join-Path $PSScriptRoot "prepare_proxy_foundation.ps1") -OutputRoot $velocityRoot -DownloadVelocity
if ($LASTEXITCODE -ne 0) { Fail "Velocity staging failed" }

Log "staging Geyser/Floodgate/Via"
& (Join-Path $PSScriptRoot "prepare_bedrock_foundation.ps1") -OutputRoot $bedrockRoot -Download
if ($LASTEXITCODE -ne 0) { Fail "Bedrock staging failed" }

$velocityPlugins = Join-Path $velocityRoot "plugins"
New-Item -ItemType Directory -Force -Path $velocityPlugins | Out-Null
Copy-Item -LiteralPath (Join-Path $bedrockRoot "proxy-plugins\Geyser-Velocity.jar") -Destination (Join-Path $velocityPlugins "Geyser-Velocity.jar") -Force
Copy-Item -LiteralPath (Join-Path $bedrockRoot "proxy-plugins\floodgate-velocity.jar") -Destination (Join-Path $velocityPlugins "floodgate-velocity.jar") -Force
$secret = (Get-Content -LiteralPath (Join-Path $velocityRoot "forwarding.secret") -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($secret) -or $secret.Length -lt 24) { Fail "forwarding secret invalid" }

Log "creating Lobby backend"
New-Item -ItemType Directory -Force -Path (Join-Path $lobbyPath "plugins") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $lobbyPath "config") | Out-Null
Copy-Item -LiteralPath $paperJar -Destination (Join-Path $lobbyPath "paper.jar") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\..\Servers\Lobby\server.properties.template") -Destination (Join-Path $lobbyPath "server.properties") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\..\Servers\Lobby\start.bat.template") -Destination (Join-Path $lobbyPath "start.bat") -Force
Copy-Item -LiteralPath (Join-Path $wildPath "config\paper-global.yml") -Destination (Join-Path $lobbyPath "config\paper-global.yml") -Force
[IO.File]::WriteAllText((Join-Path $lobbyPath "eula.txt"), ("eula=true" + [Environment]::NewLine), [Text.Encoding]::ASCII)

$rconBytes = New-Object byte[] 24
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($rconBytes) } finally { $rng.Dispose() }
$lobbyRcon = [Convert]::ToBase64String($rconBytes).Replace("+","A").Replace("/","B").TrimEnd("=")
Day10-SetServerProperty (Join-Path $lobbyPath "server.properties") "rcon.password" $lobbyRcon

Day10-CopyArtifactJar (Join-Path $artifactRoot "lobby-0.1.0") (Join-Path $lobbyPath "plugins\GeumyiLobby-0.1.0-Paper26.3.jar")
Day10-CopyArtifactJar (Join-Path $artifactRoot "gst-1.1.1-hotfix") (Join-Path $lobbyPath "plugins\GeumyiServerTools-1.1.1.jar")
Day10-CopyArtifactJar (Join-Path $artifactRoot "gds-1.1.1") (Join-Path $lobbyPath "plugins\GeumyiDiscordStatus-1.1.1.jar")
Day10-ConfigureLobbyGds (Join-Path $PSScriptRoot "..\..\Plugins\GeumyiDiscordStatus\src\main\resources\config.yml") (Join-Path $lobbyPath "plugins\GeumyiDiscordStatus\config.yml")

$via = Join-Path $bedrockRoot "backend-plugins\ViaVersion-5.12.0.jar"
$back = Join-Path $bedrockRoot "backend-plugins\ViaBackwards-5.12.0.jar"
foreach ($serverDir in @($wildPath,$playPath,$lobbyPath)) {
    Copy-Item -LiteralPath $via -Destination (Join-Path $serverDir "plugins\ViaVersion-5.12.0.jar") -Force
    Copy-Item -LiteralPath $back -Destination (Join-Path $serverDir "plugins\ViaBackwards-5.12.0.jar") -Force
}
Day10-CopyArtifactJar (Join-Path $artifactRoot "network-0.1.0") (Join-Path $wildPath "plugins\GeumyiNetwork-0.1.0-Paper26.3.jar")
Day10-CopyArtifactJar (Join-Path $artifactRoot "network-0.1.0") (Join-Path $playPath "plugins\GeumyiNetwork-0.1.0-Paper26.3.jar")
Day10-WriteNetworkConfig $wildPath "wild"
Day10-WriteNetworkConfig $playPath "playground"
Day10-DisableBackendProxyPlugins $wildPath
Day10-DisableBackendProxyPlugins $playPath

$plan = @(
    @{ dir = $wildPath; port = 25567 },
    @{ dir = $playPath; port = 25568 },
    @{ dir = $lobbyPath; port = 25569 }
)
foreach ($item in $plan) {
    $props = Join-Path $item.dir "server.properties"
    Day10-SetServerProperty $props "server-ip" "127.0.0.1"
    Day10-SetServerProperty $props "server-port" ([string]$item.port)
    Day10-SetServerProperty $props "online-mode" "false"
    Day10-SetServerProperty $props "enable-query" "false"
    Day10-SetPaperVelocity (Join-Path $item.dir "config\paper-global.yml") $secret
    Day10-SetSpigotBungeeFalse (Join-Path $item.dir "spigot.yml")
}

$wildTemp = Day10-ProfileFromSettings $wild 25567 0 $false
$playTemp = Day10-ProfileFromSettings $play 25568 0 $false
Day10-Gsc "POST" "/api/v4/server-profile" @{ action = "update"; server = $wildTemp } | Out-Null
Day10-Gsc "POST" "/api/v4/server-profile" @{ action = "update"; server = $playTemp } | Out-Null
$lobbyProfile = @{
    id = "lobby"
    name = "Geumyi Lobby"
    role = "lobby"
    update_policy = "managed"
    java_port = 25569
    rcon_port = 25579
    bedrock_port = 0
    gds_api_port = 8767
    path = $lobbyPath
    path_file = ""
    start_command = "start.bat"
    auto_start = $false
    restart_on_crash = $true
}
Day10-Gsc "POST" "/api/v4/server-profile" @{ action = "add"; server = $lobbyProfile } | Out-Null
Log "GSC profiles moved to private backend ports"

Log "bootstrapping Velocity plugins"
$bootstrap = Start-Process -FilePath $java -ArgumentList @("-Xms256M","-Xmx512M","-jar","velocity.jar") -WorkingDirectory $velocityRoot -PassThru -WindowStyle Hidden
$geyserConfig = Join-Path $velocityRoot "plugins\Geyser-Velocity\config.yml"
$deadline = (Get-Date).AddSeconds(90)
while (-not (Test-Path -LiteralPath $geyserConfig) -and (Get-Date) -lt $deadline) {
    if ($bootstrap.HasExited) { Fail "Velocity bootstrap exited early" }
    Start-Sleep -Seconds 2
}
if (-not (Test-Path -LiteralPath $geyserConfig)) { Fail "Geyser config generation timeout" }
Stop-Process -Id $bootstrap.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Day10-SetGeyserConfig $geyserConfig 19132

$startPath = Join-Path $velocityRoot "start.bat"
$quotedStart = [char]34 + $startPath + [char]34
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument ("/c " + $quotedStart)
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
Register-ScheduledTask -TaskName "Geumyi Minecraft Velocity" -Action $action -Trigger $trigger -Principal $principal -Settings $taskSettings -Force | Out-Null

Get-NetFirewallRule -DisplayName "Geumyi Velocity Java" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName "Geumyi Geyser Bedrock" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Geumyi Velocity Java" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 25565,25566 | Out-Null
New-NetFirewallRule -DisplayName "Geumyi Geyser Bedrock" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 19132 | Out-Null

foreach ($id in @("lobby","wild","playground")) {
    Day10-Gsc "POST" "/api/server/action" @{ id = $id; action = "start" } | Out-Null
    Day10-WaitOnline $id $true 300 | Out-Null
}

$wildFinal = Day10-ProfileFromSettings $wild 25567 0 ([bool]$wild.auto_start)
$playFinal = Day10-ProfileFromSettings $play 25568 0 ([bool]$play.auto_start)
Day10-Gsc "POST" "/api/v4/server-profile" @{ action = "update"; server = $wildFinal } | Out-Null
Day10-Gsc "POST" "/api/v4/server-profile" @{ action = "update"; server = $playFinal } | Out-Null
$lobbyProfile.auto_start = $true
Day10-Gsc "POST" "/api/v4/server-profile" @{ action = "update"; server = $lobbyProfile } | Out-Null

Start-ScheduledTask -TaskName "Geumyi Minecraft Velocity"
Day10-WaitTcp 25565 $true 90
Start-Sleep -Seconds 5

& netsh.exe interface portproxy delete v4tov4 listenport=25566 listenaddress=0.0.0.0 2>$null | Out-Null
& netsh.exe interface portproxy add v4tov4 listenport=25566 listenaddress=0.0.0.0 connectport=25565 connectaddress=127.0.0.1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "cannot create 25566 Velocity alias" }
Day10-WaitTcp 25566 $true 30

foreach ($port in @(25567,25568,25569)) {
    Day10-AssertLoopbackListener $port
}
$udpDeadline = (Get-Date).AddSeconds(90)
$udpReady = $false
do {
    if (Get-NetUDPEndpoint -LocalPort 19132 -ErrorAction SilentlyContinue) {
        $udpReady = $true
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $udpDeadline)
if (-not $udpReady) { Fail "Geyser UDP 19132 not listening" }

foreach ($id in @("wild","playground")) {
    $route = Invoke-RestMethod -Uri ("http://127.0.0.1:8787/api/v4/network/server-state?id=" + $id) -TimeoutSec 10
    if (-not [bool]$route.move_allowed) { Fail "$id routing gate blocked: $($route.blocked_reason)" }
}
Log "automatic live network checks PASS"

Write-Host ""
Write-Host "============================================================"
Write-Host " JAVA E2E - MANUAL CHECK"
Write-Host "============================================================"
Write-Host "1) Connect Java to 25565 -> Lobby center"
Write-Host "2) Lobby -> Wild"
Write-Host "3) Move in Wild -> /lobby -> return to Wild -> previous location restored"
Write-Host "4) Verify the same last-location restore in Playground"
Write-Host "5) Connect Java to legacy 25566 -> Lobby center"
$javaPass = Read-Host "Type JAVA PASS if every Java check passed"
if ($javaPass -ne "JAVA PASS") { Fail "Java E2E not confirmed" }

Write-Host ""
Write-Host "============================================================"
Write-Host " BEDROCK E2E - MANUAL CHECK"
Write-Host "============================================================"
Write-Host "1) Connect Bedrock to UDP 19132 -> Lobby center"
Write-Host "2) Lobby -> Wild / Playground"
Write-Host "3) Use /lobby and verify moving back to each backend"
$bedrockPass = Read-Host "Type BEDROCK PASS if every Bedrock check passed"
if ($bedrockPass -ne "BEDROCK PASS") { Fail "Bedrock E2E not confirmed" }

if (-not [bool]$wildState.online) {
    Day10-Gsc "POST" "/api/server/action" @{ id = "wild"; action = "stop" } | Out-Null
    Day10-WaitOnline "wild" $false 180 | Out-Null
}
if (-not [bool]$playState.online) {
    Day10-Gsc "POST" "/api/server/action" @{ id = "playground"; action = "stop" } | Out-Null
    Day10-WaitOnline "playground" $false 180 | Out-Null
}

$finished = $true
$result = [ordered]@{
    main_sha = $mainSha
    system_ci_run = $runId
    host_day10_selftest = "PASS"
    lobby = "PASS"
    private_backend_ports = @("127.0.0.1:25567","127.0.0.1:25568","127.0.0.1:25569")
    velocity_java_25565 = "PASS"
    java_alias_25566 = "PASS"
    geyser_udp_19132 = "PASS"
    java_user_e2e = "PASS"
    bedrock_user_e2e = "PASS"
    backup = $backupRoot
    log = $logPath
}
$resultPath = Join-Path $work "day10-result.json"
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Copy-Item -LiteralPath $resultPath -Destination (Join-Path $backupRoot "day10-result.json") -Force
Copy-Item -LiteralPath $logPath -Destination (Join-Path $backupRoot "day10-e2e.log") -Force
$result | Format-List | Out-Host
Write-Host ""
Write-Host "============================================================"
Write-Host " DAY 10 FINALIZER: PASS"
Write-Host "============================================================"
Write-Host "Result: $resultPath"
Write-Host "Log: $logPath"
Write-Host "Backup: $backupRoot"
exit 0
