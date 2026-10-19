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
