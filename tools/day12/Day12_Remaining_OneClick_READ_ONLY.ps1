[CmdletBinding()]
param([string]$OutputDir="",[switch]$Synthetic)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# This is a bounded, no-production-mutation read-only review. It intentionally
# NEVER runs completed 12.0/12.3/12.8 checks, the saturated 12.5 firewall/ACL
# collector, 12.10 native TCP/WFP scans, server restarts, 12.7 cache BUILD,
# 12.11 destructive E2E, 12.12 soak Start/End, or Stable promotion.
# Child 12.1 and 12.2 captures are not live E2E PASS.
$sourceRoot=(Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if(-not $OutputDir){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) (
    "Geumyi-Day12-Remaining-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and -not $Synthetic){
  throw "SERVER_PC_WINDOWS_ONLY"
}
# Do not accidentally run a server-side GSC/Java inventory on the SubPC.
if(-not $Synthetic){
  $hostSvc=Get-Service -Name "Geumyi Server Center Host" -ErrorAction SilentlyContinue
  if($null -eq $hostSvc){throw "SERVER_PC_HOST_SERVICE_NOT_FOUND_REFUSING_SUBPC"}
}
$reportFile=Join-Path $OutputDir "Day12-Remaining-Summary.json"
if(Test-Path -LiteralPath $reportFile -PathType Leaf){throw "REFUSE_OVERWRITE_EXISTING_REPORT"}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$phaseRows=New-Object System.Collections.ArrayList
function Row([string]$Code,[string]$Title,[string]$Status,[string]$Reason,[object]$Facts){
  [void]$phaseRows.Add([ordered]@{
    phase=$Code;name=$Title;status=$Status;next_required=$Reason;facts=$Facts
    released_to_stable=$false
  })
}
function FileJson([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
  try{return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)}
  catch{return $null}
}
function Field([object]$Obj,[string]$Name,[object]$Default=$null){
  if($null -eq $Obj){return $Default}
  $prop=$Obj.PSObject.Properties[$Name]
  if($null -eq $prop -or $null -eq $prop.Value){return $Default}
  return $prop.Value
}
function Run-ReadOnlyChild([string]$Name,[string]$Script,[string[]]$Arguments,[string]$ExpectedPhase){
  $childPath=Join-Path $PSScriptRoot $Script
  $childDir=Join-Path $OutputDir $Name
  if(-not(Test-Path -LiteralPath $childPath -PathType Leaf)){
    return [ordered]@{captured=$false;reason="COLLECTOR_NOT_PACKAGED";phase=$ExpectedPhase}
  }
  New-Item -ItemType Directory -Force -Path $childDir|Out-Null
  $args=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$childPath)+
    @($Arguments)+@("-OutputDir",$childDir)
  $code=1;$status="PROCESS_FAILURE";$record=$null
  try{
    & powershell.exe @args | Out-Host
    $code=[int]$LASTEXITCODE
    $files=@(Get-ChildItem -LiteralPath $childDir -File -Filter "*.json" -ErrorAction SilentlyContinue)
    if($files.Count -ne 1){$status="UNEXPECTED_REPORT_COUNT"}
    else{
      $record=FileJson $files[0].FullName
      if($null -eq $record){$status="INVALID_REPORT_JSON"}
      elseif([string](Field $record "phase" "") -ne $ExpectedPhase){$status="PHASE_MISMATCH"}
      elseif([bool](Field $record "synthetic" $true)){$status="CHILD_IS_SYNTHETIC"}
      elseif($code -ne 0){$status="CHILD_EXIT_NONZERO"}
      elseif([string](Field $record "result" "") -ne "CAPTURED"){$status="CHILD_NOT_CAPTURED"}
      else{$status="CAPTURED"}
    }
  }catch{$status="COLLECTION_EXCEPTION"}
  return [ordered]@{captured=($status -eq "CAPTURED");reason=$status;phase=$ExpectedPhase;exit_code=$code;data=$record}
}
function Agent-ProcessEvidence([string]$ExpectedName){
  $installed=Test-Path -LiteralPath (Join-Path (
    Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "GeumyiServerCenter\Runtime\Agent") $ExpectedName) -PathType Leaf
  $state="NOT_VERIFIABLE";$found=0;$current=0;$legacy=0
  try {
    $java=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
    $available=0
    foreach($proc in $java){
      $raw=[string](Field $proc "CommandLine" "")
      if([string]::IsNullOrWhiteSpace($raw)){continue}
      $available++
      if($raw -match '(?i)GeumyiStatusAgent-[0-9A-Za-z._-]+\.jar'){
        $found++
        if($raw.Contains($ExpectedName)){$current++}else{$legacy++}
      }
    }
    $state=if($current -gt 0 -and $legacy -eq 0){"EXPECTED_AGENT_COMMAND_FOUND"}
      elseif($legacy -gt 0){"NONCANONICAL_AGENT_LAUNCH_DETECTED"}
      elseif($java.Count -gt 0 -and $available -eq 0){"CIM_COMMAND_LINE_NOT_VISIBLE"}
      else{"NO_MATCHING_AGENT_JAVA_COMMAND"}
  }catch{$state="CIM_PROCESS_ACCESS_UNAVAILABLE"}
  # Export only aggregate counts; process paths/commands/PIDs never leave RAM.
  return [ordered]@{canonical_file_present=$installed
    agent_command_status=$state;matching_processes=$found
    expected_launches=$current;noncanonical_launches=$legacy
    expected_agent_filename_in_java_command=($state -eq "EXPECTED_AGENT_COMMAND_FOUND")
    active_agent_identity_is_proven=$false
    release_sha256_authenticity_verified=$false
    provenance_limit="Filename in JVM command line is observed; no trusted release digest or runtime loaded-JAR identity attested."
  }
}
function PolicyEvidence {
  $p=FileJson (Join-Path $sourceRoot "deploy\day12-lifecycle-policy.json")
  if($null -eq $p){return [ordered]@{readable=$false;fail_closed=$true}}
  $b=Field $p "backup";$trash=Field $p "trash"
  $safe=(([bool](Field $b "protected_exempt" $false)) -and
    ([bool](Field $b "checkpoint_exempt" $false)) -and
    ([bool](Field $b "active_transaction_exempt" $false)) -and
    [string](Field $b "apply_mode" "") -eq "trash_only" -and
    (-not [bool](Field $trash "permanent_delete_automatic" $true)))
  return [ordered]@{readable=$true;safety_flags_consistent=$safe
    approval_status=[string](Field $p "status" "MISSING")
    live_apply_executed=$false
  }
}
function CacheEvidence {
  $base=Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "GeumyiServerCenter\ArtifactCache\known-good\day12"
  $manifest=FileJson (Join-Path $base "known-good-manifest.json")
  $num=if($null -eq $manifest){0}else{@(Field $manifest "files" @()).Count}
  return [ordered]@{known_good_manifest_found=($null -ne $manifest)
    manifest_file_count=$num;offline_restart_not_performed=$true
    cache_hashes_reverified_during_this_review=$false
  }
}
function StatusOf([string]$Phase){@($phaseRows|Where-Object{$_.phase -eq $Phase})[0].status}
if($Synthetic){
  # No application requests, registry/CIM reads, child commands or network
  # operations in this branch. Contract test for the mandatory nine gates.
  foreach($item in @(
    @("12.1","Managed Content","LIVE_APPLY_E2E_REQUIRED"),
    @("12.2","Runtime Components","PROCESS_IDENTITY_REVIEW_REQUIRED"),
    @("12.4","Lifecycle Policy","POLICY_APPROVAL_REQUIRED"),
    @("12.5","Runtime Security","EFFECTIVE_ACL_FIREWALL_REVIEW_REQUIRED"),
    @("12.7","Offline Known-Good","OFFLINE_START_E2E_REQUIRED"),
    @("12.10","Backend Binding","KERNEL_OWNER_BIND_UNVERIFIED"),
    @("12.11","Final Real-Client E2E","REAL_DEVICE_E2E_REQUIRED"),
    @("12.12","Long Soak","EIGHT_HOUR_SOAK_REQUIRED"),
    @("12.13","Stable Release","RELEASE_GATES_BLOCKED")
  )){Row $item[0] $item[1] $item[2] "SYNTHETIC_TEST_ONLY" ([ordered]@{synthetic=$true})}
}else{
  $manifest=FileJson (Join-Path $sourceRoot "deploy\day12-managed-content.json")
  $enabled=0
  if($null -ne $manifest){
    $enabled=@(@(Field $manifest "resourcepacks" @())+@(Field $manifest "datapacks" @())|
      Where-Object{$null -ne $_ -and [bool](Field $_ "enabled" $false)}).Count
  }
  $content=Run-ReadOnlyChild "12.1-content" "Day12_Phase1_Content_Preflight_READ_ONLY.ps1" @(
    "-ManifestPath",(Join-Path $sourceRoot "deploy\day12-managed-content.json")) "12.1"
  Row "12.1" "Managed Content" $(if(-not $content.captured){"PREFLIGHT_CAPTURE_INCOMPLETE"}elseif($enabled -eq 0){"NOT_CONFIGURED"}else{"LIVE_APPLY_E2E_REQUIRED"}) "Requires explicit content manifest, safe apply and real Java/Bedrock proof" ([ordered]@{
    preflight_collected=$content.captured;preflight_reason=$content.reason
    enabled_managed_entries=$enabled;manifest_available=($null -ne $manifest)
    bedrock_apply_proven=$false
  })
  $inventory=Run-ReadOnlyChild "12.2-inventory" "Day12_Phase2_Component_Inventory_READ_ONLY.ps1" @() "12.2"
  $components=FileJson (Join-Path $sourceRoot "deploy\components.json")
  $agentName=[string](Field (Field (Field $components "components") "statusagent") "artifact_glob" "GeumyiStatusAgent-0.5.4.jar")
  if($agentName -notmatch '^GeumyiStatusAgent-[0-9.]+\.jar$'){$agentName="GeumyiStatusAgent-0.5.4.jar"}
  $agent=Agent-ProcessEvidence $agentName
  Row "12.2" "Runtime Components" "RUNTIME_PROVENANCE_REVIEW_REQUIRED" "Confirm GSC/StatusAgent/JAR signatures and the actual launched version" ([ordered]@{
    inventory_collected=$inventory.captured;inventory_reason=$inventory.reason
    agent=$agent;unverified_component_hash_provenance=$true
  })
  $policy=PolicyEvidence
  Row "12.4" "Lifecycle Policy" "POLICY_APPROVAL_REQUIRED" "Review safe retention rules; no backup/log Apply performed" $policy
  Row "12.5" "Runtime Security" "EFFECTIVE_ACL_FIREWALL_REVIEW_REQUIRED" "Review 04:25 firewall candidates and previous corrected ACL evidence; no duplicate scan" ([ordered]@{
    previous_20261010_firewall_candidates_reviewed=$true
    historical_distinct_tcp_or_any_allow_candidates=98
    previous_20261009_acl_5_of_5_captured=$true
    effective_security_approved=$false
  })
  $cache=CacheEvidence
  Row "12.7" "Offline Known-Good" "OFFLINE_START_E2E_REQUIRED" "Do not switch off network or restart server automatically" $cache
  Row "12.10" "Backend Binding" "KERNEL_OWNER_BIND_UNVERIFIED" "Requires an independent live socket-owner/bind proof; do not repeat the same failed TCP scans" ([ordered]@{
    operator_vantage_ipv4_lan_private_connected=0
    operator_vantage_ipv6_lan_private_connected=0
    operator_vantage_ipv4_tailnet_private_connected=0
    operator_vantage_ipv6_tailnet_private_connected=0
    gsc_tailnet_unauth_401_total=8
    evidence_basis="2026-10-10 earlier operator reports, NOT retested by this CMD"
    canonical_backend_ports_private="FAIL"
  })
  Row "12.11" "Final Real-Client E2E" "REAL_DEVICE_E2E_REQUIRED" "Human Java+Bedrock+GSCM tests; runtime reboot/actions require separate safety approval" ([ordered]@{
    java_login_proven_here=$false;bedrock_login_proven_here=$false
    gscm_on_device_proven_here=$false;reboot_performed=$false
  })
  Row "12.12" "Long Soak" "EIGHT_HOUR_SOAK_REQUIRED" "Schedule Start/End real-host snapshots for 8-12 h, separately" ([ordered]@{
    elapsed_soak_hours_during_this_review=0;soak_started=$false
  })
  $gates=FileJson (Join-Path $sourceRoot "FINAL-RELEASE-GATES.json")
  $live=Field $gates "live_gates"
  $blocks=if($null -eq $live){-1}else{@($live.PSObject.Properties|
    Where-Object{[string]$_.Value -ne "PASS"}).Count}
  Row "12.13" "Stable Release" "RELEASE_GATES_BLOCKED" "No promotion until separate validated ALL mandatory live evidence and explicit approval" ([ordered]@{
    release_manifest_readable=($null -ne $gates)
    current_manifest_status=[string](Field $gates "status" "NOT_AVAILABLE")
    nonpass_live_gate_count=$blocks
    manifest_nonpass_count_including_historical_stale_values=$blocks
    this_tool_reconciled_prior_live_pass_evidence=$false
    stable_allowed_by_this_review=$false;maintenance_allowed_by_this_review=$false
  })
}
$mandatory=@("12.1","12.2","12.4","12.5","12.7","12.10","12.11","12.12","12.13")
$actual=@($phaseRows|ForEach-Object{[string]$_.phase})
if(@($phaseRows).Count -ne $mandatory.Count -or
   @($mandatory|Where-Object{$actual -notcontains $_}).Count -gt 0 -or
   @($phaseRows|Where-Object{$_.released_to_stable}).Count -gt 0){
  throw "MISSING_MANDATORY_REMAINING_PHASE_OR_UNSAFE_RELEASE_FLAG"
}
$summary=[ordered]@{
  schema=1;tool="Day12 Remaining OneClick READ ONLY"
  generated_at=(Get-Date).ToString("o");synthetic=[bool]$Synthetic
  read_only_client=$true;production_policy_mutation=$false
  service_restart_performed=$false;firewall_acl_change_performed=$false
  world_or_golden_mutation_performed=$false;authorization_credentials_exported=$false
  raw_process_commands_or_pids_exported=$false
  collected_phase_count=$phaseRows.Count;result=$(if($Synthetic){"SYNTHETIC_CONTRACT_PASS"}else{"REVIEW_REQUIRED"})
  overall_live_completion="NOT_PROVEN";canonical_backend_ports_private="UNCHANGED_FAIL"
  stable_release_allowed=$false;maintenance_mode_allowed=$false
  phase_rows=@($phaseRows)
  notes=@(
    "No already-verified backup, whole-health, DR, LAN/Tailnet or GSC auth scans are repeated.",
    "Only Phase 12.1 and 12.2 current read-only inventory collectors run; capture is NOT live functional PASS.",
    "Phase 12.2 CIM Java command lines examined IN MEMORY only; sensitive command lines and PIDs are not exported.",
    "Additional child JSON files remain on this PC and may contain local details; share summary JSON ONLY.",
    "Phase 12.4 policy, 12.5 historical ACL/firewall and 12.7 cache are reviewed without Apply or restart.",
    "Real live Java/Bedrock client workflows, offline startup, OS socket binding and soak cannot be proven by one short CMD.",
    "Do not use this report to release Stable or change FINAL-RELEASE-GATES.json."
  )
}
$summary|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $reportFile -Encoding UTF8
Write-Host ""
Write-Host "============================================================"
Write-Host " Geumyi Day12 REMAINING 9 PHASES - READ ONLY"
Write-Host "============================================================"
foreach($row in $phaseRows){
  Write-Host ("{0,-6} {1,-31} {2}" -f $row.phase,$row.name,$row.status)
}
Write-Host ("Safe summary: "+$reportFile)
Write-Host ("Final release: BLOCKED; OS private-port kernel-owner gate unchanged.")
Write-Host "No service, firewall, ACL, Minecraft world, Golden backup or deployment changes."
exit 0
