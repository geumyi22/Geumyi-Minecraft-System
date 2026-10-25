#requires -Version 5.1
[CmdletBinding()]
param()
# Only runs inside a fresh GitHub-hosted Windows Actions runner.
# Creates a unique NO-trigger dummy PowerShell task; NEVER runs Velocity,
# Java, GSC, Minecraft or production task names. It validates the Windows
# transition semantics independently of the protected user-host task.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:CI -cne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)){
 throw 'ISOLATED_CI_WINDOWS_ONLY'
}
Import-Module ScheduledTasks -ErrorAction Stop
$name='GSC452-CI-DRAIN-'+[Guid]::NewGuid().ToString('N').Substring(0,16)
$registered=$false
$script=Join-Path $env:RUNNER_TEMP ($name+'.ps1')
try{
 if($name -notmatch '^GSC452-CI-DRAIN-[0-9a-f]{16}$' -or
    $null -ne (Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue)){
  throw 'CI unique task identity collision'
 }
 # No Java executable, no external network, no Minecraft world.
 [IO.File]::WriteAllText($script,'Start-Sleep -Seconds 70',
  (New-Object Text.UTF8Encoding($false)))
 $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $action=New-ScheduledTaskAction -Execute $exe -Argument ('-NoProfile -NonInteractive -File "'+$script+'"')
 $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
 $task=New-ScheduledTask -Action $action -Settings $settings
 Register-ScheduledTask -TaskPath '\' -TaskName $name -InputObject $task -ErrorAction Stop|Out-Null
 $registered=$true
 $original=Export-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop
 if([string](Get-ScheduledTask -TaskPath '\' -TaskName $name).State -ne 'Ready'){
  throw 'CI no-trigger task not initially Ready'
 }
 Start-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop
 $deadline=[DateTimeOffset]::UtcNow.AddSeconds(18)
 do{
  $state=[string](Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop).State
  if($state -eq 'Running'){break}
  Start-Sleep -Milliseconds 300
 }while([DateTimeOffset]::UtcNow -lt $deadline)
 if($state -ne 'Running'){throw 'CI fake task never reached Running'}
 Write-Host 'CI_DISPOSABLE_LEGACY_TASK_RUNNING=PASS'
 # Disable is a future-launch gate; it is not proof the process stopped.
 Disable-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop|Out-Null
 if([string](Get-ScheduledTask -TaskPath '\' -TaskName $name).State -ne 'Disabled'){
  throw 'CI disabling running task did not block scheduled starts'
 }
 Write-Host 'CI_DISPOSABLE_RESTART_BLOCKED_BEFORE_STOP=PASS'
 Stop-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop
 $deadline=[DateTimeOffset]::UtcNow.AddSeconds(18)
 do{
  $running=([string](Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop).State -eq 'Running')
  if(-not $running){break}
  Start-Sleep -Milliseconds 300
 }while([DateTimeOffset]::UtcNow -lt $deadline)
 if($running){throw 'CI Scheduler still reports task Running after Stop'}
 $after=Export-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop
 $x=[xml]$original;$y=[xml]$after
 foreach($obj in @($x,$y)){
  $enabled=$obj.SelectSingleNode("//*[local-name()='Settings']/*[local-name()='Enabled']")
  if($null -ne $enabled){[void]$enabled.ParentNode.RemoveChild($enabled)}
 }
 if($x.OuterXml -cne $y.OuterXml){
  throw 'CI dummy task settings unexpectedly changed beyond Enabled'
 }
 Write-Host 'CI_DISPOSABLE_TASK_STOP_AND_DEFINITION_PRESERVATION=PASS'
 Write-Host 'CI_TASK_STOP_IS_NOT_CHILD_JVM_EXIT_PROOF'
}
finally{
 if($registered){
  try{Stop-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue}catch{}
  $task=Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue
  if($null -ne $task){
   Disable-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue|Out-Null
   Unregister-ScheduledTask -TaskPath '\' -TaskName $name -Confirm:$false -ErrorAction Stop
  }
 }
 if(Test-Path -LiteralPath $script -PathType Leaf){Remove-Item -LiteralPath $script -Force}
}
Write-Host 'CI_DISPOSABLE_DRAIN_TASK_REMOVED_NO_PRODUCTION_ACTION=PASS'
