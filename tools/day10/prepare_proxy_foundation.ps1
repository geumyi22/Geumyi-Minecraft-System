param(
    [string]$OutputRoot = "",
    [int]$PublicJavaPort = 25565,
    [int]$LobbyPort = 25569,
    [int]$WildPort = 25567,
    [int]$PlaygroundPort = 25568,
    [switch]$DownloadVelocity,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$UserAgent = 'Geumyi-Minecraft-System-Day10/1.0 (https://github.com/geumyi22/Geumyi-Minecraft-System)'

function Assert-Port {
    param([int]$Port, [string]$Name)
    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "$Name must be 1..65535"
    }
}

function New-ForwardingSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes)
}

function Get-RepoRoot {
    $toolsDir = Split-Path -Parent $PSScriptRoot
    return (Resolve-Path (Join-Path $toolsDir '..')).Path
}

function Render-VelocityConfig {
    param(
        [string]$Template,
        [int]$PublicPort,
        [int]$LobbyBackendPort,
        [int]$WildBackendPort,
        [int]$PlaygroundBackendPort
    )
    return $Template.
        Replace('__PUBLIC_JAVA_PORT__', [string]$PublicPort).
        Replace('__LOBBY_PORT__', [string]$LobbyBackendPort).
        Replace('__WILD_PORT__', [string]$WildBackendPort).
        Replace('__PLAYGROUND_PORT__', [string]$PlaygroundBackendPort)
}

function Get-StableVelocityVersions {
    param($Project)
    $all = New-Object System.Collections.Generic.List[string]
    foreach ($group in $Project.versions.PSObject.Properties) {
        foreach ($v in @($group.Value)) {
            $value = [string]$v
            if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '(?i)SNAPSHOT') {
                $all.Add($value)
            }
        }
    }
    return @($all | Sort-Object {
        try { [version]($_ -replace '-.*$','') } catch { [version]'0.0.0' }
    } -Descending -Unique)
}

function Get-BuildArray {
    param($Data)
    if ($null -ne $Data.builds) {
        return @($Data.builds)
    }
    return @($Data)
}

function Get-BuildDownload {
    param($Build)
    if ($null -eq $Build.downloads) {
        return $null
    }
    $props = @($Build.downloads.PSObject.Properties)
    if ($props.Count -eq 0) {
        return $null
    }
    $preferred = $props | Where-Object { $_.Name -eq 'server:default' } | Select-Object -First 1
    if ($null -eq $preferred) {
        $preferred = $props | Where-Object { $null -ne $_.Value.url } | Select-Object -First 1
    }
    if ($null -eq $preferred -or $null -eq $preferred.Value.url) {
        return $null
    }
    return [pscustomobject]@{
        Name = [string]$preferred.Name
        Url = [string]$preferred.Value.url
        Sha256 = [string]$preferred.Value.checksums.sha256
    }
}

function Resolve-StableVelocity {
    $headers = @{ 'User-Agent' = $UserAgent }
    $project = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri 'https://fill.papermc.io/v3/projects/velocity'
    $versions = @(Get-StableVelocityVersions $project)
    foreach ($version in $versions) {
        $uri = "https://fill.papermc.io/v3/projects/velocity/versions/$version/builds"
        $data = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri $uri
        $stable = @(Get-BuildArray $data | Where-Object { [string]$_.channel -eq 'STABLE' } | Sort-Object build -Descending)
        foreach ($build in $stable) {
            $download = Get-BuildDownload $build
            if ($null -eq $download) {
                continue
            }
            $u = [Uri]$download.Url
            if ($u.Scheme -ne 'https' -or -not ($u.Host -eq 'fill.papermc.io' -or $u.Host -like '*.papermc.io')) {
                throw "Unexpected Velocity download host: $($u.Host)"
            }
            return [pscustomobject]@{
                Version = [string]$version
                Build = [int]$build.build
                Url = $download.Url
                UpstreamSha256 = $download.Sha256
                DownloadKey = $download.Name
            }
        }
    }
    throw 'No non-SNAPSHOT STABLE Velocity build found'
}

function Write-Ascii {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::ASCII)
}

