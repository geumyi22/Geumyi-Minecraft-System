[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PaperZip,[Parameter(Mandatory=$true)][string]$HostExe,[switch]$ExerciseCrashRecovery)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# Only executed by GitHub-hosted disposable Windows runner. Not user's PC.
# Uses process-level invalid HTTPS proxy for GSC update source, not a real NIC outage.
if($env:GITHUB_ACTIONS -ne "true" -or $env:GEUMYI_DAY12_DISPOSABLE_ONLY -ne "yes"){
  throw "REFUSE_NON_DISPOSABLE_RUNNER"
}
$root=Join-Path $env:RUNNER_TEMP "Geumyi-Day12-CI-Paper-Offlining"
$paperDir=Join-Path $root "paper-stage"
New-Item -ItemType Directory -Force -Path $paperDir|Out-Null
$reportPath=Join-Path $env:RUNNER_TEMP "Day12-GSC-Paper-Disposable-Offline-Source.json"
if(Test-Path -LiteralPath $reportPath){throw "REFUSE_REPORT_OVERWRITE"}
$report=[ordered]@{
  schema=1;phase="12.7-ci-disposable-actual-gsc-paper-start"
  synthetic=$false;real_disposable_ci_execution=$true;actual_operator_server_pc=$false
  offline_mode="GSC_CHILD_PROCESS_HTTPS_PROXY_REFUSES_UPDATE_SOURCE_ONLY"
  official_paper_release_sha_verified=$false;unique_paper_jar=$false
  real_paper_initial_online_boot=$false;initial_graceful_stop=$false
  real_disposable_gsc_host_started=$false;gsc_start_accepted=$false
  updater_network_failure_observed=$false;real_paper_restarted_despite_update_outage=$false
  original_paper_jar_unchanged=$false;user_world_or_golden_changed=$false
  user_host_firewall_or_adapter_changed=$false
  offline_operator_server_boot_verified=$false
  crash_recovery_requested=([bool]$ExerciseCrashRecovery)
  disposable_paper_process_exactly_identified=$false
  disposable_paper_unexpected_termination_executed=$false
  real_gsc_state_recovering_observed=$false
  real_paper_watchdog_recovery_observed=$false
  recovered_disposable_paper_new_pid_observed=$false
  backend_ports_private="UNCHANGED_FAIL";stable_release_allowed=$false
  result="NOT_RUN"
}
$first=$null;$gsc=$null
function Connected([int]$p){
  $c=[Net.Sockets.TcpClient]::new()
  try{$ar=$c.BeginConnect("127.0.0.1",$p,$null,$null)
      if(-not $ar.AsyncWaitHandle.WaitOne(450)){return $false}
      $c.EndConnect($ar);return $true
  }catch{return $false}finally{$c.Close()}
}
function WaitPort([int]$p,[int]$secs,[object]$process){
  $until=(Get-Date).AddSeconds($secs)
  while((Get-Date) -lt $until){
    if($process.HasExited){return $false}
    if(Connected $p){return $true}
    Start-Sleep -Milliseconds 500
  }
  return $false
}
# CI-only: the TCP listener can open before Paper finishes the first world boot.
# The earliest stop command can race console-command context creation on Paper 26.3.
# Require the observable Done marker and then a short stable listening interval.
function WaitPaperWorldReady([object]$Process,[string]$LogPath,[int]$Secs) {
  $until=(Get-Date).AddSeconds($Secs)
  $doneSeen=$null
  while((Get-Date) -lt $until) {
    if($Process.HasExited){return $false}
    if(Test-Path -LiteralPath $LogPath -PathType Leaf) {
      try {
        $tail=(Get-Content -LiteralPath $LogPath -Tail 50 -ErrorAction Stop) -join "`n"
        if($tail -match 'Done \\([0-9.]+s\\)! For help, type "help"') {
          if($null -eq $doneSeen){$doneSeen=Get-Date}
          if(((Get-Date)-$doneSeen).TotalSeconds -ge 6 -and (Connected 25789)) {return $true}
        }
      }catch{}
    }
    Start-Sleep -Milliseconds 600
  }
  return $false
}
function SafeWrite{
  $report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $reportPath -Encoding UTF8
  Write-Host ("Disposable result: "+$report.result)
  Write-Host ("Sanitized report: "+$reportPath)
}
try{
  $zipHash=(Get-FileHash -LiteralPath $PaperZip -Algorithm SHA256).Hash.ToLowerInvariant()
  if($zipHash -ne "6198ad133c37667a4a0a92567f204c4c24e5f265864f8dd19605407c6e3ced4b"){
    throw "OFFICIAL_PAPER_ZIP_SHA_MISMATCH"
  }
  $report.official_paper_release_sha_verified=$true
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path $PaperZip).Path)
  try{
    $jars=@($zip.Entries|Where-Object{
      $_.FullName.Replace('\','/') -match '(?i)(?:^|/)paper(?:-[^/]+)?\.jar$' -and
      $_.Length -gt 20000000 -and $_.Length -lt 130000000
    })
    if($jars.Count -ne 1){throw "NOT_ONE_PAPER_JAR_IN_RELEASE"}
    [IO.Compression.ZipFileExtensions]::ExtractToFile($jars[0],(Join-Path $paperDir "paper.jar"),$false)
  }finally{$zip.Dispose()}
  $report.unique_paper_jar=$true
  $before=(Get-FileHash -LiteralPath (Join-Path $paperDir "paper.jar") -Algorithm SHA256).Hash
  [IO.File]::WriteAllText((Join-Path $paperDir "eula.txt"),"eula=true"+[Environment]::NewLine)
  @(
    "server-ip=127.0.0.1","server-port=25789","online-mode=false",
    "enforce-secure-profile=false","enable-rcon=false","enable-query=false",
    "max-players=1","view-distance=3","simulation-distance=3",
    "level-name=day12_disposable_world","accepts-transfers=false",
    "use-native-transport=false"
  )|Set-Content -LiteralPath (Join-Path $paperDir "server.properties") -Encoding Ascii
  [IO.File]::WriteAllText((Join-Path $paperDir "start.bat"),(
    "@echo off"+[Environment]::NewLine+
    '"%JAVA_HOME%\bin\java.exe" -Xms512M -Xmx1536M -jar paper.jar nogui'+[Environment]::NewLine))
  $javaExe=Join-Path $env:JAVA_HOME "bin\java.exe"
  if(-not(Test-Path -LiteralPath $javaExe)){throw "JAVA_25_NOT_INSTALLED"}
  # First ever Paper 26.3 boot is online on the disposable runner to prepare
  # upstream vanilla components. No production Minecraft files are loaded.
  $first=[Diagnostics.Process]::new()
  $first.StartInfo.FileName=$javaExe
  $first.StartInfo.Arguments="-Xms512M -Xmx1536M -jar paper.jar nogui"
  $first.StartInfo.WorkingDirectory=$paperDir
  $first.StartInfo.UseShellExecute=$false
  $first.StartInfo.RedirectStandardInput=$true
  if(-not $first.Start()){throw "INITIAL_JAVA_PROCESS_FAILED"}
  if(-not(WaitPort 25789 240 $first)){throw "INITIAL_PAPER_NOT_READY"}
  if(-not(WaitPaperWorldReady $first (Join-Path $paperDir "logs\\latest.log") 100)){
    throw "INITIAL_PAPER_WORLD_READY_NOT_CONFIRMED"
  }
  $report.real_paper_initial_online_boot=$true
  $first.StandardInput.WriteLine("stop")
  $first.StandardInput.Flush()
  if(-not $first.WaitForExit(15000)){
    # Exactly one additional graceful request is allowed after a Paper console race;
    # never force-kill in normal initial-prewarm success logic.
    $first.StandardInput.WriteLine("stop")
    $first.StandardInput.Flush()
    if(-not $first.WaitForExit(60000)){throw "INITIAL_PAPER_NOT_GRACEFULLY_STOPPED"}
  }
  if($first.ExitCode -ne 0){throw "INITIAL_PAPER_NONZERO_EXIT"}
  $firstLog=Get-Content -LiteralPath (Join-Path $paperDir "logs\\latest.log") -Raw -ErrorAction Stop
  if($firstLog -notmatch '(?i)Stopping server'){throw "INITIAL_PAPER_GRACEFUL_STOP_LOG_MISSING"}
  $report.initial_graceful_stop=$true
  $first.Dispose();$first=$null
  if(Connected 25789){throw "PAPER_PREWARM_STILL_LISTENING"}
  $public=Join-Path $root "disposable-ed25519-public.pem"
  @("-----BEGIN PUBLIC KEY-----",
    "MCowBQYDK2VwAyEAZzf5PPqCD5/ZpsNIYUh9cV8lpE2r6ziV9sTbHrc+TDA=",
    "-----END PUBLIC KEY-----")|Set-Content -LiteralPath $public -Encoding Ascii
  $config=[ordered]@{
    port=28987;bind="127.0.0.1";api_token="ci-only-not-live"
    allow_loopback_no_auth=$true;mobile_enabled=$false;auto_start_agent=$false
    update=[ordered]@{
      enabled=$true;repository="geumyi22/Geumyi-Minecraft-System"
      channel="beta";public_key_path=$public;timeout_seconds=3}
    servers=@([ordered]@{
      id="stage-playground";name="Disposable Playground";role="playground"
      update_policy="managed";java_port=25789;rcon_port=25790
      bedrock_port=19188;gds_api_port=28788;path=$paperDir
      start_command="start.bat";auto_start=$false;restart_on_crash=([bool]$ExerciseCrashRecovery)})
  }
  $configFile=Join-Path $root "ci-only-config.json"
  $config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configFile -Encoding UTF8
  if(-not(Test-Path -LiteralPath $HostExe)){throw "BUILT_GSC_HOST_BINARY_MISSING"}
  $oldProxy=$env:HTTPS_PROXY;$oldNoProxy=$env:NO_PROXY
  $env:HTTPS_PROXY="http://127.0.0.1:1"
  $env:NO_PROXY="localhost,127.0.0.1"
  try{
    $gsc=Start-Process -FilePath $HostExe -PassThru -WindowStyle Hidden -ArgumentList @(
      "--config",('"' + $configFile + '"')
    ) -RedirectStandardOutput (Join-Path $root "host-out.log") -RedirectStandardError (Join-Path $root "host-err.log")
  }finally{
    $env:HTTPS_PROXY=$oldProxy;$env:NO_PROXY=$oldNoProxy
  }
  if(-not(WaitPort 28987 45 $gsc)){throw "GSC_HOST_NOT_RESPONDING"}
  $h=Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:28987/api/health" -TimeoutSec 7 -NoProxy
  if(-not $h.ok -or [string]$h.version -ne "4.3.8"){throw "GSC_HEALTH_WRONG_VERSION"}
  $report.real_disposable_gsc_host_started=$true
  $r=Invoke-WebRequest -Method POST -Uri "http://127.0.0.1:28987/api/server/action" -Body '{"id":"stage-playground","action":"start"}' -ContentType "application/json" -TimeoutSec 8 -NoProxy
  if([int]$r.StatusCode -ne 202){throw "DISPOSABLE_GSC_START_NOT_ACCEPTED"}
  $report.gsc_start_accepted=$true
  $end=(Get-Date).AddSeconds(230)
  while((Get-Date) -lt $end){
    try{
      $status=Invoke-RestMethod -Method GET -Uri "http://127.0.0.1:28987/api/v4/update/status?id=stage-playground" -TimeoutSec 5 -NoProxy
      if([string]$status.phase -eq "error" -and
         [string]$status.error -match '(?i)(proxy|connect|github|network|refused)'){
        $report.updater_network_failure_observed=$true
      }
    }catch{}
    if(Connected 25789){$report.real_paper_restarted_despite_update_outage=$true}
    if($report.updater_network_failure_observed -and $report.real_paper_restarted_despite_update_outage){break}
    if($gsc.HasExited){break}
    Start-Sleep -Milliseconds 900
  }
  $after=(Get-FileHash -LiteralPath (Join-Path $paperDir "paper.jar") -Algorithm SHA256).Hash
  $report.original_paper_jar_unchanged=($before -eq $after)
  if(-not $report.updater_network_failure_observed){throw "UPDATE_NETWORK_FAILURE_UNPROVEN"}
  if(-not $report.real_paper_restarted_despite_update_outage){throw "PAPER_FAILED_TO_BOOT_AFTER_GSC_PROXY_OUTAGE"}
  if(-not $report.original_paper_jar_unchanged){throw "ORIGINAL_PAPER_CHANGED"}
  if($ExerciseCrashRecovery){
    # Exact disposable Windows listener, owner process and Java 25 executable required.
    $listener=@(Get-NetTCPConnection -LocalPort 25789 -State Listen -ErrorAction Stop | Where-Object{$_.LocalAddress -eq "127.0.0.1"})
    $owners=@($listener | ForEach-Object{[int]$_.OwningProcess} | Sort-Object -Unique)
    if($owners.Count -ne 1 -or $owners[0] -le 0){throw "DISPOSABLE_PAPER_OWNER_UNPROVEN"}
    $pidToStop=[int]$owners[0]
    $proc=Get-CimInstance Win32_Process -Filter "ProcessId = $pidToStop" -ErrorAction Stop
    if($null -eq $proc -or [string]$proc.ExecutablePath -ne [string]$javaExe -or
       [string]$proc.CommandLine -notmatch '(?i)-jar\s+paper\.jar(?:\s|$)'){
      throw "DISPOSABLE_PAPER_PID_IDENTITY_UNVERIFIED"
    }
    $report.disposable_paper_process_exactly_identified=$true
    Stop-Process -Id $pidToStop -Force -ErrorAction Stop
    $report.disposable_paper_unexpected_termination_executed=$true
    $downBy=(Get-Date).AddSeconds(30)
    while((Get-Date) -lt $downBy){
      if(-not(Connected 25789)){break}
      Start-Sleep -Milliseconds 250
    }
    if(Connected 25789){throw "DISPOSABLE_PAPER_DID_NOT_DROP"}
    $recoverDeadline=(Get-Date).AddSeconds(35)
    while((Get-Date) -lt $recoverDeadline){
      try{
        $v=Invoke-RestMethod -Method GET -Uri "http://127.0.0.1:28987/api/v1/servers/stage-playground" -TimeoutSec 7 -NoProxy
        if([string]$v.state -eq "RECOVERING"){$report.real_gsc_state_recovering_observed=$true;break}
      }catch{}
      if(Connected 25789){break}
      Start-Sleep -Milliseconds 350
    }
    if(-not $report.real_gsc_state_recovering_observed){throw "GSC_RECOVERING_STATE_NOT_OBSERVED"}
    $upBy=(Get-Date).AddSeconds(170)
    while((Get-Date) -lt $upBy){
      if($gsc.HasExited){throw "GSC_HOST_EXITED_DURING_RECOVERY"}
      if(Connected 25789){
        $listen2=@(Get-NetTCPConnection -LocalPort 25789 -State Listen -ErrorAction SilentlyContinue |
          Where-Object{$_.LocalAddress -eq "127.0.0.1"})
        $owners2=@($listen2|ForEach-Object{[int]$_.OwningProcess}|Sort-Object -Unique)
        if($owners2.Count -eq 1 -and $owners2[0] -ne $pidToStop){
          $p2=Get-CimInstance Win32_Process -Filter "ProcessId = $($owners2[0])" -ErrorAction SilentlyContinue
          if($null -ne $p2 -and [string]$p2.ExecutablePath -eq [string]$javaExe -and
             [string]$p2.CommandLine -match '(?i)-jar\s+paper\.jar(?:\s|$)'){
            $report.recovered_disposable_paper_new_pid_observed=$true
            $report.real_paper_watchdog_recovery_observed=$true
            break
          }
        }
      }
      Start-Sleep -Milliseconds 750
    }
    if(-not $report.real_paper_watchdog_recovery_observed){throw "GSC_WATCHDOG_REAL_PAPER_RESTART_UNPROVEN"}
    $report.result="DISPOSABLE_REAL_GSC_PAPER_CRASH_RECOVERY_PASS"
  }else{
    $report.result="DISPOSABLE_REAL_GSC_PAPER_PROCESS_SCOPED_OFFLINE_SOURCE_PASS"
  }
}catch{
  $report.result="DISPOSABLE_TEST_FAILED_OR_INCONCLUSIVE"
  $report.failure_reason_code=($_.Exception.Message -replace '[^A-Za-z0-9_-]','_')
  Write-Warning ("Disposable CI test incomplete: "+$report.failure_reason_code)
}finally{
  if($null -ne $first){
    try{$first.StandardInput.WriteLine("stop");$first.WaitForExit(20000)|Out-Null}catch{}
    if(-not $first.HasExited){try{$first.Kill()}catch{}}
  }
  if($null -ne $gsc -and -not $gsc.HasExited){
    # Only our own disposable CI process is a permitted termination target.
    try{Stop-Process -Id $gsc.Id -Force -ErrorAction SilentlyContinue}catch{}
  }
  SafeWrite
}
if($ExerciseCrashRecovery){
  if($report.result -ne "DISPOSABLE_REAL_GSC_PAPER_CRASH_RECOVERY_PASS"){exit 2}
}else{
  if($report.result -ne "DISPOSABLE_REAL_GSC_PAPER_PROCESS_SCOPED_OFFLINE_SOURCE_PASS"){exit 2}
}
exit 0
