#requires -Version 5.1
[CmdletBinding()]
param()
# Execute only on disposable GitHub-hosted Windows CI; no real Velocity,
# Minecraft server, JAR, plugins, user credentials or production tasks.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or $env:CI -cne 'true' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)){
 throw 'CI HOST GUARD: refusing fake cutover on a user-owned Windows server'
}
Import-Module ScheduledTasks -ErrorAction Stop
$target='wild'
$name='Geumyi Day10 Velocity wild'
$kit=Join-Path $PSScriptRoot 'Velocity_Managed_Cutover.ps1'
$ticket='CI-ONLY-'+[Guid]::NewGuid().ToString('N').Substring(0,16).ToUpperInvariant()
$wasCreated=$false
$programRoot=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged'
$archive=Join-Path $programRoot 'Recovery'
$originalFile=Join-Path $archive 'wild.original.xml'
$receiptFile=Join-Path $archive 'wild.receipt.json'
$manifestFile=Join-Path $programRoot 'wild.json'
$dummyWorkdir=Join-Path $env:RUNNER_TEMP 'GeumyiServerCenter\Network\FourServer\wild'
try{
 if($null -ne (Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue)){
  throw 'CI GUARD: fixed Day10 task already exists; do not overwrite it'
 }
 if(Test-Path -LiteralPath $archive){
  throw 'CI GUARD: private recovery archive already exists; cannot use'
 }
 $null=New-Item -ItemType Directory -Path $dummyWorkdir -Force
 $java=Join-Path $env:JAVA_HOME 'bin\java.exe'
 if(-not (Test-Path -LiteralPath $java -PathType Leaf)){
  throw 'Disposable Java executable missing'
 }
 $action=New-ScheduledTaskAction -Execute $java -Argument '-jar velocity.jar' -WorkingDirectory $dummyWorkdir
 $settings=New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
 # NO trigger. NO Java is ever launched by this fixture.
 $task=New-ScheduledTask -Action $action -Settings $settings
 Register-ScheduledTask -TaskName $name -TaskPath '\' -InputObject $task -ErrorAction Stop|Out-Null
 $wasCreated=$true
 $status=(Get-ScheduledTask -TaskName $name -TaskPath '\').State.ToString()
 if($status -ne 'Ready'){throw 'Disposable no-trigger task not ready'}
 $auditFile=Join-Path $PSScriptRoot 'Velocity_Actual_Launch_Audit_READ_ONLY.ps1'
 $audited=(& powershell.exe -NoProfile -NonInteractive -File $auditFile -Target wild |Out-String)|ConvertFrom-Json
 $record=@($audited.results)[0]
 if($LASTEXITCODE -ne 0 -or $audited.read_only -ne $true -or
    $audited.lifecycle_migration_authorized -ne $false -or
    $record.target -cne 'wild' -or $record.task_state -cne 'Ready' -or
    $record.action_class -cne 'DIRECT_JAVA' -or
    $record.java_executable_exists -ne $true -or
    $record.working_directory_exists -ne $true -or
    $record.jar_file_found -ne $false -or
    $record.task_policy_999 -ne $true){
   throw 'Host launch audit misclassified no-trigger disposable Scheduler fixture'
 }
 Write-Host 'DISPOSABLE_SANITIZED_ACTUAL_LAUNCH_AUDIT=PASS'
 $source=Get-Content -LiteralPath $kit -Raw
 if($source -notmatch 'Get-NetTCPConnection' -or
    $source -notmatch 'Get-NetUDPEndpoint' -or
    $source.Contains('[Net.Sockets.TcpListener]') -or
    $source.Contains('[Net.Sockets.UdpClient]')){
  throw 'Production cutover preflight must use passive socket queries only'
 }
 Write-Host 'DISPOSABLE_PORT_PRECHECK_STATIC_PASSIVE_ONLY=PASS'
 # The one-click full fleet snapshot MUST deny incomplete fleet records
 # BEFORE writing even the first target's protected archive.
 $snapshotWrapper=Join-Path $PSScriptRoot 'Velocity_Snapshot_Three_Before_Cutover.ps1'
 $originalPreference=$ErrorActionPreference
 try{
  $ErrorActionPreference='Continue'
  $captured=& powershell.exe -NoProfile -NonInteractive -File $snapshotWrapper 2>&1
  $snapshotExit=$LASTEXITCODE
 }finally{$ErrorActionPreference=$originalPreference}
 if($snapshotExit -eq 0){throw 'Missing playground/other fleet snapshot unexpectedly succeeded'}
 if(Test-Path -LiteralPath $originalFile){throw 'Fleet snapshot wrote wild before rejecting missing peer task'}
 Write-Host 'DISPOSABLE_FLEET_SNAPSHOT_ALL_TARGET_PREFLIGHT_FAIL_CLOSED=PASS'
 $observed=(& powershell.exe -NoProfile -NonInteractive -File $kit -Mode Preflight -Target $target |Out-String)|ConvertFrom-Json
 if($LASTEXITCODE -ne 0 -or $observed.read_only -ne $true -or
    $observed.ready_for_cutover -ne $true){
  throw 'Disposable task preflight unexpectedly unsafe'
 }
 # Occupy only disposable Windows CI runner target ports. NEVER run this
 # fixture on production: the guard above requires a GitHub-hosted runner.
 $heldUdp=$null
 try {
  $heldUdp=[Net.Sockets.UdpClient]::new(19132)
  $blocked=(& powershell.exe -NoProfile -NonInteractive -File $kit -Mode Preflight -Target $target | Out-String)|ConvertFrom-Json
  if($LASTEXITCODE -ne 0 -or $blocked.proxy_ports_free -ne $false -or $blocked.ready_for_cutover -ne $false){
   throw 'UDP port occupancy not classified as unsafe'
  }
 }finally{
  if($null -ne $heldUdp){$heldUdp.Close()}
 }
 Write-Host 'DISPOSABLE_UDP_OCCUPANCY_BLOCKS_CUTOVER=PASS'
 $heldTcp=$null
 try {
  $heldTcp=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,25565)
  $heldTcp.Start()
  $blocked=(& powershell.exe -NoProfile -NonInteractive -File $kit -Mode Preflight -Target $target | Out-String)|ConvertFrom-Json
  if($LASTEXITCODE -ne 0 -or $blocked.proxy_ports_free -ne $false -or $blocked.ready_for_cutover -ne $false){
   throw 'TCP port occupancy not classified as unsafe'
  }
 }finally{
  if($null -ne $heldTcp){$heldTcp.Stop()}
 }
 Write-Host 'DISPOSABLE_TCP_OCCUPANCY_BLOCKS_CUTOVER=PASS'
 & powershell.exe -NoProfile -NonInteractive -File $kit -Mode Snapshot -Target $target -Ticket $ticket -Approved
 if($LASTEXITCODE -ne 0){throw 'Disposable private task definition snapshot failed'}
 if(-not(Test-Path -LiteralPath $originalFile) -or
    -not(Test-Path -LiteralPath $receiptFile) -or
    -not(Test-Path -LiteralPath $manifestFile)){
  throw 'Disposable original XML, private receipt or exact launcher manifest missing'
 }
 $manifest=(Get-Content -LiteralPath $manifestFile -Raw)|ConvertFrom-Json
 if($manifest.schema -ne 1 -or $manifest.target -cne 'wild' -or
    $manifest.expected_jar_sha256 -cne '35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8' -or
    $manifest.args.Count -ne 2 -or
    $manifest.args[0] -cne '-jar' -or $manifest.args[1] -cne 'velocity.jar'){
  throw 'Disposable launcher manifest changed from original Scheduler action'
 }
 # This verifies the EXISTING protected snapshot without resnapshotting.
 # No official Velocity jar exists on this disposable CI host.
 $snapshotHashBefore=(Get-FileHash -LiteralPath $originalFile -Algorithm SHA256).Hash
 $receiptHashBefore=(Get-FileHash -LiteralPath $receiptFile -Algorithm SHA256).Hash
 $manifestHashBefore=(Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash
 $verify=(& powershell.exe -NoProfile -NonInteractive -File $kit -Mode VerifyExisting -Target $target |Out-String)|ConvertFrom-Json
 if($LASTEXITCODE -ne 0 -or $verify.read_only -ne $true -or
    $verify.protected_original_snapshot_valid -ne $true -or
    $verify.protected_manifest_matches_original -ne $true -or
    $verify.task_definition_matches_original -ne $true -or
    $verify.velocity_jar_sha256_matches_pin -ne $false -or
    $verify.task_to_child_jvm_shutdown_proven -ne $false -or
    $verify.operator_cutover_authorized -ne $false -or
    $verify.cutover_already_committed -ne $false){
   throw 'Existing protected snapshot read-only verification falsely passed a live gate'
 }
 if((Get-FileHash -LiteralPath $originalFile -Algorithm SHA256).Hash -cne $snapshotHashBefore -or
    (Get-FileHash -LiteralPath $receiptFile -Algorithm SHA256).Hash -cne $receiptHashBefore -or
    (Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash -cne $manifestHashBefore){
   throw 'Existing evidence verification mutated protected operator files'
 }
 Write-Host 'DISPOSABLE_EXISTING_EVIDENCE_VERIFIED_NO_RESNAPSHOT_NO_MUTATION=PASS'
 # Even a fully verified protected snapshot must not allow maintenance
 # against a READY (non-running) task through the running-drain mode.
 $beforeTaskXml=Export-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
 $beforeReceipt=(Get-FileHash -LiteralPath $receiptFile -Algorithm SHA256).Hash
 $drainOutput=(& powershell.exe -NoProfile -NonInteractive -File $kit -Mode DrainAndCutover -Target $target -Ticket $ticket -Approved 2>&1|Out-String)
 $drainExit=$LASTEXITCODE
 if($drainExit -eq 0 -or -not $drainOutput.Contains('LEGACY_RUNNING_TASK_REQUIRED_FOR_CONTROLLED_DRAIN')){
  throw 'Running-task maintenance bypassed its original-state gate'
 }
 if([string](Get-ScheduledTask -TaskName $name -TaskPath '\').State -ne 'Ready' -or
    (Export-ScheduledTask -TaskName $name -TaskPath '\') -cne $beforeTaskXml -or
    (Get-FileHash -LiteralPath $receiptFile -Algorithm SHA256).Hash -cne $beforeReceipt){
  throw 'Blocked running-task drain unexpectedly changed task or protected receipt'
 }
 Write-Host 'DISPOSABLE_RUNNING_DRAIN_DENIES_READY_WITH_NO_MUTATION=PASS'
 & powershell.exe -NoProfile -NonInteractive -File $kit -Mode Cutover -Target $target -Ticket $ticket -Approved
 if($LASTEXITCODE -ne 0){throw 'Disposable task cutover failed'}
 if([string](Get-ScheduledTask -TaskName $name -TaskPath '\').State -ne 'Disabled'){
  throw 'Disposable fake task was not disabled'
 }
 $receipt=Get-Content -LiteralPath $receiptFile -Raw|ConvertFrom-Json
 if($receipt.cutover_committed -ne $true){throw 'Cutover receipt did not commit'}
 Write-Host 'DISPOSABLE_CUTOVER_TASK_DISABLED_WITH_PRIVATE_ARCHIVE=PASS'
 & powershell.exe -NoProfile -NonInteractive -File $kit -Mode Rollback -Target $target -Ticket $ticket -Approved
 if($LASTEXITCODE -ne 0){throw 'Disposable task rollback failed'}
 if([string](Get-ScheduledTask -TaskName $name -TaskPath '\').State -ne 'Ready'){
  throw 'Disposable fake task did not restore Ready state'
 }
 $receipt=Get-Content -LiteralPath $receiptFile -Raw|ConvertFrom-Json
 if($receipt.cutover_committed -ne $false){throw 'Rollback receipt not cleared'}
 Write-Host 'DISPOSABLE_ROLLBACK_READY_WITH_ORIGINAL_POLICY_PRESERVED=PASS'
}finally{
 if($wasCreated){
  $task=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
  if($null -ne $task){
   # Exact CI-created unique runner task only, never an external task.
   Disable-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue|Out-Null
   Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false -ErrorAction Stop
  }
 }
 # Only the fixed CI-owned files. Never sweep unrelated ProgramData.
 if(Test-Path -LiteralPath $originalFile){Remove-Item -LiteralPath $originalFile -Force}
 if(Test-Path -LiteralPath $receiptFile){Remove-Item -LiteralPath $receiptFile -Force}
 if(Test-Path -LiteralPath $manifestFile){Remove-Item -LiteralPath $manifestFile -Force}
 if(Test-Path -LiteralPath $archive){
  Remove-Item -LiteralPath $archive -ErrorAction Stop
 }
 if(Test-Path -LiteralPath $programRoot){
  Remove-Item -LiteralPath $programRoot -ErrorAction Stop
 }
 if(Test-Path -LiteralPath $dummyWorkdir){
  Remove-Item -LiteralPath $dummyWorkdir -Recurse -Force
 }
}
if($null -ne (Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue)){
 throw 'Disposable fixture task not removed'
}
Write-Host 'DISPOSABLE_CUTOVER_AND_ROLLBACK_CLEANED=PASS'
Write-Host 'NO_MINECRAFT_JVM_STARTED_NO_PRODUCTION_TASK_TOUCHED'
