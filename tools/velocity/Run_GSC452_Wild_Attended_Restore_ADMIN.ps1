#requires -Version 5.1
[CmdletBinding()]
param()
# Manual one-target RESTORE-AND-RESTART, never automatic. Only when the GSC
# owned JVM has definitely stopped, its marker is absent and ports are free.
# This is NOT called on cutover timeout or a potentially running child.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$target='wild'
$kit=Join-Path $PSScriptRoot 'Velocity_Managed_Cutover.ps1'
$ticketFile=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged\Recovery\wild.receipt.json'
$endpoint='http://127.0.0.1:8787/api/v1/velocity/managed/status'
function Denied([string]$reason){
 Write-Host ('WILD_ROLLBACK_NO_GO: '+$reason)
 exit 1
}
try{
 if($env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true'){
  Denied 'INTERACTIVE_OPERATOR_ONLY'
 }
 $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  Denied 'ADMINISTRATOR_REQUIRED'
 }
 $check=(& $kit -Mode VerifyExisting -Target wild |Out-String)|ConvertFrom-Json -ErrorAction Stop
 if($check.read_only -ne $true -or
    $check.protected_original_snapshot_valid -ne $true -or
    $check.protected_manifest_matches_original -ne $true -or
    $check.task_definition_matches_original -ne $true -or
    $check.task_state -cne 'Disabled' -or
    $check.proxy_ports_free -ne $true -or
    $check.owner_marker_present -ne $false){
  Denied 'OLD_TASK_OR_GSC_PROCESS_NOT_QUIESCENT'
 }
 $secureToken=Read-Host -Prompt 'Existing local GSC Host API token (not echoed)' -AsSecureString
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
 try{$token=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}
 finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 if([string]::IsNullOrWhiteSpace($token)){Denied 'HOST_TOKEN_MISSING'}
 $status=Invoke-RestMethod -Method Get -Uri $endpoint -Headers @{'X-GSC-Token'=$token} -TimeoutSec 10 -ErrorAction Stop
 $wild=@($status.tasks|Where-Object {$_.target -ceq 'wild'})
 if($wild.Count -ne 1 -or $wild[0].gsc_managed_running -ne $false -or
    $wild[0].recovery_required -eq $true){
  Denied 'GSC_MAY_HAVE_ORPHAN_OR_RUNNING_JVM'
 }
 if(-not (Test-Path -LiteralPath $ticketFile -PathType Leaf)){
  Denied 'PROTECTED_TICKET_MISSING'
 }
 $receipt=Get-Content -LiteralPath $ticketFile -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 if($receipt.schema -ne 1 -or $receipt.target -cne 'wild' -or
    $receipt.ticket -notmatch '^[A-Z0-9-]{8,64}$'){
  Denied 'PROTECTED_RECEIPT_INVALID'
 }
 Write-Host 'Original Wild task XML and ports verified; no GSC owned instance reported.'
 Write-Host 'Restore original task to Ready and request its original Java action start?'
 $confirmation=Read-Host 'Type RESTORE ORIGINAL WILD TASK to authorize'
 if($confirmation -cne 'RESTORE ORIGINAL WILD TASK'){Denied 'NOT_CONFIRMED'}
 & $kit -Mode Rollback -Target wild -Ticket $receipt.ticket -Approved
 if([string](Get-ScheduledTask -TaskPath '\' -TaskName 'Geumyi Day10 Velocity wild').State -ne 'Ready'){
  Denied 'ROLLBACK_REENABLE_UNCONFIRMED'
 }
 # Existing task XML and Count=999 policy remain untouched. Start its EXACT
 # original action only after Rollback succeeded; never start any Paper server.
 Start-ScheduledTask -TaskPath '\' -TaskName 'Geumyi Day10 Velocity wild' -ErrorAction Stop
 Write-Host 'WILD_ORIGINAL_TASK_REENABLED_AND_START_REQUESTED'
 Write-Host 'VERIFY_JAVA_BEDROCK_CLIENT_LOGIN_AND_PROXY_LOGS_BEFORE_CONFIRMING_RECOVERY'
}catch{
 Write-Host 'WILD_ROLLBACK_FAILED_OR_UNCONFIRMED_NO_MORE_AUTOMATIC_ACTIONS'
 Write-Host 'Do not manually launch duplicate JVMs or enable other servers.'
 exit 1
}finally{
 if(Get-Variable -Name token -ErrorAction SilentlyContinue){$token=$null}
}
