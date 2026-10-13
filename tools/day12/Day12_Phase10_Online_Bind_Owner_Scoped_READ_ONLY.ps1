[CmdletBinding()]
param(
  [ValidateSet("OFFLINE","ONLINE")]
  [string]$ExpectedOtherBackendState="OFFLINE",
  [switch]$Synthetic,
  [string]$OutputDir=""
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Day12.10: one scoped, native Windows listener-class/owner attestation.
# Corrected provider respects Windows 26220 native listener-class state 0.
# Read-only inventory; ephemeral SELFTEST sockets are owned by this process.
# No GSC POST, world, ACL, firewall, service or update changes.
# No host paths, process IDs, raw command lines, local addresses or SIDs
# are written to the shareable JSON.

. (Join-Path $PSScriptRoot "Day12_Native_TCP_Provider_READ_ONLY.ps1")
$map = @(
  [pscustomobject]@{id="wild";java=25570;rcon=25575},
  [pscustomobject]@{id="playground";java=25571;rcon=25576},
  [pscustomobject]@{id="other";java=25572;rcon=25577},
  [pscustomobject]@{id="lobby";java=25573;rcon=25579}
)
$ports = @(25570,25571,25572,25573,25575,25576,25577,25579)

function Check-LoopbackAddress([string]$Value){
  return $Value -in @("127.0.0.1","::1","::ffff:127.0.0.1")
}
function Decide-Bind([object[]]$Rows,[string]$NativeStatus,[int[]]$VerifiedPaperPids,[string]$OtherState){
  $errors=New-Object System.Collections.ArrayList
  $expected=@($map|Where-Object{$_.id -ne "other" -or $OtherState -eq "ONLINE"})
  $notExpected=@($map|Where-Object{$_.id -eq "other" -and $OtherState -eq "OFFLINE"})
  if($NativeStatus -ne "CAPTURED"){[void]$errors.Add("NATIVE_IPV4_IPV6_OWNER_OR_BASIC_UNAVAILABLE")}
  $private=@($Rows|Where-Object{$null -ne $_ -and $ports -contains [int]$_.port})
  if(@($private|Where-Object{-not (Check-LoopbackAddress ([string]$_.address))}).Count -gt 0){
    [void]$errors.Add("PRIVATE_WILDCARD_OR_NONLOOPBACK_LISTENER_OBSERVED")
  }
  $ownerSource=@("GetExtendedTcpTable_OWNER_PID_IPv4","GetExtendedTcpTable_OWNER_PID_IPv6")
  $observedPorts=New-Object System.Collections.ArrayList
  $provenPairs=0
  foreach($role in $expected){
    $ids=@()
    foreach($port in @([int]$role.java,[int]$role.rcon)){
      $matches=@($private|Where-Object{[int]$_.port -eq $port -and [string]$_.source -in $ownerSource})
      if($matches.Count -eq 0){
        [void]$errors.Add("REQUIRED_NATIVE_OWNER_LISTENER_MISSING_"+$role.id)
        continue
      }
      [void]$observedPorts.Add($port)
      $pids=@($matches|ForEach-Object{[int]$_.pid}|Select-Object -Unique)
      if($pids.Count -ne 1 -or $pids[0] -le 0){
        [void]$errors.Add("AMBIGUOUS_OR_MISSING_OWNER_"+$role.id)
        continue
      }
      if($VerifiedPaperPids -notcontains [int]$pids[0]){
        [void]$errors.Add("PAPER_PROCESS_IDENTITY_NOT_CONFIRMED_"+$role.id)
      }
      # Another native BASIC listener row on the same port must not conflict
      # in its address scope. Presence is a supporting observation, not owner.
      $ids+= [int]$pids[0]
    }
    if($ids.Count -eq 2){
      if($ids[0] -ne $ids[1]){[void]$errors.Add("JAVA_RCON_DIFFERENT_OWNER_"+$role.id)}
      elseif($VerifiedPaperPids -contains $ids[0]){$provenPairs++}
    }
  }
  foreach($role in $notExpected){
    if(@($private|Where-Object{[int]$_.port -in @([int]$role.java,[int]$role.rcon)}).Count -gt 0){
      [void]$errors.Add("OFFLINE_OTHER_BACKEND_LISTENER_UNEXPECTED")
    }
  }
  $unique=@($errors|Select-Object -Unique)
  return [ordered]@{
    result=$(if($unique.Count -eq 0 -and $provenPairs -eq $expected.Count){"SCOPED_NATIVE_BIND_OWNER_REVIEW_REQUIRED"}else{"BLOCKED_REVIEW_REQUIRED"})
    online_backends_expected=@($expected|ForEach-Object{$_.id})
    other_backend_operator_expectation=$OtherState
    other_backend_actual_state_independently_verified=$false
    owner_paper_pairs_correlated=$provenPairs
    owner_paper_pairs_expected=$expected.Count
    scoped_online_private_port_count_observed=@($observedPorts|Select-Object -Unique).Count
    scoped_online_private_port_count_expected=($expected.Count*2)
    unexpected_other_backend_listener_count=@($private|Where-Object{[int]$_.port -in @(25572,25577)}).Count
    reason_codes=$unique
    strict_backend_ports_private_gate="UNCHANGED_FAIL_PENDING_RELEASE_REVIEW"
    final_stable_release_allowed=$false
  }
}
function Write-SafeReport([object]$Decision,[bool]$IsSynthetic,[object]$Providers){
  $report=[ordered]@{
    schema=1;phase="12.10-live-online-native-bind-owner";tool="DAY12_NATIVE_SCOPED_BACKEND_OWNER"
    captured_at=(Get-Date).ToUniversalTime().ToString("o")
    synthetic=$IsSynthetic;read_only=$true
    result=$Decision.result;checks=$Decision
    native_provider_statuses=@($Providers|ForEach-Object{
      [ordered]@{source=[string]$_.source;status=[string]$_.status;matched=[int]$_.matched}
    })
    network_adapter_firewall_acl_modified=$false
    services_processes_worlds_backups_modified=$false
    config_or_secrets_exported=$false
    other_server_started_by_tool=$false
    notes=@(
      "Native GetExtendedTcpTable TCP_TABLE_OWNER_PID_LISTENER is a listener-only API table even if its returned raw Windows state is 0.",
      "No bound address, PID, executable path, command line or token leaves host; address scope and ownership are classified privately.",
      "Other Paper OFFLINE is an explicit operator expectation, not proof that an OS backend is intentionally stopped.",
      "Success is time-scoped to observed owner+loopback listeners, not WFP effective permissions or arbitrary remote reachability.",
      "A scoped result is not a canonical release gate PASS, does not inspect GSC/Bedrock application function, and does not install or change anything."
    )
  }
  if($IsSynthetic){$report|ConvertTo-Json -Depth 10;return}
  if(-not $OutputDir){
    $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) (
      "Geumyi-Day12-Native-Scope-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
  }
  if(Test-Path -LiteralPath $OutputDir){throw "REFUSE_EXISTING_OUTPUT_DIR"}
  [void](New-Item -ItemType Directory -Path $OutputDir -ErrorAction Stop)
  $out=Join-Path $OutputDir "DAY12-NATIVE-BIND-SHARE-ONLY-THIS.json"
  $json=$report|ConvertTo-Json -Depth 10
  if($json -match 'S-1-5-|[A-Za-z]:\\|(?i)password|(?i)token_value|(?:\d{1,3}\.){3}\d{1,3}'){
    throw "PRIVATE_DISCLOSURE_BLOCKED"
  }
  [IO.File]::WriteAllText($out,$json,(New-Object Text.UTF8Encoding($false)))
  Write-Host ("BIND SCOPED RESULT: "+$Decision.result)
  Write-Host ("Share ONLY: "+$out)
}
if($Synthetic){
  $native4="GetExtendedTcpTable_OWNER_PID_IPv4"
  $native6="GetExtendedTcpTable_OWNER_PID_IPv6"
  $fixture=@(
    [pscustomobject]@{port=25570;address="127.0.0.1";pid=1001;source=$native4},
    [pscustomobject]@{port=25575;address="127.0.0.1";pid=1001;source=$native4},
    [pscustomobject]@{port=25571;address="127.0.0.1";pid=1002;source=$native4},
    [pscustomobject]@{port=25576;address="127.0.0.1";pid=1002;source=$native4},
    [pscustomobject]@{port=25573;address="127.0.0.1";pid=1003;source=$native4},
    [pscustomobject]@{port=25579;address="127.0.0.1";pid=1003;source=$native4}
  )
  $good=Decide-Bind $fixture "CAPTURED" @(1001,1002,1003) "OFFLINE"
  $wildcard=@($fixture)+@([pscustomobject]@{port=25571;address="0.0.0.0";pid=1002;source=$native4})
  $otherOnline=@($fixture)+@(
    [pscustomobject]@{port=25572;address="127.0.0.1";pid=1004;source=$native4},
    [pscustomobject]@{port=25577;address="::1";pid=1004;source=$native6}
  )
  $split=@($fixture|Where-Object{$_.port -ne 25579})+@(
    [pscustomobject]@{port=25579;address="127.0.0.1";pid=9999;source=$native4}
  )
  $bad=@(
    (Decide-Bind $wildcard "CAPTURED" @(1001,1002,1003) "OFFLINE"),
    (Decide-Bind $otherOnline "CAPTURED" @(1001,1002,1003,1004) "OFFLINE"),
    (Decide-Bind $split "CAPTURED" @(1001,1002,1003,9999) "OFFLINE"),
    (Decide-Bind $fixture "PARTIAL" @(1001,1002,1003) "OFFLINE"),
    (Decide-Bind $fixture "CAPTURED" @(1001,1002) "OFFLINE"),
    (Decide-Bind @($fixture|Where-Object{$_.port -ne 25576}) "CAPTURED" @(1001,1002,1003) "OFFLINE")
  )
  if($good.result -ne "SCOPED_NATIVE_BIND_OWNER_REVIEW_REQUIRED" -or
     $good.owner_paper_pairs_correlated -ne 3 -or
     @($bad|Where-Object{$_.result -ne "BLOCKED_REVIEW_REQUIRED"}).Count -ne 0){
    throw "DAY12_SCOPED_NATIVE_OWNER_SYNTHETIC_FAIL"
  }
  Write-Host "DAY12_SCOPED_NATIVE_OWNER_SYNTHETIC_PASS"
  Write-SafeReport $good $true @()
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "WINDOWS_ONLY"}
$hostService=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
if($null -eq $hostService -or $hostService.Status -ne "Running"){throw "BLOCKED_GSC_HOST_SERVICE_NOT_RUNNING"}
# First prove this Windows native collector really sees a controlled socket
# owned by THIS PowerShell process on an ephemeral local loopback port.
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
try{
  $listener.Start()
  $controlPort=[int]$listener.LocalEndpoint.Port
  $control=Get-Day12NativeTcpInventory -WantedPorts @($controlPort)
  $controlOwners=@($control.rows|Where-Object{
    [int]$_.port -eq $controlPort -and
    [string]$_.source -eq "GetExtendedTcpTable_OWNER_PID_IPv4" -and
    [int]$_.pid -eq $PID -and (Check-LoopbackAddress ([string]$_.address))
  })
  if($control.status -ne "CAPTURED" -or $controlOwners.Count -ne 1){
    throw "BLOCKED_NATIVE_SELF_OWNED_LISTENER_CONTROL_UNVERIFIED"
  }
}finally{$listener.Stop()}
$native=Get-Day12NativeTcpInventory -WantedPorts $ports
if($native.status -ne "CAPTURED"){throw "BLOCKED_NATIVE_PROVIDER_INCOMPLETE"}
$owners=@($native.rows|Where-Object{$_.source -in @(
  "GetExtendedTcpTable_OWNER_PID_IPv4","GetExtendedTcpTable_OWNER_PID_IPv6") -and $_.pid -gt 0}|
  ForEach-Object{[int]$_.pid}|Select-Object -Unique)
$verified=New-Object System.Collections.ArrayList
foreach($owner in $owners){
  try {
    $p=Get-Process -Id $owner -ErrorAction Stop
    if($p.ProcessName -notin @("java","javaw")){continue}
    $proc=Get-CimInstance Win32_Process -Filter "ProcessId=$owner" -ErrorAction Stop
    $commandLine=[string]$proc.CommandLine
    if($commandLine -match '(?i)(?:^|\s)-jar\s+(?:"[^"]*paper[^"]*\.jar"|[^\s"]*paper[^\s"]*\.jar)'){
      [void]$verified.Add([int]$owner)
    }
  }catch {
    # Ambiguous command line or inaccessible process remains UNVERIFIED.
  }
}
$decision=Decide-Bind @($native.rows) ([string]$native.status) @($verified.ToArray()) $ExpectedOtherBackendState
Write-SafeReport $decision $false @($native.providers)
if($decision.result -ne "SCOPED_NATIVE_BIND_OWNER_REVIEW_REQUIRED"){exit 42}
exit 0
