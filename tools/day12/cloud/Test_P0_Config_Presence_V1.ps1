$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Day12_P0_Config_Presence_READ_ONLY.ps1') -FunctionsOnly
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_ONLY'}
$base=Join-Path $env:TEMP ('p0-presence-fixture-'+[guid]::NewGuid().ToString('N'))
$roles=@('wild','playground','other','lobby','gsc_state')
try {
  [void](New-Item -ItemType Directory -Path $base -ErrorAction Stop)
  $records=@()
  $hashes=@{}
  foreach($role in $roles){
    $root=Join-Path $base $role
    [void](New-Item -ItemType Directory -Path $root)
    $name=if($role -eq 'gsc_state'){'server.json'}else{'server.properties'}
    $file=Join-Path $root $name
    [IO.File]::WriteAllText($file,'TEST_ONLY_RCON_PASSWORD_00000000000000000000')
    $hashes[$role]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $records+=@{id=$role;path=$root;final_path=$root}
  }
  $ok=Build-P0PresenceReport $records
  if($ok.result -ne 'P0_PRESENCE_REVIEW_REQUIRED' -or
     $ok.paper_and_gsc_candidates.Count -ne 5 -or
     $ok.candidate_file_content_bytes_opened -ne 0 -or
     -not $ok.resolver_config_and_path_pointer_text_read_in_memory -or $ok.secret_values_exported -or
     $ok.upload_performed -or $ok.backup_created -or
     $ok.p0_backup_allowed -or $ok.stable_release_allowed){
    throw 'P0_FAIL_CLOSED_REPORT_BROKEN'
  }
  $json=$ok|ConvertTo-Json -Depth 12
  if($json.Contains($base) -or $json.Contains('TEST_ONLY_RCON_PASSWORD_')){
    throw 'P0_PRIVATE_SOURCE_LEAK'
  }
  if(($ok.reason_codes -notcontains 'THREE_VELOCITY_PROXY_ROOTS_AND_SECRETS_NOT_INVENTORIED') -or
     ($ok.reason_codes -notcontains 'CROSS_SERVER_PLUGIN_AND_RUNTIME_STATE_NOT_INVENTORIED')){
    throw 'P0_PROXY_AND_PLUGIN_GATES_MISSING'
  }
  foreach($role in $roles){
    $obj=@($ok.paper_and_gsc_candidates|Where-Object{$_.role -eq $role})
    $want=if($role -eq 'gsc_state'){'server.json'}else{'server.properties'}
    $required=@($obj[0].candidate_files|Where-Object{$_.name -eq $want})
    if($required.Count -ne 1 -or $required[0].metadata_status -ne 'LOCAL_FILE_METADATA_OBSERVED' -or
       -not $required[0].may_contain_secrets){throw 'P0_REQUIRED_PRESENCE_NOT_DETECTED'}
    $file=Join-Path (Join-Path $base $role) $want
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $hashes[$role]){
      throw 'P0_FIXTURE_MODIFIED_BY_AUDIT'
    }
  }
  $blocked=Build-P0PresenceReport @($records|Where-Object{$_.id -ne 'other'})
  if($blocked.reason_codes -notcontains 'SOURCE_ROOT_UNVERIFIED_OTHER'){
    throw 'MISSING_OTHER_NOT_REPORTED'
  }
  if((Inspect-P0Candidate (Join-Path $base 'wild') '../server.properties') -ne 'UNSAFE_RELATIVE_NAME'){
    throw 'TRAVERSAL_NOT_REFUSED'
  }
  # A nested reparse point must not be entered (no file reads).
  $junction=Join-Path (Join-Path $base 'wild') 'config'
  try {
    [void](New-Item -ItemType Junction -Path $junction -Target (Join-Path $base 'playground') -ErrorAction Stop)
    if((Inspect-P0Candidate (Join-Path $base 'wild') 'config/paper-global.yml') -ne 'NESTED_REPARSE_OR_CLOUD_PARENT_BLOCKED'){
      throw 'NESTED_REPARSE_NOT_BLOCKED'
    }
  } catch {
    if($_.Exception.Message -eq 'NESTED_REPARSE_NOT_BLOCKED'){throw}
    # A denied junction creation does not imply the production script may follow one.
    Write-Output 'P0_JUNCTION_TEST_UNAVAILABLE'
  }
  Write-Output 'P0_PRESENCE_V1_WINDOWS_DISPOSABLE_PASS'
} finally {
  if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
