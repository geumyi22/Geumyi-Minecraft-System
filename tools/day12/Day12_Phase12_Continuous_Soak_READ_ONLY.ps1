[CmdletBinding()]
param([ValidateRange(8,12)][int]$DurationHours=8,
      [ValidateRange(1,30)][int]$IntervalMinutes=5,
      [string]$OutputDir="",[switch]$Synthetic,[switch]$ProbeSelfTest,[switch]$LivePreflight,
      [ValidateSet("ONLINE","OFFLINE","UNSPECIFIED")][string]$ExpectedOtherBackendState="UNSPECIFIED")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# READ ONLY: no service, process, firewall, configuration, task, world, backup or cache mutations.
function ProcessKey($p){return ([string]$p.name+"|"+[string]$p.pid+"|"+[string]$p.started_at)}
function Compare-Samples([object[]]$a,[object[]]$b){
  $old=@{};$new=@{}
  foreach($p in @($a)){if($null -ne $p){$old[(ProcessKey $p)]=$true}}
  foreach($p in @($b)){if($null -ne $p){$new[(ProcessKey $p)]=$true}}
  return [ordered]@{
    added=@($new.Keys|Where-Object{-not $old.ContainsKey($_)}).Count
    removed=@($old.Keys|Where-Object{-not $new.ContainsKey($_)}).Count
    missing_start_time=@(@($a)+@($b)|Where-Object{$null -ne $_ -and [string]$_.started_at -eq ""}).Count
  }
}
function Analyze([object[]]$Samples,[double]$Hours,[int]$Target,[int]$Interval,[string]$OtherState){
  $new=0;$removed=0;$unknown=0;$unhealthy=0;$captureErrors=0;$maxGap=0.0;$otherProxyObservations=0
  foreach($sample in @($Samples)){
    if(-not [bool]$sample.application_probe_healthy){$unhealthy++}
    if([bool]$sample.capture_error){$captureErrors++}
    $controls=$null
    try{$controls=$sample.tcp_loopback_controls}catch{}
    if($null -ne $controls -and [bool]$controls['25567']){$otherProxyObservations++}
  }
  for($i=1;$i -lt $Samples.Count;$i++){
    $x=Compare-Samples @($Samples[$i-1].processes) @($Samples[$i].processes)
    $new+=[int]$x.added;$removed+=[int]$x.removed;$unknown+=[int]$x.missing_start_time
    $gap=([double]$Samples[$i].elapsed_seconds-[double]$Samples[$i-1].elapsed_seconds)/60
    if($gap -gt $maxGap){$maxGap=$gap}
  }
  return [ordered]@{
    schema=3;phase="12.12";mode="CONTINUOUS_READ_ONLY_SOAK"
    read_only=$true;production_mutation=$false
    result="REVIEW_REQUIRED";stable_release_allowed=$false
    duration_target_hours=$Target;duration_monotonic_hours=[math]::Round($Hours,3)
    duration_requirement_met=($Hours -ge $Target)
    sampling_interval_minutes=$Interval;sample_count=$Samples.Count
    other_backend_expected_state_by_operator=$OtherState
    other_backend_actual_state_proven=$false
    other_velocity_25567_listener_observed_samples=$otherProxyObservations
    required_local_tcp_ports=$(if($OtherState -eq "ONLINE"){@(25565,25566,25567,8787)}else{@(25565,25566,8787)})
    max_sample_gap_minutes=[math]::Round($maxGap,2)
    sampling_continuity_adequate=($Samples.Count -ge 2 -and $maxGap -le 2.2*$Interval -and $unknown -eq 0)
    observed_added_java_gsc_process_identities=$new
    observed_removed_java_gsc_process_identities=$removed
    identity_unverifiable_pairs=$unknown
    application_probe_unhealthy_samples=$unhealthy
    capture_error_samples=$captureErrors
    observed_process_identity_stable=($Samples.Count -ge 2 -and $new -eq 0 -and $removed -eq 0 -and $unknown -eq 0)
    bedrock_java_real_client_e2e_verified=$false
    notes=@(
      "Keep the console window open throughout the full monitoring interval; interruption is incomplete.",
      "Samples at 5-minute intervals may miss short failures in between; this is not a production monitoring service.",
      "Required local TCP controls: Velocity 25565/25566 + Host 8787. Port 25567 is an informational Velocity frontend when Other Paper backend is intentionally OFFLINE, and may still be reachable.",
      "Even when OTHER ONLINE is expected, a reachable 25567 frontend does not prove the Other backend state. This is only the operator expectation.",
      "TCP does NOT verify real Paper backend, Bedrock RakNet, HTTP authentication, OS socket PID ownership or game-client gameplay.",
      "Observed process churn may reflect other Java programs and requires operator review.",
      "Do not upload PRIVATE-SAMPLES-DO-NOT-UPLOAD.ndjson (includes PIDs/times); share only the summary.",
      "Eight hours and a normal summary do not establish Stable eligibility; analyze logs, user experience, resource trends and security separately."
    )
  }
}
function Test-LoopbackTcp([int]$Port) {
  # Network-only handshake of existing TCP listeners. No credentials or
  # GSC API calls, no game commands, no remote scan and no configuration writes.
  $client=New-Object System.Net.Sockets.TcpClient
  $async=$null
  try{
    $async=$client.BeginConnect("127.0.0.1",$Port,$null,$null)
    if(-not $async.AsyncWaitHandle.WaitOne(1500,$false)){return $false}
    try{$client.EndConnect($async);return $client.Connected}catch{return $false}
  }catch{return $false}
  finally{
    if($null -ne $async){$async.AsyncWaitHandle.Close()}
    $client.Dispose()
  }
}
# Proxy frontend port 25567 is NOT proof of Other backend state.
function Get-SoakTcpDecision([System.Collections.IDictionary]$Probes,[string]$OtherState){
  if($OtherState -notin @("ONLINE","OFFLINE")){return [pscustomobject]@{
    healthy=$false;status="UNSPECIFIED";required_missing=@("EXPECTED_OTHER_BACKEND_STATE_REQUIRED");
    other_frontend_is_informational=$true
  }}
  $required=@("25565","25566","8787")
  if($OtherState -eq "ONLINE"){$required+=@("25567")}
  $missing=@($required|Where-Object{-not [bool]$Probes[$_]})
  return [pscustomobject]@{
    healthy=($missing.Count -eq 0)
    status=$(if($missing.Count -eq 0){"REQUIRED_CONTROLS_REACHABLE"}else{"REQUIRED_CONTROLS_UNREACHABLE"})
    required_missing=@($missing)
    other_frontend_is_informational=($OtherState -eq "OFFLINE")
  }
}
function Snapshot([double]$Seconds,[string]$OtherState){
  $err=@();$procs=@();$healthy=$false
  try{
    $procs=@(Get-Process -ErrorAction Stop|Where-Object{
      $_.ProcessName -match '(?i)^(java|javaw|GeumyiServerHost|GeumyiServerCenter)$'
    }|ForEach-Object{
      $started=""
      try{$started=$_.StartTime.ToUniversalTime().ToString("o")}catch{}
      [ordered]@{
        name=[string]$_.ProcessName;pid=[int]$_.Id;started_at=$started
        working_set_bytes=[int64]$_.WorkingSet64;handle_count=[int]$_.HandleCount
        cumulative_cpu_seconds=$(if($null -eq $_.CPU){$null}else{[math]::Round([double]$_.CPU,2)})
      }
    })
  }catch{$err+="PROCESS_QUERY"}
  # Auth-free probes only; 25567 observes Velocity frontend, not Other Paper.
  $tcp=[ordered]@{}
  foreach($port in @(25565,25566,25567,8787)){
    $tcp["$port"]=Test-LoopbackTcp $port
  }
  $decision=Get-SoakTcpDecision -Probes $tcp -OtherState $OtherState
  $healthy=[bool]$decision.healthy
  return [ordered]@{
    captured_utc=(Get-Date).ToUniversalTime().ToString("o")
    elapsed_seconds=[math]::Round($Seconds,1)
    processes=@($procs);application_probe_healthy=$healthy
    tcp_loopback_controls=$tcp;tcp_expected_state_decision=[string]$decision.status
    tcp_required_missing=@($decision.required_missing)
    capture_error=($err.Count -gt 0);error_categories=@($err)
  }
}
if($ProbeSelfTest){
  # Disposable ephemeral loopback listener; never a Minecraft or GSC port.
  $listener=New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0)
  try{
    $listener.Start()
    $port=[int]$listener.LocalEndpoint.Port
    if(-not (Test-LoopbackTcp $port)){throw "SOAK_TCP_LOOPBACK_POSITIVE_CONTROL_FAILED"}
  }finally{$listener.Stop()}
  if(Test-LoopbackTcp $port){throw "SOAK_TCP_LOOPBACK_NEGATIVE_CONTROL_FAILED"}
  $baseline=[ordered]@{"25565"=$true;"25566"=$true;"25567"=$false;"8787"=$true}
  $offline=Get-SoakTcpDecision $baseline "OFFLINE"
  $online=Get-SoakTcpDecision $baseline "ONLINE"
  if(-not $offline.healthy -or $online.healthy -or -not $offline.other_frontend_is_informational){
    throw "SOAK_OTHER_OFFLINE_EXPECTATION_REGRESSION"
  }
  $baseline["25567"]=$true
  if(-not (Get-SoakTcpDecision $baseline "OFFLINE").healthy){
    throw "SOAK_OTHER_PROXY_IS_NOT_BACKEND_REGRESSION"
  }
  $baseline["25565"]=$false
  if((Get-SoakTcpDecision $baseline "OFFLINE").healthy -or
     (Get-SoakTcpDecision $baseline "ONLINE").healthy -or
     (Get-SoakTcpDecision $baseline "UNSPECIFIED").healthy){
    throw "SOAK_REQUIRED_CONTROLS_FAIL_CLOSED_REGRESSION"
  }
  Write-Host "SOAK_TCP_LOOPBACK_FIXTURE_PASS; SOAK_OTHER_OFFLINE_OPTIONAL_PROXY_PASS"
  exit 0
}
if($LivePreflight){
  if($ExpectedOtherBackendState -eq "UNSPECIFIED"){throw "SOAK_EXPLICIT_OTHER_EXPECTATION_REQUIRED"}
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "WINDOWS_SERVER_PC_ONLY"}
  $service=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
  if($null -eq $service){throw "REFUSE_NON_HOST_PC"}
  if($service.Status -ne 'Running'){throw "SOAK_HOST_SERVICE_NOT_RUNNING"}
  $observed=[ordered]@{}
  foreach($port in @(25565,25566,25567,8787)){$observed["$port"]=Test-LoopbackTcp $port}
  $decision=Get-SoakTcpDecision $observed $ExpectedOtherBackendState
  $failed=@($decision.required_missing)
  if($failed.Count -gt 0){
    Write-Host ("SOAK_PRECHECK_BLOCKED_LOCAL_CONTROLS=" + ($failed -join ","))
    exit 42
  }
  Write-Host ("SOAK_PREFLIGHT_REQUIRED_TCP_CONTROLS_PASS / expected_other_backend="+$ExpectedOtherBackendState+" / 25567_proxy_optional_if_offline")
  exit 0
}
if($Synthetic){
  $a=@([pscustomobject]@{name="java";pid=101;started_at="s1"},
       [pscustomobject]@{name="java";pid=102;started_at="s2"})
  $b=@([pscustomobject]@{name="java";pid=101;started_at="s1"},
       [pscustomobject]@{name="java";pid=103;started_at="s3"})
  $s=@(
    [pscustomobject]@{elapsed_seconds=0;processes=$a;application_probe_healthy=$true;capture_error=$false},
    [pscustomobject]@{elapsed_seconds=300;processes=$a;application_probe_healthy=$true;capture_error=$false},
    [pscustomobject]@{elapsed_seconds=600;processes=$b;application_probe_healthy=$false;capture_error=$false}
  )
  $result=Analyze $s 8.01 8 5 "OFFLINE"
  if($result.result -ne "REVIEW_REQUIRED" -or
     -not $result.duration_requirement_met -or
     $result.observed_added_java_gsc_process_identities -ne 1 -or
     $result.observed_removed_java_gsc_process_identities -ne 1 -or
     $result.application_probe_unhealthy_samples -ne 1 -or
     $result.observed_process_identity_stable -or
     $result.stable_release_allowed){throw "SOAK_SYNTHETIC_FAIL_CLOSED"}
  $blank=Analyze @() 8.01 8 5 "OFFLINE"
  if($blank.sampling_continuity_adequate -or $blank.observed_process_identity_stable -or
     $blank.stable_release_allowed){throw "SOAK_EMPTY_FALSE_PASS"}
  $result|ConvertTo-Json -Depth 10
  exit 0
}
if($ExpectedOtherBackendState -eq "UNSPECIFIED"){throw "SOAK_EXPLICIT_OTHER_EXPECTATION_REQUIRED"}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "WINDOWS_SERVER_PC_ONLY"}
if($null -eq (Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue)){
  throw "REFUSE_NON_HOST_PC"
}
if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) (
    "Geumyi-Day12-Soak-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
}
if(Test-Path -LiteralPath $OutputDir){throw "REFUSE_OVERWRITE_EXISTING_SOAK_DIR"}
New-Item -ItemType Directory -Path $OutputDir -ErrorAction Stop|Out-Null
$private=Join-Path $OutputDir "PRIVATE-SAMPLES-DO-NOT-UPLOAD.ndjson"
$public=Join-Path $OutputDir "DAY12-SOAK-SUMMARY-SHARE-ONLY-THIS.json"
$samples=New-Object System.Collections.ArrayList
$clock=[Diagnostics.Stopwatch]::StartNew()
$deadline=[double]$DurationHours*3600
$interval=[double]$IntervalMinutes*60
Write-Host ("READ-ONLY SOAK started: "+$DurationHours+" hours, "+$IntervalMinutes+" minute interval.")
Write-Host ("Do not close this window. Output: "+$OutputDir)
while($true){
  $now=$clock.Elapsed.TotalSeconds
  $sample=Snapshot $now $ExpectedOtherBackendState
  [void]$samples.Add($sample)
  $sample|ConvertTo-Json -Compress -Depth 10|Add-Content -LiteralPath $private -Encoding UTF8
  Write-Host ("Sample "+$samples.Count+" / "+(Get-Date -Format "HH:mm:ss")+
    " / Velocity+Host TCP="+$sample.application_probe_healthy)
  if($clock.Elapsed.TotalSeconds -ge $deadline){break}
  $next=[math]::Min($deadline,([math]::Floor($now/$interval)+1)*$interval)
  $delay=[math]::Max(1,[int][math]::Ceiling($next-$clock.Elapsed.TotalSeconds))
  Start-Sleep -Seconds $delay
}
$clock.Stop()
$result=Analyze @($samples) $clock.Elapsed.TotalHours $DurationHours $IntervalMinutes $ExpectedOtherBackendState
$result.started_utc=[string]$samples[0].captured_utc
$result.ended_utc=[string]$samples[$samples.Count-1].captured_utc
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $public -Encoding UTF8
Write-Host ("READ-ONLY SOAK ended. Share ONLY: "+$public)
