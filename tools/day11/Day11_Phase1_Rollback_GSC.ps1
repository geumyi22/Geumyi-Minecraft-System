[CmdletBinding()]
param(
    [string]$BackupPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ServiceName = "Geumyi Server Center Host"
$ProgramDataRoot = if ($env:PROGRAMDATA) { $env:PROGRAMDATA } else { "C:\ProgramData" }
$StateRoot = Join-Path $ProgramDataRoot "GeumyiServerCenter"
$BackupRoot = Join-Path $StateRoot "Backups"

function Is-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-Health {
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/health" -Method Get -TimeoutSec 3 } catch { return $null }
}
function Wait-Health([int]$Seconds=60) {
    $end=(Get-Date).AddSeconds($Seconds)
    do {
        $h=Get-Health
        if($null -ne $h -and $h.ok -eq $true){ return $h }
        Start-Sleep -Milliseconds 800
    } while((Get-Date)-lt $end)
    return $null
}
function Resolve-ServiceExe {
    $svc=Get-CimInstance Win32_Service -Filter ("Name='" + $ServiceName.Replace("'","''") + "'") -ErrorAction Stop
    $raw=[string]$svc.PathName
    if($raw.StartsWith('"')){
        $end=$raw.IndexOf('"',1)
        if($end -gt 1){ return $raw.Substring(1,$end-1) }
    }
    $fallback="C:\Program Files\Geumyi Server Center\GeumyiServerHost.exe"
    if(Test-Path -LiteralPath $fallback -PathType Leaf){ return $fallback }
    throw "Cannot resolve GSC Host executable."
}

if(-not(Is-Administrator)){ throw "Administrator privileges are required." }

if([string]::IsNullOrWhiteSpace($BackupPath)){
    $candidate=Get-ChildItem -LiteralPath $BackupRoot -Directory -Filter "Day11-GSCHostTest-*" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($null -eq $candidate){ throw "No Day 11 GSC host-test backup found." }
    $BackupPath=$candidate.FullName
}
$oldHost=Join-Path $BackupPath "GeumyiServerHost.exe"
$oldClient=Join-Path $BackupPath "GeumyiServerCenter.exe"
if(-not(Test-Path -LiteralPath $oldHost -PathType Leaf)){ throw "Backup Host executable missing: $oldHost" }

$hostPath=Resolve-ServiceExe
$installDir=Split-Path -Parent $hostPath
$clientPath=Join-Path $installDir "GeumyiServerCenter.exe"

$runningClient=Get-CimInstance Win32_Process -Filter "Name='GeumyiServerCenter.exe'" -ErrorAction SilentlyContinue
if(@($runningClient).Count -gt 0){ throw "Close the Geumyi Server Center desktop app before rollback." }

$svc=Get-Service -Name $ServiceName -ErrorAction Stop
if($svc.Status -ne "Stopped"){
    Stop-Service -Name $ServiceName -ErrorAction Stop
    $svc.WaitForStatus("Stopped",[TimeSpan]::FromSeconds(30))
}
Copy-Item -LiteralPath $oldHost -Destination $hostPath -Force
if(Test-Path -LiteralPath $oldClient -PathType Leaf){ Copy-Item -LiteralPath $oldClient -Destination $clientPath -Force }
Start-Service -Name $ServiceName -ErrorAction Stop
$h=Wait-Health 60
if($null -eq $h){ throw "Rollback files restored but GSC health did not recover." }

Write-Host "DAY 11 MANUAL GSC ROLLBACK PASS" -ForegroundColor Green
Write-Host ("Restored from: " + $BackupPath)
Write-Host ("GSC health version: " + $h.version)
Write-Host "Minecraft/Paper/Velocity were not stopped."
