param(
    [string]$ServerRoot = "",
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

# Inspection only: do not stop/restart servers, edit files, change ports or deploy.
function Read-Day10Property {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    $pattern = "^\s*" + [regex]::Escape($Key) + "\s*=\s*(.*?)\s*$"
    $matchLines = @(Get-Content -LiteralPath $Path | Where-Object { $_ -match $pattern })
    if ($matchLines.Count -eq 0) { return "" }
    $m = [regex]::Match([string]$matchLines[-1], $pattern)
    return $m.Groups[1].Value
}

function Inspect-Day10Server {
    param([string]$Root, [string]$Folder, [string]$Id)
    $dir = Join-Path $Root $Folder
    $props = Join-Path $dir "server.properties"
    $pluginDir = Join-Path $dir "plugins"
    $exists = Test-Path -LiteralPath $dir -PathType Container
    $plugins = @()
    $jarCandidates = @()
    if ($exists -and (Test-Path -LiteralPath $pluginDir -PathType Container)) {
        $plugins = @(Get-ChildItem -LiteralPath $pluginDir -File -Filter "*.jar" -ErrorAction Stop |
            Select-Object -ExpandProperty Name)
    }
    if ($exists) {
        $jarCandidates = @(Get-ChildItem -LiteralPath $dir -File -Filter "*.jar" -ErrorAction Stop |
            Select-Object -ExpandProperty Name)
    }
    return [pscustomobject]@{
        id = $Id
        directory = $dir
        directory_exists = [bool]$exists
        properties_exists = [bool](Test-Path -LiteralPath $props -PathType Leaf)
        paper_global_exists = [bool](Test-Path -LiteralPath (Join-Path $dir "config\paper-global.yml") -PathType Leaf)
        start_bat_exists = [bool](Test-Path -LiteralPath (Join-Path $dir "start.bat") -PathType Leaf)
        configured_java_port = (Read-Day10Property $props "server-port")
        configured_rcon_port = (Read-Day10Property $props "rcon.port")
        configured_bedrock_port = (Read-Day10Property $props "bedrock.port")
        jars = $jarCandidates
        plugins = $plugins
    }
}

function Assert-Day10SelfTest {
    $tempRoot = Join-Path $env:TEMP ("Day10-Preflight-SelfTest-" + [guid]::NewGuid().ToString("N"))
    try {
        $dir = Join-Path $tempRoot "야생"
        New-Item -ItemType Directory -Force -Path (Join-Path $dir "plugins") | Out-Null
        [IO.File]::WriteAllLines((Join-Path $dir "server.properties"),
            @("server-port=25565","enable-rcon=true","rcon.port=25575"), [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText((Join-Path $dir "paper.jar"), "placeholder")
        [IO.File]::WriteAllText((Join-Path $dir "plugins\ViaVersion-5.12.1-SNAPSHOT.jar"), "placeholder")
        $entry = Inspect-Day10Server $tempRoot "야생" "wild"
        if (-not $entry.directory_exists -or $entry.configured_java_port -ne "25565" -or
            $entry.configured_rcon_port -ne "25575" -or $entry.plugins.Count -ne 1 -or
            $entry.plugins[0] -ne "ViaVersion-5.12.1-SNAPSHOT.jar") {
            throw "Phase 1 inventory regression"
        }
        $absent = Inspect-Day10Server $tempRoot "기타" "other"
        if ($absent.directory_exists -or $absent.properties_exists) {
            throw "Phase 1 missing-directory regression"
        }
        Write-Host "DAY10 FOUR-SERVER READ-ONLY PREFLIGHT SELFTEST PASS"
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($SelfTest) { Assert-Day10SelfTest; exit 0 }

if ([string]::IsNullOrWhiteSpace($ServerRoot)) {
    $ServerRoot = Join-Path $env:USERPROFILE "OneDrive\Documentos\MC\Server"
}
if (-not (Test-Path -LiteralPath $ServerRoot -PathType Container)) {
    throw "Server root not found: $ServerRoot. Supply -ServerRoot with the correct directory."
}
$ServerRoot = (Resolve-Path -LiteralPath $ServerRoot).Path
$warnings = New-Object System.Collections.Generic.List[string]
$servers = @(
    (Inspect-Day10Server $ServerRoot "야생" "wild"),
    (Inspect-Day10Server $ServerRoot "놀이터" "playground"),
    (Inspect-Day10Server $ServerRoot "기타" "other")
)
foreach ($s in $servers) {
    if (-not $s.directory_exists) { $warnings.Add("Missing server folder: $($s.directory)") }
    if (-not $s.properties_exists) { $warnings.Add("Missing server.properties: $($s.id)") }
    if (-not $s.start_bat_exists) { $warnings.Add("Missing start.bat: $($s.id)") }
    if (-not $s.paper_global_exists) { $warnings.Add("Missing paper-global.yml: $($s.id)") }
}
$lobbyPath = Join-Path $ServerRoot "로비"
$lobbyExists = Test-Path -LiteralPath $lobbyPath -PathType Container
if ($lobbyExists) {
    $warnings.Add("Lobby folder exists; adoption requires manual inspection, not an overwrite.")
}
$gsc = [ordered]@{ accessible = $false; version = ""; profiles = @(); error = "" }
try {
    $settings = Invoke-RestMethod -UseBasicParsing -TimeoutSec 8 -Uri "http://127.0.0.1:8787/api/settings"
    $gsc.accessible = $true
    $gsc.version = [string]$settings.version
    $gsc.profiles = @($settings.servers | ForEach-Object {
        [pscustomobject]@{
            id = [string]$_.id
            role = [string]$_.role
            directory = [string]$_.path
            java_port = [int]$_.java_port
            rcon_port = [int]$_.rcon_port
            bedrock_port = [int]$_.bedrock_port
            update_policy = [string]$_.update_policy
        }
    })
    foreach ($id in @("wild", "playground", "other")) {
        if (@($gsc.profiles | Where-Object { $_.id -eq $id }).Count -eq 0) {
            $warnings.Add("GSC does not currently have server profile '$id'.")
        }
    }
} catch {
    $gsc.error = $_.Exception.Message
    $warnings.Add("Could not inspect GSC /api/settings. Ensure GSC host is running.")
}

# Capture port ownership for comparison; no binding, firewall or portproxy changes.
$tcp = @()
foreach ($port in @(25565,25566,25567,25570,25571,25572,25573,25575,25576,25577,25579)) {
    try {
        $tcp += @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop |
            Select-Object @{Name="port";Expression={$_.LocalPort}},
                          @{Name="address";Expression={$_.LocalAddress}},
                          @{Name="pid";Expression={$_.OwningProcess}})
    } catch { }
}
$udp = @()
foreach ($port in @(19132,19133,19134)) {
    try {
        $udp += @(Get-NetUDPEndpoint -LocalPort $port -ErrorAction Stop |
            Select-Object @{Name="port";Expression={$_.LocalPort}},
                          @{Name="address";Expression={$_.LocalAddress}},
                          @{Name="pid";Expression={$_.OwningProcess}})
    } catch { }
}
$report = [ordered]@{
    schema = 1
    purpose = "day10-phase1-inspection-only"
    generated_at = (Get-Date).ToString("o")
    live_changes = $false
    server_root = $ServerRoot
    expected_lobby_path = $lobbyPath
    lobby_folder_exists = [bool]$lobbyExists
    public_java = [ordered]@{ wild = 25565; playground = 25566; other = 25567 }
    public_bedrock = [ordered]@{ wild = 19132; playground = 19133; other = 19134 }
    rcon = [ordered]@{ wild = 25575; playground = 25576; other = 25577; lobby = 25579 }
    proposed_backend_java = [ordered]@{ wild = 25570; playground = 25571; other = 25572; lobby = 25573 }
    servers = $servers
    gsc = $gsc
    tcp_listeners = @($tcp)
    udp_listeners = @($udp)
    warnings = @($warnings.ToArray())
}
$reportPath = Join-Path $env:TEMP ("Geumyi-Day10-Phase1-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "DAY 10 PHASE 1 INSPECTION COMPLETE - NO SERVER FILES CHANGED"
Write-Host "Server root: $ServerRoot"
Write-Host "Lobby target: $lobbyPath"
foreach ($s in $servers) {
    Write-Host ("{0}: folder={1}; Java={2}; RCON={3}; plugin JARs={4}" -f
        $s.id, $s.directory_exists, $s.configured_java_port, $s.configured_rcon_port, $s.plugins.Count)
}
Write-Host ("GSC accessible: " + $gsc.accessible)
foreach ($w in $warnings) { Write-Warning $w }
Write-Host "Report: $reportPath"
Write-Host "Send the JSON report. DO NOT run the retired Day10_Final_E2E.cmd."
