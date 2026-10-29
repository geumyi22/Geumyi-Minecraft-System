#requires -Version 5.1
<#
Ephemeral Github-hosted Windows runner only.
Real Windows SCM Host service start, live HTTP capability/auth E2E, stop,
delete and local binary/config checks; NO Minecraft world, task changes,
production service, RCON, public release, or actual machine migration.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$HostExe
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:RUNNER_OS -ne 'Windows' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:GSC5_DISPOSABLE_HOST_SCM_E2E -ne 'EXPLICIT_CI_ONLY' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'Refusing SCM Host E2E outside an explicit GitHub-hosted disposable Windows runner'
}
$sc = Join-Path $env:SystemRoot 'System32\sc.exe'
if (-not (Test-Path -LiteralPath $sc -PathType Leaf)) { throw 'sc.exe missing' }
$hostExe = (Resolve-Path -LiteralPath $HostExe -ErrorAction Stop).Path
if ((Get-Item -LiteralPath $hostExe).Length -lt 100000) {
    throw 'Built GSC Host executable too small'
}
$service = 'Geumyi Server Center Host'
if ($null -ne (Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'")) {
    throw 'Existing GSC Host service detected: refuse to install or alter it'
}
foreach ($target in @('wild','playground','other')) {
    if ($null -ne (Get-ScheduledTask -TaskName "Geumyi Day10 Velocity $target" -ErrorAction SilentlyContinue)) {
        throw 'Unexpected existing Minecraft Velocity task: do not run CI Host E2E'
    }
}
$port = 18787
if (@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'CI Host test port occupied'
}
$root = Join-Path $env:RUNNER_TEMP ("gsc5-disposable-host-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$exe = Join-Path $root 'GeumyiServerHost.exe'
$config = Join-Path $root 'server.json'
Copy-Item -LiteralPath $hostExe -Destination $exe -ErrorAction Stop
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $hostExe -Algorithm SHA256).Hash) {
    throw 'Disposable Host binary copy hash mismatch'
}
$token = 'ci-disposable-' + [guid]::NewGuid().ToString('N')
@{
    bind = '127.0.0.1'
    port = $port
    api_token = $token
    allow_loopback_no_auth = $false
    mobile_enabled = $false
    auto_start_agent = $false
    pairing_ttl_seconds = 300
    servers = @()
    update = @{ enabled = $false; repository = 'offline/ci'; channel = 'stable'; timeout_seconds = 2 }
} | ConvertTo-Json -Depth 10 | ForEach-Object {
    # Windows PowerShell 5.1's Set-Content -Encoding UTF8 writes a BOM,
    # which the Go encoding/json decoder rejects. Use UTF-8 without BOM.
    [System.IO.File]::WriteAllText($config, $_, (New-Object System.Text.UTF8Encoding($false)))
}

$registered = $false
try {
    $bin = '"' + $exe + '" --service --config "' + $config + '"'
    $output = & $sc create $service 'binPath=' $bin 'start=' 'demand' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ('Disposable SCM create failed: ' + ($output -join ' '))
    }
    $registered = $true
    $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'"
    if ($null -eq $serviceInfo -or $serviceInfo.PathName -notlike '*gsc5-disposable-host-*') {
        throw 'SCM binary path does not point to disposable Host'
    }
    $output = & $sc start $service 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ('Disposable SCM start failed: ' + ($output -join ' '))
    }
    $url = 'http://127.0.0.1:' + $port
    $health = $null
    $deadline = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri ($url + '/api/health') -Method Get -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($r.StatusCode -eq 200) {
                $health = $r.Content | ConvertFrom-Json -ErrorAction Stop
                if ($health.ok -eq $true -and $health.version -eq '5.0.0-beta.1' -and
                    $health.service -eq $true -and $health.generation -eq 4) { break }
            }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $health -or $health.version -ne '5.0.0-beta.1' -or
        $health.service -ne $true -or $health.generation -ne 4) {
        throw 'Real SCM Host health version/service contract did not become healthy'
    }

    # Check the service process owns the observed listening socket.
    $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'"
    if ($serviceInfo.State -ne 'Running' -or [int]$serviceInfo.ProcessId -le 0) {
        throw 'SCM does not report a running GSC Host process'
    }
    $listeners = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop)
    if (@($listeners | Where-Object { $_.OwningProcess -eq $serviceInfo.ProcessId }).Count -eq 0) {
        throw 'Health server TCP listener is not owned by the SCM Host process'
    }
    if (@($listeners | Where-Object { $_.OwningProcess -ne $serviceInfo.ProcessId }).Count -gt 0) {
        throw 'Extra unexpected TCP owner present on disposable Host port'
    }
    if (@(Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Unexpected Java process in disposable no-servers Host test'
    }

    # Deliberately disable loopback-without-auth to exercise real HTTP auth.
    $anonymousCode = 0
    try {
        $null = Invoke-WebRequest -Uri ($url + '/api/v5/release') -UseBasicParsing -TimeoutSec 3
        $anonymousCode = 200
    } catch {
        if ($_.Exception.Response) { $anonymousCode = [int]$_.Exception.Response.StatusCode }
    }
    if ($anonymousCode -ne 401) { throw "Anonymous release endpoint returned $anonymousCode instead of 401" }
    $headers = @{ Authorization = 'Bearer ' + $token }
    $res = Invoke-WebRequest -Uri ($url + '/api/v5/release') -UseBasicParsing -Headers $headers -TimeoutSec 3
    $cap = $res.Content | ConvertFrom-Json
    if ($res.StatusCode -ne 200 -or $cap.version -ne '5.0.0-beta.1' -or
        $cap.gsc_owns_velocity_processes -ne $false -or
        $cap.automatic_stable_promotion -ne $false -or
        $cap.velocity_lifecycle_owner -ne 'windows_task_scheduler') {
        throw 'Real SCM Host v5 release capability contract failed'
    }
    if ($res.Headers['Cache-Control'] -ne 'no-store') {
        throw 'Authenticated release response cache header is unsafe'
    }
    $status = Invoke-WebRequest -Uri ($url + '/api/status') -UseBasicParsing -Headers $headers -TimeoutSec 5
    $body = $status.Content | ConvertFrom-Json
    if ($status.StatusCode -ne 200 -or $null -eq $body) {
        throw 'Real Host authenticated v4 status route failed'
    }
    $stored = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
    if ($stored.auto_start_agent -ne $false -or @($stored.servers).Count -ne 0) {
        throw 'No-server/no-agent test config was modified unexpectedly'
    }
    Write-Host 'GSC5_DISPOSABLE_REAL_HOST_SCM_AND_AUTH_E2E_PASS'
} finally {
    if ($registered) {
        try { & $sc stop $service 2>&1 | Out-Null } catch {}
        $deadline = (Get-Date).AddSeconds(25)
        while ((Get-Date) -lt $deadline) {
            $current = Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction SilentlyContinue
            if ($null -eq $current -or $current.State -eq 'Stopped') { break }
            Start-Sleep -Milliseconds 350
        }
        try { & $sc delete $service 2>&1 | Out-Null } catch {}
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline) {
            $current = Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction SilentlyContinue
            if ($null -eq $current) { break }
            Start-Sleep -Milliseconds 350
        }
        $current = Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction SilentlyContinue
        if ($null -ne $current) {
            throw 'Disposable Host SCM service was not fully deleted'
        }
    }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
