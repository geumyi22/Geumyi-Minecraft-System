[CmdletBinding()]
param([switch]$Synthetic, [string]$OutputDir = "")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# This script NEVER stops/starts/kills services or server processes, touches
# configurations, changes network/firewall settings, or installs updates.
function JarRole([string]$CommandLine) {
  if ([string]::IsNullOrWhiteSpace($CommandLine)) { return "NONE" }
  $m = [regex]::Matches($CommandLine, '(?i)(?:^|\s)-jar\s+(?:"([^"\r\n]+)"|([^\s"]+))(?=\s|$)')
  if ($m.Count -ne 1) { return "NONE" }
  $arg = if ($m[0].Groups[1].Success) { $m[0].Groups[1].Value } else { $m[0].Groups[2].Value }
  $name = [IO.Path]::GetFileName($arg)
  if ($name -ieq 'velocity.jar') { return "VELOCITY" }
  if ($name -match '(?i)^paper(?:[-.][a-z0-9._-]+)?\.jar$') { return "PAPER" }
  return "NONE"
}

function ClassifyCensus([object[]]$Rows, [hashtable]$Udp, [string]$HostServiceStatus) {
  $java = @($Rows | Where-Object { $_.name -in @("java.exe", "javaw.exe") })
  $hostRows = @($Rows | Where-Object { $_.name -ieq "GeumyiServerHost.exe" })
  $velocity = @($java | Where-Object { (JarRole ([string]$_.command_line)) -eq "VELOCITY" })
  $paper = @($java | Where-Object { (JarRole ([string]$_.command_line)) -eq "PAPER" })
  $vPids = @($velocity | ForEach-Object { [int]$_.pid })
  $pPids = @($paper | ForEach-Object { [int]$_.pid })
  $roots = @($velocity | Where-Object { [int]$_.parent_pid -notin $vPids })
  $leaves = @($velocity | Where-Object { [int]$_.parent_pid -in $vPids })
  $unique = @($vPids + $pPids + @($hostRows | ForEach-Object { [int]$_.pid }) | Select-Object -Unique)
  $allKnown = @($vPids + $pPids + @($hostRows | ForEach-Object { [int]$_.pid }))
  $pidUnique = ($unique.Count -eq $allKnown.Count)
  $pairs = ($roots.Count -eq 3 -and $leaves.Count -eq 3 -and $velocity.Count -eq 6)
  if ($pairs) {
    foreach ($root in $roots) {
      if (@($leaves | Where-Object { [int]$_.parent_pid -eq [int]$root.pid }).Count -ne 1) { $pairs=$false; break }
    }
  }
  $expectedPorts = @(19132,19133,19134)
  $udpMatch = ($Udp.Count -eq 3 -and $pairs)
  if ($udpMatch) {
    $owned = @()
    foreach ($port in $expectedPorts) {
      $key = [string]$port
      if (-not $Udp.ContainsKey($key)) { $udpMatch=$false; break }
      $owner = [int]$Udp[$key]
      if ($owner -le 4 -or $owned -contains $owner -or @($leaves | Where-Object { [int]$_.pid -eq $owner }).Count -ne 1) { $udpMatch=$false; break }
      $owned += $owner
    }
  }
  $hostOk = ($HostServiceStatus -eq "Running" -and $hostRows.Count -eq 1)
  $paperOk = ($paper.Count -eq 4 -and @($pPids | Select-Object -Unique).Count -eq 4)
  $healthy = ($hostOk -and $paperOk -and $pairs -and $udpMatch -and $pidUnique)
  return [ordered]@{
    result=if($healthy){"PASS_HOST_PROCESS_CENSUS_SCOPED"}else{"REVIEW_REQUIRED"}
    service_running=($HostServiceStatus -eq "Running")
    gsc_host_process_count=[int]$hostRows.Count
    velocity_process_count=[int]$velocity.Count
    velocity_parent_child_3_pairs=[bool]$pairs
    velocity_udp_3_port_owner_matches_child=[bool]$udpMatch
    java_paper_candidate_count=[int]$paper.Count
    paper_four_unique_processes=[bool]$paperOk
    candidate_process_ids_unique=[bool]$pidUnique
    other_java_process_count=[int]($java.Count-$velocity.Count-$paper.Count)
    scope="Configured fleet process structure: GSC Host 1, Velocity 3 task-parent + 3 children and Geyser UDP owners 19132-19134, Paper candidate 4. Native backend bind address privacy is NOT tested."
  }
}

