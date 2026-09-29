param(
    [string]$Repository = "geumyi22/Geumyi-Minecraft-System",
    [string]$Tag = "",
    [switch]$RunServerE2E,
    [switch]$TryAndroidADB,
    [switch]$ReuseExistingRelease
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
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Gsc([string]$Method,[string]$Path,$Body=$null) {
    $u = "http://127.0.0.1:8787$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Method $Method -Uri $u -TimeoutSec 15 }
    Invoke-RestMethod -Method $Method -Uri $u -TimeoutSec 15 -ContentType "application/json" -Body ($Body|ConvertTo-Json -Depth 8 -Compress)
}
function WaitGsc([int]$sec=120) {
    $end=(Get-Date).AddSeconds($sec)
    do { try { return Gsc "GET" "/api/status" } catch {} ; Start-Sleep 2 } while((Get-Date)-lt $end)
    throw "GSC :8787 readiness timeout"
}
function State([string]$id) {
    $s=Gsc "GET" "/api/status"
    @($s.servers)|Where-Object {$_.id -eq $id}|Select-Object -First 1
}
function WaitOnline([string]$id,[bool]$want,[int]$sec=240) {
    $end=(Get-Date).AddSeconds($sec)
    do {
        $s=State $id
        if($null-ne $s -and [bool]$s.online -eq $want){ return $s }
        Start-Sleep 3
    } while((Get-Date)-lt $end)
    throw "server $id online=$want timeout"
}
function Need([string]$name,[string[]]$candidates=@()) {
    $c=Get-Command $name -ErrorAction SilentlyContinue
    if($c){ return $c.Source }
    foreach($candidate in $candidates) {
        if($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw "$name not found"
}

if(-not (IsAdmin)){ throw "Run this script from an Administrator PowerShell." }

$stamp=Get-Date -Format "yyyyMMdd-HHmmss"
$work=Join-Path $env:TEMP "Geumyi-Day8-$stamp"
New-Item -ItemType Directory -Force $work|Out-Null
$script:LogPath=Join-Path $work "day8-e2e.log"
Log "Day 8 E2E finalizer start"

trap {
    try {
        Log ("UNHANDLED: " + $_.Exception.Message)
    }
    catch {}
    Write-Host ""
    Write-Host "DAY 8 FINALIZER STOPPED"
    Write-Host "Log: $script:LogPath"
    exit 1
}

$gh=Need "gh"
$openssl=Need "openssl" @(
    "$env:ProgramFiles\Git\usr\bin\openssl.exe"
)
& $gh auth status
if($LASTEXITCODE-ne 0){ Fail "gh auth login required" }

$bootstrap=Join-Path $PSScriptRoot "bootstrap_day8_signing.ps1"
if(-not(Test-Path $bootstrap)){ Fail "bootstrap_day8_signing.ps1 missing beside finalizer" }
& $bootstrap -Repository $Repository
if($LASTEXITCODE-ne 0){ Fail "signing bootstrap failed" }

$trusted=Join-Path $env:ProgramData "GeumyiServerCenter\deployment-public.pem"
if(-not(Test-Path $trusted)){ Fail "trusted deployment public key missing" }

if($ReuseExistingRelease){
    if([string]::IsNullOrWhiteSpace($Tag)){ Fail "ReuseExistingRelease requires -Tag" }
    & $gh release view $Tag --repo $Repository --json tagName,isPrerelease,publishedAt | Out-Null
    if($LASTEXITCODE-ne 0){ Fail "existing release not found: $Tag" }
    Log "reusing existing secure release tag=$Tag"
} else {
    if([string]::IsNullOrWhiteSpace($Tag)){
        $Tag="system-"+(Get-Date -Format "yyyy.MM.dd-HHmmss")+"-canary"
    }
    Log "release tag=$Tag"

    & $gh workflow run day8-release.yml --repo $Repository --ref main -f channel=canary -f "tag=$Tag" -f prerelease=true
    if($LASTEXITCODE-ne 0){ Fail "workflow dispatch failed" }
    Start-Sleep 5
    $runJson=& $gh run list --repo $Repository --workflow day8-release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId,status,conclusion,createdAt,headSha
    if($LASTEXITCODE-ne 0){ Fail "cannot list release workflow" }
    $run=(($runJson -join "`n")|ConvertFrom-Json|Select-Object -First 1)
    if(-not $run.databaseId){ Fail "cannot identify release workflow run" }
    $runId=[string]$run.databaseId
    Log "watching workflow run $runId"
    & $gh run watch $runId --repo $Repository --exit-status
    if($LASTEXITCODE-ne 0){ Fail "secure release workflow failed" }
    Log "secure release workflow PASS"
}

$rel=Join-Path $work "release"
New-Item -ItemType Directory -Force $rel|Out-Null
& $gh release download $Tag --repo $Repository --dir $rel
if($LASTEXITCODE-ne 0){ Fail "release download failed" }

$manifest=Join-Path $rel "deployment-canary.json"
$sig="$manifest.sig"
$pub=Join-Path $rel "deployment-public.pem"
foreach($p in @($manifest,$sig,$pub)){ if(-not(Test-Path $p)){ Fail "missing release asset: $p" } }

if((Get-FileHash $trusted -Algorithm SHA256).Hash -ne (Get-FileHash $pub -Algorithm SHA256).Hash){
    Fail "release public key != trusted local public key"
}
& $openssl pkeyutl -verify -rawin -pubin -inkey $trusted -in $manifest -sigfile $sig | Out-Null
if($LASTEXITCODE-ne 0){ Fail "manifest Ed25519 verification failed" }

$m=Get-Content $manifest -Raw|ConvertFrom-Json
if($m.channel-ne "canary" -or $m.release-ne $Tag){ Fail "manifest channel/tag mismatch" }
if($m.components.technology.version-ne "0.1.4"){ Fail "Technology marker is not 0.1.4" }
if(@($m.components.technology.targets)-notcontains "wild"){ Fail "Technology is not wild-only in manifest" }

foreach($p in $m.components.PSObject.Properties){
    $c=$p.Value
    $f=Join-Path $rel ([string]$c.file)
    if(-not(Test-Path $f)){ Fail "manifest artifact missing: $($c.file)" }
    if((Get-Item $f).Length-ne [int64]$c.size){ Fail "size mismatch: $($c.file)" }
    $h=(Get-FileHash $f -Algorithm SHA256).Hash.ToLowerInvariant()
    if($h-ne ([string]$c.sha256).ToLowerInvariant()){ Fail "sha256 mismatch: $($c.file)" }
}
Log "signed manifest + all release artifact hashes PASS"

$gscOk=$false
try { if(Gsc "GET" "/api/v4/update/status"){ $gscOk=$true } } catch {}
if(-not $gscOk){
    $setup=Join-Path $rel "GeumyiServerCenter-v4.2.3-Setup.exe"
    if(-not(Test-Path $setup)){ Fail "GSC setup asset missing" }
    Log "Day 8 GSC not active. Installer will open; complete the existing-role upgrade."
    $p=Start-Process $setup -PassThru
    if(-not $p.WaitForExit(900000)){ Fail "GSC setup did not exit within 15 minutes" }
    if($p.ExitCode-ne 0){ Fail "GSC setup exit=$($p.ExitCode)" }
    Copy-Item $pub $trusted -Force
    WaitGsc 120|Out-Null
    try { if(Gsc "GET" "/api/v4/update/status"){ $gscOk=$true } } catch {}
}
if(-not $gscOk){ Fail "Day 8 GSC update API unavailable" }
Log "GSC Day 8 update API PASS"

Gsc "POST" "/api/v4/update/settings" @{
    enabled=$true; channel="canary"; repository=$Repository; public_key_path=$trusted
}|Out-Null
$check=Gsc "POST" "/api/v4/update/check" @{id="wild"}
Log ("wild dry-check phase={0} message={1}" -f $check.phase,$check.message)

$serverResult="SKIPPED"
if($RunServerE2E){
    $playBefore=Gsc "GET" "/api/v4/inventory?id=playground"
    if(@($playBefore.plugins|Where-Object {$_.name-eq "GeumyiTechnology"}).Count-gt 0){
        Fail "Technology exists on Playground before test; wild-only invariant already violated"
    }
    $wild=State "wild"
    if($null-eq $wild){ Fail "wild server missing" }
    $players=0
    if($wild.minecraft -and $null-ne $wild.minecraft.online){ $players=[int]$wild.minecraft.online }
    if($players-gt 0){ Fail "wild has $players online player(s); refusing automatic restart" }

    if([bool]$wild.online){
        Log "gracefully stopping Wild"
        Gsc "POST" "/api/server/action" @{id="wild";action="stop"}|Out-Null
        WaitOnline "wild" $false 180|Out-Null
    }
    Log "starting Wild; pre-start updater must install Technology 0.1.4"
    Gsc "POST" "/api/server/action" @{id="wild";action="start"}|Out-Null
    WaitOnline "wild" $true 240|Out-Null

    $wi=Gsc "GET" "/api/v4/inventory?id=wild"
    $t=@($wi.plugins|Where-Object {$_.name-eq "GeumyiTechnology" -and $_.enabled})
    if($t.Count-ne 1 -or [string]$t[0].version-ne "0.1.4"){
        Fail "Wild Technology did not end at exactly one enabled 0.1.4"
    }
    $pi=Gsc "GET" "/api/v4/inventory?id=playground"
    if(@($pi.plugins|Where-Object {$_.name-eq "GeumyiTechnology"}).Count-gt 0){
        Fail "Technology appeared on Playground"
    }
    $us=Gsc "GET" "/api/v4/update/status?id=wild"
    if($us.phase-notin @("applied","current")){ Fail "unexpected updater phase: $($us.phase)" }
    Log "SERVER E2E PASS: Wild=Technology 0.1.4, Playground untouched"
    $serverResult="PASS"
}

$androidResult="NOT_RUN"
$apk=Join-Path $rel "GSCM-v1.1.2+113-Android.apk"
if(-not(Test-Path $apk)){ Fail "Android APK missing" }
if($TryAndroidADB){
    $adb=Get-Command adb -ErrorAction SilentlyContinue
    if(-not $adb){
        $androidResult="NO_ADB"
        Log "Android ADB test skipped: adb not found"
    } else {
        $dev=@(& $adb.Source devices|Select-String "`tdevice$"|ForEach-Object {($_ -split "`t")[0]})
        if($dev.Count-ne 1){
            $androidResult="NO_DEVICE"
            Log "Android ADB test skipped: connect exactly one device"
        } else {
            & $adb.Source -s $dev[0] install -r $apk | Out-Host
            if($LASTEXITCODE-eq 0){
                $androidResult="PASS"
                Log "ANDROID ADB E2E PASS"
            } else {
                $androidResult="SIGNER_TRANSITION_REQUIRED"
                Log "Android install-r failed. Do NOT auto-uninstall; if signer mismatch is reported, one manual uninstall/reinstall is required once."
            }
        }
    }
}

$result=[ordered]@{
    tag=$Tag
    release="PASS"
    manifest="PASS"
    hashes="PASS"
    gsc_update_api="PASS"
    dry_check=[string]$check.phase
    server_e2e=$serverResult
    android_e2e=$androidResult
    log=$script:LogPath
}
$out=Join-Path $work "day8-result.json"
$result|ConvertTo-Json -Depth 5|Set-Content $out -Encoding UTF8
$result|Format-List|Out-Host
Write-Host "Result: $out"
Write-Host "Log:    $script:LogPath"

if($RunServerE2E -and $serverResult-ne "PASS"){ exit 2 }
if($TryAndroidADB -and $androidResult-ne "PASS"){ exit 3 }
exit 0
