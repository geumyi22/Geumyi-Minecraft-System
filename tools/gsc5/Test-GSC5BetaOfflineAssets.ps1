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

# Pin all seven public prerelease assets, not just the editable SHA256SUMS text.
$expectedDigests = @{
    "GeumyiServerCenter-v5.0.0-beta.1-Setup.exe" = "89e4a99fb7be536c31cfcb36d416215bd6e9d7865a0bc9f52c1bc580d634c13a"
    "GeumyiServerHost.exe" = "68c3304c256d8287cbe92826cf98cd742f4f598b669a706973656443fb8088ad"
    "GeumyiServerCenter.exe" = "d4bce2eb2e3ea78057732d26da15c730677e7e6603f8d857324b6a57461ef431"
    "SHA256SUMS.txt" = "8bae175f2c948bc592835ab048b3755f2f92e0788def8859b5ded7770a42284c"
    "SOURCE-COMMIT.txt" = "6e589313483fe2fea80dd6a3e683afca858ec884b4ff8df8c11c35d3f4e9b843"
    "RELEASE-CHANNEL.txt" = "e379f1b5729ca557d3175323e767b32e20ec8b5b084846a9f5ccdec3ede4e8e8"
    "RELEASE-NOTES-5.0.0-beta.1.md" = "805763234fe4e895485b1947b374ea5d27223b39b536c4b572cf500deafc66b7"
}

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

foreach ($name in ($executables + $metadata)) {
    $actual = (Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $expectedDigests[$name]) {
        throw "Official immutable prerelease SHA256 mismatch: $name"
    }
}
Write-Output "PASS pinned official SHA256 for all seven assets"

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
