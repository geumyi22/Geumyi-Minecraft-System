[CmdletBinding()]
param(
    [string]$BaseUrl = "http://127.0.0.1:8790",
    [string]$OutputDir = "",
    [switch]$Synthetic,
    [string]$FixtureRoot=""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Expected = [ordered]@{
    gsc = "4.3.8"
    gscm = "1.1.5+117"
    status_agent = "0.5.4"
    gst = "1.1.1"
    gds = "1.1.1"
    technology = "0.1.4"
    chemistry = "0.4.1"
    network = [ordered]@{
        public = @(
            [ordered]@{ id="wild"; java=25565; bedrock=19132 }
            [ordered]@{ id="playground"; java=25566; bedrock=19133 }
            [ordered]@{ id="other"; java=25567; bedrock=19134 }
        )
        backend = @(
            [ordered]@{ id="wild"; java=25570; rcon=25575 }
            [ordered]@{ id="playground"; java=25571; rcon=25576 }
            [ordered]@{ id="other"; java=25572; rcon=25577 }
            [ordered]@{ id="lobby"; java=25573; rcon=25579 }
        )
    }
}

function Get-PDRoot {
    if(-not [string]::IsNullOrWhiteSpace($env:PROGRAMDATA)){ return $env:PROGRAMDATA }
    return "C:\ProgramData"
}
function Hash-File([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path) -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){ return "" }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { return "" }
}
# Backup API JSON intentionally omits false/empty fields (Go omitempty).
# Never assume optional properties exist under Set-StrictMode.
function Read-BackupField([object]$Backup,[string]$Field,[object]$Default=$null){
    if($null -eq $Backup){ return $Default }
    $prop=$Backup.PSObject.Properties[$Field]
    if($null -eq $prop -or $null -eq $prop.Value){ return $Default }
    return $prop.Value
}
# Treat omitted API fields as unknown/default; never crash under StrictMode.
function Optional([object]$Value,[string]$Field,[object]$Default=$null){
    foreach($part in $Field.Split('.')){
        if($null -eq $Value){return $Default}
        if($Value -is [System.Collections.IDictionary]){
            if(-not $Value.Contains($part)){return $Default}
            $Value=$Value[$part]
        }else{
            $prop=$Value.PSObject.Properties[$part]
            if($null -eq $prop){return $Default}
            $Value=$prop.Value
        }
    }
    if($null -eq $Value){return $Default}
    return $Value
}
function Json-File([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){ return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Resolve-HostExe {
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
        $raw = [string]$svc.PathName
        if(-not [string]::IsNullOrWhiteSpace($raw)){
            $candidate = ""
            $trim = $raw.Trim()
            if($trim.StartsWith('"')){
                $end = $trim.IndexOf('"',1)
                if($end -gt 1){ $candidate = $trim.Substring(1,$end-1) }
            } else {
                $m = [regex]::Match($trim,'^(.+?\.exe)(?:\s|$)',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if($m.Success){ $candidate = $m.Groups[1].Value }
            }
            if(-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)){ return $candidate }
        }
    } catch {}
    $fallback = Join-Path $(if($env:ProgramFiles){$env:ProgramFiles}else{"C:\Program Files"}) "Geumyi Server Center\GeumyiServerHost.exe"
    if(Test-Path -LiteralPath $fallback -PathType Leaf){ return $fallback }
    return ""
}
function Get-Json([string]$Base,[string]$Path,[int]$Timeout=8){
  if($FixtureRoot){
    if($env:GITHUB_ACTIONS -ne "true"){throw "FixtureRoot is restricted to CI"}
    $route=(($Path -replace '[^A-Za-z0-9]+','_').Trim('_'))+".json"
    $fixtureFile=Join-Path $FixtureRoot $route
    if(Test-Path -LiteralPath $fixtureFile -PathType Leaf){
      return (Get-Content -LiteralPath $fixtureFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return $null
  }
  
    try { return Invoke-RestMethod -Uri ($Base.TrimEnd('/')+$Path) -Method GET -TimeoutSec $Timeout -ErrorAction Stop } catch { return $null }
}
function Get-Jars([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Container)){ return @() }
    return @(Get-ChildItem -LiteralPath $Path -Filter *.jar -File -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object {
            [ordered]@{ name=$_.Name; size=[int64]$_.Length; sha256=Hash-File $_.FullName }
        })
}
function Tcp-Listening([int]$Port){
    # Get-NetTCPConnection may return an empty result without throwing.
    # That must not skip netstat and active loopback TCP checks.
    try {
        if(@(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue).Count -gt 0){return $true}
    } catch {}
    try {
        $lines=@(& netstat.exe -ano -p tcp 2>$null)
        $regex='^\\s*TCP\\s+\\S+:'+$Port+'\\s+\\S+\\s+LISTENING(?:\\s+\\d+)?\\s*$'
        if(@($lines | Where-Object {$_ -match $regex}).Count -gt 0){return $true}
    } catch {}
    # Loopback handshake is valid evidence of a listening TCP endpoint,
    # but does not establish ownership, public reachability or player E2E.
    $client=New-Object System.Net.Sockets.TcpClient
    try {
        $pending=$client.BeginConnect("127.0.0.1",$Port,$null,$null)
        if(-not $pending.AsyncWaitHandle.WaitOne(500,$false)){return $false}
        $client.EndConnect($pending)
        return $client.Connected
    } catch {return $false}
    finally {$client.Dispose()}
}
function Udp-Bound([int]$Port){
    try { return [bool](Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1) } catch {}
    try { return [bool](& netstat.exe -ano -p udp 2>$null | Select-String -SimpleMatch (":"+$Port+" ")) } catch { return $false }
}
function Add-Check([System.Collections.Generic.List[object]]$List,[string]$Key,[bool]$Pass,[string]$Message,[bool]$Mandatory=$true){
    $List.Add([pscustomobject]@{
        key=$Key
        status=$(if($Pass){"PASS"}else{"CHECK"})
        mandatory=$Mandatory
        message=$Message
    }) | Out-Null
}

if([string]::IsNullOrWhiteSpace($OutputDir)){
    $OutputDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase0"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outPath = Join-Path $OutputDir ("Geumyi-Day12-Phase0-GoldenBaseline-"+$stamp+".json")

if($Synthetic){
    # Regression: unprotected backup records omit 'protected' and source_reason.
    $unprotected=[pscustomobject]@{file="fixture.zip";created_at="2026-01-01T00:00:00Z"}
    if([bool](Read-BackupField $unprotected "protected" $false) -or [string](Read-BackupField $unprotected "source_reason" "") -ne ""){
        throw "Omitted optional backup metadata regression"
    }
    $report=[ordered]@{
        schema=1
        phase="12.0A"
        tool="Day12 Golden Baseline READ-ONLY"
        mode="READ_ONLY"
        synthetic=$true
        generated_at=(Get-Date).ToString("o")
        result="SYNTHETIC_PASS"
        expected=$Expected
        checks=@(
            [ordered]@{key="synthetic_contract";status="PASS";mandatory=$true;message="No live state inspected."}
        )
        failed_mandatory=@()
        ready_for_phase_12_0B=$true
        redaction=[ordered]@{secrets_exported=$false;full_local_paths_exported=$false}
        mutation=[ordered]@{performed=$false;server_lifecycle=$false;backup_created=$false;backup_moved_or_deleted=$false;config_changed=$false}
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Host "DAY 12 PHASE 0A SYNTHETIC PASS"
    Write-Host ("Report: "+$outPath)
    exit 0
}

$pd = Get-PDRoot
$gscRoot = Join-Path $pd "GeumyiServerCenter"
$configPath = Join-Path $gscRoot "server.json"
$networkRoot = Join-Path $gscRoot "Network\FourServer"
$updatesRoot = Join-Path $gscRoot "Updates"

# Prefer the local Client proxy because it carries the configured Host token.
$apiBase = $BaseUrl.TrimEnd('/')
$status = Get-Json $apiBase "/api/status"
if($null -eq $status){
    $apiBase = "http://127.0.0.1:8787"
    $status = Get-Json $apiBase "/api/status"
}
$client = Get-Json ($BaseUrl.TrimEnd('/')) "/client/config"
$info = Get-Json $apiBase "/api/v1/info"
$snapshot = Get-Json $apiBase "/api/v1/snapshot"
$fleet = Get-Json $apiBase "/api/v4/update/fleet"
$network = Get-Json $apiBase "/api/v4/network/entry-status"
$health = Get-Json $apiBase "/api/v4/health"
$selfUpdate = Get-Json $apiBase "/api/v4/update/self/status"

$hostExe = Resolve-HostExe
$installDir = if([string]::IsNullOrWhiteSpace($hostExe)){""}else{Split-Path -Parent $hostExe}
$clientExe = if($installDir){Join-Path $installDir "GeumyiServerCenter.exe"}else{""}
$setupExe = if($installDir){Join-Path $installDir "GeumyiServerCenter-Setup.exe"}else{""}

$cfg = Json-File $configPath
$serverRows = @()
if($null -ne $cfg -and $null -ne $cfg.servers){
    foreach($s in @($cfg.servers)){
        $dir = [string](Optional $s "path" "")
        $props = if($dir){Join-Path $dir "server.properties"}else{""}
        $serverRows += [ordered]@{
            id=[string]$s.id
            name=[string](Optional $s "name" "")
            role=[string](Optional $s "role" "")
            directory_present=((-not [string]::IsNullOrWhiteSpace($dir)) -and (Test-Path -LiteralPath $dir -PathType Container))
            server_properties_present=((-not [string]::IsNullOrWhiteSpace($props)) -and (Test-Path -LiteralPath $props -PathType Leaf))
            server_properties_sha256=Hash-File $props
            java_port=[int](Optional $s "java_port" 0)
            rcon_port=[int](Optional $s "rcon_port" 0)
            bedrock_profile_port=[int](Optional $s "bedrock_port" 0)
            gds_api_port=[int](Optional $s "gds_api_port" 0)
            auto_start=[bool](Optional $s "auto_start" $false)
            restart_on_crash=[bool](Optional $s "restart_on_crash" $false)
            update_policy=[string](Optional $s "update_policy" "")
            plugins=$(if($dir){Get-Jars (Join-Path $dir "plugins")}else{@()})
        }
    }
}

$proxyRows = @()
foreach($e in @($Expected.network.public)){
    $root = Join-Path $networkRoot ([string]$e.id)
    $plugins = Join-Path $root "plugins"
    $keyCount = @(
        Join-Path $plugins "floodgate\key.pem"
        Join-Path $plugins "floodgate-velocity\key.pem"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Measure-Object | Select-Object -ExpandProperty Count
    $proxyRows += [ordered]@{
        id=[string]$e.id
        root_present=(Test-Path -LiteralPath $root -PathType Container)
        velocity_toml_present=(Test-Path -LiteralPath (Join-Path $root "velocity.toml") -PathType Leaf)
        forwarding_secret_present=(Test-Path -LiteralPath (Join-Path $root "forwarding.secret") -PathType Leaf)
        floodgate_key_present=([int]$keyCount -gt 0)
        java_port=[int]$e.java
        java_listening=(Tcp-Listening ([int]$e.java))
        bedrock_port=[int]$e.bedrock
        bedrock_bound=(Udp-Bound ([int]$e.bedrock))
        jars=Get-Jars $plugins
    }
}

$serverIds = @()
if($null -ne $fleet){ $serverIds=@($fleet.servers | ForEach-Object {[string]$_.server_id} | Where-Object {$_}) }
$backupRows = @()
$backupErrors = @()
foreach($id in $serverIds){
    $active = Get-Json $apiBase ("/api/v4/backups?id="+[uri]::EscapeDataString($id)) 15
    $trash = Get-Json $apiBase ("/api/v4/backups/trash?id="+[uri]::EscapeDataString($id)) 15
    if($null -eq $active -or $null -eq $trash){
        $backupErrors += $id
        $backupRows += [ordered]@{server_id=$id; readable=$false}
        continue
    }
    $activeRows=@($active.backups | Where-Object { $null -ne $_ })
    $trashRows=@($trash.backups | Where-Object { $null -ne $_ })
    $latest=$activeRows | Sort-Object created_at -Descending | Select-Object -First 1
    $backupRows += [ordered]@{
        server_id=$id
        readable=$true
        active_count=$activeRows.Count
        trash_count=$trashRows.Count
        protected_count=@($activeRows | Where-Object {[bool](Read-BackupField $_ "protected" $false)}).Count
        checkpoint_count=@($activeRows | Where-Object {[string](Read-BackupField $_ "kind" "") -eq "checkpoint"}).Count
        golden_count=@(($activeRows+$trashRows) | Where-Object {[string](Read-BackupField $_ "source_reason" "") -match "(?i)golden|day12"}).Count
        latest_active=$(if($null -eq $latest){$null}else{
            [ordered]@{
                file=[string](Read-BackupField $latest "file" "")
                kind=[string](Read-BackupField $latest "kind" "")
                protected=[bool](Read-BackupField $latest "protected" $false)
                source_reason=[string](Read-BackupField $latest "source_reason" "")
                sha256=[string](Read-BackupField $latest "sha256" "")
            }
        })
    }
}

$serviceState = "missing"
try { $serviceState=[string](Get-Service -Name "Geumyi Server Center Host" -ErrorAction Stop).Status } catch {}
$tasks=@()
try{
    if(Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue){
        $tasks=@(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {$_.TaskName -like "Geumyi*"} | ForEach-Object {
            [ordered]@{name=$_.TaskName;state=[string]$_.State}
        })
    }
}catch{}

$freeBytes=[int64]0
try{
    $drive=(Get-Item -LiteralPath $gscRoot -ErrorAction Stop).PSDrive
    $freeBytes=[int64]$drive.Free
}catch{}

$residue=@()
if(Test-Path -LiteralPath $updatesRoot -PathType Container){
    $residue=@(Get-ChildItem -LiteralPath $updatesRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {$_.Name -match "(?i)\.tmp$|\.part$|pending|journal|transaction"} |
        Select-Object -First 200 | ForEach-Object {
            [ordered]@{name=$_.Name;size=[int64]$_.Length;modified=$_.LastWriteTime.ToString("o")}
        })
}

$checks=New-Object 'System.Collections.Generic.List[object]'
Add-Check $checks "gsc_host_4_3_8" ($null -ne $status -and [string](Optional $status "app_version" "") -eq $Expected.gsc) $(if($null -ne $status){"host="+[string](Optional $status "app_version" "")}else{"status unavailable"})
Add-Check $checks "control_api_v1" ($null -ne $info -and [bool](Optional $info "ok" $false) -and [int](Optional $info "api_version" 0) -ge 1 -and [string](Optional $info "gsc_version" "") -eq $Expected.gsc) $(if($null -ne $info){"api="+[string]$info.api_version+" gsc="+[string](Optional $info "gsc_version" "")}else{"info unavailable"})
Add-Check $checks "four_server_snapshot" ($null -ne $snapshot -and @($snapshot.servers).Count -ge 4) $(if($null -ne $snapshot){"servers="+@($snapshot.servers).Count}else{"snapshot unavailable"})
Add-Check $checks "expected_server_ids" (@(@("wild","playground","other","lobby") | Where-Object {$serverIds -notcontains $_}).Count -eq 0) ("fleet="+($serverIds -join ","))
Add-Check $checks "server_directories_present" (@($serverRows | Where-Object {-not [bool]$_.directory_present}).Count -eq 0 -and $serverRows.Count -ge 4) ("profiles="+$serverRows.Count)
Add-Check $checks "backend_ports_match" (@($Expected.network.backend | Where-Object {
    $x=$_
    $row=$serverRows | Where-Object {[string]$_.id -eq [string]$x.id} | Select-Object -First 1
    $null -eq $row -or [int]$row.java_port -ne [int]$x.java -or [int]$row.rcon_port -ne [int]$x.rcon
}).Count -eq 0) "Expected private Paper/RCON ports"
Add-Check $checks "proxy_roots_ready" (@($proxyRows | Where-Object {-not [bool]$_.root_present -or -not [bool]$_.velocity_toml_present -or -not [bool]$_.forwarding_secret_present -or -not [bool]$_.floodgate_key_present}).Count -eq 0) "3 proxy roots/config/identity present"
Add-Check $checks "public_ports_bound" (@($proxyRows | Where-Object {-not [bool]$_.java_listening -or -not [bool]$_.bedrock_bound}).Count -eq 0) "TCP loopback/listener responsiveness 25565-25567 + UDP bound 19132-19134; port owner/public reachability requires live E2E"
$networkRows=if($null -ne $network){@($network.endpoints)}else{@()}
Add-Check $checks "public_entry_api_healthy" ($networkRows.Count -eq 3 -and @($networkRows | Where-Object {-not [bool](Optional $_ "java_responding" $false) -or -not [bool](Optional $_ "bedrock_raknet_pong" $false)}).Count -eq 0) ("entries="+$networkRows.Count)
Add-Check $checks "gsc_service_running" ($serviceState -eq "Running") ("service="+$serviceState)
Add-Check $checks "host_binary_fingerprint" (-not [string]::IsNullOrWhiteSpace((Hash-File $hostExe))) "Host binary SHA-256 captured"
Add-Check $checks "server_config_fingerprint" (-not [string]::IsNullOrWhiteSpace((Hash-File $configPath))) "server.json SHA-256 captured"
Add-Check $checks "backup_inventory_readable" ($serverIds.Count -ge 4 -and $backupErrors.Count -eq 0) ("unreadable="+($backupErrors -join ","))
$unsafe=@()
if($null -ne $fleet){
    $unsafe=@($fleet.servers | Where-Object {
        [bool](Optional $_ "status.block_start" $false) -or [string](Optional $_ "status.phase" "") -in @("blocked","rollback_failed","rolling_back","pending_health","downloading")
    })
}
Add-Check $checks "no_unsafe_update_transaction" ($null -ne $fleet -and $unsafe.Count -eq 0) ("unsafe="+$unsafe.Count)
$activeJobs=if($null -ne $snapshot){[int](Optional $snapshot "active_jobs" -1)}else{-1}
Add-Check $checks "no_active_control_jobs" ($activeJobs -eq 0) ("active_jobs="+$activeJobs)
$healthRows=if($null -ne $health){@($health.servers)}else{@()}
Add-Check $checks "health_no_fail" ($healthRows.Count -ge 4 -and @($healthRows | Where-Object {[string](Optional $_ "overall" "") -eq "fail"}).Count -eq 0) ("health_rows="+$healthRows.Count)
Add-Check $checks "disk_headroom" ($freeBytes -ge 50GB) ("free_gib="+([math]::Round($freeBytes/1GB,2))) $true
Add-Check $checks "local_client_4_3_8_or_not_running" ($null -eq $client -or [string](Optional $client "version" "") -eq $Expected.gsc) $(if($null -eq $client){"local Client endpoint not running; Host capture still valid"}else{"client="+[string](Optional $client "version" "")}) $false

$failedMandatory=@($checks | Where-Object {$_.mandatory -and $_.status -ne "PASS"})
$ready=($failedMandatory.Count -eq 0 -and -not $FixtureRoot)

$report=[ordered]@{
    schema=1
    phase="12.0A"
    tool="Day12 Golden Baseline READ-ONLY"
    mode="READ_ONLY"
    synthetic=$false
    fixture_mode=([bool]$FixtureRoot)
    generated_at=(Get-Date).ToString("o")
    result=$(if($ready){"READY_FOR_GOLDEN_CHECKPOINT"}else{"CHECK_REQUIRED"})
    expected=$Expected
    api_base_used=$apiBase
    versions=[ordered]@{
        host=$(if($null -ne $status){[string](Optional $status "app_version" "")}else{""})
        local_client=$(if($null -ne $client){[string](Optional $client "version" "")}else{""})
        control_api=$(if($null -ne $info){[int](Optional $info "api_version" 0)}else{0})
        verified_release=$(if($null -ne $selfUpdate){[string](Optional $selfUpdate "release" "")}else{""})
        verified_latest=$(if($null -ne $selfUpdate){[string](Optional $selfUpdate "latest" "")}else{""})
        gscm_day11_verified=$Expected.gscm
    }
    fingerprints=[ordered]@{
        host_exe=[ordered]@{present=((-not [string]::IsNullOrWhiteSpace($hostExe)) -and (Test-Path -LiteralPath $hostExe));sha256=Hash-File $hostExe}
        client_exe=[ordered]@{present=((-not [string]::IsNullOrWhiteSpace($clientExe)) -and (Test-Path -LiteralPath $clientExe));sha256=Hash-File $clientExe}
        setup_exe=[ordered]@{present=((-not [string]::IsNullOrWhiteSpace($setupExe)) -and (Test-Path -LiteralPath $setupExe));sha256=Hash-File $setupExe}
        server_json=[ordered]@{present=(Test-Path -LiteralPath $configPath -PathType Leaf);sha256=Hash-File $configPath}
    }
    servers=$serverRows
    proxies=$proxyRows
    public_entry=@($networkRows | ForEach-Object {
        [ordered]@{
            id=[string]$_.id
            java_tcp=[int](Optional $_ "java_tcp" 0)
            java_responding=[bool](Optional $_ "java_responding" $false)
            bedrock_udp=[int](Optional $_ "bedrock_udp" 0)
            bedrock_raknet_pong=[bool](Optional $_ "bedrock_raknet_pong" $false)
        }
    })
    fleet=$(if($null -eq $fleet){$null}else{
        [ordered]@{
            global_enabled=[bool](Optional $fleet "global.enabled" $false)
            global_channel=[string](Optional $fleet "global.channel" "")
            servers=@($fleet.servers | ForEach-Object {
                [ordered]@{
                    server_id=[string]$_.server_id
                    role=[string](Optional $_ "role" "")
                    online=[bool](Optional $_ "online" $false)
                    policy=[string](Optional $_ "policy" "")
                    channel=[string](Optional $_ "channel" "")
                    effective_channel=[string](Optional $_ "effective_channel" "")
                    pin=[string](Optional $_ "pin" "")
                    update_phase=[string](Optional $_ "status.phase" "")
                    block_start=[bool](Optional $_ "status.block_start" $false)
                }
            })
        }
    })
    backups=$backupRows
    service_state=$serviceState
    scheduled_tasks=$tasks
    disk=[ordered]@{free_bytes=$freeBytes;free_gib=[math]::Round($freeBytes/1GB,2)}
    update_residue=$residue
    checks=$checks.ToArray()
    failed_mandatory=@($failedMandatory | ForEach-Object {[string]$_.key})
    ready_for_phase_12_0B=$ready
    redaction=[ordered]@{
        secrets_exported=$false
        full_local_paths_exported=$false
        config_contents_exported=$false
        note="Hashes, logical server IDs, ports, filenames and presence flags only. Secret values and full local paths are omitted."
    }
    mutation=[ordered]@{
        performed=$false
        server_lifecycle=$false
        backup_created=$false
        backup_moved_or_deleted=$false
        config_changed=$false
        firewall_changed=$false
    }
}

$report | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $outPath -Encoding UTF8

Write-Host "============================================================"
Write-Host " Geumyi Minecraft System - DAY 12 PHASE 0A / GOLDEN BASELINE"
Write-Host "============================================================"
Write-Host ("HOST          : "+$report.versions.host)
Write-Host ("CLIENT        : "+$(if($report.versions.local_client){$report.versions.local_client}else{"not running / not required"}))
Write-Host ("FLEET         : "+$serverIds.Count+" profiles")
Write-Host ("PUBLIC ENTRY  : "+$networkRows.Count)
Write-Host ("BACKUP API    : unreadable="+$backupErrors.Count)
Write-Host ("DISK FREE     : "+$report.disk.free_gib+" GiB")
Write-Host ""
foreach($c in $checks.ToArray()){
    Write-Host ("{0,-42} {1}" -f $c.key,$c.status)
}
Write-Host ""
Write-Host ("RESULT        : "+$report.result)
Write-Host ("MUTATION      : false")
Write-Host ("REPORT        : "+$outPath)
Write-Host ""
if($ready){
    Write-Host "12.0A capture is clean. Send this JSON before creating/protecting the Golden checkpoint."
    exit 0
}
Write-Host "12.0A needs review. Do NOT create the Golden checkpoint yet."
exit 2
