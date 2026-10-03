param([Parameter(Mandatory=$true)][string]$StageRoot,[string]$ServerRoot="",[switch]$SelfTest)
$isSelfTest=[bool]$SelfTest
$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "day10_live_helpers.ps1")
. (Join-Path $PSScriptRoot "four_server_port_transaction.ps1")
. (Join-Path $PSScriptRoot "four_cutover_helpers.ps1")
if($isSelfTest){
    foreach($file in @("rollback_four_servers.ps1","validate_four_server_cutover.ps1","four_cutover_helpers.ps1")){
        if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)){throw "Missing: $file"}
    }
    $p=Day10-FourPortMap
    if($p.wild -ne 25570 -or $p.other -ne 25572 -or $p.lobby -ne 25573){throw "Port map regression"}
    Write-Host "DAY10 FOUR-SERVER FINALIZER STATIC SELFTEST PASS (NOT LIVE E2E)"
    exit 0
}
if(-not([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "Administrator required"}
if($ServerRoot -eq ""){$ServerRoot=Join-Path $env:USERPROFILE "OneDrive\Documentos\MC\Server"}
$java=(Get-Command java.exe -ErrorAction Stop).Source
$backup=Join-Path $env:PROGRAMDATA ("GeumyiServerCenter\Backups\Day10-Four-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
$proxyRoot=Join-Path $env:PROGRAMDATA "GeumyiServerCenter\Network\FourServer"
$artifacts=Join-Path $env:TEMP ("Geumyi-Day10-FourCI-"+[guid]::NewGuid().ToString("N"))
$statePath=Join-Path $backup "four-rollback-state.json"
$phase="preflight"
$profiles=@()
$state=$null
$stopped=$false
try{
    & (Join-Path $PSScriptRoot "validate_four_server_cutover.ps1") -StageRoot $StageRoot -ServerRoot $ServerRoot
    $readinessFile=Join-Path $StageRoot "four-server-readiness.json"
    if(-not(Test-Path -LiteralPath $readinessFile -PathType Leaf)){throw "Readiness report was not generated"}
    $readinessResult=Get-Content -LiteralPath $readinessFile -Raw | ConvertFrom-Json
    if(-not [bool]$readinessResult.staging_and_first_deploy_preflight_pass){
        throw ("Read-only cutover preflight blocked: "+(@($readinessResult.errors) -join "; "))
    }
    if(Test-Path -LiteralPath $proxyRoot){throw "Proxy root already exists; first-time deployment only"}
    foreach($id in @("wild","playground","other")){
        if(Get-ScheduledTask -TaskName ("Geumyi Day10 Velocity "+$id) -ErrorAction SilentlyContinue){
            throw "An existing Day10 Velocity startup task needs reconciliation"
        }
    }
    foreach($rule in @("Geumyi Day10 Velocity Java","Geumyi Day10 Geyser UDP")){
        if(Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue){
            throw "Existing Day10 firewall rule needs reconciliation: $rule"
        }
    }
    # Check whether the installed GSC contains the new Day 10 APIs. The exact
    # current-main setup is already downloaded/verified below, but no install
    # occurs until DEPLOY FOUR is explicitly confirmed.
    $gscNeedsUpgrade=$false
    try {
        $versionGate=Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8787/api/v4/network/entry-status" -TimeoutSec 8
        if($versionGate.StatusCode -ne 200){$gscNeedsUpgrade=$true}
    } catch {
        $gscNeedsUpgrade=$true
    }
    $ci=Day10-FourGetArtifacts $artifacts "geumyi22/Geumyi-Minecraft-System"
    $settings=Day10-Gsc "GET" "/api/settings"
    $entries=@(
      @{id="wild";name="야생";port=25570;udp=19132},
      @{id="playground";name="놀이터";port=25571;udp=19133},
      @{id="other";name="기타";port=25572;udp=19134}
    )
    $udpMap=@($entries | ForEach-Object {[int]$_.udp})
    if(($udpMap | Sort-Object -Unique).Count -ne 3 -or ($udpMap -join ",") -ne "19132,19133,19134"){
        throw "Bedrock public port map regression"
    }
    foreach($e in $entries){
        $original=@($settings.servers | Where-Object {$_.id -eq $e.id}) | Select-Object -First 1
        if($null -eq $original){throw "Missing GSC profile: $($e.id)"}
        $dir=Join-Path $ServerRoot $e.name
        $null=Day10-GetViaBaseline $dir
        $st=Day10-State $e.id
        if($null -eq $st -or $null -eq $st.minecraft){throw "GSC status unavailable: $($e.id)"}
        if([int]$st.minecraft.online -gt 0){throw "Players online in $($e.id)"}
        $profiles += [ordered]@{
            id=$e.id;path=$dir;port=$e.port;udp=$e.udp;was_online=[bool]$st.online
            profile=(Day10-ProfileFromSettings $original ([int]$original.java_port) ([int]$original.bedrock_port) ([bool]$original.auto_start))
        }
    }
    $existingGds=@($settings.servers | ForEach-Object {[int]$_.gds_api_port})
    $lobbyGds=0
    foreach($port in @(8768,8769,8770,8771,8772,8773)){
        if($port -notin $existingGds -and -not(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)){$lobbyGds=$port;break}
    }
    if($lobbyGds -eq 0){throw "No free lobby GDS port"}
    Day10-FourCheckBackupSpace ($profiles | ForEach-Object {$_.path}) $backup
    Write-Host "Four-server cutover: Java 25565/66/67; Bedrock 19132/33/34; Lobby first."
    Write-Host "Existing three servers will stop for FULL offline backups. Backup: $backup"
    if($gscNeedsUpgrade){Write-Host "The installed GSC is older than today's Day10 API build and will be upgraded first."}
    if((Read-Host "Type DEPLOY FOUR to continue") -cne "DEPLOY FOUR"){throw "Cancelled before modifications"}
    if($gscNeedsUpgrade){
        $gscConfig=Join-Path $env:PROGRAMDATA "GeumyiServerCenter\server.json"
        $gscPreBackup=Join-Path $StageRoot "gsc-server-before-live-cutover.json"
        if(Test-Path -LiteralPath $gscConfig -PathType Leaf){
            Copy-Item -LiteralPath $gscConfig -Destination $gscPreBackup -Force -ErrorAction Stop
        }
        Write-Host "Updating GSC from SHA-verified current-main CI package before stopping Minecraft servers..."
        $setup=Start-Process -FilePath $ci.Setup -PassThru
        if(-not $setup.WaitForExit(900000)){throw "GSC Setup timeout. Minecraft servers were not stopped."}
        if($setup.ExitCode -ne 0){throw "GSC Setup failed with exit code $($setup.ExitCode). Minecraft servers were not stopped."}
        Day10-WaitGsc 120 | Out-Null
        try {
            $newGate=Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8787/api/v4/network/entry-status" -TimeoutSec 8
            if($newGate.StatusCode -ne 200){throw "unexpected HTTP status"}
        } catch {
            throw "Updated GSC still lacks the Day10 network API. Minecraft servers were not stopped."
        }
        $afterSettings=Day10-Gsc "GET" "/api/settings"
        foreach($p in $profiles){
            $after=@($afterSettings.servers | Where-Object {$_.id -eq $p.id}) | Select-Object -First 1
            if($null -eq $after -or [string]$after.path -ne [string]$p.path -or
               [int]$after.java_port -ne [int]$p.profile.java_port -or
               [int]$after.rcon_port -ne [int]$p.profile.rcon_port){
                throw "GSC upgrade changed the existing $($p.id) profile. Minecraft servers were not stopped."
            }
        }
    }
    foreach($p in $profiles){
        if($p.was_online){
            Day10-Gsc "POST" "/api/server/action" @{id=$p.id;action="stop"} | Out-Null
            Day10-WaitOnline $p.id $false 180 | Out-Null
        }
    }
    $stopped=$true
    foreach($port in @(25565,25566,25567)){
        if(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue){
            throw "Original Java port still listening after graceful shutdown: $port"
        }
    }
    foreach($port in @(19132,19133,19134)){
        if(Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue){
            throw "Public Bedrock UDP port still occupied after graceful shutdown: $port"
        }
    }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach($p in $profiles){Day10-FourBackupServer $p.path (Join-Path $backup ("servers\"+$p.id))}
    $state=[ordered]@{
        schema=1;created=(Get-Date).ToString("o");ci_main_sha=$ci.Commit;ci_run=$ci.Run
        server_root=$ServerRoot;lobby_path=(Join-Path $ServerRoot "로비")
        proxy_install_root=$proxyRoot;proxy_pids=@();servers=$profiles
    }
    Day10-FourSaveState $statePath $state
    $phase="backed_up"
    New-Item -ItemType Directory -Path $proxyRoot -Force | Out-Null
    foreach($e in $entries){
        Copy-Item -LiteralPath (Join-Path $StageRoot ("proxy\"+$e.id)) -Destination (Join-Path $proxyRoot $e.id) -Recurse -Force -ErrorAction Stop
    }
    $bedrock=Join-Path $StageRoot "bedrock-dependencies"
    Day10-FourCreateLobby $state.lobby_path $profiles[0].path $artifacts $bedrock $lobbyGds
    $paths=[ordered]@{wild=$profiles[0].path;playground=$profiles[1].path;other=$profiles[2].path;lobby=$state.lobby_path}
    foreach($p in $profiles){
        Day10-InstallViaIfMissing $p.path (Join-Path $bedrock "backend-plugins\ViaVersion-5.12.0.jar") (Join-Path $bedrock "backend-plugins\ViaBackwards-5.12.0.jar")
        Day10-CopyArtifactJar (Join-Path $artifacts "network-0.1.0") (Join-Path $p.path "plugins\GeumyiNetwork-0.1.0.jar")
        Day10-WriteNetworkConfig $p.path $p.id
        Day10-DisableBackendProxyPlugins $p.path
        Day10-SetSpigotBungeeFalse (Join-Path $p.path "spigot.yml")
        $private=Day10-ProfileFromSettings $p.profile $p.port 0 $false
        $private.update_policy="hold"
        Day10-Gsc "POST" "/api/v4/server-profile" @{action="update";server=$private} | Out-Null
    }
    Day10-ApplyFourConfig $paths (Join-Path $backup "port-transaction") (Join-Path $proxyRoot "wild\forwarding.secret")
    $lobby=@{
        id="lobby";name="Geumyi Lobby";role="lobby";update_policy="manual";java_port=25573
        rcon_port=25579;bedrock_port=0;gds_api_port=$lobbyGds;path=$state.lobby_path
        path_file="";start_command="start.bat";auto_start=$false;restart_on_crash=$false
    }
    Day10-Gsc "POST" "/api/v4/server-profile" @{action="add";server=$lobby} | Out-Null
    $privateSettings=Day10-Gsc "GET" "/api/settings"
    foreach($id in @("wild","playground","other","lobby")){
        $check=@($privateSettings.servers | Where-Object {$_.id -eq $id}) | Select-Object -First 1
        if($null -eq $check -or [int]$check.bedrock_port -ne 0){
            throw "Backend GSC bedrock_port must be 0 during proxy cutover: $id"
        }
    }
    foreach($id in @("lobby","wild","playground","other")){
        Day10-Gsc "POST" "/api/server/action" @{id=$id;action="start"} | Out-Null
        Day10-WaitOnline $id $true 300 | Out-Null
    }
    $shared=""
    foreach($e in $entries){
        $dir=Join-Path $proxyRoot $e.id
        $key=Day10-FourBootstrapProxy $dir $java $e.udp $shared $state $statePath
        if($shared -eq ""){$shared=$key}
    }
    Day10-FourProtectProxySecrets $proxyRoot
    foreach($e in $entries){
        $dir=Join-Path $proxyRoot $e.id
        $proc=Start-Process -FilePath $java -ArgumentList @("-Xms256M","-Xmx512M","-jar",(Join-Path $dir "velocity.jar")) -WorkingDirectory $dir -PassThru
        Day10-FourTrackProcess $statePath $state $proc.Id
    }
    Day10-FourCheckPorts
    New-NetFirewallRule -DisplayName "Geumyi Day10 Velocity Java" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 25565,25566,25567 | Out-Null
    New-NetFirewallRule -DisplayName "Geumyi Day10 Geyser UDP" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 19132,19133,19134 | Out-Null
    foreach($p in $profiles){
        $route=Invoke-RestMethod -Uri ("http://127.0.0.1:8787/api/v4/network/server-state?id="+$p.id) -TimeoutSec 10
        if(-not [bool]$route.move_allowed){throw "GSC blocked $($p.id) movement"}
    }
    Write-Host "JAVA TEST: join public TCP 25565,25566,25567. Each enters Lobby. Try all 3 destinations, /lobby and last position restoration."
    if((Read-Host "Type JAVA PASS after ALL Java checks") -cne "JAVA PASS"){throw "Java E2E not confirmed"}
    Write-Host "BEDROCK TEST: join UDP 19132,19133,19134. Each enters Lobby. Try all 3 destinations and /lobby."
    if((Read-Host "Type BEDROCK PASS after ALL Bedrock checks") -cne "BEDROCK PASS"){throw "Bedrock E2E not confirmed"}
    foreach($p in $profiles){
        $final=Day10-ProfileFromSettings $p.profile $p.port 0 ([bool]$p.profile.auto_start)
        Day10-Gsc "POST" "/api/v4/server-profile" @{action="update";server=$final} | Out-Null
        if(-not $p.was_online){
            Day10-Gsc "POST" "/api/server/action" @{id=$p.id;action="stop"} | Out-Null
            Day10-WaitOnline $p.id $false 180 | Out-Null
        }
    }
        # Install three durable startup tasks only after both Java and Bedrock tests.
    foreach($e in $entries){
        $name="Geumyi Day10 Velocity "+$e.id
        if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){throw "Unexpected scheduled task already exists: $name"}
        $workDir=Join-Path $proxyRoot $e.id
        $action=New-ScheduledTaskAction -Execute $java -Argument "-Xms256M -Xmx512M -jar velocity.jar" -WorkingDirectory $workDir
        $trigger=New-ScheduledTaskTrigger -AtStartup
        $principal=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $taskSettings=New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $taskSettings -ErrorAction Stop | Out-Null
    }
    $lobby.auto_start=$true
    $lobby.restart_on_crash=$true
    Day10-Gsc "POST" "/api/v4/server-profile" @{action="update";server=$lobby} | Out-Null
    $result=[ordered]@{
        main_sha=$ci.Commit;ci_run=$ci.Run;java_manual_e2e="PASS";bedrock_manual_e2e="PASS"
        backup=$backup;proxy_root=$proxyRoot;rollback_rehearsal="NOT EXECUTED"
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backup "four-server-result.json") -Encoding UTF8
    $phase="verified"
    Write-Host "JAVA/BEDROCK MANUAL E2E REPORTED PASS; backup retained: $backup"
}catch{
    Write-Host ("Cutover stopped in "+$phase+": "+$_.Exception.Message)
    if($null -ne $state -and (Test-Path -LiteralPath $statePath -PathType Leaf) -and $phase -ne "verified"){
        try{
            & (Join-Path $PSScriptRoot "rollback_four_servers.ps1") -BackupRoot $backup
            Day10-FourRequireSuccess "Four-server rollback"
        }catch{Write-Host ("CRITICAL ROLLBACK BLOCKED: "+$_.Exception.Message)}
    }elseif($stopped){
        Write-Host "Full backup was incomplete; no port changes should have started."
        foreach($p in $profiles){
            if($p.was_online){try{Day10-Gsc "POST" "/api/server/action" @{id=$p.id;action="start"} | Out-Null}catch{}}
        }
    }
    exit 1
}
