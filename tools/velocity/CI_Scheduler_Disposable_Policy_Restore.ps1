#requires -Version 5.1
[CmdletBinding()]
param()

# GitHub-hosted Windows runner ONLY, never the user's server.
# One brand-new disabled scheduled task, no trigger and no task execution.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:CI -cne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
    [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) {
    throw 'CI HOST GUARD: denied outside disposable GitHub Windows runner'
}
Import-Module ScheduledTasks -ErrorAction Stop
$name = 'GSC452-CI-DISABLED-' + [Guid]::NewGuid().ToString('N').Substring(0,16)
$created=$false
$originalXml=$null
$recovered=$false

function GetTestTask([string]$id){
    return Get-ScheduledTask -TaskName $id -TaskPath '\' -ErrorAction SilentlyContinue
}
function AssertSafeTask([string]$id){
    if ($id -notmatch '^GSC452-CI-DISABLED-[0-9a-f]{16}$') {
        throw 'non-disposable task name rejected'
    }
    $t=GetTestTask $id
    if($null -eq $t){throw 'Unique disposable CI task not found'}
    # A @($null) PowerShell array can have Count=1. Exclude null objects
    # explicitly before assessing the trigger-free task.
    $triggerCount=@($t.Triggers | Where-Object { $null -ne $_ }).Count
    $actionCount=@($t.Actions | Where-Object { $null -ne $_ }).Count
    $disabled=[string]$t.State -eq 'Disabled'
    if(-not $disabled -or $triggerCount -ne 0 -or $actionCount -ne 1){
        Write-Host ('CI_ONLY_DISPOSABLE_SHAPE disabled='+$disabled+
            ' trigger_count='+$triggerCount+' action_count='+$actionCount)
        throw 'CI task not disabled or unexpected trigger/action'
    }
    return $t
}
function GetTestPolicy([string]$id){
    $null=AssertSafeTask $id
    $xml=[xml](Export-ScheduledTask -TaskName $id -TaskPath '\' -ErrorAction Stop)
    $restart=$xml.SelectSingleNode("//*[local-name()='RestartOnFailure']")
    $count=$xml.SelectSingleNode("//*[local-name()='RestartOnFailure']/*[local-name()='Count']")
    $mode=$xml.SelectSingleNode("//*[local-name()='MultipleInstancesPolicy']")
    if($null -eq $mode -or [string]$mode.InnerText -ne 'IgnoreNew'){
        throw 'CI task collision policy missing or drifted'
    }
    if($null -ne $restart -and $null -eq $count){throw 'Incomplete CI task restart policy'}
    $restarts=0
    if($null -ne $count){$restarts=[int]$count.InnerText}
    return [pscustomobject]@{XML=$xml;Count=$restarts}
}
function SetOnlyTestPolicy([string]$id,[xml]$xml,[int]$newCount){
    if($newCount -notin @(0,999)){throw 'only 0/999 synthetic counts are permitted'}
    $null=AssertSafeTask $id
    $restart=$xml.SelectSingleNode("//*[local-name()='RestartOnFailure']")
    if($newCount -eq 0){
        # Windows Task Scheduler rejects a RestartOnFailure element whose
        # Count is zero. Suppress the CI-only restart policy by removing that
        # element, then later register the exact original XML with Count=999.
        if($null -eq $restart){throw 'CI fixture missing original restart element'}
        $null=$restart.ParentNode.RemoveChild($restart)
    }else{
        $count=$xml.SelectSingleNode("//*[local-name()='RestartOnFailure']/*[local-name()='Count']")
        if($null -eq $count){throw 'original 999 restart field missing'}
        $count.InnerText='999'
    }
    Register-ScheduledTask -TaskName $id -TaskPath '\' -Xml $xml.OuterXml -Force -ErrorAction Stop | Out-Null
    Disable-ScheduledTask -TaskName $id -TaskPath '\' -ErrorAction Stop | Out-Null
    $check=GetTestPolicy $id
    if($check.Count -ne $newCount){throw 'CI task count mismatch after registration'}
    return $check
}
try {
    if($null -ne (GetTestTask $name)){throw 'random name collision'}
    $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument '/c exit 0'
    $settings=New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    # Intentionally NO triggers. This test must never start a command or JVM.
    $fixture=New-ScheduledTask -Action $action -Settings $settings
    Register-ScheduledTask -TaskName $name -TaskPath '\' -InputObject $fixture -ErrorAction Stop | Out-Null
    $created=$true
    Disable-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop | Out-Null
    if((GetTestPolicy $name).Count -ne 999){throw 'initial 999 policy missing'}
    $originalXml=[string](Export-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop)
    if([string]::IsNullOrWhiteSpace($originalXml)){throw 'failed to snapshot CI task'}
    # 999 -> 0 -> 999 on unique disposable CI fixture ONLY.
    if((SetOnlyTestPolicy $name ([xml]$originalXml) 0).Count -ne 0){throw 'failed to simulate override'}
    Write-Host 'DISPOSABLE_999_TO_0=PASS'
    if((SetOnlyTestPolicy $name ([xml]$originalXml) 999).Count -ne 999){throw 'original 999 not restored'}
    $recovered=$true
    Write-Host 'DISPOSABLE_RESTORE_ORIGINAL_999=PASS'
}
finally {
    if($created -and $null -ne (GetTestTask $name)){
        if($null -ne $originalXml -and -not $recovered){
            try{
                $null=SetOnlyTestPolicy $name ([xml]$originalXml) 999
                Write-Host 'DISPOSABLE_ERROR_ROLLBACK=RESTORED'
            }catch{
                Write-Warning 'Disposable CI task restore failed; cleanup required'
            }
        }
        Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false -ErrorAction Stop
    }
    if($null -ne (GetTestTask $name)){throw 'disposable CI task cleanup not verified'}
}
Write-Host 'DISPOSABLE_CI_TASK_CLEANED=PASS'
Write-Host 'NO_PRODUCTION_TASK_OR_RUNNING_JVM_TOUCHED'
