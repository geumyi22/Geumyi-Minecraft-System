#requires -Version 5.1
[CmdletBinding()]
param()

# GitHub-hosted WINDOWS RUNNER ONLY. This is NOT a user-host script.
# Runs ONLY an isolated CI-created fake PowerShell action that records an
# attempt marker and exits 1. Limit restart retries to TWO, one-minute delay.
# No Minecraft JVM, Velocity, ports, world files, or real task names used.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:CI -cne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) {
    throw 'CI HOST GUARD: refused outside ephemeral GitHub Windows runner'
}
Import-Module ScheduledTasks -ErrorAction Stop
$id=[Guid]::NewGuid().ToString('N').Substring(0,16)
$name='GSC452-CI-CRASH-' + $id
$folder=Join-Path $env:RUNNER_TEMP ('gsc452-crash-'+$id)
$script=Join-Path $folder 'fake-failing-task.ps1'
$counter=Join-Path $folder 'attempts.txt'
$registered=$false
try {
    if($name -notmatch '^GSC452-CI-CRASH-[0-9a-f]{16}$' -or
       $null -ne (Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue)) {
        throw 'CI task name validation failed'
    }
    $null=New-Item -ItemType Directory -Path $folder -Force
    # Only a dummy local marker: no commands, Java, network or external files.
    [IO.File]::WriteAllText($script,
        "Add-Content -LiteralPath '$counter' -Value 'x'; exit 1",
        (New-Object Text.UTF8Encoding($false)))
    $exe=Join-Path $PSHOME 'powershell.exe'
    if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){
        $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }
    $action=New-ScheduledTaskAction -Execute $exe -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$script+'"')
    $settings=New-ScheduledTaskSettingsSet -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
    # Triggerless definition cannot start by itself. Explicitly run only the
    # exact newly registered CI task; it always exits 1 and can auto-retry 2x.
    $task=New-ScheduledTask -Action $action -Settings $settings
    Register-ScheduledTask -TaskName $name -TaskPath '\' -InputObject $task -ErrorAction Stop | Out-Null
    $registered=$true
    $current=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
    if(@($current.Triggers | Where-Object {$null -ne $_}).Count -ne 0){
        throw 'CI task unexpectedly has a trigger; do not start it'
    }
    $xml=[xml](Export-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop)
    $count=$xml.SelectSingleNode("//*[local-name()='RestartOnFailure']/*[local-name()='Count']")
    if($null -eq $count -or [string]$count.InnerText -ne '2'){
        throw 'CI bounded restart count was not retained'
    }
    Start-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(130)
    $first=$false
    $second=$false
    while([DateTimeOffset]::UtcNow -lt $deadline) {
        $attempts=0
        if(Test-Path -LiteralPath $counter -PathType Leaf) {
            $attempts=@(Get-Content -LiteralPath $counter -ErrorAction Stop).Count
        }
        if($attempts -ge 1){$first=$true}
        if($attempts -ge 2){$second=$true;break}
        Start-Sleep -Milliseconds 900
    }
    if(-not $first){throw 'Disposable fake crash action did not start'}
    if(-not $second){throw 'Disposable Task Scheduler failure retry not observed within 130s'}
    Write-Host 'DISPOSABLE_FAILED_DUMMY_STARTED=PASS'
    Write-Host 'DISPOSABLE_AUTOMATIC_CRASH_RESTART_OBSERVED=PASS'
}
finally {
    # Cleanup ONLY the one unique CI-owned task and local temp folder.
    if($registered){
        $t=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
        if($null -ne $t){
            try{Stop-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop}catch{}
            Disable-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop | Out-Null
            Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false -ErrorAction Stop
        }
    }
    if(Test-Path -LiteralPath $folder -PathType Container) {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop
    }
    if($null -ne (Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue)){
        throw 'CI fake-crash task not removed'
    }
}
Write-Host 'DISPOSABLE_CRASH_TASK_CLEANUP=PASS'
Write-Host 'NO_PRODUCTION_TASK_OR_JAVA_PROCESS_USED'
