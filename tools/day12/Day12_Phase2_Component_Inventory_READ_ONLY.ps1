[CmdletBinding()]
param([string]$BaseUrl="http://127.0.0.1:8790",[string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase2"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase2-ComponentInventory-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){
  [ordered]@{schema=1;phase="12.2";read_only=$true;synthetic=$true;result="SYNTHETIC_PASS";components=@([ordered]@{id="gsc";installed="4.3.8";policy="verified"})}|ConvertTo-Json -Depth 8|Set-Content $out -Encoding UTF8
  Write-Host "SYNTHETIC PASS";exit 0
}
function G([string]$p){try{Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+$p) -Method GET -TimeoutSec 20}catch{$null}}
$status=G "/api/status";$fleet=G "/api/v4/update/fleet";$ext=G "/api/v4/update/external/status";$snap=G "/api/v1/snapshot";$self=G "/api/v4/update/self/status?fresh=0"
$rows=New-Object System.Collections.ArrayList
[void]$rows.Add([ordered]@{id="gsc";kind="gsc";installed=$(if($status){[string]$status.app_version}else{""});latest_verified=$(if($self){[string]$self.latest}else{""});channel=$(if($self){[string]$self.channel}else{""});last_known_good="Day11-4.3.8";rollback="GSC self-update backup";state="live-runtime"})
[void]$rows.Add([ordered]@{id="gscm";kind="mobile";installed="1.1.5+117";latest_verified="1.1.5+117";channel="day11-verified";last_known_good="1.1.5+117";rollback="platform reinstall/update constraints";state="user-device-verified-at-Day11"})
foreach($id in @("gst","gds","statusagent","technology","chemistry")){
  [void]$rows.Add([ordered]@{id=$id;kind=$(if($id -eq "statusagent"){"agent"}else{"plugin"});installed="runtime-inventory-required";latest_verified="deploy/components.json";state="PENDING_LIVE_FINGERPRINT"})
}
if($ext){
  foreach($x in @($ext.components)){
    [void]$rows.Add([ordered]@{id=[string]$x.component;kind="external";installed=$x.installed;latest_verified=[string]$x.version;status=[string]$x.status;source=[string]$x.source;sha256_verified=[bool]$x.sha256_verified;policy=$(if([string]$x.component -eq "paper"){"manual-approve"}else{"managed-staging"})})
  }
}
if($fleet){
  foreach($s in @($fleet.servers)){
    [void]$rows.Add([ordered]@{id=("server:"+[string]$s.server_id);kind="server-policy";installed=$(if([bool]$s.online){"online"}else{"offline"});channel=[string]$s.channel;effective_channel=[string]$s.effective_channel;policy=[string]$s.policy;pin=[string]$s.pin;update_phase=[string]$s.status.phase})
  }
}
$report=[ordered]@{
 schema=1;phase="12.2";read_only=$true;synthetic=$false;generated_at=(Get-Date).ToString("o")
 result=$(if($status -and $fleet -and $snap){"CAPTURED"}else{"CHECK_REQUIRED"})
 components=@($rows);active_jobs=$(if($snap){[int]$snap.active_jobs}else{-1})
 paper_policy=$(if($ext){[string]$ext.paper_policy}else{"unknown"})
 notes=@("Runtime plugin exact JAR fingerprints are finalized by Phase 12.0A/12.10 reports.","No files or policies are changed.")
}
$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("COMPONENT INVENTORY: "+$report.result);Write-Host ("Report: "+$out)
if($report.result -ne "CAPTURED"){exit 2}
