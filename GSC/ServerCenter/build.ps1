param([string]$Go = "go")
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    foreach ($name in @('GeumyiStatusAgent-0.5.4.jar', 'GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar', 'GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar')) {
        if (-not (Test-Path -LiteralPath (Join-Path 'cmd/setup/payload' $name))) {
            throw "Missing release payload: $name. Follow BUILD.md before building Setup."
        }
    }
    $env:GOOS = "windows"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    New-Item -ItemType Directory -Force -Path dist | Out-Null
    & $Go build -buildvcs=false -trimpath -ldflags="-s -w -H=windowsgui" -o cmd/setup/payload/GeumyiServerHost.exe ./cmd/host
    if ($LASTEXITCODE -ne 0) { throw "Host build failed" }
    & $Go build -buildvcs=false -trimpath -ldflags="-s -w -H=windowsgui" -o cmd/setup/payload/GeumyiServerCenter.exe ./cmd/client
    if ($LASTEXITCODE -ne 0) { throw "Client build failed" }
    & $Go build -buildvcs=false -trimpath -ldflags="-s -w -H=windowsgui" -o dist/GeumyiServerCenter-v4.3.0-Setup.exe ./cmd/setup
    if ($LASTEXITCODE -ne 0) { throw "Setup build failed" }
    Write-Host "Created dist/GeumyiServerCenter-v4.3.0-Setup.exe"
} finally { Pop-Location }
