param(
    [string]$Repository = "geumyi22/Geumyi-Minecraft-System",
    [switch]$RunWildFailOpen
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
    Write-Host $line
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
}
function Fail([string]$m) { Log "FAIL: $m"; throw $m }
function IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Need([string]$name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    throw "$name not found"
}
function Gsc([string]$Method,[string]$Path,$Body=$null) {
    $u = "http://127.0.0.1:8787$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $u -TimeoutSec 20
    }
    return Invoke-RestMethod -Method $Method -Uri $u -TimeoutSec 20 -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 8 -Compress)
}
function WaitGsc([int]$sec=120) {
    $end = (Get-Date).AddSeconds($sec)
    do {
        try {
            $h = Invoke-RestMethod -Method GET -Uri "http://127.0.0.1:8787/api/health" -TimeoutSec 5
            if ($h.ok) { return $h }
        } catch {}
        Start-Sleep 2
    } while ((Get-Date) -lt $end)
    throw "GSC :8787 readiness timeout"
}
function State([string]$id) {
    $s = Gsc "GET" "/api/status"
    return @($s.servers) | Where-Object { $_.id -eq $id } | Select-Object -First 1
}
function WaitOnline([string]$id,[bool]$want,[int]$sec=240) {
    $end = (Get-Date).AddSeconds($sec)
    do {
        $s = State $id
        if ($null -ne $s -and [bool]$s.online -eq $want) { return $s }
        Start-Sleep 3
    } while ((Get-Date) -lt $end)
    throw "server $id online=$want timeout"
}
function VerifySums([string]$dir) {
    $sum = Join-Path $dir "SHA256SUMS.txt"
    if (-not (Test-Path -LiteralPath $sum)) { Fail "SHA256SUMS.txt missing" }
    foreach ($line in Get-Content -LiteralPath $sum) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { Fail "bad checksum line: $line" }
        $want = $Matches[1].ToLowerInvariant()
        $name = $Matches[2].Trim()
        $p = Join-Path $dir $name
        if (-not (Test-Path -LiteralPath $p)) { Fail "artifact missing: $name" }
        $got = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($got -ne $want) { Fail "SHA256 mismatch: $name" }
    }
}

if (-not (IsAdmin)) { throw "Run from Administrator PowerShell." }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$work = Join-Path $env:TEMP "Geumyi-Day9-$stamp"
New-Item -ItemType Directory -Force $work | Out-Null
$script:LogPath = Join-Path $work "day9-e2e.log"
Log "Day 9 finalizer start"

trap {
    try { Log ("UNHANDLED: " + $_.Exception.Message) } catch {}
    Write-Host ""
    Write-Host "DAY 9 FINALIZER STOPPED"
    Write-Host "Log: $script:LogPath"
    exit 1
}

$gh = Need "gh"
& $gh auth status
if ($LASTEXITCODE -ne 0) { Fail "gh auth login required" }

Log "dispatching a fresh System CI for current main"
$mainSha = ((& $gh api "repos/$Repository/commits/main" --jq .sha) -join "").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($mainSha)) { Fail "cannot resolve current main SHA" }

$dispatchLines = @(& $gh workflow run system-ci.yml --repo $Repository --ref main 2>&1)
$dispatchExit = $LASTEXITCODE
$dispatchLines | ForEach-Object { Write-Host $_ }
if ($dispatchExit -ne 0) { Fail "cannot dispatch System CI" }

$dispatchText = ($dispatchLines -join "`n")
$runMatch = [regex]::Match($dispatchText, 'actions/runs/(?<id>[0-9]+)')
if (-not $runMatch.Success) { Fail "workflow dispatch succeeded but run URL was not returned" }
$runId = [string]$runMatch.Groups['id'].Value

$runViewJson = @(& $gh run view $runId --repo $Repository --json databaseId,headSha,event,status,conclusion,url,workflowName)
if ($LASTEXITCODE -ne 0) { Fail "cannot read dispatched System CI run $runId" }
$runView = (($runViewJson -join "`n") | ConvertFrom-Json)
if ([string]$runView.headSha -ne $mainSha) { Fail "dispatched run SHA mismatch: run=$($runView.headSha) main=$mainSha" }
if ([string]$runView.event -ne "workflow_dispatch") { Fail "unexpected run event: $($runView.event)" }
if ([string]$runView.workflowName -ne "System CI") { Fail "unexpected workflow: $($runView.workflowName)" }
Log "captured fresh System CI run directly: $runId head=$mainSha"
Log "watching fresh System CI run $runId head=$mainSha"
& $gh run watch $runId --repo $Repository --exit-status
if ($LASTEXITCODE -ne 0) { Fail "fresh main System CI failed" }
Log "fresh main System CI PASS"

$artifact = Join-Path $work "gsc"
New-Item -ItemType Directory -Force $artifact | Out-Null
& $gh run download $runId --repo $Repository -n "gsc-4.2.4-ci" -D $artifact
if ($LASTEXITCODE -ne 0) { Fail "cannot download gsc-4.2.4-ci artifact" }
VerifySums $artifact
Log "GSC 4.2.4 CI artifact hashes PASS"

$hostExe = Join-Path $artifact "GeumyiServerHost.exe"
$setup = Join-Path $artifact "GeumyiServerCenter-v4.2.4-Setup.exe"
foreach ($p in @($hostExe,$setup)) {
    if (-not (Test-Path -LiteralPath $p)) { Fail "missing artifact: $p" }
}

Log "running deployed Host transaction/rollback self-test"
$self = Start-Process -FilePath $hostExe -ArgumentList "--day9-selftest" -PassThru -Wait
if ($self.ExitCode -ne 0) { Fail "Host --day9-selftest failed with exit code $($self.ExitCode)" }
Log "HOST DAY9 SELFTEST PASS"

