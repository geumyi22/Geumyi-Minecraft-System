param(
    [string]$StageRoot = "",
    [string]$ServerRoot = "",
    [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

function Day10-ReadProperty {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    $pattern = "^\s*" + [regex]::Escape($Key) + "\s*=\s*(.*?)\s*$"
    $result = @(Get-Content -LiteralPath $Path | Where-Object { $_ -match $pattern })
    if ($result.Count -lt 1) { return "" }
    return [regex]::Match($result[-1], $pattern).Groups[1].Value
}

function Day10-CheckFileSha {
    param([string]$Path, [string]$Expected, [long]$MinBytes = 0)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt $MinBytes) { return $false }
    if ($Expected -notmatch '^[a-fA-F0-9]{64}$') { return $false }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected
}

function Day10-CheckStage {
    param([string]$Root, [switch]$Synthetic)
    $issues = New-Object System.Collections.Generic.List[string]
    $planPath = Join-Path $Root "four-server-network-plan.json"
    $dependencies = Join-Path $Root "bedrock-dependencies\bedrock-plan.json"
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
        $issues.Add("Missing four-server network plan")
        return @($issues)
    }
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if ($plan.schema -ne 2 -or $plan.ready_for_live_cutover -or
        -not $plan.dependencies_downloaded -or $plan.live_files_modified.Count -ne 0) {
        $issues.Add("Stage plan is not a verified, non-destructive downloaded stage")
    }
    if (-not (Test-Path -LiteralPath $dependencies -PathType Leaf)) {
        $issues.Add("Missing official dependency verification plan")
        return @($issues)
    }
    $b = Get-Content -LiteralPath $dependencies -Raw | ConvertFrom-Json
    if ($null -eq $b.resolved.geyser -or $null -eq $b.resolved.floodgate) {
        $issues.Add("Official Geyser/Floodgate metadata not resolved")
    }
    if (-not $Synthetic) {
        $pairs = @(
            @{path="bedrock-dependencies\proxy-plugins\Geyser-Velocity.jar"; expected=[string]$b.resolved.geyser.Sha256; min=100000},
            @{path="bedrock-dependencies\proxy-plugins\floodgate-velocity.jar"; expected=[string]$b.resolved.floodgate.Sha256; min=100000},
            @{path="bedrock-dependencies\backend-plugins\ViaVersion-5.12.0.jar"; expected=[string]$b.resolved.viaversion.sha256; min=100000},
            @{path="bedrock-dependencies\backend-plugins\ViaBackwards-5.12.0.jar"; expected=[string]$b.resolved.viabackwards.sha256; min=100000}
        )
        foreach ($pair in $pairs) {
            $target = Join-Path $Root $pair.path
            if (-not (Day10-CheckFileSha $target $pair.expected $pair.min)) {
                $issues.Add("Verified dependency missing or SHA-256 mismatch: $($pair.path)")
            }
        }
    }
    $firstSecret = ""
    foreach ($entry in @(
        @{id="wild";java=25565;bedrock=19132},
        @{id="playground";java=25566;bedrock=19133},
        @{id="other";java=25567;bedrock=19134}
    )) {
        $dir = Join-Path $Root ("proxy\" + $entry.id)
        $toml = Join-Path $dir "velocity.toml"
        $secretPath = Join-Path $dir "forwarding.secret"
        $overridesPath = Join-Path $dir "geyser-required-overrides.yml"
        if (-not (Test-Path -LiteralPath $toml -PathType Leaf) -or
            -not (Test-Path -LiteralPath $secretPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $overridesPath -PathType Leaf)) {
            $issues.Add("Proxy configuration missing: $($entry.id)")
            continue
        }
        $v = Get-Content -LiteralPath $toml -Raw
        $override = Get-Content -LiteralPath $overridesPath -Raw
        $secret = (Get-Content -LiteralPath $secretPath -Raw).Trim()
        if (-not $v.Contains('bind = "0.0.0.0:' + $entry.java + '"') -or
            -not $v.Contains('lobby = "127.0.0.1:25573"') -or
            -not $v.Contains('other = "127.0.0.1:25572"') -or
            -not $override.Contains('port: ' + $entry.bedrock)) {
            $issues.Add("Proxy public/backend port mismatch: $($entry.id)")
        }
        if ($secret.Length -lt 32 -or ($firstSecret -ne "" -and $secret -cne $firstSecret)) {
            $issues.Add("Velocity forwarding secret missing/mismatched: $($entry.id)")
        }
        if ($firstSecret -eq "") { $firstSecret = $secret }
        if (-not $Synthetic) {
            $velocityInfo = Get-Content -LiteralPath (Join-Path $Root "proxy\wild\network-plan.json") -Raw | ConvertFrom-Json
            if (-not (Day10-CheckFileSha (Join-Path $dir "velocity.jar") ([string]$velocityInfo.velocity.ActualSha256) 1000000)) {
                $issues.Add("Velocity JAR not verified: $($entry.id)")
            }
            foreach ($jar in @(
                @{file="Geyser-Velocity.jar";sha=[string]$b.resolved.geyser.Sha256},
                @{file="floodgate-velocity.jar";sha=[string]$b.resolved.floodgate.Sha256}
            )) {
                if (-not (Day10-CheckFileSha (Join-Path $dir ("plugins\" + $jar.file)) $jar.sha 100000)) {
                    $issues.Add("Proxy plugin JAR not verified: $($entry.id)/$($jar.file)")
                }
            }
        }
    }
    return @($issues)
}

function Day10-CheckServerRoot {
    param([string]$Root)
    $issues = New-Object System.Collections.Generic.List[string]
    $entries = @(
        @{id="wild";name="야생";java=25565;rcon=25575},
        @{id="playground";name="놀이터";java=25566;rcon=25576},
        @{id="other";name="기타";java=25567;rcon=25577}
    )
    foreach ($entry in $entries) {
        $folder = Join-Path $Root $entry.name
        $props = Join-Path $folder "server.properties"
        if (-not (Test-Path -LiteralPath $props -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $folder "config\paper-global.yml") -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $folder "paper.jar") -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $folder "start.bat") -PathType Leaf)) {
            $issues.Add("Paper startup/config files missing: $($entry.id)")
            continue
        }
        if ((Day10-ReadProperty $props "server-port") -ne [string]$entry.java -or
            (Day10-ReadProperty $props "rcon.port") -ne [string]$entry.rcon) {
            $issues.Add("Unexpected original Java/RCON port; do not attempt first cutover: $($entry.id)")
        }
        $plugins = Join-Path $folder "plugins"
        if ($entry.id -eq "playground") {
            foreach ($plugin in @("GeumyiTechnology","GeumyiChemistry")) {
                if (@(Get-ChildItem -LiteralPath $plugins -File -Filter "$plugin*.jar" -ErrorAction SilentlyContinue).Count -gt 0) {
                    $issues.Add("$plugin is not permitted in Playground")
                }
            }
        }
        if ($entry.id -in @("wild","other")) {
            foreach ($plugin in @("GeumyiTechnology","GeumyiChemistry")) {
                if (@(Get-ChildItem -LiteralPath $plugins -File -Filter "$plugin*.jar" -ErrorAction SilentlyContinue).Count -eq 0) {
                    $issues.Add("$plugin missing in $($entry.id)")
                }
            }
        }
    }
    $lobby = Join-Path $Root "로비"
    if (Test-Path -LiteralPath $lobby) {
        $issues.Add("Lobby directory already exists: inspect prior cutover before first deploy")
    }
    return @($issues)
}

function Day10-RunReadiness {
    param([string]$Staging, [string]$Servers, [switch]$Synthetic)
    $issues = New-Object System.Collections.Generic.List[string]
    foreach ($i in @(Day10-CheckStage $Staging -Synthetic:$Synthetic)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$i)) { $issues.Add([string]$i) }
    }
    foreach ($i in @(Day10-CheckServerRoot $Servers)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$i)) { $issues.Add([string]$i) }
    }
    if (-not $Synthetic) {
        try {
            $s = Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/settings" -TimeoutSec 5
            $roles = @($s.servers)
            foreach ($entry in @(
                @{id="wild";java=25565;rcon=25575;name="야생"},
                @{id="playground";java=25566;rcon=25576;name="놀이터"},
                @{id="other";java=25567;rcon=25577;name="기타"}
            )) {
                $found = @($roles | Where-Object { $_.id -eq $entry.id })
                if ($found.Count -ne 1 -or [int]$found[0].java_port -ne $entry.java -or
                    [int]$found[0].rcon_port -ne $entry.rcon) {
                    $issues.Add("GSC backend profile mismatch: $($entry.id)")
                }
            }
            if (@($roles | Where-Object { $_.id -eq "lobby" }).Count -ne 0) {
                $issues.Add("GSC Lobby already registered: first-deploy cutover must stop")
            }
        } catch {
            $issues.Add("GSC settings unavailable: $($_.Exception.Message)")
        }
        foreach ($port in @(25570,25571,25572,25573)) {
            if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
                $issues.Add("Private Java port already occupied: $port")
            }
        }
    }
    $result = [ordered]@{
        schema = 1
        generated_at = (Get-Date).ToString("o")
        synthetic_test = [bool]$Synthetic
        source_staging = $Staging
        server_root = $Servers
        staging_and_first_deploy_preflight_pass = ($issues.Count -eq 0)
        live_cutover_verified = $false
        required_live_steps = @(
            "Verified full-world and plugin-data backup",
            "Graceful GSC shutdown of all three existing servers with zero players",
            "GSC four-server profile transition and safe shared Floodgate identity key",
            "Start/monitor three Velocity+Geyser instances, firewall and service setup",
            "Six public-port Java/Bedrock Lobby-first E2E, last-location test and rollback rehearsal"
        )
        errors = @($issues.ToArray())
    }
    return $result
}

