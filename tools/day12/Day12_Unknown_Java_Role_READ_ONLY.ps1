[CmdletBinding()]
param([switch]$Synthetic,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Narrow follow-up to actual 2026-10-11 00:29 report:
# 6 recognized Velocity JVMs + 3 recognized Paper JVMs + 1 unknown JVM.
# READ ONLY: Win32_Process query + optional localhost GSC snapshot GET.
# NEVER exports command lines, PIDs, paths, token, usernames or IPs.
function Get-LauncherRole([string]$CommandLine) {
  if([string]::IsNullOrWhiteSpace($CommandLine)){return "COMMAND_UNREADABLE"}
  $matchesJar=[regex]::Matches($CommandLine,'(?i)(?:^|\s)-jar\s+(?:"([^"\r\n]+)"|([^\s"]+))(?=\s|$)')
  if($matchesJar.Count -ne 1){
    if($matchesJar.Count -gt 1){return "MULTIPLE_JAR_ARGS"}
    return "NO_JAR_ARG"
  }
  $arg=if($matchesJar[0].Groups[1].Success){$matchesJar[0].Groups[1].Value}else{$matchesJar[0].Groups[2].Value}
  # Process environment is Windows; allow either path separator without leaking it.
  $file=([string]$arg -replace '^.*[\\/]','')
  if($file -ieq "velocity.jar"){return "VELOCITY"}
  if($file -match '(?i)^paper(?:[-.][a-z0-9._-]+)?\.jar$'){return "PAPER"}
  if($file -match '(?i)^GeumyiStatusAgent(?:[-.][a-z0-9._-]+)?\.jar$'){return "STATUS_AGENT"}
  if($file -match '(?i)^(?:purpur|spigot|fabric-server|minecraft_server|server)(?:[-.][a-z0-9._-]+)?\.jar$'){return "OTHER_SERVER_JAR"}
  return "UNKNOWN_JAR"
}
function Measure-Unknown([object[]]$JavaRows,[object[]]$SnapshotServers,[string]$SnapshotStatus){
  $roles=@($JavaRows | ForEach-Object {Get-LauncherRole ([string]$_.command_line)})
  $vel=@($roles|Where-Object{$_ -eq "VELOCITY"}).Count
  $paper=@($roles|Where-Object{$_ -eq "PAPER"}).Count
  $agent=@($roles|Where-Object{$_ -eq "STATUS_AGENT"}).Count
  $other=@($roles|Where-Object{$_ -notin @("VELOCITY","PAPER","STATUS_AGENT")})
  $apiValid=($SnapshotStatus -eq "CAPTURED" -and @($SnapshotServers).Count -eq 4)
  $on=0;$off=0;$bad=0
  if($apiValid){
    $ids=@()
    foreach($s in @($SnapshotServers)){
      $id=[string]$s.id
      if($id -notin @("wild","playground","other","lobby") -or $ids -contains $id){$bad++;continue}
      $ids+= $id
      # Both state and online are present in GSC Control API v1:
      if($null -eq $s.PSObject.Properties["online"]){$bad++;continue}
      if([bool]$s.online){$on++}else{$off++}
    }
    $apiValid=($bad -eq 0 -and $ids.Count -eq 4)
  }
  $resolved=($vel -eq 6 -and $other.Count -eq 0 -and $agent -le 1 -and $apiValid -and $paper -eq $on -and $on+$off -eq 4)
  $rolesOther=@($other|Sort-Object -Unique)
  return [ordered]@{
    result=if($resolved){"PASS_SCOPED_ROLE_RECONCILIATION"}else{"REVIEW_REQUIRED"}
    java_total=[int]$roles.Count
    velocity_count=[int]$vel
    paper_count=[int]$paper
    status_agent_count=[int]$agent
    unclassified_java_count=[int]$other.Count
    unclassified_java_categories=@($rolesOther)
    gsc_snapshot_status=$SnapshotStatus
    gsc_snapshot_four_known_unique_ids=[bool]$apiValid
    gsc_servers_online=if($apiValid){[int]$on}else{$null}
    gsc_servers_offline=if($apiValid){[int]$off}else{$null}
    consistency_rule="4 configured GSC servers; recognized Paper JVM count must equal snapshot ONLINE count; Velocity 6 expected; <=1 StatusAgent; no unknown Java. Earlier 3-pair UDP/process proof reused only as earlier dated evidence."
    risk="Process naming and GSC snapshot are corroborating evidence, not process working-directory/PID-to-Minecraft-server attestation and not Day12.10 OS kernel bind proof."
  }
}

if($Synthetic){
  $rows=@()
  for($i=0;$i -lt 6;$i++){$rows+= [pscustomobject]@{command_line='java -jar velocity.jar'}}
  for($i=0;$i -lt 3;$i++){$rows+= [pscustomobject]@{command_line='java -jar paper.jar'}}
  $rows+= [pscustomobject]@{command_line='java -Xmx256M -jar "C:\GSC\Agent\GeumyiStatusAgent-0.5.4.jar"'}
  $statuses=@(
    [pscustomobject]@{id="wild";online=$true},
    [pscustomobject]@{id="playground";online=$true},
    [pscustomobject]@{id="other";online=$false},
    [pscustomobject]@{id="lobby";online=$true}
  )
  $positive=Measure-Unknown $rows $statuses "CAPTURED"
  if($positive.result -ne "PASS_SCOPED_ROLE_RECONCILIATION" -or $positive.status_agent_count -ne 1){throw "EXPECTED_AGENT_FIXTURE_REJECTED"}
  $four=@($statuses|ForEach-Object{[pscustomobject]@{id=$_.id;online=$true}})
  $mismatch=Measure-Unknown $rows $four "CAPTURED"
  if($mismatch.result -ne "REVIEW_REQUIRED"){throw "MISSING_ONLINE_PAPER_ACCEPTED"}
  $unauthorized=Measure-Unknown $rows $statuses "UNAUTHORIZED"
  if($unauthorized.result -ne "REVIEW_REQUIRED"){throw "API_AUTH_FAILURE_ACCEPTED"}
  $bad=@($rows | ForEach-Object {$_})
  $bad[-1]=[pscustomobject]@{command_line='java -jar C:\unrelated\unknown.jar'}
  if((Measure-Unknown $bad $statuses "CAPTURED").result -ne "REVIEW_REQUIRED"){throw "UNKNOWN_JAR_ACCEPTED"}
  if((Get-LauncherRole 'java -jar "C:\a\paper-1.21.11.jar"') -ne "PAPER"){throw "PAPER_PATH_FIXTURE"}
  if((Get-LauncherRole 'java -jar "C:\a\fabric-server-launch.jar"') -ne "OTHER_SERVER_JAR"){throw "FABRIC_CLASSIFY_FIXTURE"}
  Write-Host "SYNTHETIC_PASS: expected StatusAgent, 3/4 offline, mismatch, API auth, unknown JAR, alternate server, Windows paths"
  exit 0
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Three-Tests"
}
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$destination=Join-Path $OutputDir ("Day12-Unknown-Java-Role-READ-ONLY-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report=[ordered]@{
  schema=1;purpose="DAY12_11_CASE_2_ONE_UNKNOWN_JAVA_ROLE_REVIEW"
  read_only=$true;synthetic=$false
  generated_utc=(Get-Date).ToUniversalTime().ToString("o")
  result="REVIEW_REQUIRED";reason="NOT_COLLECTED"
  process_classification=$null
  prior_confirmed_velocity_parent_child_and_udp="REUSE_PRIOR_OPERATOR_REPORT_20261011_002947_ONLY"
  production_services_modified=$false;server_processes_modified=$false;game_world_modified=$false
  backend_ports_private="UNCHANGED_FAIL"
  real_crash_recovery_test_performed=$false;real_canary_update_performed=$false;stable_allowed=$false
}
try{
  $raw=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
  $rows=@($raw|ForEach-Object{[pscustomobject]@{command_line=[string]$_.CommandLine}})
  $status="API_UNAVAILABLE";$servers=@()
  try{
    # Local GET only; does not submit tokens or send actions/console commands.
    $snap=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/v1/snapshot" -Method Get -TimeoutSec 5 -ErrorAction Stop
    if($null -ne $snap -and $null -ne $snap.servers){
      $servers=@($snap.servers);$status="CAPTURED"
    }else{$status="INVALID_SNAPSHOT"}
  }catch{$status="API_UNAVAILABLE_OR_AUTH_REQUIRED"}
  $summary=Measure-Unknown $rows $servers $status
  $report.process_classification=$summary
  $report.result=$summary.result
  $report.reason=if($summary.result -eq "PASS_SCOPED_ROLE_RECONCILIATION"){"ALL_JAVA_LAUNCHERS_RECONCILED_WITH_GSC_ONLINE_COUNT"}else{"IDENTITY_OR_GSC_STATUS_NEEDS_REVIEW"}
}catch{
  $report.reason="WINDOWS_CIM_PROCESS_ENUMERATION_FAILED"
}
$report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $destination -Encoding UTF8
Write-Host ("DAY12 JAVA ROLE REVIEW: "+$report.result)
Write-Host ("SHARE ONLY: "+$destination)
Write-Host "This tool did not stop or restart any server."
