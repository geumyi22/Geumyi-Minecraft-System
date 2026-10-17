[CmdletBinding()]
param([switch]$Synthetic)

# GSC 4.5.2 Canary / TASK POLICY READ-ONLY. No Register/Set/Stop/Start
# ScheduledTask, no PowerShell process control, no filesystem writes except
# the ONE sanitized report in the user Desktop reports folder.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$names=@('wild','playground','other')

function GetNodeText([xml]$doc,[string]$localName,[string]$parentName) {
    $nodes=@($doc.SelectNodes("//*[local-name()='$parentName']/*[local-name()='$localName']"))
    if($nodes.Count -ne 1){ return '' }
    return [string]$nodes[0].InnerText
}
function SafePolicy([string]$candidate) {
    if ($candidate -cin @('IgnoreNew','Queue','Parallel','StopExisting')){return $candidate}
    return 'UNKNOWN'
}
function NewRecord([string]$id) {
    return [ordered]@{
        id=$id
        task_present=$false
        task_count=[int]0
        task_definition_matches_expected=$false
        task_state='UNVERIFIED'
        restart_policy_verified=$false
        restart_count=[int]0
        automatic_restart_configured=$false
        multiple_instance_policy='UNKNOWN'
        task_to_jvm_identity_verified=$false
        live_control_authorized=$false
        result='UNVERIFIED'
    }
}

$report=[ordered]@{
    schema=1
    kind='GEUMYI_GSC_452_VELOCITY_TASK_RESTART_POLICY'
    synthetic=[bool]$Synthetic
    collected_at_utc=[DateTimeOffset]::UtcNow.ToString('o')
    server_state_changed=$false
    scheduled_task_modified=$false
    read_only=$true
    live_control_authorized=$false
    result='UNVERIFIED'
    instances=@()
}

if($Synthetic) {
    foreach($id in $names){
        $fake=NewRecord $id
        $fake.task_present=$true
        $fake.task_count=1
        $fake.task_definition_matches_expected=$true
        $fake.task_state='Running'
        $fake.restart_policy_verified=$true
        $fake.restart_count=999
        $fake.automatic_restart_configured=$true
        $fake.multiple_instance_policy='IgnoreNew'
        $fake.result='AUTO_RESTART_RISK_SIMULATED_NOT_LIVE'
        $report.instances+= $fake
    }
    $report.result='SYNTHETIC_AUTO_RESPAWN_RISK_NOT_LIVE'
    $report|ConvertTo-Json -Depth 7 -Compress
    exit 0
}

foreach($id in $names) {
    $entry=NewRecord $id
    $taskName='Geumyi Day10 Velocity '+$id
    $tasks=@()
    try {
        $tasks=@(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.TaskPath -eq '\' })
    } catch {
        $tasks=@()
    }
    $entry.task_count=[int]$tasks.Count
    $entry.task_present=$tasks.Count -eq 1
    if($tasks.Count -eq 1) {
        try {
            $task=$tasks[0]
            $entry.task_state= if([string]$task.State -in @('Running','Ready','Disabled','Queued')){
                [string]$task.State
            }else{'UNVERIFIED'}
            $actions=@($task.Actions)
            $workingDir=[string]$env:ProgramData
            $expectedDir=Join-Path (Join-Path $workingDir 'GeumyiServerCenter\Network\FourServer') $id
            if($actions.Count -eq 1){
                $a=$actions[0]
                $entry.task_definition_matches_expected=(
                    ([IO.Path]::GetFileName([string]$a.Execute) -ieq 'java.exe') -and
                    (([string]$a.WorkingDirectory).TrimEnd('\') -ieq $expectedDir.TrimEnd('\')) -and
                    ([string]$a.Arguments -match '(?i)(?:^|\s)-jar\s+(?:"velocity\.jar"|velocity\.jar)(?:\s|$)')
                )
            }
            # Export-ScheduledTask returns XML in memory; it does NOT export a
            # file or mutate the task. Do not log this XML or any raw path.
            $rawXml=[string](Export-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop)
            if($rawXml.Length -gt 0 -and $rawXml.Length -lt 131072){
                [xml]$xml=$rawXml
                $policy=SafePolicy (GetNodeText $xml 'MultipleInstancesPolicy' 'Settings')
                $entry.multiple_instance_policy=$policy
                $countText=GetNodeText $xml 'Count' 'RestartOnFailure'
                if($countText -match '^\d{1,5}$') {
                    $count=[int]$countText
                    if($count -le 99999){
                        $entry.restart_count=$count
                        $entry.restart_policy_verified=$true
                        $entry.automatic_restart_configured=$count -gt 0
                    }
                }
                $entry.result=if(-not $entry.task_definition_matches_expected){
                    'TASK_DEFINITION_DRIFT_NO_GO'
                }elseif(-not $entry.restart_policy_verified -or $policy -eq 'UNKNOWN'){
                    'RESTART_POLICY_UNKNOWN_NO_GO'
                }elseif($entry.automatic_restart_configured){
                    'AUTO_RESTART_RISK_NO_GO'
                }else{
                    'POLICY_OBSERVED_LIVE_IDENTITY_UNVERIFIED'
                }
            }
        }catch {
            $entry.result='TASK_READ_FAILED_NO_GO'
        }
    } elseif($tasks.Count -gt 1) {
        $entry.result='AMBIGUOUS_TASK_DEFINITION_NO_GO'
    }else{
        $entry.result='TASK_NOT_FOUND_NO_GO'
    }
    $report.instances += $entry
}
$unknown=@($report.instances | Where-Object {
    $_.result -notin @('AUTO_RESTART_RISK_NO_GO','POLICY_OBSERVED_LIVE_IDENTITY_UNVERIFIED')
})
if($unknown.Count -eq 0) {
    if(@($report.instances|Where-Object{$_.automatic_restart_configured}).Count -gt 0){
        $report.result='AUTO_RESTART_RISK_PRESENT_NO_GO'
    }else{
        $report.result='TASK_POLICIES_CAPTURED_CONTROL_UNVERIFIED'
    }
}else{
    $report.result='PARTIAL_OR_UNKNOWN_TASK_POLICIES_NO_GO'
}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)){
    Write-Host 'Desktop report directory unavailable; no task state changed.'
    exit 2
}
$dir=Join-Path $desktop 'Geumyi-Velocity-ReadOnly-Reports'
[void](New-Item -ItemType Directory -Path $dir -Force)
$path=Join-Path $dir ('Velocity-TaskPolicy-READ-ONLY-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))
Write-Host ('READ-ONLY result: '+$report.result)
Write-Host ('Sanitized report: '+$path)
Write-Host 'Share only this JSON. No tasks, processes, configs, worlds, keys, or backups changed.'