function Day10-SyntheticSelfTest {
    $tmp = Join-Path $env:TEMP ("Day10-Readiness-Test-" + [guid]::NewGuid().ToString("N"))
    try {
        $servers = Join-Path $tmp "Server"
        foreach ($entry in @(
            @{name="야생";java=25565;rcon=25575},
            @{name="놀이터";java=25566;rcon=25576},
            @{name="기타";java=25567;rcon=25577}
        )) {
            $root = Join-Path $servers $entry.name
            New-Item -ItemType Directory -Force -Path (Join-Path $root "config"),(Join-Path $root "plugins") | Out-Null
            [IO.File]::WriteAllText((Join-Path $root "server.properties"),"server-port=$($entry.java)" + [Environment]::NewLine + "rcon.port=$($entry.rcon)")
            [IO.File]::WriteAllText((Join-Path $root "paper.jar"),"paper")
            [IO.File]::WriteAllText((Join-Path $root "start.bat"),"start")
            [IO.File]::WriteAllText((Join-Path $root "config\paper-global.yml"),"proxies:")
            if ($entry.name -ne "놀이터") {
                foreach ($plugin in @("GeumyiTechnology","GeumyiChemistry")) {
                    [IO.File]::WriteAllText((Join-Path $root ("plugins\" + $plugin + ".jar")),"test")
                }
            }
        }
        $stage = Join-Path $tmp "stage"
        New-Item -ItemType Directory -Force -Path (Join-Path $stage "bedrock-dependencies") | Out-Null
        $plan = @{schema=2;ready_for_live_cutover=$false;dependencies_downloaded=$true;live_files_modified=@()}
        $plan | ConvertTo-Json | Set-Content (Join-Path $stage "four-server-network-plan.json")
        $b = @{resolved=@{geyser=@{Sha256=('a'*64)};floodgate=@{Sha256=('b'*64)}}}
        $b | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $stage "bedrock-dependencies\bedrock-plan.json")
        foreach ($entry in @(
            @{id="wild";java=25565;udp=19132},
            @{id="playground";java=25566;udp=19133},
            @{id="other";java=25567;udp=19134}
        )) {
            $dir = Join-Path $stage ("proxy\" + $entry.id)
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $toml = 'bind = "0.0.0.0:' + $entry.java + '"' + [Environment]::NewLine +
                    'lobby = "127.0.0.1:25573"' + [Environment]::NewLine +
                    'other = "127.0.0.1:25572"'
            [IO.File]::WriteAllText((Join-Path $dir "velocity.toml"),$toml)
            [IO.File]::WriteAllText((Join-Path $dir "forwarding.secret"),"abcdefghijklmnopqrstuvwx12345678")
            [IO.File]::WriteAllText((Join-Path $dir "geyser-required-overrides.yml"),"port: $($entry.udp)")
        }
        $ok = Day10-RunReadiness $stage $servers -Synthetic
        if (-not $ok.staging_and_first_deploy_preflight_pass -or $ok.live_cutover_verified) {
            throw ("Expected staged-only success: " + ($ok.errors -join "; "))
        }
        [IO.File]::Delete((Join-Path $servers "기타\plugins\GeumyiChemistry.jar"))
        $bad = Day10-RunReadiness $stage $servers -Synthetic
        if ($bad.staging_and_first_deploy_preflight_pass -or
            @($bad.errors | Where-Object { $_ -match "GeumyiChemistry" }).Count -eq 0) {
            throw "Missing Other Chemistry must block first-deploy readiness"
        }
        Write-Host "DAY10 FOUR-SERVER CUTOVER READINESS SELFTEST PASS"
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($SelfTest) { Day10-SyntheticSelfTest; exit 0 }
if ([string]::IsNullOrWhiteSpace($StageRoot) -or
    -not (Test-Path -LiteralPath $StageRoot -PathType Container)) {
    throw "Specify the existing downloaded stage directory via -StageRoot"
}
if ([string]::IsNullOrWhiteSpace($ServerRoot)) {
    $ServerRoot = Join-Path $env:USERPROFILE "OneDrive\Documentos\MC\Server"
}
$result = Day10-RunReadiness $StageRoot $ServerRoot
$report = Join-Path $StageRoot "four-server-readiness.json"
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $report -Encoding UTF8
if ($result.staging_and_first_deploy_preflight_pass) {
    Write-Host "DAY10 STAGING AND FIRST-DEPLOY PREFLIGHT PASS - LIVE CUTOVER NOT DONE"
} else {
    Write-Host "DAY10 STAGING/DEPLOY PREFLIGHT BLOCKED - NO LIVE CHANGES"
    $result.errors | ForEach-Object { Write-Host ("- " + $_) }
}
Write-Host "Readiness report: $report"
Write-Host "Send both four-server-network-plan.json and four-server-readiness.json."
if (-not $result.staging_and_first_deploy_preflight_pass) { exit 2 }
