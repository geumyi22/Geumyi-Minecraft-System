#requires -Version 5.1
[CmdletBinding()]
param(
 [switch]$VerifyOnly
)
# INTERACTIVE operator-only wrapper for ONE target. NEVER run in CI or on
# unattended schedule. NO auto-elevation, no remote network beyond localhost,
# no world/Paper edits. This may interrupt active Wild Java+Bedrock players.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$target='wild'
$kit=Join-Path $PSScriptRoot 'Velocity_Managed_Cutover.ps1'
$ticketFile=Join-Path $env:ProgramData 'GeumyiServerCenter\VelocityManaged\Recovery\wild.receipt.json'
$endpoint='http://127.0.0.1:8787/api/v1/velocity/managed'
function StopSafely([string]$reason){
 Write-Host ('WILD_MAINTENANCE_NO_GO: '+$reason)
 exit 1
}
try{
 if($env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true'){
  StopSafely 'INTERACTIVE_REAL_OPERATOR_ONLY'
 }
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=[Security.Principal.WindowsPrincipal]::new($identity)
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  StopSafely 'ADMINISTRATOR_REQUIRED'
 }
 # Snapshot and pinned JAR bytes must ALREADY exist and match. No re-snapshot.
 $check=(& $kit -Mode VerifyExisting -Target $target |Out-String)|ConvertFrom-Json -ErrorAction Stop
 if($check.read_only -ne $true -or
    $check.protected_original_snapshot_valid -ne $true -or
    $check.protected_manifest_matches_original -ne $true -or
    $check.task_definition_matches_original -ne $true -or
    $check.velocity_jar_sha256_matches_pin -ne $true -or
    $check.task_state -cne 'Running' -or
    $check.owner_marker_present -ne $false -or
    $check.cutover_already_committed -ne $false){
  StopSafely 'EXISTING_EVIDENCE_OR_RUNNING_TASK_NOT_READY'
 }
 Write-Host 'WILD_PROTECTED_EVIDENCE_AND_CURRENT_JAR=PASS'
 # Use host token ONLY in memory. Do not paste it into chat or command line.
 $secureToken=Read-Host -Prompt 'Existing local GSC Host API token (not echoed)' -AsSecureString
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
 try{$token=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}
 finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 if([string]::IsNullOrWhiteSpace($token)){StopSafely 'HOST_TOKEN_MISSING'}
 # Authenticated GET may succeed with AllowLoopbackNoAuth=true.
 # Validate the explicit action token BEFORE any task mutation.
 $verifier=Join-Path $PSScriptRoot 'GSC452_Host_Action_Token_Verifier.ps1'
 if(-not(Test-Path -LiteralPath $verifier -PathType Leaf)){
  StopSafely 'HOST_ACTION_TOKEN_VERIFIER_MISSING_NO_CUTOVER'
 }
 . $verifier
 if(-not(Test-GSCActualHostActionToken $token)){
  StopSafely 'HOST_ACTION_TOKEN_NOT_VERIFIED_NO_CUTOVER'
 }
 Write-Host 'WILD_EXPLICIT_HOST_ACTION_TOKEN_MATCHES_RUNNING_CONFIG=PASS'
 $headers=@{'X-GSC-Token'=$token;'Cache-Control'='no-store'}
 $status=Invoke-RestMethod -Method Get -Uri ($endpoint+'/status') -Headers $headers -TimeoutSec 20 -ErrorAction Stop
 if($status.canary_enabled -ne $true -or $status.read_only -ne $true){
  StopSafely 'GSC_HOST_CANARY_DIRECT_OWNERSHIP_NOT_ACTIVE'
 }
 # CRITICAL: production incident 2026-10-25 proved localhost Host can
 # answer managed/status with all controls false when its internal Scheduler
 # observation is UNKNOWN. Confirm that THIS running GSC Host can actually
 # observe all three legacy tasks BEFORE disabling the original Wild task.
 # Endpoint is authenticated GET only, never a live task mutation.
 $taskProbe=Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:8787/api/v1/velocity/tasks' -Headers $headers -TimeoutSec 20 -ErrorAction Stop
 if($taskProbe.ok -ne $true -or $taskProbe.read_only -ne $true -or
    $taskProbe.control_authorized -ne $false -or
    @($taskProbe.tasks).Count -ne 3){
  StopSafely 'HOST_SCHEDULER_OBSERVATION_UNTRUSTED_NO_CUTOVER'
 }
 foreach($t in @('wild','playground','other')){
  $seen=@($taskProbe.tasks|Where-Object {$_.target -ceq $t})
  if($seen.Count -ne 1 -or $seen[0].task_state -cne 'Running'){
   StopSafely 'HOST_CANNOT_PROVE_ORIGINAL_RUNNING_TASKS_NO_CUTOVER'
  }
 }
 Write-Host 'WILD_HOST_INDEPENDENT_SCHEDULER_PROBE_ALL_3_RUNNING=PASS'
 $wild=@($status.tasks|Where-Object {$_.target -ceq 'wild'})
 if(@($status.tasks).Count -ne 3 -or $wild.Count -ne 1 -or
    $wild[0].legacy_task_disabled -ne $false -or
    $wild[0].can_start -ne $false -or
    $wild[0].can_stop -ne $false -or
    $wild[0].can_restart -ne $false -or
    $wild[0].gsc_managed_running -ne $false -or
    $wild[0].recovery_required -eq $true){
  StopSafely 'GSC_HOST_EXISTING_OWNER_OR_AMBIGUOUS_TASK_STATE'
 }
 if(-not (Test-Path -LiteralPath $ticketFile -PathType Leaf)){
  StopSafely 'ORIGINAL_LOCAL_RECOVERY_TICKET_MISSING'
 }
 $receipt=Get-Content -LiteralPath $ticketFile -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 if($receipt.schema -ne 1 -or $receipt.target -cne 'wild' -or
    $receipt.ticket -notmatch '^[A-Z0-9-]{8,64}$' -or
    $receipt.cutover_committed -ne $false){
  StopSafely 'ORIGINAL_LOCAL_RECOVERY_TICKET_UNVERIFIED'
 }
 # Fleet isolation: do not risk Wild maintenance when other legacy task
 # state is abnormal. These checks are observational only.
 foreach($neighbor in @('playground','other')){
  $neighborTask=Get-ScheduledTask -TaskPath '\' -TaskName ('Geumyi Day10 Velocity '+$neighbor) -ErrorAction Stop
  if($neighborTask.State -ne 'Running' -or $neighborTask.Settings.Enabled -ne $true){
   StopSafely 'OTHER_PROXY_TASK_STATE_UNEXPECTED_NO_WILD_CUTOVER'
  }
 }
 Write-Host 'WILD_HOST_CANARY_AUTHENTICATION_AND_MIGRATION_PREREQUISITES=PASS'
 if($VerifyOnly){
  Write-Host 'WILD_EXPLICIT_TOKEN_VERIFIED_AND_PRECUTOVER_GATES=PASS_READ_ONLY'
  Write-Host 'ORIGINAL_WILD_PROXY_AND_ALL_TASKS_NOT_MODIFIED'
  return
 }
 Write-Host 'DANGER: Windows will stop the exact existing Wild Scheduler task.'
 Write-Host 'This is NOT a Velocity console-graceful shutdown; players may disconnect.'
 Write-Host 'If a legacy child JVM persists, the task remains Disabled and no GSC'
 Write-Host 'proxy will be started automatically. Separate operator recovery is needed.'
 $confirmation=Read-Host 'Type DISCONNECT WILD PLAYERS AND CUTOVER to authorize the interruption'
 if($confirmation -cne 'DISCONNECT WILD PLAYERS AND CUTOVER'){
  StopSafely 'OPERATOR_DID_NOT_APPROVE_PLAYER_DISCONNECT'
 }
 # No PID-kill, no original task XML rewrite, no other server impact.
 & $kit -Mode DrainAndCutover -Target $target -Ticket $receipt.ticket -Approved
 $after=Get-Content -LiteralPath $ticketFile -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
 if($after.cutover_committed -ne $true){
  StopSafely 'RECEIPT_NOT_COMMITTED_NO_GSC_START'
 }
 $body=@{target='wild';action='start';confirm='I_ACCEPT_VELOCITY_PLAYER_DISCONNECT'}|ConvertTo-Json -Compress
 $result=Invoke-RestMethod -Method Post -Uri ($endpoint+'/action') -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 25 -ErrorAction Stop
 if($result.ok -ne $true -or $result.gsc_owned_running -ne $true){
  StopSafely 'GSC_START_NOT_CONFIRMED_LEAVE_LEGACY_DISABLED_FOR_RECOVERY'
 }
 Write-Host 'WILD_GSC_OWNED_PROXY_LAUNCH_REQUEST=PASS'
 Write-Host 'REQUIRES_REAL_JAVA_AND_BEDROCK_CLIENT_LOGIN_E2E_BEFORE_MARKING_LIVE_COMPLETE'
} catch {
 # Never display raw host token, private ticket, command line or paths.
 Write-Host 'WILD_MAINTENANCE_BLOCKED_OR_UNCONFIRMED'
 Write-Host 'Inspect GSC owned state and both proxy ports LOCALLY before any rollback.'
 Write-Host 'DO NOT reenable the legacy task or launch another JVM blindly.'
 exit 1
} finally {
 if(Get-Variable -Name token -ErrorAction SilentlyContinue){$token=$null}
}
