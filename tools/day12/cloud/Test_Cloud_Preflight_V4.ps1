[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Day12_Cloud_Recovery_Preflight_READ_ONLY.ps1') -FunctionsOnly
function Assert($Condition,[string]$Code){if(-not $Condition){throw ('V4_FIXTURE_FAILED_'+$Code)}}
function Packet($Profiles){return @{status='OK';shape='TOP_LEVEL_SERVERS';profiles=@($Profiles)}}
function EmptyPacket {return @{status='CONFIG_UNAVAILABLE';shape='NOT_PARSED';profiles=@()}}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_FIXTURES_REQUIRED'}
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('day12-v4-fixture-'+[guid]::NewGuid().ToString('N'))
$sandbox=[IO.Path]::GetFullPath($sandbox)
Assert ($sandbox.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) 'SANDBOX_BOUNDARY'
$files=New-Object Collections.ArrayList;$directories=New-Object Collections.ArrayList
$oldVariable=[Environment]::GetEnvironmentVariable('DAY12_V4_FIXTURE_ROOT')
$junction='';$sample=$null
try {
  [void](New-Item -ItemType Directory -Path $sandbox);[void]$directories.Add($sandbox)
  foreach($name in @('private-user-secret-world','cloud-a','cloud-b')){
    $p=Join-Path $sandbox $name;[void](New-Item -ItemType Directory -Path $p);[void]$directories.Add($p)
  }
  $world=Join-Path $sandbox 'private-user-secret-world'
  $marker=Join-Path $world 'server.properties'
  [IO.File]::WriteAllText($marker,'private-token-sentinel-do-not-export');[void]$files.Add($marker)
  $markerHash=(Get-FileHash -LiteralPath $marker).Hash
  [Environment]::SetEnvironmentVariable('DAY12_V4_FIXTURE_ROOT',$world)
  $pointer=Join-Path $sandbox 'private-pointer.txt'
  [IO.File]::WriteAllText($pointer,([char]0xfeff+'  "'+$world+'"'+"`r`n"),(New-Object Text.UTF8Encoding($true)))
  [void]$files.Add($pointer)
  $direct=Resolve-ServerProfile ([pscustomobject]@{path='  "%DAY12_V4_FIXTURE_ROOT%"  '})
  Assert ($direct.root.path -eq $world -and $direct.server_properties_metadata -eq 'ACCESSIBLE') 'PERCENT_ENV_QUOTES'
  foreach($value in @('$DAY12_V4_FIXTURE_ROOT','${DAY12_V4_FIXTURE_ROOT}')){
    Assert ((Resolve-ServerProfile @{path=$value}).root.path -eq $world) 'GO_ENV_EXPANSION'
  }
  Assert ((Resolve-ServerProfile @{path_file=$pointer}).root.path -eq $world) 'POINTER_BOM_UTF8_QUOTES'
  Assert ((Resolve-ServerProfile @{path_file=(Join-Path $sandbox 'missing.txt')}).pointer_status -eq 'NOT_FOUND_OR_UNAVAILABLE') 'MISSING_POINTER'
  $empty=Join-Path $sandbox 'empty.txt';[IO.File]::WriteAllText($empty,'');[void]$files.Add($empty)
  Assert ((Resolve-ServerProfile @{path_file=$empty}).root.status -eq 'EMPTY') 'EMPTY_POINTER'
  $missing=Join-Path $sandbox 'missing-world'
  $precedence=Resolve-ServerProfile @{path=$missing;path_file=$pointer}
  Assert (-not $precedence.root.path -and $precedence.pointer_status -eq 'DIRECT_PATH_PRECEDENCE') 'HOST_DIRECT_PRECEDENCE'
  Assert ((Inspect-ExactPath '%DAY12_V4_ENV_DOES_NOT_EXIST%\x').status -eq 'ENVIRONMENT_UNRESOLVED') 'UNKNOWN_ENV'
  Assert ((Inspect-ExactPath 'world').status -eq 'RELATIVE_HOST_CONTEXT_REQUIRED') 'RELATIVE_CONTEXT'
  Assert ((Inspect-ExactPath 'D:world').status -eq 'RELATIVE_HOST_CONTEXT_REQUIRED') 'DRIVE_RELATIVE_CONTEXT'
  Assert ((Inspect-ExactPath '::{private-shell-namespace}').status -eq 'RELATIVE_HOST_CONTEXT_REQUIRED') 'NAMESPACE_IS_NOT_FILESYSTEM'
  Assert ((Inspect-ExactPath $marker).status -eq 'WRONG_PATH_TYPE') 'FILE_NOT_FOLDER'
  Assert ((Inspect-ExactPath $world $false).status -eq 'WRONG_PATH_TYPE') 'FOLDER_NOT_FILE'
  $profile=[pscustomobject]@{id='wild';path=$world}
  $parsed=Parse-SettingsShape ('{"servers":[{"id":"wild","path_file":"private"}],"token":"private-token-sentinel"}'|ConvertFrom-Json)
  Assert ($parsed.status -eq 'TOP_LEVEL_SERVERS' -and $parsed.profiles.Count -eq 1) 'ACTUAL_HOST_SHAPE'
  foreach($wrapper in @('data','settings','config')){
    $wrapped=@{};$wrapped[$wrapper]=@{servers=@($profile)}
    Assert ((Parse-SettingsShape $wrapped).profiles.Count -eq 1) 'EXPLICIT_WRAPPER_COMPATIBILITY'
  }
  Assert ((Parse-SettingsShape @{servers=@($profile);data=@{servers=@($profile)}}).status -eq 'AMBIGUOUS_SERVER_LIST') 'AMBIGUOUS_SCHEMA'
  Assert ((Parse-SettingsShape @{servers='not-an-array'}).status -eq 'INVALID_SERVER_LIST') 'MALFORMED_SCHEMA'
  Assert ((Parse-SettingsShape ('{"servers":[]}'|ConvertFrom-Json)).status -eq 'TOP_LEVEL_SERVERS') 'EMPTY_LIST_SCHEMA'
  Assert ((Parse-SettingsShape @{unrelated=@{servers=@($profile)}}).status -eq 'NO_SERVER_LIST') 'NO_RECURSIVE_SCHEMA_GUESS'
  $fallback=Inspect-Sources (EmptyPacket) (Packet @($profile))
  Assert ($fallback.profiles[0].root_found -and $fallback.profiles[0].root_resolution_method -eq 'LOCAL_SETTINGS_GET') 'MISSING_CONFIG_API_FALLBACK'
  $pointerApi=Inspect-Sources (EmptyPacket) (Packet @(@{id='wild';path_file=$pointer}))
  Assert $pointerApi.profiles[0].root_found 'API_POINTER_FALLBACK'
  $denied=Inspect-Sources (EmptyPacket) @{status='API_READ_ACCESS_DENIED';shape='NOT_PARSED';profiles=@()}
  Assert (-not $denied.profiles[0].root_found) 'AUTH_DENIED_NO_BYPASS'
  $duplicate=Inspect-Sources (EmptyPacket) (Packet @($profile,$profile))
  Assert ($duplicate.profiles[0].duplicate_profile -and -not $duplicate.profiles[0].root_found) 'DUPLICATE_FAIL_CLOSED'
  $conflict=Inspect-Sources (Packet @($profile)) (Packet @(@{id='wild';path=(Join-Path $sandbox 'cloud-a')}))
  Assert ($conflict.profiles[0].config_api_path_conflict -and -not $conflict.profiles[0].root_found) 'CONFLICT_FAIL_CLOSED'
  # Disposable Windows junction: never create/remove anything at its target.
  $junction=Join-Path $sandbox 'fixture-junction'
  [void](New-Item -ItemType Junction -Path $junction -Target $world)
  $rp=Inspect-ExactPath $junction
  Assert ($rp.path -and $rp.reparse -and $rp.status -eq 'ACCESSIBLE_REPARSE') 'WINDOWS_REPARSE_SUPPORTED'
  Assert (Private-PathInside ($world+'\backup') $world) 'OVERLAP_INSIDE'
  Assert (-not (Private-PathInside ($world+'-other') $world)) 'OVERLAP_BOUNDARY'
  $all=@('wild','playground','other','lobby')|ForEach-Object{@{id=$_;path=$world}}
  $config=Packet $all;$api=Packet $all;$sources=Inspect-Sources $config $api
  $google=Inspect-ExactPath (Join-Path $sandbox 'cloud-a');$microsoft=Inspect-ExactPath (Join-Path $sandbox 'cloud-b')
  $candidates=New-Object Collections.ArrayList
  Add-PrivateCandidate $candidates $microsoft.path 'REGISTRY_SYNC_ROOT'
  Add-PrivateCandidate $candidates $microsoft.path 'ENVIRONMENT'
  Assert ($candidates.Count -eq 1) 'CANDIDATE_DEDUP'
  # Mock every OS discovery source: no real registry/account/shell reads in tests.
  $savedKnown=${function:Read-OneDriveKnownFolder};$savedShell=${function:Read-OneDriveShellRoot}
  $savedEnv=@{}
  foreach($name in @('OneDrive','OneDriveConsumer','OneDriveCommercial')){
    $savedEnv[$name]=[Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name,$null)
  }
  try {
    function Read-OneDriveKnownFolder {return $microsoft.path}
    function Read-OneDriveShellRoot {return @{status='NAMESPACE_ONLY';path=''}}
    function Get-ChildItem([string]$LiteralPath){
      if($LiteralPath -like '*OneDrive\Accounts'){
        return [pscustomobject]@{PSPath='fixture-account';PSChildName='Personal'}
      }
      if($LiteralPath -like '*SyncRootManager'){
        return [pscustomobject]@{PSPath='fixture-sync';PSChildName='OneDrive!fixture!Personal'}
      }
    }
    function Get-ItemProperty([string]$LiteralPath){
      if($LiteralPath -eq 'fixture-account'){return [pscustomobject]@{UserFolder=$microsoft.path}}
      if($LiteralPath -eq 'fixture-sync\UserSyncRoots'){return [pscustomobject]@{'fixture-user-sid'=$google.path}}
      return [pscustomobject]@{}
    }
    $discovery=Get-OneDriveCandidates
    Assert ($discovery.signals.environment -eq 'ABSENT' -and $discovery.signals.known_folder -eq 'OBSERVED' -and $discovery.signals.registry -eq 'OBSERVED') 'ONE_DRIVE_NON_ENV_DISCOVERY'
    Assert ($discovery.items.Count -eq 2 -and $discovery.signals.shell_namespace -eq 'NAMESPACE_ONLY') 'SYNC_ROOT_REGISTRY_AND_SHELL_NAMESPACE'
    function Read-OneDriveKnownFolder {return ''}
    function Get-ChildItem([string]$LiteralPath){throw 'fixture-registry-denied'}
    $discovery=Get-OneDriveCandidates
    Assert ($discovery.items.Count -eq 0 -and $discovery.signals.registry -eq 'PARTIAL_OR_UNAVAILABLE' -and $discovery.signals.shell_namespace -eq 'NAMESPACE_ONLY') 'NAMESPACE_ALONE_NOT_VERIFIED'
  } finally {
    Set-Item -LiteralPath function:Read-OneDriveKnownFolder -Value $savedKnown
    Set-Item -LiteralPath function:Read-OneDriveShellRoot -Value $savedShell
    Remove-Item -LiteralPath function:Get-ChildItem,function:Get-ItemProperty
    foreach($name in $savedEnv.Keys){[Environment]::SetEnvironmentVariable($name,$savedEnv[$name])}
  }
  $od=@{items=@($candidates.ToArray());signals=@{environment='ABSENT';known_folder='OBSERVED';registry='OBSERVED';shell_namespace='NAMESPACE_ONLY'}}
  $choice=@{method='OPERATOR_CONFIRMED_CANDIDATE';operator_confirmed=$true}
  $sample=BuildReport $config $api $sources $google $microsoft $od $choice $true $true $true $true
  Assert ($sample.result -eq 'DESTINATIONS_AND_SOURCE_DISCOVERED_REVIEW_REQUIRED' -and $sample.checks.active_server_roots_found -eq 3) 'DISCOVERY_ONLY'
  Assert ($sample.checks.onedrive_selected_path_matches_discovery -and -not $sample.checks.provider_folder_identity_proven) 'REGISTRY_IS_NOT_PROVIDER_VERIFICATION'
  $bad=BuildReport $config $api $sources $google (Inspect-ExactPath '') $od $choice $true $true $true $true
  Assert ($bad.result -eq 'BLOCKED_DISCOVERY_REVIEW_REQUIRED') 'MISSING_ONEDRIVE_BLOCKED'
  $bad=BuildReport $config $api $sources (Inspect-ExactPath $world) $microsoft $od $choice $true $true $true $true
  Assert ($bad.checks.lexical_overlap_observed -and $bad.result -eq 'BLOCKED_DISCOVERY_REVIEW_REQUIRED') 'LIVE_SOURCE_OVERLAP_BLOCKED'
  $bad=BuildReport $config $api $sources $google $google $od $choice $true $true $true $true
  Assert $bad.checks.lexical_overlap_observed 'PROVIDER_OVERLAP'
  $bad=BuildReport $config $api $sources $google $microsoft $od $choice $false $true $false $true
  Assert ($bad.result -eq 'BLOCKED_DISCOVERY_REVIEW_REQUIRED') 'CLIENT_ABSENT_BLOCKED'
  Assert ((Classify-Volume @{filesystem_reported='FAT32'}) -eq 'REPORTED_FAT32_VERIFY_ACTUAL_FILE_LIMIT_BEFORE_ARCHIVE') 'EMULATED_FAT32_NOT_PROVEN'
  foreach($key in @('provider_folder_identity_proven','actual_cloud_free_quota_verified','actual_cloud_upload_verified','cloud_backup_created','restore_test_passed','stable_release_allowed','physical_overlap_verified','live_data_loss_detected','live_data_loss_assessed')){
    Assert (-not $sample.checks[$key]) ('FALSE_CLAIM_'+$key)
  }
  $json=$sample|ConvertTo-Json -Depth 15
  foreach($private in @($sandbox,$world,$pointer,'private-user-secret-world','private-token-sentinel','C:\Users\')){
    Assert (-not $json.Contains($private) -and -not $json.Contains($private.Replace('\','\\'))) 'PRIVATE_DATA_NOT_EXPORTED'
  }
  Assert ((Get-FileHash -LiteralPath $marker).Hash -eq $markerHash) 'SOURCE_BYTES_UNCHANGED'
  # Simulate metadata-denied roots deterministically, no production ACL changes.
  $realInspect=${function:Inspect-ExactPath}
  try {
    function Inspect-ExactPath([string]$Value,[bool]$Directory=$true){return @{status='ACCESS_DENIED';path='';reparse=$false;final_target_verified=$false}}
    Assert ((Resolve-ServerProfile @{path=$world}).root.status -eq 'ACCESS_DENIED') 'DENIED_CATEGORICAL'
  } finally {Set-Item -LiteralPath function:Inspect-ExactPath -Value $realInspect}
  # The diagnostic must not introduce recursive directory scans or mutations.
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Day12_Cloud_Recovery_Preflight_READ_ONLY.ps1'),[ref]$tokens,[ref]$errors)
  Assert (@($errors).Count -eq 0) 'PARSER'
  $commands=$ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)
  foreach($cmd in $commands){
    Assert ($cmd.GetCommandName() -notin @('Copy-Item','Remove-Item','Move-Item','Set-Acl','Stop-Service','Start-Service','Restart-Service','Stop-Process','Invoke-Expression','Invoke-RestMethod')) 'MUTATION_COMMAND_ABSENT'
    if($cmd.GetCommandName() -eq 'Get-ChildItem'){
      Assert ($cmd.Extent.Text -notmatch '-Recurse') 'NO_RECURSION'
    }
  }
  Write-Host 'CLOUD_PREFLIGHT_SYNTHETIC_PASS'
  Write-Host 'CLOUD_PREFLIGHT_V4_WINDOWS_PATH_PRIVACY_PASS'
  Emit-Report $sample ''
} finally {
  [Environment]::SetEnvironmentVariable('DAY12_V4_FIXTURE_ROOT',$oldVariable)
  # Absolute, verified sandbox paths only; no recursive delete or traversal.
  if($junction -and (Test-Path -LiteralPath $junction)){[IO.Directory]::Delete($junction)}
  foreach($p in $files){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force}}
  for($i=$directories.Count-1;$i -ge 0;$i--){[IO.Directory]::Delete($directories[$i])}
}
