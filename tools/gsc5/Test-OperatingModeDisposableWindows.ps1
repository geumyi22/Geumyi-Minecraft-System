param([Parameter(Mandatory=$true)][string]$Manager)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'This test registers disposable Windows objects and runs only on a GitHub-hosted Windows runner.'
}
$id = 'GscModeFixture' + [Guid]::NewGuid().ToString('N')
$root = [IO.Directory]::CreateDirectory((Join-Path $env:RUNNER_TEMP $id)).FullName
$inert = Join-Path $root 'GeumyiServerHost.exe'
$serviceMade = $false
$taskMade = $false
try {
    [void][Reflection.Assembly]::LoadFrom((Resolve-Path $Manager).Path)
    [IO.File]::WriteAllText($inert, 'Inert identity fixture. Never executed.')
    New-Service -Name $id -BinaryPathName ('"' + $inert + '" --service') -StartupType Manual | Out-Null
    $serviceMade = $true
    & "$env:SystemRoot\System32\sc.exe" config $id start= delayed-auto
    if ($LASTEXITCODE) { throw 'Could not configure fixture service' }
    $action = New-ScheduledTaskAction -Execute $inert
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddYears(10)
    Register-ScheduledTask -TaskName $id -Action $action -Trigger $trigger -User 'SYSTEM' -ErrorAction Stop | Out-Null
    $taskMade = $true
    $scheduler = New-Object -ComObject Schedule.Service
    $scheduler.Connect()
    $folder = $scheduler.GetFolder('\')
    $sddl = $folder.GetTask($id).GetSecurityDescriptor(7)
    $system = New-Object GmsMode.WindowsEntries(,[string[]]@($root))
    $notes = New-Object 'System.Collections.Generic.List[string]'
    $selected = @($system.Scan($notes) | Where-Object {
        $_.Eligible -and $_.Proof -eq $inert -and
        (($_.Kind -eq 'Service' -and $_.Id -eq $id) -or ($_.Kind -eq 'Task' -and $_.Id -eq "\$id"))
    })
    if ($selected.Count -ne 2) {
        $reason = @($notes | Where-Object { $_.Contains($id) }) -join '; '
        throw "Both fixture registrations must be recognized. Found $($selected.Count). $reason"
    }
    foreach ($entry in $selected) {
        if ($system.Read($entry) -cne $entry.Before) { throw 'Incorrect before-image' }
        $system.Write($entry,$entry.After)
        if ($system.Read($entry) -cne $entry.After) { throw 'Change readback failed' }
    }
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Services\$id"
    if ((Get-ItemProperty $reg).Start -ne 3 -or (Get-Service $id).Status -ne 'Stopped') { throw 'Service not in manual mode' }
    $task = $folder.GetTask($id)
    if (!$task.Enabled -or !$task.Definition.Settings.AllowDemandStart -or $task.Definition.Triggers.Item(1).Enabled) {
        throw 'Manual task start or trigger state was lost'
    }
    foreach ($entry in $selected) {
        $system.Write($entry,$entry.Before)
        if ($system.Read($entry) -cne $entry.Before) { throw 'Restore readback failed' }
    }
    $svc = Get-ItemProperty $reg
    $task = $folder.GetTask($id)
    if ($svc.Start -ne 2 -or $svc.DelayedAutoStart -ne 1 -or !$task.Definition.Triggers.Item(1).Enabled -or
        $task.GetSecurityDescriptor(7) -cne $sddl) { throw 'Restore changed the original startup policy or task ACL' }
    Write-Output 'OPERATING_MODE_REAL_SCM_AND_TASK_ROUNDTRIP_PASS'
}
finally {
    if ($taskMade) { Unregister-ScheduledTask -TaskName $id -Confirm:$false }
    if ($serviceMade) { & "$env:SystemRoot\System32\sc.exe" delete $id }
    if ([IO.File]::Exists($inert)) { [IO.File]::Delete($inert) }
    [IO.Directory]::Delete($root,$false)
}
