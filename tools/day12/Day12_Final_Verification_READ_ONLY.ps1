[CmdletBinding()]
param(
    [string]$OutputDir = "",
    [switch]$Synthetic
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Check([string]$Key,[string]$Label,[string]$Status,[string]$Message){
    [pscustomobject]@{ key=$Key; label=$Label; status=$Status; message=$Message }
}
function Size-Bytes([string]$Path){
    if(-not(Test-Path -LiteralPath $Path)){return [int64]0}
    $sum=[int64]0
    Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {$sum += [int64]$_.Length}
    return $sum
}
function Tcp-Listening([int]$Port){
    try { return [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { return $false }
}
function Udp-Listening([int]$Port){
    try { return [bool](Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { return $false }
}
function Safe-JsonGet([string]$Url){
    try { return Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 5 -ErrorAction Stop } catch { return $null }
}

if([string]::IsNullOrWhiteSpace($OutputDir)){
    $OutputDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Final-Verification"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$checks = New-Object 'System.Collections.Generic.List[object]'
$pd = if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root = Join-Path $pd "GeumyiServerCenter"

if($Synthetic){
    $checks.Add((New-Check "synthetic" "Synthetic safety mode" "ok" "No live state inspected or changed.")) | Out-Null
} else {
    $checks.Add((New-Check "gsc_root" "GSC data root" $(if(Test-Path -LiteralPath $root){"ok"}else{"fail"}) $root)) | Out-Null

    $health = Safe-JsonGet "http://127.0.0.1:8787/api/health"
    $checks.Add((New-Check "gsc_health" "GSC Host health" $(if($null -ne $health){"ok"}else{"fail"}) $(if($null -ne $health){"localhost API responding"}else{"localhost API unavailable"}))) | Out-Null

    $status = Safe-JsonGet "http://127.0.0.1:8787/api/status"
    if($null -eq $status){
        $checks.Add((New-Check "gsc_status" "GSC status snapshot" "fail" "Unable to read /api/status")) | Out-Null
    } else {
        $checks.Add((New-Check "gsc_status" "GSC status snapshot" "ok" ("v"+[string]$status.app_version))) | Out-Null
        foreach($s in @($status.servers)){
            $sid=[string]$s.id
            $checks.Add((New-Check ("server_"+$sid+"_java") ($sid+" Java") $(if([bool]$s.java_port_open){"ok"}else{"warn"}) $(if([bool]$s.java_port_open){"listening"}else{"offline"}))) | Out-Null
            if([bool]$s.online){
                $checks.Add((New-Check ("server_"+$sid+"_rcon") ($sid+" RCON") $(if([bool]$s.rcon_port_open){"ok"}else{"warn"}) $(if([bool]$s.rcon_port_open){"usable"}else{"management limited"}))) | Out-Null
            }
        }
    }

    $entry = Safe-JsonGet "http://127.0.0.1:8787/api/v4/network/entry-status"
    if($null -eq $entry){
        $checks.Add((New-Check "network_entry" "Java/Bedrock public entrypoints" "warn" "GSC network entry API unavailable")) | Out-Null
    } else {
        foreach($e in @($entry.endpoints)){
            $javaOk=[bool]$e.java_responding
            $bedOk=[bool]$e.bedrock_raknet_pong
            $st=if($javaOk -and $bedOk){"ok"}elseif($javaOk -or $bedOk){"warn"}else{"fail"}
            $checks.Add((New-Check ("entry_"+[string]$e.id) ("Public entry "+[string]$e.id) $st ("Java="+$javaOk+" Bedrock="+$bedOk))) | Out-Null
        }
    }

    foreach($p in @(25565,25566,25567)){
        $checks.Add((New-Check ("tcp_"+$p) ("TCP "+$p) $(if(Tcp-Listening $p){"ok"}else{"warn"}) $(if(Tcp-Listening $p){"LISTEN"}else{"not listening"}))) | Out-Null
    }
    foreach($p in @(19132,19133,19134)){
        $checks.Add((New-Check ("udp_"+$p) ("UDP "+$p) $(if(Udp-Listening $p){"ok"}else{"warn"}) $(if(Udp-Listening $p){"BOUND"}else{"not bound"}))) | Out-Null
    }

    try{
        $svc=Get-Service -Name "Geumyi Server Center Host" -ErrorAction Stop
        $checks.Add((New-Check "gsc_service" "GSC Windows service" $(if($svc.Status -eq "Running"){"ok"}else{"warn"}) ([string]$svc.Status))) | Out-Null
    }catch{
        $checks.Add((New-Check "gsc_service" "GSC Windows service" "warn" "Service not found")) | Out-Null
    }

    foreach($id in @("wild","playground","other")){
        $taskName="Geumyi Day10 Velocity "+$id
        try{
            $task=Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            $checks.Add((New-Check ("task_velocity_"+$id) ($taskName+" startup task") $(if($task.State -ne "Disabled"){"ok"}else{"fail"}) ([string]$task.State))) | Out-Null
        }catch{
            $checks.Add((New-Check ("task_velocity_"+$id) ($taskName+" startup task") "warn" "Task not found")) | Out-Null
        }
    }

    $backupRoot=Join-Path $root "Backups"
    $backupBytes=Size-Bytes $backupRoot
    $latest=Get-ChildItem -LiteralPath $backupRoot -Filter "*.zip" -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $backupMsg=("size={0:N2} GiB" -f ($backupBytes/1GB))
    if($null -ne $latest){$backupMsg += "; latest="+$latest.LastWriteTime.ToString("s")}
    $checks.Add((New-Check "backup_inventory" "Backup inventory" $(if($null -ne $latest){"ok"}else{"warn"}) $backupMsg)) | Out-Null

    $updates=Join-Path $root "Updates"
    $residue=@()
    if(Test-Path -LiteralPath $updates){
        $residue=@(Get-ChildItem -LiteralPath $updates -File -Recurse -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '(?i)\.tmp$|\.part$|pending|journal|transaction'})
    }
    $checks.Add((New-Check "update_residue" "Update transaction residue" $(if($residue.Count -eq 0){"ok"}else{"warn"}) ("items="+$residue.Count))) | Out-Null

    try{
        $drive=(Get-Item -LiteralPath $root).PSDrive
        $free=[int64]$drive.Free
        $checks.Add((New-Check "disk_free" "Disk free space" $(if($free -ge 50GB){"ok"}elseif($free -ge 20GB){"warn"}else{"fail"}) ("{0:N2} GiB" -f ($free/1GB)))) | Out-Null
    }catch{
        $checks.Add((New-Check "disk_free" "Disk free space" "warn" "Unable to read disk space")) | Out-Null
    }
}

$pass=@($checks | Where-Object {$_.status -eq "ok"}).Count
$warn=@($checks | Where-Object {$_.status -eq "warn"}).Count
$fail=@($checks | Where-Object {$_.status -eq "fail"}).Count
$report=[ordered]@{
    schema=1
    tool="Geumyi Final Verification"
    read_only=$true
    synthetic=[bool]$Synthetic
    generated_at=(Get-Date).ToString("o")
    summary=[ordered]@{pass=$pass;warn=$warn;fail=$fail}
    checks=@($checks)
    notes=@(
        "This verifier does not prove Java/Bedrock real-client E2E.",
        "No passwords, tokens, private keys, or full configuration files are exported."
    )
}
$out=Join-Path $OutputDir ("Geumyi-Final-Verification-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("FINAL VERIFICATION: PASS {0} / WARN {1} / FAIL {2}" -f $pass,$warn,$fail)
Write-Host ("Report: "+$out)
if($fail -gt 0){exit 2}
exit 0