if($Synthetic) {
  $rows = @([pscustomobject]@{name="GeumyiServerHost.exe";pid=500;parent_pid=100;command_line=""})
  $udp=@{}
  for($i=0;$i -lt 3;$i++) {
    $r=1000+($i*2); $c=$r+1; $udp[[string](19132+$i)]=$c
    $rows+= [pscustomobject]@{name="java.exe";pid=$r;parent_pid=400;command_line='java.exe -Xmx512M -jar velocity.jar'}
    $rows+= [pscustomobject]@{name="java.exe";pid=$c;parent_pid=$r;command_line='java.exe -Xmx512M -jar velocity.jar'}
  }
  for($i=0;$i -lt 4;$i++){$rows += [pscustomobject]@{name="java.exe";pid=(2200+$i);parent_pid=400;command_line='java.exe -Xmx2G -jar paper.jar'}}
  $positive=ClassifyCensus $rows $udp "Running"
  if($positive.result -ne "PASS_HOST_PROCESS_CENSUS_SCOPED") {throw ("POSITIVE_FIXTURE_FAILED:"+($positive | ConvertTo-Json -Compress))}
  $bad=@($rows|Where-Object { $_.pid -ne 1001 })
  $negative=ClassifyCensus $bad $udp "Running"
  if($negative.result -eq "PASS_HOST_PROCESS_CENSUS_SCOPED") {throw "ORPHAN_NEGATIVE_FIXTURE_ACCEPTED"}
  $wrong=ClassifyCensus $rows @{19132=1001;19133=1003;19134=9999} "Running"
  if($wrong.result -eq "PASS_HOST_PROCESS_CENSUS_SCOPED") {throw "UDP_OWNER_NEGATIVE_FIXTURE_ACCEPTED"}
  $noHost=ClassifyCensus $rows $udp "Stopped"
  if($noHost.result -eq "PASS_HOST_PROCESS_CENSUS_SCOPED") {throw "STOPPED_SERVICE_NEGATIVE_FIXTURE_ACCEPTED"}
  Write-Host "SYNTHETIC_PASS: parent/child, UDP, Paper, Host, fail-closed negatives"
  exit 0
}

if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Three-Tests"
}
[void](New-Item -ItemType Directory -Path $OutputDir -Force)
$destination=Join-Path $OutputDir ("Day12-2-12-17-SHARE-SUMMARY-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$report=[ordered]@{
  schema=1;phase="12.11";read_only=$true;synthetic=$false
  generated_at=(Get-Date).ToUniversalTime().ToString("o")
  host_census=[ordered]@{result="REVIEW_REQUIRED";reason="NOT_COLLECTED"}
  recovery_12="CI_DISPOSABLE_STATE_MACHINE_TEST_ONLY_UNLESS_SEPARATE_REAL_EVIDENCE"
  update_17="CI_DISPOSABLE_TRANSACTION_TEST_ONLY_UNLESS_SEPARATE_REAL_EVIDENCE"
  production_crash_performed=$false;production_update_performed=$false
  production_process_modified=$false;production_firewall_modified=$false
  backend_ports_private="UNCHANGED_FAIL"
  actual_25_case_e2e_complete=$false
  stable_allowed=$false
}
try {
  $svc=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
  $svcState=if($null -eq $svc){"NOT_FOUND"}else{[string]$svc.Status}
  $all=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe' OR Name='GeumyiServerHost.exe'" -ErrorAction Stop)
  $rows=@()
  foreach($item in $all){
    $rows+= [pscustomobject]@{
      name=[string]$item.Name;pid=[int]$item.ProcessId
      parent_pid=[int]$item.ParentProcessId
      command_line=[string]$item.CommandLine
    }
  }
  $udp=@{}
  $udpError=$false
  try{
    foreach($port in @(19132,19133,19134)){
      $r=@(Get-NetUDPEndpoint -LocalPort $port -ErrorAction Stop)
      if($r.Count -ne 1 -or [int]$r[0].OwningProcess -le 4){$udpError=$true;continue}
      $udp[[string]$port]=[int]$r[0].OwningProcess
    }
  }catch{$udpError=$true}
  $result=ClassifyCensus $rows $udp $svcState
  $report.host_census=$result
  $report.udp_inventory_complete=(-not $udpError)
}catch{
  # Error category only. Never leak command lines, user names, absolute paths,
  # local IPs, tokens, PIDs or raw exception texts into the shared report.
  $report.host_census=[ordered]@{result="REVIEW_REQUIRED";reason="CIM_OR_SERVICE_READ_FAILED"}
}
$report | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $destination -Encoding UTF8
Write-Host ""
Write-Host ("DAY12 2/12/17 READ-ONLY HOST REVIEW: "+$report.host_census.result)
Write-Host ("SHARE THIS JSON: "+$destination)
Write-Host "12/17 disposable CI results are in CI-EVIDENCE.json included in this ZIP."
Write-Host "Do not upload server logs, tokens, process command lines, or Golden backup content."
