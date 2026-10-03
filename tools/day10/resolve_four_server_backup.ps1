param(
    [string]$BackupRoot = "",
    [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-Day10FourBackup {
    param([string]$Explicit = "")

    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        $state = Join-Path $Explicit "four-rollback-state.json"
        if (-not (Test-Path -LiteralPath $state -PathType Leaf)) {
            throw "four-rollback-state.json missing: $Explicit"
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }

    $base = Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Backups"
    if (-not (Test-Path -LiteralPath $base -PathType Container)) {
        throw "GSC backup directory missing: $base"
    }

    $candidate = Get-ChildItem -LiteralPath $base -Directory -Filter "Day10-Four-*" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "four-rollback-state.json") -PathType Leaf } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($null -eq $candidate) {
        throw "No Day10-Four backup with four-rollback-state.json was found"
    }
    return $candidate.FullName
}

if ($SelfTest) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("Day10-BackupResolver-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $older = Join-Path $root "Day10-Four-older"
        $newer = Join-Path $root "Day10-Four-newer"
        New-Item -ItemType Directory -Force -Path $older,$newer | Out-Null
        "{}" | Set-Content -LiteralPath (Join-Path $older "four-rollback-state.json") -Encoding UTF8
        "{}" | Set-Content -LiteralPath (Join-Path $newer "four-rollback-state.json") -Encoding UTF8
        (Get-Item $older).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-10)
        (Get-Item $newer).LastWriteTimeUtc = [datetime]::UtcNow
        $explicit = Resolve-Day10FourBackup -Explicit $newer
        if ($explicit -ne (Resolve-Path $newer).Path) { throw "Explicit backup resolver failed" }
        Write-Host "DAY10 BACKUP RESOLVER SELFTEST PASS"
        exit 0
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$resolved = Resolve-Day10FourBackup -Explicit $BackupRoot
[Console]::Out.WriteLine($resolved)
