# Windows PowerShell 5.1. READ ONLY: no services, scheduled tasks, worlds,
# network endpoints, or GitHub releases are modified.
# Example: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\gsc5\Test-GSC5BetaOfflineAssets.ps1 -AssetDirectory C:\GSC5-Beta-Downloads
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AssetDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$expectedVersion = "5.0.0-beta.1"
$expectedSourceCommit = "3283f769c96eeb5f4ffe9c2ebfbfa7d028a6d4b6"
$executables = @(
    "GeumyiServerCenter-v5.0.0-beta.1-Setup.exe",
    "GeumyiServerHost.exe",
    "GeumyiServerCenter.exe"
)
$metadata = @(
    "SHA256SUMS.txt",
    "SOURCE-COMMIT.txt",
    "RELEASE-CHANNEL.txt",
    "RELEASE-NOTES-5.0.0-beta.1.md"
)

$root = (Resolve-Path -LiteralPath $AssetDirectory -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Not a directory: $root"
}
foreach ($name in ($executables + $metadata)) {
    $filePath = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "Missing beta asset: $name"
    }
}

$sourceCommit = (Get-Content -LiteralPath (Join-Path $root "SOURCE-COMMIT.txt") -Raw -Encoding UTF8).Trim()
if ($sourceCommit -cne $expectedSourceCommit) {
    throw "Immutable beta source commit mismatch (do not install)."
}
$channel = Get-Content -LiteralPath (Join-Path $root "RELEASE-CHANNEL.txt") -Raw -Encoding UTF8
$requiredFlags = @(
    "channel=beta",
    "version=$expectedVersion",
    "stable_release_allowed=false",
    "auto_install_production=false",
    "velocity_direct_management=false"
)
foreach ($flag in $requiredFlags) {
    $pattern = '(?m)^' + [regex]::Escape($flag) + '\r?$'
    if ($channel -notmatch $pattern) {
        throw "Release safety flag is missing or changed: $flag"
    }
}

$hashes = @{}
foreach ($line in (Get-Content -LiteralPath (Join-Path $root "SHA256SUMS.txt") -Encoding UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([a-fA-F0-9]{64})\s+\*?([^\\/:*?"<>|]+)$') {
        throw "Invalid or unsafe SHA256SUMS entry."
    }
    $fileName = $Matches[2]
    if ($hashes.ContainsKey($fileName)) {
        throw "Duplicate SHA256SUMS entry: $fileName"
    }
    $hashes[$fileName] = $Matches[1].ToLowerInvariant()
}
if ($hashes.Count -ne $executables.Count) {
    throw "SHA256SUMS must contain exactly the three released EXEs."
}

foreach ($name in $executables) {
    if (-not $hashes.ContainsKey($name)) {
        throw "SHA256SUMS is missing $name"
    }
    $file = Join-Path $root $name
    $info = Get-Item -LiteralPath $file
    if ($info.Length -le 100000) {
        throw "Binary unexpectedly small: $name"
    }
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $hashes[$name]) {
        throw "SHA256 mismatch: $name"
    }
    Write-Output ("PASS SHA256 {0} ({1} bytes)" -f $name, $info.Length)
}

$extraExecutables = @(Get-ChildItem -LiteralPath $root -File -Filter "*.exe" | Where-Object {
    $executables -notcontains $_.Name
})
if ($extraExecutables.Count -gt 0) {
    throw "Unrecognized EXE files in asset directory; isolate the seven official assets."
}
Write-Output "GSC5_BETA_OFFLINE_ASSETS_PASS"
Write-Output "READ_ONLY_ONLY: this does NOT prove installer safety, live compatibility, or permission to deploy Stable."
