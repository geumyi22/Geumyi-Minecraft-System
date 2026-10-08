[CmdletBinding()]
param([string]$BaseUrl="http://127.0.0.1:8790",[string]$OutputDir="",[switch]$Synthetic,[string]$FixtureRoot="")
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
function Check([string]$k,[string]$status,[string]$message,[bool]$mandatory=$true){[pscustomobject]@{key=$k;status=$status;message=$message;mandatory=$mandatory}}
function Optional([object]$Value,[string]$Field,[object]$Default=$null){
  foreach($part in $Field.Split('.')){
    if($null -eq $Value){return $Default}
    $property=$Value.PSObject.Properties[$part]
    if($null -eq $property){return $Default}
    $Value=$property.Value
  }
  if($null -eq $Value){return $Default}
  return $Value
}
function G([string]$p,[int]$t=15){
  if($FixtureRoot){
    if($env:GITHUB_ACTIONS -ne "true"){throw "FixtureRoot is restricted to CI"}
    $route=(($p -replace '[^A-Za-z0-9]+','_').Trim('_'))+".json"
    $fixtureFile=Join-Path $FixtureRoot $route
    if(Test-Path -LiteralPath $fixtureFile -PathType Leaf){
      return (Get-Content -LiteralPath $fixtureFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return $null
  }
  try{Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$p) -Method GET -TimeoutSec $t}catch{$null}}
function Get-Sha256([string]$p){if(-not(Test-Path $p -PathType Leaf)){return ""};(Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant()}
# Merge independent Windows listener inventories. A missing provider must never
# be interpreted as proof that backend/RCON ports are private.
function Parse-Day12NetstatTcp([string[]]$Lines,[int[]]$WantedPorts){
  $found=New-Object System.Collections.ArrayList
  $pattern='^\s*TCP\s+(\S+)\s+(\S+)\s+LISTENING\s+(\d+)\s*$'
  foreach($line in $Lines){
    if($line -match $pattern){
      $localText=[string]$Matches[1]
      $pidNumber=[int]$Matches[3]
      if($localText -match '^(.+):(\d+)$'){
        $port=[int]$Matches[2]
        if($WantedPorts -contains $port){
          [void]$found.Add([ordered]@{
            port=$port;address=([string]$Matches[1]).Trim('[',']')
            pid=$pidNumber;source="netstat"
          })
        }
      }
    }
  }
  return $found.ToArray()
}
function Get-Day12TcpInventory([int[]]$WantedPorts){
  $rows=New-Object System.Collections.ArrayList
  foreach($p in $WantedPorts){
    try {
      $raw=@(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction Stop)
      foreach($item in $raw){
        if($null -eq $item){continue}
        [void]$rows.Add([ordered]@{port=[int]$p;address=[string]$item.LocalAddress;pid=[int]$item.OwningProcess;source="Get-NetTCPConnection"})
      }
    }catch{}
  }
  # The .NET API uses the native TCP table and does not need an admin shell.
  try {
    $ips=[System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    foreach($item in @($ips.GetActiveTcpListeners())){
      $port=[int]$item.Port
      if($WantedPorts -contains $port){
        [void]$rows.Add([ordered]@{port=$port;address=[string]$item.Address.ToString();pid=0;source="IPGlobalProperties"})
      }
    }
  }catch{}
  try {
    $netstat=Join-Path $env:WINDIR "System32\netstat.exe"
    if(Test-Path -LiteralPath $netstat -PathType Leaf){
      foreach($entry in @(Parse-Day12NetstatTcp @(& $netstat -ano -p TCP 2>$null) $WantedPorts)){
        [void]$rows.Add($entry)
      }
    }
  }catch{}
  $dedup=New-Object System.Collections.ArrayList
  $seen=@{}
  foreach($row in @($rows.ToArray())){
    $k=[string]$row.port+"|"+([string]$row.address).ToLowerInvariant()
    if(-not $seen.ContainsKey($k)){
      $seen[$k]=$true
      [void]$dedup.Add($row)
    }
  }
  return $dedup.ToArray()
}
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Final-Verification"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$stamp=Get-Date -Format "yyyyMMdd-HHmmss";$out=Join-Path $OutputDir ("Geumyi-Final-Verification-"+$stamp+".json");$canonical=Join-Path $OutputDir "FINAL-HEALTH-REPORT.json"
if($Synthetic){
  $probe=@(Parse-Day12NetstatTcp @(
    '  TCP    127.0.0.1:25570    0.0.0.0:0    LISTENING    1234',
    '  TCP    0.0.0.0:25571    0.0.0.0:0    LISTENING    1235',
    '  TCP    [::1]:25573    [::]:0    LISTENING    1236'
  ) @(25570,25571,25573))
  if($probe.Count -ne 3 -or $probe[0].address -ne "127.0.0.1" -or $probe[1].address -ne "0.0.0.0" -or $probe[2].address -ne "::1"){
    throw "Windows netstat TCP listener parser synthetic regression"
  }
  $fixture=[pscustomobject]@{server_id="wild";status=[pscustomobject]@{phase="idle"}}
  if([bool](Optional $fixture "status.block_start" $false)){throw "optional fleet metadata regression"}
  $r=[ordered]@{schema=2;tool="Geumyi Final Verification";read_only=$true;synthetic=$true;result="SYNTHETIC_PASS";summary=[ordered]@{pass=1;warn=0;fail=0};checks=@(Check "synthetic" "PASS" "CI contract")}
  $r|ConvertTo-Json -Depth 8|Set-Content $out -Encoding UTF8;$r|ConvertTo-Json -Depth 8|Set-Content $canonical -Encoding UTF8;exit 0
}
$status=G "/api/status";$info=G "/api/v1/info";$snap=G "/api/v1/snapshot";$fleet=G "/api/v4/update/fleet";$health=G "/api/v4/health";$entry=G "/api/v4/network/entry-status";$mobile=G "/api/v1/mobile";$ext=G "/api/v4/update/external/status"
$checks=New-Object System.Collections.ArrayList
[void]$checks.Add((Check "gsc_4_3_8" $(if($status -and [string](Optional $status "app_version" "") -eq "4.3.8"){"PASS"}else{"FAIL"}) $(if($status){"v"+[string](Optional $status "app_version" "")}else{"status unavailable"})))
[void]$checks.Add((Check "control_api" $(if($info -and [bool](Optional $info "ok" $false) -and [int](Optional $info "api_version" 0) -ge 1){"PASS"}else{"FAIL"}) $(if($info){"api="+[string]$info.api_version}else{"unavailable"})))
[void]$checks.Add((Check "four_servers" $(if($snap -and @($snap.servers).Count -ge 4){"PASS"}else{"FAIL"}) $(if($snap){"count="+@($snap.servers).Count}else{"unavailable"})))
[void]$checks.Add((Check "no_active_jobs" $(if($snap -and [int](Optional $snap "active_jobs" -1) -eq 0){"PASS"}else{"FAIL"}) $(if($snap){"active="+[int](Optional $snap "active_jobs" -1)}else{"unavailable"})))
$hrows=if($health){@($health.servers)}else{@()};[void]$checks.Add((Check "health_no_fail" $(if($hrows.Count -ge 4 -and @($hrows|Where-Object{[string](Optional $_ "overall" "") -eq "fail"}).Count -eq 0){"PASS"}else{"FAIL"}) ("rows="+$hrows.Count)))
$erows=if($entry){@($entry.endpoints)}else{@()};[void]$checks.Add((Check "java_bedrock_probe" $(if($erows.Count -eq 3 -and @($erows|Where-Object{-not[bool](Optional $_ "java_responding" $false) -or -not[bool](Optional $_ "bedrock_raknet_pong" $false)}).Count -eq 0){"PASS"}else{"FAIL"}) ("entries="+$erows.Count)))
if($fleet){$unsafe=@($fleet.servers|Where-Object{[bool](Optional $_ "status.block_start" $false) -or [string](Optional $_ "status.phase" "") -in @("blocked","rollback_failed","rolling_back","pending_health","downloading")});[void]$checks.Add((Check "fleet_no_unsafe_transaction" $(if($unsafe.Count -eq 0){"PASS"}else{"FAIL"}) ("unsafe="+$unsafe.Count))) } else {[void]$checks.Add((Check "fleet_no_unsafe_transaction" "FAIL" "fleet unavailable"))}
if($mobile){[void]$checks.Add((Check "mobile_security" $(if([bool](Optional $mobile "security.auth_required" $false) -and -not[bool](Optional $mobile "security.rcon_exposed" $true) -and -not[bool](Optional $mobile "security.gds_exposed" $true)){"PASS"}else{"FAIL"}) "auth/rcon/gds boundary"))}else{[void]$checks.Add((Check "mobile_security" "WARN" "mobile endpoint unavailable" $false))}
if($ext){[void]$checks.Add((Check "external_update_policy" $(if([string](Optional $ext "mode" "") -eq "read-only" -and [string](Optional $ext "paper_policy" "") -eq "notify/manual-approve"){"PASS"}else{"FAIL"}) ("mode="+[string](Optional $ext "mode" "")+" paper="+[string](Optional $ext "paper_policy" ""))))}else{[void]$checks.Add((Check "external_update_policy" "WARN" "external status unavailable" $false))}

$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"};$root=Join-Path $pd "GeumyiServerCenter";$cfgPath=Join-Path $root "server.json"
[void]$checks.Add((Check "server_json" $(if((Get-Sha256 $cfgPath)){"PASS"}else{"FAIL"}) "config fingerprint readable"))
try{$svc=Get-Service "Geumyi Server Center Host" -ErrorAction Stop;[void]$checks.Add((Check "host_service" $(if($svc.Status -eq "Running"){"PASS"}else{"FAIL"}) ([string]$svc.Status)))}catch{[void]$checks.Add((Check "host_service" "FAIL" "service missing"))}
foreach($id in @("wild","playground","other")){
  try{$task=Get-ScheduledTask -TaskName ("Geumyi Day10 Velocity "+$id) -ErrorAction Stop;[void]$checks.Add((Check ("velocity_task_"+$id) $(if($task.State -ne "Disabled"){"PASS"}else{"FAIL"}) ([string]$task.State)))}catch{[void]$checks.Add((Check ("velocity_task_"+$id) "FAIL" "task missing"))}
}
# Golden protected backups are a final mandatory gate.
$goldenOK=$true;$golden=@()
foreach($id in @("wild","playground","other","lobby")){
  $b=G ("/api/v4/backups?id="+[uri]::EscapeDataString($id))
  $matches=@()
  if($b){$matches=@($b.backups|Where-Object{$null -ne $_ -and $null -ne $_.PSObject.Properties["protected"] -and [bool]$_.PSObject.Properties["protected"].Value -and $null -ne $_.PSObject.Properties["source_reason"] -and [string]$_.PSObject.Properties["source_reason"].Value -match "(?i)day12-golden|golden-baseline"})}
  $golden += [ordered]@{server_id=$id;count=$matches.Count;files=@($matches|ForEach-Object{[string]$_.file})}
  if($matches.Count -lt 1){$goldenOK=$false}
}
[void]$checks.Add((Check "protected_golden_backups" $(if($goldenOK){"PASS"}else{"FAIL"}) "one protected Day12 Golden full backup required per backend"))
# Known-good cache is required for offline hardening.
$cache=Join-Path $root "ArtifactCache\known-good\day12\known-good-manifest.json";$cacheOK=Test-Path $cache -PathType Leaf
[void]$checks.Add((Check "known_good_cache" $(if($cacheOK){"PASS"}else{"FAIL"}) $(if($cacheOK){"manifest present"}else{"cache manifest missing"})))
$residue=@();$ur=Join-Path $root "Updates";if(Test-Path $ur){$residue=@(Get-ChildItem $ur -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Name -match '(?i)\.tmp$|\.part$|pending|journal|transaction'})}
[void]$checks.Add((Check "update_residue" $(if($residue.Count -eq 0){"PASS"}else{"WARN"}) ("items="+$residue.Count) $false))
$free=0;try{$free=[int64](Get-Item $root).PSDrive.Free}catch{};[void]$checks.Add((Check "disk_free_50g" $(if($free -ge 50GB){"PASS"}else{"FAIL"}) ("free_gib="+[math]::Round($free/1GB,2))))
# Collect listener bindings using PowerShell, native .NET, and netstat;
# do not assume that 0 rows means ports are safe.
$interestingPorts=@(25565,25566,25567,25570,25571,25572,25573,25575,25576,25577,25579,8787,8790)
$portRows=@(Get-Day12TcpInventory $interestingPorts)
$tcpInventorySources=@($portRows | ForEach-Object {[string]$_.source} | Select-Object -Unique)
$tcpInventorySource=if($tcpInventorySources.Count){$tcpInventorySources -join ","}else{"unavailable"}
$privatePorts=@(25570,25571,25572,25573,25575,25576,25577,25579)
$privateListeners=@($portRows | Where-Object {$privatePorts -contains [int]$_.port})
$backendPublic=@($privateListeners | Where-Object {[string]$_.address -notin @("127.0.0.1","::1","::ffff:127.0.0.1")})
$javaById=@{wild=25570;playground=25571;other=25572;lobby=25573}
$requiredJava=@()
if($fleet){
  foreach($s in @($fleet.servers)){
    $id=[string](Optional $s "server_id" "")
    if([bool](Optional $s "online" $false) -and $javaById.ContainsKey($id)){
      $requiredJava += [int]$javaById[$id]
    }
  }
}
$missingJava=@($requiredJava | Where-Object { $needed=$_; @($privateListeners|Where-Object{[int]$_.port -eq $needed}).Count -eq 0 })
$privacyOK=($backendPublic.Count -eq 0 -and $missingJava.Count -eq 0 -and $privateListeners.Count -gt 0)
[void]$checks.Add((Check "backend_ports_private" $(if($privacyOK){"PASS"}else{"FAIL"}) (
  "public_backend_listeners="+$backendPublic.Count+
  "; private_listener_rows="+$privateListeners.Count+
  "; online_java_missing="+($missingJava -join ",")+
  "; tcp_inventory="+$tcpInventorySource
)))
$pass=@($checks|Where-Object{$_.status -eq "PASS"}).Count;$warn=@($checks|Where-Object{$_.status -eq "WARN"}).Count;$fail=@($checks|Where-Object{$_.status -eq "FAIL" -and $_.mandatory}).Count
$r=[ordered]@{schema=2;tool="Geumyi Final Verification";read_only=$true;synthetic=$false;fixture_mode=([bool]$FixtureRoot);generated_at=(Get-Date).ToString("o");result=$(if($fail -eq 0){"PASS"}else{"FAIL"});summary=[ordered]@{pass=$pass;warn=$warn;fail=$fail};checks=@($checks);golden_backups=$golden;network_entry=$erows;health=$hrows;listener_inventory=$portRows;listener_inventory_sources=$tcpInventorySources;notes=@("Real Java/Bedrock login/routing and GSCM device E2E are separate Phase 12.11 gates.","No secret values or configuration contents are exported.");mutation_performed=$false}
$r|ConvertTo-Json -Depth 14|Set-Content $out -Encoding UTF8;$r|ConvertTo-Json -Depth 14|Set-Content $canonical -Encoding UTF8
Write-Host ("FINAL VERIFICATION: PASS $pass / WARN $warn / FAIL $fail");Write-Host ("Result: "+$r.result);Write-Host ("Report: "+$out);if($fail){exit 2}
