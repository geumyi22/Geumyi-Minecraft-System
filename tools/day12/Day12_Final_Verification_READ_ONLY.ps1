[CmdletBinding()]
param([string]$BaseUrl="http://127.0.0.1:8790",[string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
function Check([string]$k,[string]$status,[string]$message,[bool]$mandatory=$true){[pscustomobject]@{key=$k;status=$status;message=$message;mandatory=$mandatory}}
function G([string]$p,[int]$t=15){try{Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$p) -Method GET -TimeoutSec $t}catch{$null}}
function Get-Sha256([string]$p){if(-not(Test-Path $p -PathType Leaf)){return ""};(Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant()}
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Final-Verification"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$stamp=Get-Date -Format "yyyyMMdd-HHmmss";$out=Join-Path $OutputDir ("Geumyi-Final-Verification-"+$stamp+".json");$canonical=Join-Path $OutputDir "FINAL-HEALTH-REPORT.json"
if($Synthetic){
  $r=[ordered]@{schema=2;tool="Geumyi Final Verification";read_only=$true;synthetic=$true;result="SYNTHETIC_PASS";summary=[ordered]@{pass=1;warn=0;fail=0};checks=@(Check "synthetic" "PASS" "CI contract")}
  $r|ConvertTo-Json -Depth 8|Set-Content $out -Encoding UTF8;$r|ConvertTo-Json -Depth 8|Set-Content $canonical -Encoding UTF8;exit 0
}
$status=G "/api/status";$info=G "/api/v1/info";$snap=G "/api/v1/snapshot";$fleet=G "/api/v4/update/fleet";$health=G "/api/v4/health";$entry=G "/api/v4/network/entry-status";$mobile=G "/api/v1/mobile";$ext=G "/api/v4/update/external/status"
$checks=New-Object System.Collections.ArrayList
[void]$checks.Add((Check "gsc_4_3_8" $(if($status -and [string]$status.app_version -eq "4.3.8"){"PASS"}else{"FAIL"}) $(if($status){"v"+[string]$status.app_version}else{"status unavailable"})))
[void]$checks.Add((Check "control_api" $(if($info -and [bool]$info.ok -and [int]$info.api_version -ge 1){"PASS"}else{"FAIL"}) $(if($info){"api="+[string]$info.api_version}else{"unavailable"})))
[void]$checks.Add((Check "four_servers" $(if($snap -and @($snap.servers).Count -ge 4){"PASS"}else{"FAIL"}) $(if($snap){"count="+@($snap.servers).Count}else{"unavailable"})))
[void]$checks.Add((Check "no_active_jobs" $(if($snap -and [int]$snap.active_jobs -eq 0){"PASS"}else{"FAIL"}) $(if($snap){"active="+[int]$snap.active_jobs}else{"unavailable"})))
$hrows=if($health){@($health.servers)}else{@()};[void]$checks.Add((Check "health_no_fail" $(if($hrows.Count -ge 4 -and @($hrows|Where-Object{[string]$_.overall -eq "fail"}).Count -eq 0){"PASS"}else{"FAIL"}) ("rows="+$hrows.Count)))
$erows=if($entry){@($entry.endpoints)}else{@()};[void]$checks.Add((Check "java_bedrock_probe" $(if($erows.Count -eq 3 -and @($erows|Where-Object{-not[bool]$_.java_responding -or -not[bool]$_.bedrock_raknet_pong}).Count -eq 0){"PASS"}else{"FAIL"}) ("entries="+$erows.Count)))
if($fleet){$unsafe=@($fleet.servers|Where-Object{[bool]$_.status.block_start -or [string]$_.status.phase -in @("blocked","rollback_failed","rolling_back","pending_health","downloading")});[void]$checks.Add((Check "fleet_no_unsafe_transaction" $(if($unsafe.Count -eq 0){"PASS"}else{"FAIL"}) ("unsafe="+$unsafe.Count))) } else {[void]$checks.Add((Check "fleet_no_unsafe_transaction" "FAIL" "fleet unavailable"))}
if($mobile){[void]$checks.Add((Check "mobile_security" $(if([bool]$mobile.security.auth_required -and -not[bool]$mobile.security.rcon_exposed -and -not[bool]$mobile.security.gds_exposed){"PASS"}else{"FAIL"}) "auth/rcon/gds boundary"))}else{[void]$checks.Add((Check "mobile_security" "WARN" "mobile endpoint unavailable" $false))}
if($ext){[void]$checks.Add((Check "external_update_policy" $(if([string]$ext.mode -eq "read-only" -and [string]$ext.paper_policy -eq "notify/manual-approve"){"PASS"}else{"FAIL"}) ("mode="+[string]$ext.mode+" paper="+[string]$ext.paper_policy)))}else{[void]$checks.Add((Check "external_update_policy" "WARN" "external status unavailable" $false))}

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
  $matches=if($b){@($b.backups|Where-Object{$null -ne $_ -and $null -ne $_.PSObject.Properties["protected"] -and [bool]$_.PSObject.Properties["protected"].Value -and $null -ne $_.PSObject.Properties["source_reason"] -and [string]$_.PSObject.Properties["source_reason"].Value -match "(?i)day12-golden|golden-baseline"})}else{@()}
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
# Public entrypoints must be public; Paper backend/admin ports should remain local-only by topology.
$portRows=@();foreach($p in @(25565,25566,25567,25570,25571,25572,25573,25575,25576,25577,25579,8787,8790)){try{$portRows+=@(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{port=$p;address=$_.LocalAddress;pid=$_.OwningProcess}})}catch{}}
$backendPublic=@($portRows|Where-Object{$_.port -in @(25570,25571,25572,25573,25575,25576,25577,25579) -and $_.address -notin @("127.0.0.1","::1")})
[void]$checks.Add((Check "backend_ports_private" $(if($backendPublic.Count -eq 0){"PASS"}else{"FAIL"}) ("public_backend_listeners="+$backendPublic.Count)))
$pass=@($checks|Where-Object{$_.status -eq "PASS"}).Count;$warn=@($checks|Where-Object{$_.status -eq "WARN"}).Count;$fail=@($checks|Where-Object{$_.status -eq "FAIL" -and $_.mandatory}).Count
$r=[ordered]@{schema=2;tool="Geumyi Final Verification";read_only=$true;synthetic=$false;generated_at=(Get-Date).ToString("o");result=$(if($fail -eq 0){"PASS"}else{"FAIL"});summary=[ordered]@{pass=$pass;warn=$warn;fail=$fail};checks=@($checks);golden_backups=$golden;network_entry=$erows;health=$hrows;listener_inventory=$portRows;notes=@("Real Java/Bedrock login/routing and GSCM device E2E are separate Phase 12.11 gates.","No secret values or configuration contents are exported.");mutation_performed=$false}
$r|ConvertTo-Json -Depth 14|Set-Content $out -Encoding UTF8;$r|ConvertTo-Json -Depth 14|Set-Content $canonical -Encoding UTF8
Write-Host ("FINAL VERIFICATION: PASS $pass / WARN $warn / FAIL $fail");Write-Host ("Result: "+$r.result);Write-Host ("Report: "+$out);if($fail){exit 2}
