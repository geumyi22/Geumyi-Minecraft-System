[CmdletBinding()]
param(
  [string]$EvidencePath="",
  [string]$OutputDir="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Validates structured evidence ONLY. Absolutely no networking, system,
# firewall, audit, process, service or world mutations. It neither captures
# evidence nor treats self-reported booleans as independently authenticated.
function Field($Obj,[string]$Key) {
  if($null -eq $Obj){return $null}
  return $Obj.PSObject.Properties[$Key].Value
}
function BoolExactlyTrue($Obj,[string]$Key) {
  $v=Field $Obj $Key
  return ($v -is [bool] -and $v -eq $true)
}
function BoolExactlyFalse($Obj,[string]$Key) {
  $v=Field $Obj $Key
  return ($v -is [bool] -and $v -eq $false)
}
function Evaluate-Stage($Evidence) {
  $issues=[System.Collections.Generic.List[string]]::new()
  if((Field $Evidence "schema") -ne 1){$issues.Add("SCHEMA_NOT_ONE")}
  if((Field $Evidence "environment") -ne "DISPOSABLE_TWO_HOST"){
    $issues.Add("NOT_DISPOSABLE_TWO_HOST")
  }
  if(-not (BoolExactlyTrue $Evidence "explicitly_not_production")){
    $issues.Add("PRODUCTION_EXCLUSION_NOT_PROVEN")
  }
  if(-not (BoolExactlyTrue $Evidence "independent_client_host")){
    $issues.Add("SEPARATE_CLIENT_NOT_ATTESTED")
  }
  if(-not (BoolExactlyFalse $Evidence "production_modified")){
    $issues.Add("PRODUCTION_UNCHANGED_NOT_ATTESTED")
  }
  if(-not (BoolExactlyTrue $Evidence "rule_backup_created")){
    $issues.Add("RULE_BACKUP_NOT_ATTESTED")
  }
  foreach($phase in @("before","after","rollback")){
    $obj=Field $Evidence $phase
    if($null -eq $obj){
      $issues.Add("MISSING_"+$phase.ToUpperInvariant())
      continue
    }
    if(-not (BoolExactlyTrue $obj "server_process_alive")){
      $issues.Add("STAGING_SERVER_NOT_ALIVE_"+$phase.ToUpperInvariant())
    }
    if(-not (BoolExactlyTrue $obj "tcp_public_control_ok")){
      $issues.Add("PUBLIC_CONTROL_FAILED_"+$phase.ToUpperInvariant())
    }
    if(-not (BoolExactlyTrue $obj "udp_public_control_ok")){
      $issues.Add("UDP_CONTROL_UNVERIFIED_"+$phase.ToUpperInvariant())
    }
    if(-not (BoolExactlyTrue $obj "ipv4_local_loopback_ok")){
      $issues.Add("IPV4_LOOPBACK_FAILED_"+$phase.ToUpperInvariant())
    }
    if(-not (BoolExactlyTrue $obj "ipv6_local_loopback_ok")){
      $issues.Add("IPV6_LOOPBACK_FAILED_"+$phase.ToUpperInvariant())
    }
    $remoteExpected=$phase -ne "after"
    foreach($family in @("ipv4","ipv6")){
      $key=$family+"_remote_stage_port_connects"
      $expected=$remoteExpected
      $okay=if($expected){BoolExactlyTrue $obj $key}else{BoolExactlyFalse $obj $key}
      if(-not $okay){
        $issues.Add("REMOTE_"+$family.ToUpperInvariant()+"_"+$phase.ToUpperInvariant()+"_NOT_EXPECTED")
      }
    }
  }
  if(-not (BoolExactlyTrue $Evidence "created_only_owned_test_rules")){
    $issues.Add("RULE_OWNERSHIP_NOT_PROVEN")
  }
  if(-not (BoolExactlyTrue $Evidence "owned_rules_removed")){
    $issues.Add("ROLLBACK_INCOMPLETE")
  }
  $result=if($issues.Count -eq 0){"EVIDENCE_MATRIX_CONSISTENT_REVIEW_ONLY"}else{"CHECK_REQUIRED"}
  return [ordered]@{
    result=$result
    issue_codes=@($issues.ToArray())
    self_reported_evidence_only=$true
    remote_vantage_authenticated=$false
    live_minecraft_firewall_tested=$false
    current_backend_bind_owner_proven=$false
    ipv4_ipv6_matrix_required=$true
    canonical_backend_ports_private="UNCHANGED_FAIL"
    stable_promotion_allowed=$false
  }
}
if(-not $OutputDir){
  if($Synthetic){$OutputDir=Join-Path ([IO.Path]::GetTempPath()) "Geumyi-TwoHost-Review-CI"}
  else{$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-TwoHost-Review"}
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Day12-TwoHost-Evidence-Review-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  $phaseBase=[pscustomobject]@{
    server_process_alive=$true;tcp_public_control_ok=$true
    udp_public_control_ok=$true;ipv4_local_loopback_ok=$true;ipv6_local_loopback_ok=$true
    ipv4_remote_stage_port_connects=$true;ipv6_remote_stage_port_connects=$true
  }
  $after=[pscustomobject]@{
    server_process_alive=$true;tcp_public_control_ok=$true
    udp_public_control_ok=$true;ipv4_local_loopback_ok=$true;ipv6_local_loopback_ok=$true
    ipv4_remote_stage_port_connects=$false;ipv6_remote_stage_port_connects=$false
  }
  $fixture=[pscustomobject]@{
    schema=1;environment="DISPOSABLE_TWO_HOST"
    explicitly_not_production=$true
    independent_client_host=$true
    production_modified=$false
    rule_backup_created=$true
    created_only_owned_test_rules=$true
    owned_rules_removed=$true
    before=$phaseBase;after=$after;rollback=$phaseBase
  }
  $good=Evaluate-Stage $fixture
  if($good.result -ne "EVIDENCE_MATRIX_CONSISTENT_REVIEW_ONLY" -or
     -not $good.self_reported_evidence_only -or
     $good.stable_promotion_allowed -or
     $good.current_backend_bind_owner_proven -or
     $good.remote_vantage_authenticated){
    throw "TWO_HOST_SYNTHETIC_FAIL_CLOSED_BASELINE"
  }
  $after.ipv6_remote_stage_port_connects=$true
  $unsafe=Evaluate-Stage $fixture
  if($unsafe.result -ne "CHECK_REQUIRED" -or
     $unsafe.issue_codes -notcontains "REMOTE_IPV6_AFTER_NOT_EXPECTED"){
    throw "TWO_HOST_SYNTHETIC_IPV6_FAIL_OPEN"
  }
  $after.ipv6_remote_stage_port_connects=$false
  $fixture.independent_client_host=$false
  $noVantage=Evaluate-Stage $fixture
  if($noVantage.result -ne "CHECK_REQUIRED" -or
     $noVantage.issue_codes -notcontains "SEPARATE_CLIENT_NOT_ATTESTED"){
    throw "TWO_HOST_SYNTHETIC_SAME_HOST_FAIL_OPEN"
  }
  $fixture.independent_client_host=$true
  $fixture.owned_rules_removed=$false
  $badRollback=Evaluate-Stage $fixture
  if($badRollback.result -ne "CHECK_REQUIRED" -or
     $badRollback.issue_codes -notcontains "ROLLBACK_INCOMPLETE"){
    throw "TWO_HOST_SYNTHETIC_ROLLBACK_FAIL_OPEN"
  }
  $fixture.owned_rules_removed=$true
  $after.tcp_public_control_ok=$false
  $badPublic=Evaluate-Stage $fixture
  if($badPublic.result -ne "CHECK_REQUIRED" -or
     $badPublic.issue_codes -notcontains "PUBLIC_CONTROL_FAILED_AFTER"){
    throw "TWO_HOST_SYNTHETIC_PUBLIC_CONTROL_FAIL_OPEN"
  }
  [ordered]@{
    schema=1;synthetic=$true;result="SYNTHETIC_PASS"
    expected_positive_case=$good.result
    negative_cases=@("IPV6_REMAINS_ACCESSIBLE","SAME_HOST","ROLLBACK_INCOMPLETE","PUBLIC_CONTROL_DOWN")
    reads_existing_evidence_only=$true
    firewall_mutation_performed=$false
    network_probes_performed=$false
    canonical_backend_ports_private="UNCHANGED_FAIL"
  }|ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host "Two-host evidence evaluator synthetic PASS"
  exit 0
}
if([string]::IsNullOrWhiteSpace($EvidencePath)){
  throw "EXPLICIT_DISPOSABLE_TWO_HOST_EVIDENCE_FILE_REQUIRED"
}
if(-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)){throw "EVIDENCE_FILE_MISSING"}
$source=Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$review=Evaluate-Stage $source
$report=[ordered]@{
  schema=1
  synthetic=$false
  generated_at=(Get-Date).ToString("o")
  phase="12.10-two-host-offline-evidence-review"
  result=$review.result
  issue_codes=$review.issue_codes
  self_reported_evidence_only=$true
  current_backend_bind_owner_proven=$false
  remote_vantage_authenticated=$false
  stable_promotion_allowed=$false
  canonical_backend_ports_private="UNCHANGED_FAIL"
  firewall_mutation_performed=$false
  network_probes_performed=$false
  notes=@(
    "This does not collect remote network evidence; the input file is self-reported and not independently authenticated.",
    "Consistent staging matrix is only a review milestone, not production firewall isolation or exclusive loopback socket binding.",
    "No IPs, file paths, process identities or secrets are copied into the output JSON."
  )
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("Two-host evidence review: "+$review.result)
Write-Host ("Output: "+$out)
if($review.result -ne "EVIDENCE_MATRIX_CONSISTENT_REVIEW_ONLY"){exit 2}
exit 0