$health = $null
try { $health = WaitGsc 15 } catch {}
if ($null -eq $health -or [string]$health.version -ne "4.2.4") {
    Log "GSC 4.2.4 is not active. Installer will open; keep the existing role and server paths."
    $p = Start-Process -FilePath $setup -PassThru
    if (-not $p.WaitForExit(900000)) { Fail "GSC 4.2.4 Setup did not exit within 15 minutes" }
    if ($p.ExitCode -ne 0) { Fail "GSC Setup exit=$($p.ExitCode)" }
    $health = WaitGsc 120
}
if ([string]$health.version -ne "4.2.4") { Fail "GSC API version is $($health.version), expected 4.2.4" }
Log "GSC 4.2.4 installed and API healthy"

$liveResult = "SKIPPED"
$failOpenPhase = ""
$wildInitialOnline = $null
$wildFinalOnline = $null
if ($RunWildFailOpen) {
    $wild = State "wild"
    if ($null -eq $wild) { Fail "wild server missing" }
    $players = 0
    if ($wild.minecraft -and $null -ne $wild.minecraft.online) { $players = [int]$wild.minecraft.online }
    if ($players -gt 0) { Fail "wild has $players online player(s); refusing restart" }

    $wildInitialOnline = [bool]$wild.online
    Log ("Wild initial state: online=" + $wildInitialOnline)

    $before = Gsc "GET" "/api/v4/update/settings"
    $restore = @{
        enabled = [bool]$before.enabled
        repository = [string]$before.repository
        channel = [string]$before.channel
        public_key_path = [string]$before.public_key_path
        timeout_seconds = [int]$before.timeout_seconds
    }
    $restoreErrors = New-Object System.Collections.Generic.List[string]

    try {
        if ([bool]$wild.online) {
            Log "gracefully stopping Wild"
            Gsc "POST" "/api/server/action" @{id="wild";action="stop"} | Out-Null
            WaitOnline "wild" $false 180 | Out-Null
        }

        Log "injecting GitHub lookup failure; existing server files must still boot"
        Gsc "POST" "/api/v4/update/settings" @{
            enabled = $true
            repository = "geumyi22/Geumyi-Minecraft-System-day9-offline-test"
            channel = [string]$before.channel
            public_key_path = [string]$before.public_key_path
            timeout_seconds = 3
        } | Out-Null

        Gsc "POST" "/api/server/action" @{id="wild";action="start"} | Out-Null
        WaitOnline "wild" $true 240 | Out-Null
        $us = Gsc "GET" "/api/v4/update/status?id=wild"
        $failOpenPhase = [string]$us.phase
        if ($failOpenPhase -ne "error") {
            Fail "expected updater error during GitHub failure injection, got phase=$failOpenPhase"
        }
        Log "LIVE FAIL-OPEN PASS: updater failed but Wild returned ONLINE"

        $end = (Get-Date).AddSeconds(45)
        $v4 = $null
        do {
            try { $v4 = Gsc "GET" "/api/v4/health?id=wild" } catch {}
            if ($null -ne $v4 -and [string]$v4.overall -ne "fail") { break }
            Start-Sleep 3
        } while ((Get-Date) -lt $end)
        if ($null -eq $v4 -or [string]$v4.overall -eq "fail") { Fail "Wild v4 health failed after fail-open restart" }
        Log ("Wild health after fail-open restart: " + [string]$v4.overall)
    }
    finally {
        try {
            Gsc "POST" "/api/v4/update/settings" $restore | Out-Null
            Log "original update settings restored"
        } catch {
            $restoreErrors.Add("update settings restore failed: " + $_.Exception.Message)
        }

        try {
            $cur = State "wild"
            if ($null -eq $cur) {
                $restoreErrors.Add("cannot read Wild state during restoration")
            } elseif ($wildInitialOnline -and -not [bool]$cur.online) {
                Log "restoring original Wild state: ONLINE"
                Gsc "POST" "/api/server/action" @{id="wild";action="start"} | Out-Null
                WaitOnline "wild" $true 240 | Out-Null
            } elseif (-not $wildInitialOnline -and [bool]$cur.online) {
                Log "restoring original Wild state: OFFLINE"
                Gsc "POST" "/api/server/action" @{id="wild";action="stop"} | Out-Null
                WaitOnline "wild" $false 180 | Out-Null
            }
        } catch {
            $restoreErrors.Add("Wild state restore failed: " + $_.Exception.Message)
        }
    }

    if ($restoreErrors.Count -gt 0) {
        Fail ("post-test restoration failed: " + ($restoreErrors -join " | "))
    }

    $finalWild = State "wild"
    if ($null -eq $finalWild) { Fail "cannot read final Wild state" }
    $wildFinalOnline = [bool]$finalWild.online
    if ($wildFinalOnline -ne $wildInitialOnline) {
        Fail "Wild final state does not match initial state"
    }
    Log ("Wild original state restored: online=" + $wildFinalOnline)
    $liveResult = "PASS"
}

$result = [ordered]@{
    gsc_version = "4.2.4"
    system_ci_run = $runId
    artifact_hashes = "PASS"
    host_transaction_selftest = "PASS"
    gsc_install_api = "PASS"
    live_fail_open = $liveResult
    fail_open_phase = $failOpenPhase
    wild_initial_online = $wildInitialOnline
    wild_final_online = $wildFinalOnline
    log = $script:LogPath
}
$out = Join-Path $work "day9-result.json"
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $out -Encoding UTF8
$result | Format-List | Out-Host
Write-Host "Result: $out"
Write-Host "Log:    $script:LogPath"
exit 0
