param(
    [string]$TempRoot = $env:TEMP,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-FourServerStage {
    param([Parameter(Mandatory=$true)][string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) { return $null }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $null }

    $candidates = @(
        Get-ChildItem -LiteralPath $Root -Directory -Filter 'Geumyi-Day10-FourServer-Assets-*' -ErrorAction SilentlyContinue |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName 'four-server-network-plan.json') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'four-server-readiness.json') -PathType Leaf)
            } |
            Sort-Object LastWriteTimeUtc -Descending
    )

    if ($candidates.Count -eq 0) { return $null }
    return $candidates[0].FullName
}

if ($SelfTest) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('Geumyi-ResolveStage-Test-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path $root | Out-Null

        $older = Join-Path $root 'Geumyi-Day10-FourServer-Assets-older'
        $newer = Join-Path $root 'Geumyi-Day10-FourServer-Assets-newer'
        $invalid = Join-Path $root 'Geumyi-Day10-FourServer-Assets-invalid'

        foreach ($d in @($older, $newer, $invalid)) {
            New-Item -ItemType Directory -Force -Path $d | Out-Null
        }

        '{}' | Set-Content -LiteralPath (Join-Path $older 'four-server-network-plan.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $older 'four-server-readiness.json') -Encoding UTF8
        Start-Sleep -Milliseconds 50
        '{}' | Set-Content -LiteralPath (Join-Path $newer 'four-server-network-plan.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $newer 'four-server-readiness.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $invalid 'four-server-network-plan.json') -Encoding UTF8

        (Get-Item -LiteralPath $older).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-5)
        (Get-Item -LiteralPath $newer).LastWriteTimeUtc = [datetime]::UtcNow

        $resolved = Resolve-FourServerStage -Root $root
        if ([string]::IsNullOrWhiteSpace($resolved)) { throw 'Resolver returned an empty stage path.' }
        if ($resolved -ne $newer) { throw "Resolver selected the wrong stage: $resolved" }

        Write-Host 'RESOLVE FOUR SERVER STAGE SELFTEST PASS'
        exit 0
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$stage = Resolve-FourServerStage -Root $TempRoot
if ([string]::IsNullOrWhiteSpace($stage)) {
    exit 13
}

[Console]::Out.WriteLine($stage)
