#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param()
# PRE-MAINTENANCE only: protect exact original Scheduler task definitions
# and vetted Java launcher manifests. NO JVM stop, task disable or restart.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=$PSScriptRoot
$kit=Join-Path $root 'Velocity_Managed_Cutover.ps1'
$audit=Join-Path $root 'Velocity_Actual_Launch_Audit_READ_ONLY.ps1'
$targets=@('wild','playground','other')
foreach($file in @($kit,$audit)){
 if(-not(Test-Path -LiteralPath $file -PathType Leaf)){
  throw 'SNAPSHOT_NO_GO: required maintenance kit file missing'
 }
}
$reportText=(& powershell.exe -NoProfile -NonInteractive -File $audit -Target all|Out-String)
if($LASTEXITCODE -ne 0){throw 'SNAPSHOT_NO_GO: read-only audit failed'}
$report=$reportText|ConvertFrom-Json
$items=@($report.results)
if($report.read_only -ne $true -or
 $report.lifecycle_migration_authorized -ne $false -or
 $items.Count -ne 3){throw 'SNAPSHOT_NO_GO: unexpected audit schema'}
foreach($target in $targets){
 $matches=@($items|Where-Object {$_.target -ceq $target})
 if($matches.Count -ne 1){throw 'SNAPSHOT_NO_GO: wrong number of target records'}
 $item=$matches[0]
 if($item.status -cne 'READ_ONLY_LAUNCH_PROFILE_CAPTURED_NO_GO' -or
    $item.action_class -cne 'DIRECT_JAVA' -or
    $item.launch_workdir_class -cne 'PROGRAMDATA' -or
    $item.matches_old_fixed_programdata_layout -ne $true -or
    $item.working_directory_exists -ne $true -or
    $item.java_executable_exists -ne $true -or
    $item.jar_file_found -ne $true -or
    $item.jar_sha256_class -cne 'MATCHES_CI_420_TEST_JAR' -or
    $item.task_policy_999 -ne $true -or
    $item.console_stdin_reachability -cne 'NOT_PROVEN' -or
    $item.task_state -notin @('Running','Ready')){
   throw ('SNAPSHOT_NO_GO: launcher does not match tested format: '+$target)
 }
}
$privateDir=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged\Recovery'
foreach($target in $targets){
 if(Test-Path -LiteralPath (Join-Path $privateDir ($target+'.original.xml'))){
   throw ('SNAPSHOT_NO_GO: refuse to overwrite existing original: '+$target)
 }
}
$ticket='GSC-'+[guid]::NewGuid().ToString('N').Substring(0,20).ToUpperInvariant()
$saved=New-Object 'System.Collections.Generic.List[string]'
foreach($target in $targets){
 try{
  $null=& powershell.exe -NoProfile -NonInteractive -File $kit -Mode Snapshot -Target $target -Ticket $ticket -Approved
  if($LASTEXITCODE -ne 0){throw ('subprocess failure: '+$target)}
  $saved.Add($target)
 }catch{
  # No rollback of already captured private originals. Partial is explicit.
  throw ('SNAPSHOT_NO_GO: partial snapshot; completed: '+($saved -join ',')+
    '; failed target: '+$target+'. Existing tasks remain untouched.')
 }
}
[pscustomobject]@{
 schema=1
 operation='SNAPSHOT_ONLY'
 task_mutations=0
 launched_jvms=0
 saved_targets=@($saved)
 original_xml_and_launcher_private=$true
 no_shutdown_or_cutover_performed=$true
 next_step='CONSOLE_REACHABILITY_REVIEW_NOT_AUTOMATIC_CUTOVER'
}|ConvertTo-Json -Compress
