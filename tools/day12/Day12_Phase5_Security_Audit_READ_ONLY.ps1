[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase5"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase5-Security-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
if($Synthetic){[ordered]@{schema=1;phase="12.5";synthetic=$true;read_only=$true;result="SYNTHETIC_PASS"}|ConvertTo-Json|Set-Content $out -Encoding UTF8;exit 0}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"};$root=Join-Path $pd "GeumyiServerCenter";$cfg=Join-Path $root "server.json"
$bind="unknown";$loop=$null
if(Test-Path $cfg){$j=Get-Content $cfg -Raw -Encoding UTF8|ConvertFrom-Json;$bind=[string]$j.bind;$loop=[bool]$j.allow_loopback_no_auth}
$ports=@()
foreach($p in @(8787,8790,25565,25566,25567,19132,19133,19134)){
  $tcp=@();$udp=@()
  try{$tcp=@(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{address=$_.LocalAddress;pid=$_.OwningProcess}})}catch{}
  try{$udp=@(Get-NetUDPEndpoint -LocalPort $p -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{address=$_.LocalAddress;pid=$_.OwningProcess}})}catch{}
  $ports += [ordered]@{port=$p;tcp=$tcp;udp=$udp}
}
$acl=$null;try{$a=Get-Acl $root;$acl=[ordered]@{owner=[string]$a.Owner;entries=@($a.Access|ForEach-Object{[ordered]@{identity=[string]$_.IdentityReference;rights=[string]$_.FileSystemRights;type=[string]$_.AccessControlType;inherited=[bool]$_.IsInherited}})}}catch{}
$fw=@();try{$fw=@(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue|Where-Object{$_.DisplayName -like "*Geumyi*" -or $_.DisplayName -like "*Minecraft*" -or $_.DisplayName -like "*Velocity*"}|ForEach-Object{[ordered]@{name=$_.DisplayName;profile=[string]$_.Profile;action=[string]$_.Action}})}catch{}
$r=[ordered]@{schema=1;phase="12.5";mode="READ_ONLY";generated_at=(Get-Date).ToString("o");gsc=[ordered]@{bind=$bind;allow_loopback_no_auth=$loop;token_exported=$false};listeners=$ports;acl=$acl;firewall_rules=$fw;secret_values_exported=$false;result="CAPTURED_FOR_REVIEW"}
$r|ConvertTo-Json -Depth 12|Set-Content $out -Encoding UTF8
Write-Host "SECURITY AUDIT CAPTURED FOR REVIEW";Write-Host ("Report: "+$out)
