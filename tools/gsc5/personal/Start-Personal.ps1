param([switch]$Background)
$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
$dataRoot = Join-Path $packageRoot 'data'
$hostExecutable = Join-Path $packageRoot 'GeumyiServerHost.exe'
$clientExecutable = Join-Path $packageRoot 'GeumyiServerCenter.exe'
$hostPort = 18787
$clientPort = 18790
$revision = 'gsc-5.1.0-personal-20261115'
$encoding = [Text.UTF8Encoding]::new($false)

function Test-LocalPort([int]$Port) {
    $connection = [Net.Sockets.TcpClient]::new()
    try { $connection.Connect('127.0.0.1', $Port); return $true }
    catch [Net.Sockets.SocketException] { return $false }
    finally { $connection.Dispose() }
}
function Confirm-PackageProcess([int]$Port, [string]$Executable, [string]$Config) {
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { $_.RemotePort -eq 0 })
    if ($listeners.Count -eq 0) { return $false }
    foreach ($listener in $listeners) {
        $process = Get-CimInstance Win32_Process -Filter ('ProcessId={0}' -f $listener.OwningProcess)
        if (!$process -or $process.ExecutablePath -ne $Executable -or !$process.CommandLine.Contains($Config)) { return $false }
    }
    return $true
}
function Write-NewJson([string]$Path, $Value) {
    $bytes = $encoding.GetBytes(($Value | ConvertTo-Json -Depth 8))
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}

try {
    if (!(Test-Path -LiteralPath $hostExecutable) -or !(Test-Path -LiteralPath $clientExecutable)) { throw 'Extract the entire ZIP before starting.' }
    New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
    $hostConfig = Join-Path $dataRoot 'server.json'
    $clientConfig = Join-Path $dataRoot 'client.json'
    if (!(Test-Path -LiteralPath $hostConfig) -and !(Test-Path -LiteralPath $clientConfig)) {
        Add-Type -AssemblyName System.Security
        $tokenBytes = New-Object byte[] 32
        $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $generator.GetBytes($tokenBytes) } finally { $generator.Dispose() }
        $token = [Convert]::ToBase64String($tokenBytes)
        $protectedBytes = [Security.Cryptography.ProtectedData]::Protect($encoding.GetBytes($token), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $protectedToken = 'dpapi-u:' + [Convert]::ToBase64String($protectedBytes).TrimEnd('=')
        Write-NewJson $hostConfig @{bind='127.0.0.1';port=$hostPort;api_token=$protectedToken;allow_loopback_no_auth=$false;mobile_enabled=$false;auto_start_agent=$false;agent=@{health_url='';state_url='';working_dir='';start_command=''};servers=@();update=@{enabled=$false}}
        Write-NewJson $clientConfig @{host_url="http://127.0.0.1:$hostPort";token=$protectedToken}
    }
    if (!(Test-Path -LiteralPath $hostConfig) -or !(Test-Path -LiteralPath $clientConfig)) { throw 'Personal configuration is incomplete. Keep data and check the README.' }
    $hostUp = Test-LocalPort $hostPort
    $clientUp = Test-LocalPort $clientPort
    if ($hostUp -and !(Confirm-PackageProcess $hostPort $hostExecutable $hostConfig)) { throw "Port $hostPort is used by another application. Nothing was stopped." }
    if ($clientUp -and !(Confirm-PackageProcess $clientPort $clientExecutable $clientConfig)) { throw "Port $clientPort is used by another application. Nothing was stopped." }
    if (!$hostUp) {
        $hostProcess = Start-Process -FilePath $hostExecutable -ArgumentList @('--config', ('"'+$hostConfig+'"'), '--personal-mode') -WorkingDirectory $dataRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $dataRoot 'host.log') -RedirectStandardError (Join-Path $dataRoot 'host-error.log')
        for ($attempt=0; $attempt -lt 40; $attempt++) {
            if (Test-LocalPort $hostPort) { break }
            if ($hostProcess.HasExited) { throw 'Personal Host exited. Read data/host-error.log.' }
            Start-Sleep -Milliseconds 250
        }
    }
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$hostPort/api/health" -TimeoutSec 4
    if (!$health.ok -or $health.version -ne '5.1.0' -or $health.build_revision -ne $revision) { throw 'Unexpected Host build. No server action was sent.' }
    $clientArguments = @('--config', ('"'+$clientConfig+'"'), '--port', "$clientPort", '--no-start-host')
    if ($Background) { $clientArguments += '--background' }
    if (!$clientUp -or !$Background) {
        Start-Process -FilePath $clientExecutable -ArgumentList $clientArguments -WorkingDirectory $dataRoot -WindowStyle Hidden | Out-Null
    }
    Write-Host 'GSC Personal Preview started. Servers and Proxies have separate dashboard pages.'
    Write-Host "Dashboard: http://127.0.0.1:$clientPort/#servers"
    Write-Host 'Original installed servers and Scheduled Tasks were not changed by this launcher.'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
