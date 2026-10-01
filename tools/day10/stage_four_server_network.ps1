param(
    [string]$OutputRoot = "",
    [string]$ServerRoot = "",
    [switch]$DownloadDependencies,
    [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

function Assert-FourServerStage {
    param([string]$Root, [bool]$WithJars)
    $p = Get-Content -LiteralPath (Join-Path $Root "four-server-network-plan.json") -Raw | ConvertFrom-Json
    if ($p.live_files_modified.Count -ne 0 -or $p.ready_for_live_cutover) {
        throw "Staging must not claim a live deployment"
    }
    $names = @("wild", "playground", "other")
    $tcp = @(25565,25566,25567)
    $udp = @(19132,19133,19134)
    $firstSecret = ""
    for ($i = 0; $i -lt $names.Count; $i++) {
        $instance = Join-Path $Root ("proxy\" + $names[$i])
        $toml = Get-Content -LiteralPath (Join-Path $instance "velocity.toml") -Raw
        if (-not $toml.Contains('bind = "0.0.0.0:' + $tcp[$i] + '"') -or
            -not $toml.Contains('lobby = "127.0.0.1:25573"') -or
            -not $toml.Contains('other = "127.0.0.1:25572"') -or
            -not $toml.Contains('try = [')) { throw "Velocity config mismatch: $($names[$i])" }
        $override = Get-Content -LiteralPath (Join-Path $instance "geyser-required-overrides.yml") -Raw
        if (-not $override.Contains('port: ' + $udp[$i]) -or
            -not $override.Contains('auth-type: floodgate')) {
            throw "Geyser config mismatch: $($names[$i])"
        }
        $secret = Get-Content -LiteralPath (Join-Path $instance "forwarding.secret") -Raw
        if ($secret.Length -lt 32) { throw "Forwarding secret is too short" }
        if ($i -eq 0) { $firstSecret = $secret }
        elseif ($secret -cne $firstSecret) { throw "Proxy forwarding secrets differ" }
        if ($WithJars) {
            foreach ($jar in @("velocity.jar", "plugins\Geyser-Velocity.jar", "plugins\floodgate-velocity.jar")) {
                if (-not (Test-Path -LiteralPath (Join-Path $instance $jar) -PathType Leaf)) {
                    throw "Missing proxy dependency: $($names[$i])/$jar"
                }
            }
        }
    }
}

function Test-FourServerStage {
    $tmp = Join-Path $env:TEMP ("Day10-Stage-Test-" + [guid]::NewGuid().ToString("N"))
    try {
        & $PSCommandPath -OutputRoot $tmp -ServerRoot (Join-Path $tmp "example-servers")
        Assert-FourServerStage $tmp $false
        Write-Host "DAY10 FOUR SERVER NETWORK STAGING SELFTEST PASS"
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($SelfTest) { Test-FourServerStage; exit 0 }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $env:TEMP ("Geumyi-Day10-Stage-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "Refusing to overwrite existing directory: $OutputRoot"
}
if ([string]::IsNullOrWhiteSpace($ServerRoot)) {
    $ServerRoot = Join-Path $env:USERPROFILE "OneDrive\Documentos\MC\Server"
}
$proxyHelper = Join-Path $PSScriptRoot "prepare_proxy_foundation.ps1"
$bedrockHelper = Join-Path $PSScriptRoot "prepare_bedrock_foundation.ps1"
$names = @("wild", "playground", "other")
$java = @(25565,25566,25567)
$bedrock = @(19132,19133,19134)
$proxyRoot = Join-Path $OutputRoot "proxy"
$bedrockRoot = Join-Path $OutputRoot "bedrock-dependencies"
$master = Join-Path $proxyRoot "wild"

for ($i=0; $i -lt $names.Count; $i++) {
    $target = Join-Path $proxyRoot $names[$i]
    $args = @{
        OutputRoot = $target
        PublicJavaPort = $java[$i]
        LobbyPort = 25573
        WildPort = 25570
        PlaygroundPort = 25571
        OtherPort = 25572
    }
    if ($i -eq 0 -and $DownloadDependencies) { $args.DownloadVelocity = $true }
    & $proxyHelper @args
    if ($i -gt 0) {
        Copy-Item -LiteralPath (Join-Path $master "forwarding.secret") -Destination (Join-Path $target "forwarding.secret") -Force
        if ($DownloadDependencies) {
            Copy-Item -LiteralPath (Join-Path $master "velocity.jar") -Destination (Join-Path $target "velocity.jar")
        }
    }
}
if ($DownloadDependencies) {
    & $bedrockHelper -OutputRoot $bedrockRoot -BedrockPort 19132 -Download
} else {
    & $bedrockHelper -OutputRoot $bedrockRoot -BedrockPort 19132
}

for ($i=0; $i -lt $names.Count; $i++) {
    $target = Join-Path $proxyRoot $names[$i]
    $override = "bedrock:" + [Environment]::NewLine +
        "  address: 0.0.0.0" + [Environment]::NewLine +
        "  port: $($bedrock[$i])" + [Environment]::NewLine +
        "  clone-remote-port: false" + [Environment]::NewLine +
        "remote:" + [Environment]::NewLine +
        "  address: auto" + [Environment]::NewLine +
        "  auth-type: floodgate" + [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $target "geyser-required-overrides.yml"),
        $override, (New-Object Text.UTF8Encoding($false)))
    if ($DownloadDependencies) {
        $plugins = Join-Path $target "plugins"
        New-Item -ItemType Directory -Path $plugins -Force | Out-Null
        foreach ($jar in @("Geyser-Velocity.jar","floodgate-velocity.jar")) {
            Copy-Item -LiteralPath (Join-Path $bedrockRoot ("proxy-plugins\" + $jar)) -Destination (Join-Path $plugins $jar)
        }
    }
}

$plan = [ordered]@{
    schema = 2
    description = "four-server three-proxy STAGING ONLY"
    staged_at = (Get-Date).ToString("o")
    server_root = $ServerRoot
    lobby_directory = (Join-Path $ServerRoot "로비")
    live_files_modified = @()
    ready_for_live_cutover = $false
    dependencies_downloaded = [bool]$DownloadDependencies
    internal_java = [ordered]@{wild=25570;playground=25571;other=25572;lobby=25573}
    rcon = [ordered]@{wild=25575;playground=25576;other=25577;lobby=25579}
    instances = @(
        [ordered]@{id="wild";java_tcp=25565;bedrock_udp=19132;initial_server="lobby"}
        [ordered]@{id="playground";java_tcp=25566;bedrock_udp=19133;initial_server="lobby"}
        [ordered]@{id="other";java_tcp=25567;bedrock_udp=19134;initial_server="lobby"}
    )
    shared_forwarding_secret = "same local secret for all proxies; value omitted"
    shared_floodgate_key = "must distribute same generated key locally before live cutover"
    before_live_deploy = @(
        "Verify backups, original server process states, and zero online players",
        "Move existing backends to 127.0.0.1 private ports and set Paper modern forwarding",
        "Create Lobby alongside Wild, Playground and Other, and register in GSC",
        "Generate one Floodgate identity key and copy to other proxy instances",
        "Apply each instance's Geyser overrides to actual generated runtime config",
        "Extend transaction backup and rollback across Other and all three proxy instances",
        "Verify ports, firewall rules, Java and Bedrock login on all six public endpoints"
    )
}
$planFile = Join-Path $OutputRoot "four-server-network-plan.json"
$plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planFile -Encoding UTF8
Assert-FourServerStage $OutputRoot ([bool]$DownloadDependencies)
Write-Host "DAY10 FOUR SERVER NETWORK STAGED - NO LIVE CHANGES"
Write-Host "Plan: $planFile"
Write-Host "Do not launch staged proxies against live backends until the four-server cutover is verified."
