[CmdletBinding()]
param([string]$BaseUrl="http://127.0.0.1:8790",[string]$OutputDir="",[switch]$Synthetic,[string]$FixtureRoot="")
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
# Native OS listener helper is read-only; its absence must not turn missing bind evidence into PASS.
$nativeHelper=Join-Path $PSScriptRoot "Day12_Native_TCP_Provider_READ_ONLY.ps1"
if(Test-Path -LiteralPath $nativeHelper -PathType Leaf){. $nativeHelper}
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
  # Preserve provider/PID distinctions. Deduplicating by address alone
  # hides contradictory owner claims from other OS inventory sources.
  $dedup=New-Object System.Collections.ArrayList
  $seen=@{}
  foreach($row in @($rows.ToArray())){
    $k=[string]$row.port+"|"+([string]$row.address).ToLowerInvariant()+"|"+
       [string]$row.source+"|"+[string]$row.pid
    if(-not $seen.ContainsKey($k)){
      $seen[$k]=$true
      [void]$dedup.Add($row)
    }
  }
  return $dedup.ToArray()
}
# Resolve only process *image family* for native listener PIDs; no command lines,
# paths, tokens or PID values are exported in the final report.
function Get-Day12VerifiedJavaPids([object[]]$Rows){
  $verified=New-Object System.Collections.ArrayList
  $seen=@{}
  foreach($row in @($Rows)){
    if($null -eq $row){continue}
    if([string]$row.source -notin @("GetExtendedTcpTable_OWNER_PID_IPv4","GetExtendedTcpTable_OWNER_PID_IPv6")){continue}
    $owner=[int]$row.pid
    if($owner -le 0 -or $seen.ContainsKey($owner)){continue}
    $seen[$owner]=$true
    try {
      $p=Get-Process -Id $owner -ErrorAction Stop
      if(([string]$p.ProcessName).ToLowerInvariant() -in @("java","javaw")){
        [void]$verified.Add($owner)
      }
    }catch{
      # Missing, denied or recycled process identity cannot be trusted as Java.
    }
  }
  return @($verified.ToArray())
}
# Require current native IPv4+IPv6 OWNER_PID provider coverage, a positively
# identified Java/javaw process for every ONLINE port, and the SAME owner
# for Java + RCON within each managed Paper instance.
# A successful netstat/.NET/TCP handshake alone is never ownership evidence.
function Test-Day12PrivateListenerEvidence {
  param(
    [object[]]$Rows,
    [int[]]$ExpectedJava,
    [int[]]$ExpectedRcon,
    [string]$NativeStatus,
    [int[]]$VerifiedJavaPids
  )
  $expectedAll=@($ExpectedJava)+@($ExpectedRcon)
  if($NativeStatus -ne "CAPTURED" -or
     $ExpectedJava.Count -eq 0 -or $ExpectedJava.Count -ne $ExpectedRcon.Count -or
     $VerifiedJavaPids.Count -eq 0){return $false}
  $privatePorts=@(25570,25571,25572,25573,25575,25576,25577,25579)
  $javaRconPairs=@{"25570"=25575;"25571"=25576;"25572"=25577;"25573"=25579}
  $relevant=@($Rows|Where-Object{$null -ne $_ -and $privatePorts -contains [int]$_.port})
  if($relevant.Count -eq 0){return $false}
  foreach($row in $relevant){
    if([string]$row.address -notin @("127.0.0.1","::1","::ffff:127.0.0.1")){return $false}
  }
  foreach($javaPort in $ExpectedJava){
    if(-not $javaRconPairs.ContainsKey([string]$javaPort)){return $false}
    $rconPort=[int]$javaRconPairs[[string]$javaPort]
    if($ExpectedRcon -notcontains $rconPort){return $false}
    $owners=@()
    foreach($port in @([int]$javaPort,$rconPort)){
      $found=@($relevant|Where-Object{
        [int]$_.port -eq $port -and
        [string]$_.source -in @("GetExtendedTcpTable_OWNER_PID_IPv4","GetExtendedTcpTable_OWNER_PID_IPv6") -and
        [int]$_.pid -gt 0
      })
      if($found.Count -lt 1){return $false}
      $ids=@($found|ForEach-Object{[int]$_.pid}|Select-Object -Unique)
      if($ids.Count -ne 1 -or $VerifiedJavaPids -notcontains [int]$ids[0]){return $false}
      $owners+= [int]$ids[0]
      # A different OS provider reporting a different nonzero owner must
      # block success, not be silently discarded by address-only dedup.
      $conflict=@($relevant|Where-Object{
        [int]$_.port -eq $port -and
        [string]$_.source -ne "IPGlobalProperties" -and
        [int]$_.pid -gt 0 -and
        [int]$_.pid -ne [int]$ids[0]
      })
      if($conflict.Count -gt 0){return $false}
    }
    if($owners[0] -ne $owners[1]){return $false}
  }
  foreach($rconPort in $ExpectedRcon){
    if($rconPort -notin @($javaRconPairs.Values)){return $false}
  }
  return $true
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
  $native4="GetExtendedTcpTable_OWNER_PID_IPv4"
  $native6="GetExtendedTcpTable_OWNER_PID_IPv6"
  $safeFixture=@(
    [pscustomobject]@{port=25570;address="127.0.0.1";pid=1234;source=$native4},
    [pscustomobject]@{port=25575;address="::1";pid=1234;source=$native6}
  )
  $passSafe=Test-Day12PrivateListenerEvidence -Rows $safeFixture -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234)
  $failMissing=Test-Day12PrivateListenerEvidence -Rows $safeFixture -ExpectedJava @(25570) -ExpectedRcon @(25575,25576) -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234)
  $failNoNative=Test-Day12PrivateListenerEvidence -Rows $safeFixture -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "ERROR" -VerifiedJavaPids @(1234)
  $failNoFleet=Test-Day12PrivateListenerEvidence -Rows $safeFixture -ExpectedJava @() -ExpectedRcon @() -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234)
  $failWildcard=Test-Day12PrivateListenerEvidence -Rows @(
    [pscustomobject]@{port=25570;address="0.0.0.0";pid=1234;source=$native4},
    [pscustomobject]@{port=25575;address="::1";pid=1234;source=$native6}
  ) -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234)
  $failIPv6Wildcard=Test-Day12PrivateListenerEvidence -Rows @(
    [pscustomobject]@{port=25570;address="127.0.0.1";pid=1234;source=$native4},
    [pscustomobject]@{port=25575;address="::1";pid=1234;source=$native6},
    [pscustomobject]@{port=25575;address="::";pid=1234;source=$native6}
  ) -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234)
  $failOtherOwner=Test-Day12PrivateListenerEvidence -Rows $safeFixture -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "CAPTURED" -VerifiedJavaPids @(5678)
  $failPidMissing=Test-Day12PrivateListenerEvidence -Rows @(
    [pscustomobject]@{port=25570;address="127.0.0.1";pid=0;source=$native4},
    [pscustomobject]@{port=25575;address="::1";pid=1234;source=$native6}
  ) -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234)
  $failNetstatOnly=Test-Day12PrivateListenerEvidence -Rows @(
    [pscustomobject]@{port=25570;address="127.0.0.1";pid=1234;source="netstat"},
    [pscustomobject]@{port=25575;address="127.0.0.1";pid=1234;source="Get-NetTCPConnection"}
  ) -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234)
  $failSplitOwner=Test-Day12PrivateListenerEvidence -Rows @(
    [pscustomobject]@{port=25570;address="127.0.0.1";pid=1234;source=$native4},
    [pscustomobject]@{port=25575;address="::1";pid=5678;source=$native6}
  ) -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234,5678)
  $failConflictingSource=Test-Day12PrivateListenerEvidence -Rows @(
    [pscustomobject]@{port=25570;address="127.0.0.1";pid=1234;source=$native4},
    [pscustomobject]@{port=25570;address="127.0.0.1";pid=5678;source="netstat"},
    [pscustomobject]@{port=25575;address="::1";pid=1234;source=$native6}
  ) -ExpectedJava @(25570) -ExpectedRcon @(25575) -NativeStatus "CAPTURED" -VerifiedJavaPids @(1234)
  if(-not $passSafe -or $failMissing -or $failNoNative -or $failNoFleet -or
     $failWildcard -or $failIPv6Wildcard -or $failOtherOwner -or
     $failPidMissing -or $failNetstatOnly -or $failSplitOwner -or $failConflictingSource){
    throw "Private listener native-owner/Java/RCON fail-closed regression"
  }
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
$nativeResult=[pscustomobject]@{status="UNAVAILABLE";rows=@();providers=@();error_categories=@("NATIVE_HELPER_MISSING")}
if(Test-Path -LiteralPath $nativeHelper -PathType Leaf){
  try{$nativeResult=Get-Day12NativeTcpInventory -WantedPorts $interestingPorts}
  catch{
    $nativeResult=[pscustomobject]@{status="ERROR";rows=@();providers=@();error_categories=@("NATIVE_PROVIDER_CALL_FAILED")}
  }
}
# Native read is an independent OS API path. Duplicate rows from distinct
# providers are retained for source traceability, never counted as new ports.
foreach($n in @($nativeResult.rows)){
  if($null -eq $n){continue}
  $portRows+= [ordered]@{
    port=[int]$n.port;address=[string]$n.address;pid=[int]$n.pid;source=[string]$n.source
  }
}
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
# GSC fleet currently reports four profiles; only the online servers require
# listener evidence. RCON is configured enabled for the managed backend fleet.
$rconById=@{wild=25575;playground=25576;other=25577;lobby=25579}
$requiredRcon=@()
if($fleet){
  foreach($fs in @($fleet.servers)){
    $sid=[string](Optional $fs "server_id" "")
    if([bool](Optional $fs "online" $false) -and $rconById.ContainsKey($sid)){
      $requiredRcon+=[int]$rconById[$sid]
    }
  }
}
$missingRcon=@($requiredRcon|Where-Object{$target=$_;@($privateListeners|Where-Object{[int]$_.port -eq $target}).Count -eq 0})
# Do not turn a no-listeners / no-fleet / missing-native situation into PASS.
$verifiedJavaPids=@(Get-Day12VerifiedJavaPids -Rows $portRows)
$privacyOK=Test-Day12PrivateListenerEvidence -Rows $portRows -ExpectedJava $requiredJava -ExpectedRcon $requiredRcon -NativeStatus ([string]$nativeResult.status) -VerifiedJavaPids $verifiedJavaPids
[void]$checks.Add((Check "backend_ports_private" $(if($privacyOK){"PASS"}else{"FAIL"}) (
  "public_backend_listener_observations="+$backendPublic.Count+
  "; private_listener_observations="+$privateListeners.Count+
  "; online_java_missing="+($missingJava -join ",")+
  "; online_rcon_missing="+($missingRcon -join ",")+
  "; native_java_owner_count="+$verifiedJavaPids.Count+
  "; native_provider="+[string]$nativeResult.status+
  "; tcp_inventory="+$tcpInventorySource
)))
$pass=@($checks|Where-Object{$_.status -eq "PASS"}).Count;$warn=@($checks|Where-Object{$_.status -eq "WARN"}).Count;$fail=@($checks|Where-Object{$_.status -eq "FAIL" -and $_.mandatory}).Count
# Listener addresses are inspected in memory; reports redact nonloopback IPs.
$safeListeners=@()
foreach($pr in @($portRows)){
  $addr=[string]$pr.address
  $scope=if($addr -in @("127.0.0.1","::1","::ffff:127.0.0.1")){"LOOPBACK"}
    elseif($addr -in @("0.0.0.0","::")){"WILDCARD"}
    else{"NON_LOOPBACK_REDACTED"}
  $safeListeners+= [ordered]@{
    port=[int]$pr.port;address_scope=$scope
    address=$(if($scope -ne "NON_LOOPBACK_REDACTED"){$addr}else{"REDACTED"})
    source=[string]$pr.source
  }
}
$r=[ordered]@{
  schema=2;tool="Geumyi Final Verification";read_only=$true;synthetic=$false
  fixture_mode=([bool]$FixtureRoot);generated_at=(Get-Date).ToString("o")
  result=$(if($fail -eq 0){"PASS"}else{"FAIL"})
  summary=[ordered]@{pass=$pass;warn=$warn;fail=$fail}
  checks=@($checks);golden_backups=$golden;network_entry=$erows;health=$hrows
  listener_inventory=$safeListeners;listener_inventory_sources=$tcpInventorySources
  native_provider_status=[string]$nativeResult.status
  native_providers=@($nativeResult.providers)
  native_error_categories=@($nativeResult.error_categories)
  notes=@(
    "Native OWNER_PID IPv4+IPv6 and BASIC IPv4 listener classes augment Get-NetTCPConnection/.NET/netstat.",
    "Native owner-PID IPv4+IPv6 coverage, Java/javaw process identity and same-owner Java/RCON pairing are mandatory.",
    "Native provider failure or missing online Java/RCON listener evidence fails the backend privacy gate closed.",
    "No observed listener is not evidence of private bind; public/wildcard listener evidence is a failure.",
    "Real Java/Bedrock login/routing and GSCM device E2E are separate Phase 12.11 gates.",
    "Nonloopback listener IPs, authentication credentials and config contents are not exported."
  )
  mutation_performed=$false
}
$r|ConvertTo-Json -Depth 14|Set-Content $out -Encoding UTF8;$r|ConvertTo-Json -Depth 14|Set-Content $canonical -Encoding UTF8
Write-Host ("FINAL VERIFICATION: PASS $pass / WARN $warn / FAIL $fail");Write-Host ("Result: "+$r.result);Write-Host ("Report: "+$out);if($fail){exit 2}
