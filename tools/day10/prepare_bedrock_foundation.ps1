param(
    [string]$OutputRoot = "",
    [int]$BedrockPort = 19132,
    [switch]$Download,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$UserAgent = 'Geumyi-Minecraft-System-Day10/1.0'

$ViaVersionVersion = '5.12.0'
$ViaVersionSha256 = '72c40a6a702d67f226fc9a0d8ad82aba1483fdabe2e6159bcdddb2dc070750b0'
$ViaVersionUrl = 'https://github.com/ViaVersion/ViaVersion/releases/download/5.12.0/ViaVersion-5.12.0.jar'

$ViaBackwardsVersion = '5.12.0'
$ViaBackwardsSha256 = '194e9250224632274d7b3c17e411e031a9223c1863c6f5138d53c721f07ab78d'
$ViaBackwardsUrl = 'https://github.com/ViaVersion/ViaBackwards/releases/download/5.12.0/ViaBackwards-5.12.0.jar'

function Assert-Port {
    param([int]$Port, [string]$Name)
    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "$Name must be 1..65535"
    }
}

function Resolve-GeyserDownload {
    param(
        [string]$Project,
        [string]$ExpectedFile
    )

    $headers = @{ 'User-Agent' = $UserAgent; 'Accept' = 'application/json' }
    $metaUri = "https://download.geysermc.org/v2/projects/$Project/versions/latest/builds/latest"
    $meta = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri $metaUri

    if ($null -eq $meta -or $null -eq $meta.downloads -or $null -eq $meta.version -or $null -eq $meta.build) {
        throw "Incomplete GeyserMC metadata for project=$Project"
    }

    $picked = $null
    foreach ($property in @($meta.downloads.PSObject.Properties)) {
        $value = $property.Value
        if ($null -eq $value) {
            continue
        }
        if ([string]$value.name -eq $ExpectedFile) {
            $picked = [pscustomobject]@{
                Key = [string]$property.Name
                Name = [string]$value.name
                Sha256 = ([string]$value.sha256).ToLowerInvariant()
            }
            break
        }
    }

    if ($null -eq $picked) {
        throw "Could not find $ExpectedFile in GeyserMC project=$Project build=$($meta.build)"
    }
    if ($picked.Sha256 -notmatch '^[a-f0-9]{64}$') {
        throw "Invalid SHA-256 metadata for $ExpectedFile"
    }

    return [pscustomobject]@{
        Project = $Project
        Version = [string]$meta.version
        Build = [int]$meta.build
        Channel = [string]$meta.channel
        Promoted = [bool]$meta.promoted
        DownloadKey = $picked.Key
        Name = $picked.Name
        Sha256 = $picked.Sha256
        Url = "https://download.geysermc.org/v2/projects/$Project/versions/$($meta.version)/builds/$($meta.build)/downloads/$($picked.Key)"
    }
}

function Assert-Hash {
    param([string]$Path, [string]$Expected)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing download: $Path"
    }
    if ((Get-Item -LiteralPath $Path).Length -lt 100000) {
        throw "Suspiciously small download: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected.ToLowerInvariant()) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch: $Path"
    }
    return $actual
}

