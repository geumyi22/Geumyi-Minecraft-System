param(
    [string]$OutputRoot = "",
    [int]$PublicJavaPort = 25565,
    [int]$LobbyPort = 25573,
    [int]$WildPort = 25570,
    [int]$PlaygroundPort = 25571,
    [int]$OtherPort = 25572,
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
        [int]$PlaygroundBackendPort,
        [int]$OtherBackendPort
    )
    return $Template.
        Replace('__PUBLIC_JAVA_PORT__', [string]$PublicPort).
        Replace('__LOBBY_PORT__', [string]$LobbyBackendPort).
        Replace('__WILD_PORT__', [string]$WildBackendPort).
        Replace('__PLAYGROUND_PORT__', [string]$PlaygroundBackendPort).
        Replace('__OTHER_PORT__', [string]$OtherBackendPort)
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
    if ($null -eq $Data) { return @() }
    # PaperMC Fill v3 /builds returns an array, not {builds:[...]}.
    # Keep support for the wrapped shape without StrictMode property errors.
    if ($Data -is [array]) { return $Data }
    if ($Data.PSObject.Properties['builds']) { return @($Data.builds) }
    if ($Data.PSObject.Properties['id'] -or $Data.PSObject.Properties['build']) {
        return @($Data)
    }
    throw 'Unexpected PaperMC builds response shape'
}

function Get-BuildNumber {
    param($Build)
    if ($Build.PSObject.Properties['id']) { return [int]$Build.id }
    if ($Build.PSObject.Properties['build']) { return [int]$Build.build }
    throw 'Velocity build lacks id/build number'
}

function Select-VelocityBuilds {
    param($Response)
    $items = @(Get-BuildArray $Response)
    # Velocity releases use RECOMMENDED; support STABLE when available.
    return @($items | Where-Object {
        $_.PSObject.Properties['channel'] -and
        [string]$_.channel -in @('RECOMMENDED', 'STABLE')
    } | Sort-Object -Property @{ Expression = {
        if ([string]$_.channel -eq 'RECOMMENDED') { 1 } else { 0 }
    }; Descending = $true }, @{ Expression = { Get-BuildNumber $_ }; Descending = $true })
}

function Get-BuildDownload {
    param($Build)
    if (-not $Build.PSObject.Properties['downloads'] -or $null -eq $Build.downloads) {
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
        $candidates = @(Select-VelocityBuilds $data)
        foreach ($build in $candidates) {
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
                Build = Get-BuildNumber $build
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
    # Fill v3 returns an array with id (not build), and Velocity releases
    # can use the RECOMMENDED channel. Verify all cases under StrictMode.
    $modern = [pscustomobject]@{ id = 42; channel = 'RECOMMENDED'; downloads = $downloads }
    $legacy = [pscustomobject]@{ build = 30; channel = 'STABLE'; downloads = $downloads }
    $fromArray = @(Select-VelocityBuilds @($legacy, $modern))
    if ($fromArray.Count -ne 2 -or (Get-BuildNumber $fromArray[0]) -ne 42) {
        throw 'Fill v3 array/channel selection regression'
    }
    $wrapped = [pscustomobject]@{ builds = @($legacy) }
    $fromWrapped = @(Select-VelocityBuilds $wrapped)
    if ($fromWrapped.Count -ne 1 -or (Get-BuildNumber $fromWrapped[0]) -ne 30) {
        throw 'Wrapped builds backward compatibility regression'
    }
    $unsupportedRejected = $false
    try { [void](Get-BuildArray ([pscustomobject]@{ notBuilds = @() })) } catch {
        $unsupportedRejected = $true
    }
    if (-not $unsupportedRejected) {
        throw 'Unexpected Fill v3 response shape was silently accepted'
    }


    $template = @'
player-info-forwarding-mode = "modern"
[servers]
lobby = "127.0.0.1:__LOBBY_PORT__"
wild = "127.0.0.1:__WILD_PORT__"
playground = "127.0.0.1:__PLAYGROUND_PORT__"
other = "127.0.0.1:__OTHER_PORT__"
bind = "0.0.0.0:__PUBLIC_JAVA_PORT__"
'@
    $rendered = Render-VelocityConfig $template 25565 25573 25570 25571 25572
    foreach ($needle in @(
        'player-info-forwarding-mode = "modern"',
        '127.0.0.1:25573',
        '127.0.0.1:25570',
        '127.0.0.1:25571',
        '127.0.0.1:25572',
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
Assert-Port $OtherPort 'OtherPort'

$ports = @($PublicJavaPort,$LobbyPort,$WildPort,$PlaygroundPort,$OtherPort)
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
$config = Render-VelocityConfig $template $PublicJavaPort $LobbyPort $WildPort $PlaygroundPort $OtherPort

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
        other = "127.0.0.1:$OtherPort"
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
Write-Host "No Wild/Playground/Other live configuration was modified."
