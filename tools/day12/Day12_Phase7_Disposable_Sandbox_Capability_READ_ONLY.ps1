[CmdletBinding()]
param([switch]$Synthetic,[string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# NO Sandbox startup. NO copying server files. NO use of Docker/Hyper-V,
# networking, firewall, player queries, localhost GSC calls or settings writes.
# This only decides whether a future NETWORK-DISABLED Windows Sandbox test
# of GSC Host + a disposable, plugin-free Paper world is even possible.
$phase="12.7-offline-disposable-sandbox-capability"
if(-not $OutputDir){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) (
    "Geumyi-Day12-Sandbox-Capability-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
}
function Field([object]$Object,[string]$Key,[object]$Default=$null) {
  if($null -eq $Object){return $Default}
  $p=$Object.PSObject.Properties[$Key]
  if($null -eq $p -or $null -eq $p.Value){return $Default}
  return $p.Value
}
function Decide([object]$Facts) {
  $missing=New-Object System.Collections.ArrayList
  $must=@(
    "sandbox_binary_found","sandbox_feature_enabled","virtualization_enabled",
    "host_service_running","gsc_host_executable_found","playground_root_found",
    "single_paper_jar_found","java_runtime_found","public_update_verification_key_found",
    "minimum_memory_available","minimum_free_disk_available"
  )
  foreach($key in $must){
    if(-not [bool](Field $Facts $key $false)){[void]$missing.Add($key)}
  }
  $isReady=($missing.Count -eq 0)
  return [ordered]@{
    result=if($isReady){"ISOLATED_SANDBOX_PREREQUISITES_PRESENT_NOT_EXECUTED"}else{"SANDBOX_CAPABILITY_REVIEW_REQUIRED"}
    missing_prerequisites=@($missing)
    prerequisite_flags=$Facts
    sandbox_launched=$false
    original_server_copied=$false
    copied_live_world=$false
    game_client_test_executed=$false
    actual_offline_gsc_paper_boot_verified=$false
    proof_of_stable_release=$false
  }
}
function Save([object]$Decision,[bool]$Mock) {
  $report=[ordered]@{
    schema=1;phase=$phase
    generated_at=(Get-Date).ToString("o")
    synthetic=$Mock;read_only=$true
    production_changes=$false;server_restarted=$false
    host_firewall_or_adapter_changed=$false
    virtual_machine_or_sandbox_started=$false
    golden_backup_modified=$false
    result=$Decision.result;checks=$Decision
    canonical_backend_ports_private="UNCHANGED_FAIL"
    stable_release_allowed=$false
    note=@(
      "Only capability preflight; does not switch off a network or start Sandbox.",
      "Windows Sandbox is optional and not universally supported by Windows editions.",
      "GSC second instance must NEVER be launched on the production host: startup includes firewall synchronization and companion reconciliation.",
      "If a later sandbox is approved, map only sanitized Paper JAR and Host binary, with networking disabled, all worlds and logs disposable.",
      "No credentials, private network addresses, local paths, file names, raw command lines, PIDs or OS usernames are exported.",
      "Phase 12.7 real offline GSC/Paper boot and Phase12.10 socket owner remain unproven."
    )
  }
  New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
  $out=Join-Path $OutputDir "Day12-Sandbox-Capability-READ-ONLY.json"
  if(Test-Path -LiteralPath $out -PathType Leaf){throw "REFUSE_OVERWRITE_REPORT"}
  $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host ("Day12.7 DISPOSABLE SANDBOX capability: "+[string]$Decision.result)
  if(@($Decision.missing_prerequisites).Count){
    Write-Host ("Items requiring review: "+(@($Decision.missing_prerequisites) -join ", "))
  }
  Write-Host ("Safe report: "+$out)
}
if($Synthetic) {
  $trueCase=[pscustomobject]@{
    sandbox_binary_found=$true;sandbox_feature_enabled=$true;virtualization_enabled=$true
    host_service_running=$true;gsc_host_executable_found=$true
    playground_root_found=$true;single_paper_jar_found=$true;java_runtime_found=$true
    public_update_verification_key_found=$true;minimum_memory_available=$true
    minimum_free_disk_available=$true
  }
  $valid=Decide $trueCase
  if($valid.result -ne "ISOLATED_SANDBOX_PREREQUISITES_PRESENT_NOT_EXECUTED" -or
      $valid.actual_offline_gsc_paper_boot_verified -or $valid.sandbox_launched){
    throw "SANDBOX_MOCK_READY_FALSE_PASS"
  }
  $noFeature=[pscustomobject]@{}
  foreach($p in $trueCase.PSObject.Properties){$noFeature|Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value}
  $noFeature.sandbox_feature_enabled=$false
  if((Decide $noFeature).result -ne "SANDBOX_CAPABILITY_REVIEW_REQUIRED"){
    throw "SANDBOX_DISABLED_FALSE_READY"
  }
  $noJava=[pscustomobject]@{}
  foreach($p in $trueCase.PSObject.Properties){$noJava|Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value}
  $noJava.java_runtime_found=$false
  if((Decide $noJava).result -ne "SANDBOX_CAPABILITY_REVIEW_REQUIRED"){
    throw "SANDBOX_NO_JAVA_FALSE_READY"
  }
  Save $valid $true
  exit 0
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw "SERVER_PC_WINDOWS_ONLY"}
$service=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
if($null -eq $service){throw "SERVER_PC_SERVICE_NOT_FOUND_REFUSING_SUBPC"}
$bools=[ordered]@{
  sandbox_binary_found=$false
  sandbox_feature_enabled=$false
  virtualization_enabled=$false
  host_service_running=([string]$service.Status -eq "Running")
  gsc_host_executable_found=$false
  playground_root_found=$false
  single_paper_jar_found=$false
  java_runtime_found=$false
  public_update_verification_key_found=$false
  minimum_memory_available=$false
  minimum_free_disk_available=$false
}
$sandboxBinary=Join-Path $env:WINDIR "System32\WindowsSandbox.exe"
$bools.sandbox_binary_found=(Test-Path -LiteralPath $sandboxBinary -PathType Leaf)
try{
  $feature=Get-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -ErrorAction Stop
  $bools.sandbox_feature_enabled=([string]$feature.State -eq "Enabled")
}catch{}
try{
  $cpu=Get-CimInstance Win32_Processor -ErrorAction Stop|Select-Object -First 1
  $bools.virtualization_enabled=[bool]$cpu.VirtualizationFirmwareEnabled
}catch{}
try{
  $hostService=Get-CimInstance Win32_Service -Filter "Name='Geumyi Server Center Host'" -ErrorAction Stop
  $rawPath=[string](Field $hostService "PathName" "")
  $bin=""
  if($rawPath -match '^"([^"]+\.exe)"'){$bin=$Matches[1]}
  elseif($rawPath -match '^(.+?\.exe)(?:\s|$)'){$bin=$Matches[1]}
  $bools.gsc_host_executable_found=($bin -and
    (Test-Path -LiteralPath $bin -PathType Leaf) -and
    ([IO.Path]::GetFileName($bin) -eq "GeumyiServerHost.exe"))
}catch{}
$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$configFile=Join-Path $pd "GeumyiServerCenter\server.json"
$cfg=$null
try{
  if(Test-Path -LiteralPath $configFile -PathType Leaf){
    $cfg=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
  }
}catch{}
$playground=@(Field $cfg "servers" @()|Where-Object{[string](Field $_ "id" "") -eq "playground"})
if($playground.Count -eq 1){
  $root=[string](Field $playground[0] "path" "")
  if(-not $root){
    $pathFile=[string](Field $playground[0] "path_file" "")
    if($pathFile -and (Test-Path -LiteralPath $pathFile -PathType Leaf)){
      try{$root=(Get-Content -LiteralPath $pathFile -TotalCount 1 -ErrorAction Stop).Trim()}catch{}
    }
  }
  if($root -and (Test-Path -LiteralPath $root -PathType Container)){
    $bools.playground_root_found=$true
    $paper=@(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue|
      Where-Object{$_.Name -match '(?i)^paper(?:-[A-Za-z0-9._-]+)?\.jar$' -and
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0})
    $bools.single_paper_jar_found=($paper.Count -eq 1)
  }
}
$javaCmd=Get-Command "java.exe" -ErrorAction SilentlyContinue
if($null -ne $javaCmd){
  $source=[string](Field $javaCmd "Source" "")
  if($source -and (Test-Path -LiteralPath $source -PathType Leaf)){
    $bools.java_runtime_found=$true
  }
}
$pubKey=Join-Path $pd "GeumyiServerCenter\deployment-public.pem"
if($null -ne $cfg){
  $configuredPath=[string](Field (Field $cfg "update" $null) "public_key_path" "")
  if($configuredPath){$pubKey=[Environment]::ExpandEnvironmentVariables($configuredPath)}
}
$bools.public_update_verification_key_found=($pubKey -and
  (Test-Path -LiteralPath $pubKey -PathType Leaf))
try{
  $sys=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
  $bools.minimum_memory_available=([double]$sys.TotalPhysicalMemory -ge 8GB)
}catch{}
try{
  $drive=Get-PSDrive -Name ([IO.Path]::GetPathRoot($env:TEMP).Substring(0,1)) -ErrorAction Stop
  $bools.minimum_free_disk_available=([double]$drive.Free -ge 8GB)
}catch{}
$result=Decide ([pscustomobject]$bools)
Save $result $false
# A valid precheck report is not a real-world offline-start PASS.
exit 0
