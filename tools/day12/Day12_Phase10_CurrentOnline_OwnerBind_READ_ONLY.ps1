[CmdletBinding()]
param([switch]$Synthetic,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# SCOPE: six private Java/RCON ports for Wild/Playground/Lobby currently ONLINE.
# Other is OPERATOR-EXPECTED OFFLINE. No service, firewall, account, ACL,
# config, world, backup or process mutation; local sanitized JSON only.
. (Join-Path $PSScriptRoot "Day12_Native_TCP_Provider_READ_ONLY.ps1")
$ownedSources=@("GetExtendedTcpTable_OWNER_PID_IPv4","GetExtendedTcpTable_OWNER_PID_IPv6")
$privatePorts=@(25570,25571,25572,25573,25575,25576,25577,25579)
$pairs=@(
  [pscustomobject]@{id="wild";java=25570;rcon=25575},
  [pscustomobject]@{id="playground";java=25571;rcon=25576},
  [pscustomobject]@{id="lobby";java=25573;rcon=25579}
)
function New-Row([int]$Port,[string]$Address,[int]$Owner,[string]$Source){
  return [pscustomobject]@{port=$Port;address=$Address;pid=$Owner;source=$Source}
}
function Review-Snapshot([object[]]$Rows,[object]$Fleet,[string]$NativeStatus,
                        [object[]]$Providers,[int[]]$VerifiedJavaPids) {
  $errors=New-Object System.Collections.ArrayList
  $verified=New-Object System.Collections.ArrayList
  $expected=@{wild=$true;playground=$true;lobby=$true;other=$false}
  if($null -eq $Fleet -or -not [bool]$Fleet.captured) {
    [void]$errors.Add("FLEET_UNAVAILABLE")
  } else {
    $servers=@($Fleet.servers)
    $known=@{}
    foreach($server in $servers){
      if($null -eq $server){continue}
      $id=[string]$server.id
      if(-not $expected.ContainsKey($id) -or $known.ContainsKey($id) -or
         $null -eq $server.online -or [bool]$server.online -ne $expected[$id]){
        [void]$errors.Add("FLEET_UNEXPECTED_STATE_OR_DUPLICATE")
      } else {$known[$id]=$true}
    }
    if($known.Count -ne 4){[void]$errors.Add("FLEET_NOT_EXACTLY_FOUR_ROLES")}
  }
  $expectedProviders=@("GetExtendedTcpTable_OWNER_PID_IPv4",
                       "GetExtendedTcpTable_OWNER_PID_IPv6",
                       "GetExtendedTcpTable_BASIC_LISTENER_IPv4")
  if($NativeStatus -ne "CAPTURED") {
    [void]$errors.Add("NATIVE_PROVIDERS_INCOMPLETE")
  }
  foreach($source in $expectedProviders){
    if(@($Providers|Where-Object{$null -ne $_ -and $_.source -eq $source -and $_.status -eq "CAPTURED"}).Count -ne 1){
      [void]$errors.Add("NATIVE_PROVIDER_MISSING_OR_DUPLICATE")
    }
  }
  $private=@($Rows|Where-Object{$null -ne $_ -and [int]$_.port -in $privatePorts})
  foreach($row in $private) {
    $addr=([string]$row.address).ToLowerInvariant().Trim('[',']')
    if($addr -notin @("127.0.0.1","::1","::ffff:127.0.0.1")) {
      [void]$errors.Add("PRIVATE_LISTENER_NOT_LOOPBACK_OR_UNKNOWN")
    }
    if([string]$row.source -in $ownedSources -and [int]$row.pid -le 0){
      [void]$errors.Add("OWNER_PID_UNAVAILABLE")
    }
  }
  if(@($private|Where-Object{[int]$_.port -in @(25572,25577)}).Count -gt 0) {
    [void]$errors.Add("OTHER_OFFLINE_HAS_PRIVATE_LISTENER")
  }
  $perRoleOwner=@{}
  foreach($pair in $pairs){
    $ids=@()
    foreach($p in @([int]$pair.java,[int]$pair.rcon)){
      $owners=@($private|Where-Object{
        [int]$_.port -eq $p -and [string]$_.source -in $ownedSources
      })
      if($owners.Count -eq 0) {
        [void]$errors.Add("ONLINE_PRIVATE_PORT_OWNER_MISSING")
        continue
      }
      $allPids=@($owners|ForEach-Object{[int]$_.pid}|Sort-Object -Unique)
      if($allPids.Count -ne 1 -or $allPids[0] -le 0){
        [void]$errors.Add("PRIVATE_PORT_OWNER_CONFLICT_OR_ZERO")
        continue
      }
      if($VerifiedJavaPids -notcontains $allPids[0]){
        [void]$errors.Add("PRIVATE_PORT_OWNER_NOT_PROVEN_JAVA")
        continue
      }
      $ids+= $allPids[0]
      # Any PID-capable independently captured row that contradicts native
      # OWNER_PID must block acceptance rather than being silently ignored.
      $conflicts=@($private|Where-Object{
        [int]$_.port -eq $p -and [int]$_.pid -gt 0 -and
        [int]$_.pid -ne $allPids[0]
      })
      if($conflicts.Count){[void]$errors.Add("OTHER_PROVIDER_OWNER_CONFLICT")}
    }
    if($ids.Count -ne 2 -or $ids[0] -ne $ids[1]){
      [void]$errors.Add("JAVA_RCON_SAME_OWNER_NOT_PROVEN")
    }else{
      $perRoleOwner[$pair.id]=$ids[0]
      [void]$verified.Add($pair.id)
    }
  }
  if(@($perRoleOwner.Values|Sort-Object -Unique).Count -ne 3){
    [void]$errors.Add("THREE_DISTINCT_PAPER_OWNERS_NOT_PROVEN")
  }
  $uniqueErrors=@($errors.ToArray()|Sort-Object -Unique)
  return [ordered]@{
    result=$(if($uniqueErrors.Count -eq 0){"PASS_SCOPED_ONLINE_OWNER_LOOPBACK_OBSERVED"}else{"BLOCKED_REVIEW_REQUIRED"})
    expected_other_backend="OFFLINE"
    other_backend_expected_not_actual_observed=$true
    three_expected_online_roles=@("wild","playground","lobby")
    distinct_online_roles_with_java_rcon_same_owner=$verified.Count
    expected_online_private_port_count=6
    native_private_rows_seen=$private.Count
    native_ipv4_ipv6_owner_providers_captured=($NativeStatus -eq "CAPTURED")
    blocking_categories=@($uniqueErrors)
    strict_final_stable_gate="NOT_PASSED"
    note="Scope: one current native TCP snapshot with owner, address and process image; does not prove all host security, firewall, real-world Internet exposure or signature promotion."
  }
}
function FleetSnapshot {
  try{
    $data=Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8790/api/v4/update/fleet" -TimeoutSec 5 -ErrorAction Stop
    $ids=@()
    foreach($s in @($data.servers)){
      if($null -eq $s){continue}
      $id=[string]$s.server_id
      if($id -notin @("wild","playground","other","lobby")){continue}
      if($null -eq $s.PSObject.Properties["online"]){return [pscustomobject]@{captured=$false;servers=@()}}
      $ids+= [pscustomobject]@{id=$id;online=([bool]$s.online)}
    }
    return [pscustomobject]@{captured=$true;servers=@($ids)}
  }catch{
    return [pscustomobject]@{captured=$false;servers=@()}
  }
}
if($Synthetic){
  $provider=@(
    [pscustomobject]@{source=$ownedSources[0];status="CAPTURED"},
    [pscustomobject]@{source=$ownedSources[1];status="CAPTURED"},
    [pscustomobject]@{source="GetExtendedTcpTable_BASIC_LISTENER_IPv4";status="CAPTURED"}
  )
  $fleet=[pscustomobject]@{captured=$true;servers=@(
    [pscustomobject]@{id="wild";online=$true},
    [pscustomobject]@{id="playground";online=$true},
    [pscustomobject]@{id="lobby";online=$true},
    [pscustomobject]@{id="other";online=$false})}
  $good=@()
  for($i=0;$i -lt $pairs.Count;$i++){
    $pid=101+$i
    foreach($port in @([int]$pairs[$i].java,[int]$pairs[$i].rcon)){
      $good+=New-Row $port "127.0.0.1" $pid $ownedSources[0]
    }
  }
  $pass=Review-Snapshot $good $fleet "CAPTURED" $provider @(101,102,103)
  if($pass.result -ne "PASS_SCOPED_ONLINE_OWNER_LOOPBACK_OBSERVED"){throw "SYNTHETIC_POSITIVE_FAILED"}
  $badWild=@($good)+@(New-Row 25570 "0.0.0.0" 101 $ownedSources[0])
  $badOther=@($good)+@(New-Row 25572 "127.0.0.1" 105 $ownedSources[0])
  $badOwner=@($good|Where-Object{$_.port -ne 25575})+@(New-Row 25575 "127.0.0.1" 999 $ownedSources[0])
  $badZero=@($good|Where-Object{$_.port -ne 25576})+@(New-Row 25576 "127.0.0.1" 0 $ownedSources[0])
  $badFleet=[pscustomobject]@{captured=$true;servers=@(
    [pscustomobject]@{id="wild";online=$true},
    [pscustomobject]@{id="playground";online=$true},
    [pscustomobject]@{id="lobby";online=$true},
    [pscustomobject]@{id="other";online=$true})}
  $cases=@(
    (Review-Snapshot $badWild $fleet "CAPTURED" $provider @(101,102,103)),
    (Review-Snapshot $badOther $fleet "CAPTURED" $provider @(101,102,103)),
    (Review-Snapshot $badOwner $fleet "CAPTURED" $provider @(101,102,103)),
    (Review-Snapshot $badZero $fleet "CAPTURED" $provider @(101,102,103)),
    (Review-Snapshot $good $badFleet "CAPTURED" $provider @(101,102,103)),
    (Review-Snapshot $good $fleet "PARTIAL" $provider @(101,102,103)),
    (Review-Snapshot $good ([pscustomobject]@{captured=$false;servers=@()}) "CAPTURED" $provider @(101,102,103))
  )
  if(@($cases|Where-Object{$_.result -ne "BLOCKED_REVIEW_REQUIRED"}).Count){
    throw "SYNTHETIC_FAIL_CLOSED_NEGATIVE_FAILED"
  }
  Write-Host "DAY12_10_CURRENT_ONLINE_OWNER_BIND_SYNTHETIC_PASS"
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "WINDOWS_SERVER_PC_ONLY"}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path $env:LOCALAPPDATA "Geumyi-Day12-10-CurrentOnline-Bind"
}
New-Item -ItemType Directory -Force -Path $OutputDir -ErrorAction Stop|Out-Null
$target=Join-Path $OutputDir ("DAY12-10-CURRENT-ONLINE-BIND-SHARE-ONLY-THIS-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
$fleet=FleetSnapshot
$native=Get-Day12NativeTcpInventory -WantedPorts $privatePorts
$verified=@()
$owned=@($native.rows|Where-Object{$null -ne $_ -and [string]$_.source -in $ownedSources -and [int]$_.pid -gt 0})
foreach($pid in @($owned|ForEach-Object{[int]$_.pid}|Sort-Object -Unique)){
  try{
    $proc=Get-Process -Id $pid -ErrorAction Stop
    if(([string]$proc.ProcessName).ToLowerInvariant() -in @("java","javaw")){$verified+=$pid}
  }catch{}
}
$analysis=Review-Snapshot @($native.rows) $fleet ([string]$native.status) @($native.providers) @($verified)
$report=[ordered]@{
  schema=1;phase="12.10";tool="DAY12_CURRENT_ONLINE_NATIVE_OWNER_BIND"
  synthetic=$false;read_only=$true;production_mutation=$false
  generated_at=(Get-Date).ToUniversalTime().ToString("o")
  result=$analysis.result
  analysis=$analysis
  native_query_status=[string]$native.status
  fleet_query_status=$(if($fleet.captured){"CAPTURED"}else{"UNAVAILABLE"})
  raw_ip_pid_paths_users_sddl_exported=$false
}
$report|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $target -Encoding UTF8 -ErrorAction Stop
Write-Host ("DAY12_10_RESULT="+$analysis.result)
Write-Host ("DAY12_10_CATEGORY_COUNT="+@($analysis.blocking_categories).Count)
Write-Host ("Send only sanitized JSON: "+$target)
if($analysis.result -ne "PASS_SCOPED_ONLINE_OWNER_LOOPBACK_OBSERVED"){exit 42}
exit 0