function Download-Verified {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Sha256
    )
    $uri = [Uri]$Url
    if ($uri.Scheme -ne 'https') {
        throw "HTTPS required: $Url"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent' = $UserAgent } -Uri $Url -OutFile $Destination
    return Assert-Hash $Destination $Sha256
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Run-SelfTest {
    $downloads = New-Object psobject
    $downloads | Add-Member -MemberType NoteProperty -Name 'velocity' -Value ([pscustomobject]@{
        name = 'Geyser-Velocity.jar'
        sha256 = ('a' * 64)
    })
    $fake = [pscustomobject]@{
        version = '2.99.0-SNAPSHOT'
        build = 1234
        channel = 'default'
        promoted = $true
        downloads = $downloads
    }

    $picked = $null
    foreach ($property in @($fake.downloads.PSObject.Properties)) {
        if ([string]$property.Value.name -eq 'Geyser-Velocity.jar') {
            $picked = $property
        }
    }
    if ($null -eq $picked -or $picked.Name -ne 'velocity') {
        throw 'Geyser download metadata parser regression'
    }
    if ($ViaVersionSha256 -notmatch '^[a-f0-9]{64}$' -or
        $ViaBackwardsSha256 -notmatch '^[a-f0-9]{64}$') {
        throw 'Pinned Via SHA-256 regression'
    }
    if ($ViaVersionVersion -ne $ViaBackwardsVersion) {
        throw 'ViaVersion/ViaBackwards baseline must remain aligned'
    }

    $required = @(
        'bedrock:',
        '  address: 0.0.0.0',
        '  port: 19132',
        '  clone-remote-port: false',
        'remote:',
        '  address: auto',
        '  auth-type: floodgate'
    )
    $override = ($required -join [Environment]::NewLine)
    foreach ($line in $required) {
        if (-not $override.Contains($line)) {
            throw "Geyser override regression: $line"
        }
    }

    Write-Host 'DAY10 BEDROCK FOUNDATION SELFTEST PASS'
}

if ($SelfTest) {
    Run-SelfTest
    exit 0
}

Assert-Port $BedrockPort 'BedrockPort'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $pd = $env:PROGRAMDATA
    if ([string]::IsNullOrWhiteSpace($pd)) {
        $pd = 'C:\ProgramData'
    }
    $OutputRoot = Join-Path $pd 'GeumyiServerCenter\Network\Bedrock'
}

$proxyPlugins = Join-Path $OutputRoot 'proxy-plugins'
$backendPlugins = Join-Path $OutputRoot 'backend-plugins'
New-Item -ItemType Directory -Force -Path $proxyPlugins,$backendPlugins | Out-Null

$override = @"
# Apply these values to the generated Geyser-Velocity config after first startup.
bedrock:
  address: 0.0.0.0
  port: $BedrockPort
  clone-remote-port: false

remote:
  address: auto
  auth-type: floodgate
"@
Write-Utf8NoBom (Join-Path $OutputRoot 'geyser-required-overrides.yml') $override

$resolved = [ordered]@{
    geyser = $null
    floodgate = $null
    viaversion = [ordered]@{
        version = $ViaVersionVersion
        url = $ViaVersionUrl
        sha256 = $ViaVersionSha256
    }
    viabackwards = [ordered]@{
        version = $ViaBackwardsVersion
        url = $ViaBackwardsUrl
        sha256 = $ViaBackwardsSha256
    }
}

if ($Download) {
    $geyser = Resolve-GeyserDownload 'geyser' 'Geyser-Velocity.jar'
    $floodgate = Resolve-GeyserDownload 'floodgate' 'floodgate-velocity.jar'

    $geyserPath = Join-Path $proxyPlugins 'Geyser-Velocity.jar'
    $floodgatePath = Join-Path $proxyPlugins 'floodgate-velocity.jar'
    $viaPath = Join-Path $backendPlugins "ViaVersion-$ViaVersionVersion.jar"
    $backwardsPath = Join-Path $backendPlugins "ViaBackwards-$ViaBackwardsVersion.jar"

    [void](Download-Verified $geyser.Url $geyserPath $geyser.Sha256)
    [void](Download-Verified $floodgate.Url $floodgatePath $floodgate.Sha256)
    [void](Download-Verified $ViaVersionUrl $viaPath $ViaVersionSha256)
    [void](Download-Verified $ViaBackwardsUrl $backwardsPath $ViaBackwardsSha256)

    $resolved.geyser = $geyser
    $resolved.floodgate = $floodgate
}

$plan = [ordered]@{
    schema = 1
    staged_at = (Get-Date).ToString('o')
    destructive_changes_applied = $false
    bedrock = [ordered]@{
        udp_port = $BedrockPort
        geyser_java_emulation = '26.2'
        entry = 'Velocity'
        initial_server = 'lobby'
    }
    proxy_plugins = @(
        'Geyser-Velocity.jar',
        'floodgate-velocity.jar'
    )
    backend_plugins = @(
        "ViaVersion-$ViaVersionVersion.jar",
        "ViaBackwards-$ViaBackwardsVersion.jar"
    )
    backend_targets = @('lobby','wild','playground')
    floodgate_backend_install = $false
    live_files_modified = @()
    resolved = $resolved
}
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputRoot 'bedrock-plan.json') -Encoding UTF8

Write-Host 'DAY10 BEDROCK FOUNDATION STAGED'
Write-Host "Root: $OutputRoot"
Write-Host 'No live proxy/backend/firewall/router configuration was modified.'