function Run-SelfTest {
    $sample = [pscustomobject]@{
        versions = [pscustomobject]@{
            current = @('4.2.1-SNAPSHOT','4.2.0','4.1.1')
        }
    }
    $versions = @(Get-StableVelocityVersions $sample)
    if ($versions.Count -lt 2 -or $versions[0] -ne '4.2.0') {
        throw "Stable version selection regression: $($versions -join ',')"
    }

    $downloads = New-Object psobject
    $d = [pscustomobject]@{
        url = 'https://fill-data.papermc.io/test/velocity.jar'
        checksums = [pscustomobject]@{ sha256 = ('a' * 64) }
    }
    $downloads | Add-Member -MemberType NoteProperty -Name 'server:default' -Value $d
    $build = [pscustomobject]@{ build = 30; channel = 'STABLE'; downloads = $downloads }
    $picked = Get-BuildDownload $build
    if ($null -eq $picked -or $picked.Name -ne 'server:default') {
        throw 'Velocity download selection regression'
    }

    $template = @'
player-info-forwarding-mode = "modern"
[servers]
lobby = "127.0.0.1:__LOBBY_PORT__"
wild = "127.0.0.1:__WILD_PORT__"
playground = "127.0.0.1:__PLAYGROUND_PORT__"
bind = "0.0.0.0:__PUBLIC_JAVA_PORT__"
'@
    $rendered = Render-VelocityConfig $template 25565 25569 25567 25568
    foreach ($needle in @(
        'player-info-forwarding-mode = "modern"',
        '127.0.0.1:25569',
        '127.0.0.1:25567',
        '127.0.0.1:25568',
        '0.0.0.0:25565'
    )) {
        if (-not $rendered.Contains($needle)) {
            throw "Velocity template render regression: missing $needle"
        }
    }

    $secret = New-ForwardingSecret
    if ([string]::IsNullOrWhiteSpace($secret) -or $secret.Length -lt 32) {
        throw 'Forwarding secret generation regression'
    }

    Write-Host 'DAY10 PROXY FOUNDATION SELFTEST PASS'
}

if ($SelfTest) {
    Run-SelfTest
    exit 0
}

Assert-Port $PublicJavaPort 'PublicJavaPort'
Assert-Port $LobbyPort 'LobbyPort'
Assert-Port $WildPort 'WildPort'
Assert-Port $PlaygroundPort 'PlaygroundPort'

$ports = @($PublicJavaPort,$LobbyPort,$WildPort,$PlaygroundPort)
if (@($ports | Select-Object -Unique).Count -ne $ports.Count) {
    throw 'Public and backend Java ports must be unique'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $pd = $env:PROGRAMDATA
    if ([string]::IsNullOrWhiteSpace($pd)) {
        $pd = 'C:\ProgramData'
    }
    $OutputRoot = Join-Path $pd 'GeumyiServerCenter\Network\Velocity'
}

$repoRoot = Get-RepoRoot
$templatePath = Join-Path $repoRoot 'Network\Velocity\velocity.toml.template'
if (-not (Test-Path -LiteralPath $templatePath)) {
    throw "Velocity template missing: $templatePath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$template = Get-Content -LiteralPath $templatePath -Raw
$config = Render-VelocityConfig $template $PublicJavaPort $LobbyPort $WildPort $PlaygroundPort

$configPath = Join-Path $OutputRoot 'velocity.toml'
[System.IO.File]::WriteAllText($configPath, $config, (New-Object System.Text.UTF8Encoding($false)))

$secretPath = Join-Path $OutputRoot 'forwarding.secret'
if (-not (Test-Path -LiteralPath $secretPath)) {
    [System.IO.File]::WriteAllText($secretPath, (New-ForwardingSecret), (New-Object System.Text.UTF8Encoding($false)))
}

$startPath = Join-Path $OutputRoot 'start.bat'
$start = "@echo off@@setlocal@@cd /d ""%~dp0""@@java -Xms256M -Xmx512M -jar ""%~dp0velocity.jar""@@"
$start = $start.Replace('@@', [Environment]::NewLine)
Write-Ascii $startPath $start

$velocity = $null
if ($DownloadVelocity) {
    $velocity = Resolve-StableVelocity
    $jarPath = Join-Path $OutputRoot 'velocity.jar'
    Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent' = $UserAgent } -Uri $velocity.Url -OutFile $jarPath
    if (-not (Test-Path -LiteralPath $jarPath) -or (Get-Item $jarPath).Length -lt 1000000) {
        throw 'Downloaded Velocity JAR is missing or suspiciously small'
    }
    $actualHash = (Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($velocity.UpstreamSha256) -and
        $velocity.UpstreamSha256.ToLowerInvariant() -ne $actualHash) {
        Remove-Item -LiteralPath $jarPath -Force
        throw 'Velocity SHA-256 mismatch'
    }
    $velocity | Add-Member -MemberType NoteProperty -Name ActualSha256 -Value $actualHash
}

$plan = [ordered]@{
    schema = 1
    staged_at = (Get-Date).ToString('o')
    destructive_changes_applied = $false
    public = [ordered]@{
        java_tcp = $PublicJavaPort
        bedrock_udp = 19132
    }
    backends = [ordered]@{
        lobby = "127.0.0.1:$LobbyPort"
        wild = "127.0.0.1:$WildPort"
        playground = "127.0.0.1:$PlaygroundPort"
    }
    forwarding = [ordered]@{
        mode = 'modern'
        secret_file = 'forwarding.secret'
    }
    live_backend_files_modified = @()
    velocity = $velocity
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'network-plan.json') -Encoding UTF8

Write-Host "DAY10 PROXY FOUNDATION STAGED"
Write-Host "Root: $OutputRoot"
Write-Host "No Wild/Playground live configuration was modified."
