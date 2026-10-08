[CmdletBinding()]
param([string]$BaseUrl="http://127.0.0.1:8790",[string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase3"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase3-Health-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
function C([string]$k,[string]$s,[string]$m){[pscustomobject]@{key=$k;status=$s;message=$m}}
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
function G([string]$p){try{Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$p) -Method GET -TimeoutSec 15}catch{$null}}
function T([int]$p){try{[bool](Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue|Select-Object -First 1)}catch{$false}}
function U([int]$p){try{[bool](Get-NetUDPEndpoint -LocalPort $p -ErrorAction SilentlyContinue|Select-Object -First 1)}catch{$false}}
if($Synthetic){
  $fixture=[pscustomobject]@{server_id="wild";status=[pscustomobject]@{phase="idle"}}
  $flag=[bool](Optional $fixture "status.block_start" $false)
  if($flag){throw "unsafe fleet metadata regression"}
  [ordered]@{schema=1;phase="12.3";synthetic=$true;result="SYNTHETIC_PASS";summary=[ordered]@{pass=1;warn=0;fail=0};checks=@(C "synthetic" "PASS" "temp/CI only")}|ConvertTo-Json -Depth 8|Set-Content $out -Encoding UTF8;exit 0}
$status=G "/api/status";$v4=G "/api/v4/health";$entry=G "/api/v4/network/entry-status";$snap=G "/api/v1/snapshot";$fleet=G "/api/v4/update/fleet";$ext=G "/api/v4/update/external/status"
$checks=New-Object System.Collections.ArrayList
[void]$checks.Add((C "host_api" $(if($status){"PASS"}else{"FAIL"}) $(if($status){"v"+[string](Optional $status "app_version" "")}else{"unavailable"})))
[void]$checks.Add((C "four_servers" $(if($snap -and @($snap.servers).Count -ge 4){"PASS"}else{"FAIL"}) $(if($snap){"count="+@($snap.servers).Count}else{"snapshot unavailable"})))
[void]$checks.Add((C "no_active_jobs" $(if($snap -and [int](Optional $snap "active_jobs" -1) -eq 0){"PASS"}else{"WARN"}) $(if($snap){"active="+[int]$snap.active_jobs}else{"unknown"})))
$hrows=if($v4){@($v4.servers)}else{@()};[void]$checks.Add((C "v4_health" $(if($hrows.Count -ge 4 -and @($hrows|Where-Object{[string](Optional $_ "overall" "") -eq "fail"}).Count -eq 0){"PASS"}else{"FAIL"}) ("servers="+$hrows.Count)))
$erows=if($entry){@($entry.endpoints)}else{@()};[void]$checks.Add((C "public_entry_api" $(if($erows.Count -eq 3 -and @($erows|Where-Object{-not[bool](Optional $_ "java_responding" $false) -or -not[bool](Optional $_ "bedrock_raknet_pong" $false)}).Count -eq 0){"PASS"}else{"FAIL"}) ("entries="+$erows.Count)))
foreach($p in @(25565,25566,25567)){[void]$checks.Add((C ("tcp_"+$p) $(if(T $p){"PASS"}else{"WARN"}) $(if(T $p){"LISTEN"}else{"not listening"})))}
foreach($p in @(19132,19133,19134)){[void]$checks.Add((C ("udp_"+$p) $(if(U $p){"PASS"}else{"WARN"}) $(if(U $p){"BOUND"}else{"not bound"})))}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"};$root=Join-Path $pd "GeumyiServerCenter"
try{$svc=Get-Service "Geumyi Server Center Host" -ErrorAction Stop;[void]$checks.Add((C "host_service" $(if($svc.Status -eq "Running"){"PASS"}else{"WARN"}) ([string]$svc.Status)))}catch{[void]$checks.Add((C "host_service" "WARN" "not found"))}
$ports=@(25565,25566,25567,25570,25571,25572,25573,25575,25576,25577,25579,8787,8790)
foreach($p in $ports){
  try{$owners=@(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue|Select-Object -ExpandProperty OwningProcess -Unique);if($owners.Count -gt 1){[void]$checks.Add((C ("duplicate_port_"+$p) "FAIL" ("owners="+($owners -join ","))))}}catch{}
}
$residue=@();$ur=Join-Path $root "Updates";if(Test-Path $ur){$residue=@(Get-ChildItem $ur -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Name -match '(?i)\.tmp$|\.part$|pending|journal|transaction'})}
[void]$checks.Add((C "update_residue" $(if($residue.Count -eq 0){"PASS"}else{"WARN"}) ("items="+$residue.Count)))
if($fleet){$unsafe=@($fleet.servers|Where-Object{[bool](Optional $_ "status.block_start" $false) -or [string](Optional $_ "status.phase" "") -in @("blocked","rollback_failed","rolling_back","pending_health","downloading")});[void]$checks.Add((C "fleet_safe" $(if($unsafe.Count -eq 0){"PASS"}else{"FAIL"}) ("unsafe="+$unsafe.Count)))}
if($ext){[void]$checks.Add((C "paper_manual_policy" $(if([string](Optional $ext "paper_policy" "") -eq "notify/manual-approve"){"PASS"}else{"WARN"}) ([string]$ext.paper_policy)))}
$pass=@($checks|Where-Object{$_.status -eq "PASS"}).Count;$warn=@($checks|Where-Object{$_.status -eq "WARN"}).Count;$fail=@($checks|Where-Object{$_.status -eq "FAIL"}).Count
$r=[ordered]@{schema=1;phase="12.3";read_only=$true;generated_at=(Get-Date).ToString("o");result=$(if($fail -eq 0){"CAPTURED_NO_MANDATORY_FAIL"}else{"FAIL"});summary=[ordered]@{pass=$pass;warn=$warn;fail=$fail};checks=@($checks);health=$hrows;entrypoints=$erows;mutation_performed=$false}
$r|ConvertTo-Json -Depth 14|Set-Content $out -Encoding UTF8
Write-Host ("HEALTH: PASS $pass / WARN $warn / FAIL $fail");Write-Host ("Report: "+$out);if($fail){exit 2}
