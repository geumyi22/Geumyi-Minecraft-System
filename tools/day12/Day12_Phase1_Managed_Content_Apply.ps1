[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ManifestPath,
  [string]$OutputDir="",
  [string]$Confirm="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-Sha1([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA1).Hash.ToLowerInvariant()}
function Write-AtomicText([string]$Path,[string]$Text){
  $tmp=$Path+".day12-new"
  [IO.File]::WriteAllText($tmp,$Text,(New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Set-PropertyLine([string]$Text,[string]$Key,[string]$Value){
  $lines=$Text -split "\r?\n";$done=$false
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match ("^"+[regex]::Escape($Key)+"=")){
      $lines[$i]=$Key+"="+$Value;$done=$true
    }
  }
  if(-not $done){$lines += ($Key+"="+$Value)}
  return ($lines -join [Environment]::NewLine)
}
function Test-PackZip([string]$Path,[string]$Kind){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z=[IO.Compression.ZipFile]::OpenRead($Path)
  try{
    $names=@($z.Entries|ForEach-Object{$_.FullName.Replace("\","/")})
    if($names -notcontains "pack.mcmeta"){throw "pack.mcmeta missing"}
    if($Kind -eq "datapack" -and @($names|Where-Object{$_ -like "data/*"}).Count -eq 0){throw "data/ content missing"}
  }finally{$z.Dispose()}
}
function Save-Transaction([string]$Root,[object]$Entries,[string]$State){
  [ordered]@{
    schema=1
    phase="12.1"
    state=$State
    updated_at=(Get-Date).ToString("o")
    entries=@($Entries)
  }|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $Root "transaction.json") -Encoding UTF8
}
function Undo-Entries([object[]]$Entries){
  $errors=New-Object System.Collections.ArrayList
  for($i=$Entries.Count-1;$i -ge 0;$i--){
    $e=$Entries[$i]
    try{
      if([string]$e.kind -eq "java_resourcepack"){
        if(-not(Test-Path -LiteralPath ([string]$e.backup_path) -PathType Leaf)){throw "properties backup missing"}
        Copy-Item -LiteralPath ([string]$e.backup_path) -Destination ([string]$e.target_path) -Force
      }elseif([string]$e.kind -eq "datapack"){
        if([bool]$e.target_existed){
          if(-not(Test-Path -LiteralPath ([string]$e.backup_path) -PathType Leaf)){throw "datapack backup missing"}
          Copy-Item -LiteralPath ([string]$e.backup_path) -Destination ([string]$e.target_path) -Force
        }else{
          if(Test-Path -LiteralPath ([string]$e.target_path) -PathType Leaf){
            Remove-Item -LiteralPath ([string]$e.target_path) -Force
          }
        }
      }
    }catch{
      [void]$errors.Add([ordered]@{id=[string]$e.id;error=[string]$_.Exception.Message})
    }
  }
  return @($errors)
}


# Fail closed before creating a transaction or touching any server content.
function Test-ManagedManifest([object]$Manifest){
  if($null -eq $Manifest -or [int]$Manifest.schema -ne 1){throw "MANIFEST_SCHEMA_INVALID"}
  if($null -eq $Manifest.resourcepacks -or $null -eq $Manifest.datapacks){throw "MANIFEST_COLLECTION_MISSING"}
  $ids=@{}
  $javaTargets=@{}
  $datapackTargets=@{}
  $checked=0
  $enabled=@(@($Manifest.resourcepacks)+@($Manifest.datapacks)|Where-Object{[bool]$_.enabled})
  foreach($x in $enabled){
    $id=[string]$x.id
    $server=[string]$x.server_id
    $kind=[string]$x.kind
    if([string]::IsNullOrWhiteSpace($id) -or $ids.ContainsKey($id)){throw "MANAGED_ID_EMPTY_OR_DUPLICATE"}
    $ids[$id]=$true
    if($server -notin @("wild","playground","other","lobby")){throw "UNKNOWN_MANAGED_SERVER"}
    if($kind -notin @("java_resourcepack","datapack")){throw "UNSUPPORTED_MANAGED_KIND"}
    if([string]$x.expected_sha256 -notmatch '^[0-9a-fA-F]{64} ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase1"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase1-ContentApply-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")


if($Synthetic){
  # Synthetic rejects dangerous configurations, without accessing operator server.
  $reference=[pscustomobject]@{schema=1;resourcepacks=@([pscustomobject]@{
    enabled=$true;id="wild-pack";server_id="wild";kind="java_resourcepack"
    expected_sha256=("a"*64);expected_sha1=("b"*40)
    source_zip="C:\\ci-only\\pack.zip";public_url="https://example.invalid/pack.zip"
  });datapacks=@()}
  if((Test-ManagedManifest $reference) -ne 1){throw "MANIFEST_VALID_FIXTURE_FAILED"}
  foreach($case in @("missing_sha","missing_sha1","duplicate_id","duplicate_target","non_https","unknown_kind")){
    $b=$reference|ConvertTo-Json -Depth 8|ConvertFrom-Json
    switch($case){
      "missing_sha"{$b.resourcepacks[0].expected_sha256=""}
      "missing_sha1"{$b.resourcepacks[0].expected_sha1=""}
      "duplicate_id"{$b.resourcepacks=@($b.resourcepacks[0],$b.resourcepacks[0])}
      "duplicate_target"{$b.resourcepacks=@($b.resourcepacks[0],$b.resourcepacks[0]);$b.resourcepacks[1].id="other-id"}
      "non_https"{$b.resourcepacks[0].public_url="http://example.invalid/pack.zip"}
      "unknown_kind"{$b.resourcepacks[0].kind="untrusted"}
    }
    $blocked=$false
    try{$null=Test-ManagedManifest $b}catch{$blocked=$true}
    if(-not $blocked){throw "UNSAFE_MANAGED_MANIFEST_ACCEPTED_$case"}
  }
  $dp=[pscustomobject]@{schema=1;resourcepacks=@();datapacks=@([pscustomobject]@{
    enabled=$true;id="dp";server_id="wild";kind="datapack"
    expected_sha256=("c"*64);source_zip="C:\\ci-only\\safe.zip";target_file="safe.zip"
  })}
  if((Test-ManagedManifest $dp) -ne 1){throw "DATAPACK_FIXTURE_FAILED"}
  $dp.datapacks[0].target_file="../escape.zip"
  $blocked=$false;try{$null=Test-ManagedManifest $dp}catch{$blocked=$true}
  if(-not $blocked){throw "UNSAFE_DATAPACK_PATH_ACCEPTED"}
  $tmpRoot=Join-Path $env:TEMP ("Geumyi-Day12-Content-"+[guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmpRoot|Out-Null
  try{
    $target=Join-Path $tmpRoot "server.properties"
    $backup=Join-Path $tmpRoot "server.properties.before"
    [IO.File]::WriteAllText($target,"level-name=world"+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    Copy-Item $target $backup
    $text=Set-PropertyLine (Get-Content $target -Raw) "resource-pack-sha1" ("a"*40)
    Write-AtomicText $target $text
    $entries=@([pscustomobject]@{id="synthetic";kind="java_resourcepack";target_path=$target;backup_path=$backup;target_existed=$true})
    $changed=(Get-Content $target -Raw) -match "resource-pack-sha1="
    $undo=@(Undo-Entries $entries)
    $restored=((Get-Content $target -Raw) -notmatch "resource-pack-sha1=")
    $pass=$changed -and $restored -and $undo.Count -eq 0
    [ordered]@{
      schema=1;phase="12.1-apply";synthetic=$true
      result=$(if($pass){"SYNTHETIC_PASS"}else{"FAIL"})
      apply_test=$changed;rollback_test=$restored;rollback_errors=$undo
      production_files_touched=$false
    }|ConvertTo-Json -Depth 8|Set-Content $out -Encoding UTF8
    if(-not$pass){exit 2}
  }finally{
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host "SYNTHETIC APPLY + ROLLBACK PASS"
  exit 0
}

if($Confirm -ne "APPLY_DAY12_MANAGED_CONTENT"){
  Write-Host "[BLOCKED] -Confirm APPLY_DAY12_MANAGED_CONTENT required"
  exit 23
}

$m=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$null=Test-ManagedManifest $m

$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root=Join-Path $pd "GeumyiServerCenter"
$configPath=Join-Path $root "server.json"
if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw "server.json missing"}
$cfg=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json

$targets=@(@($m.resourcepacks)+@($m.datapacks)|Where-Object{[bool]$_.enabled})
if($targets.Count -eq 0){throw "No enabled managed-content entries"}
$serverIds=@($targets|ForEach-Object{[string]$_.server_id}|Select-Object -Unique)

try{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/status" -TimeoutSec 15}
catch{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/status" -TimeoutSec 15}
$online=@($status.servers|Where-Object{$serverIds -contains [string]$_.id -and [bool]$_.online})
if($online.Count -gt 0){throw ("Target servers must be OFFLINE: "+(($online|ForEach-Object{$_.id})-join ","))}

$txRoot=Join-Path $root ("ContentTransactions\"+(Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $txRoot|Out-Null
$entries=New-Object System.Collections.ArrayList
$steps=New-Object System.Collections.ArrayList
Save-Transaction $txRoot @($entries) "preflight"

$result=""
$failure=""
$rollbackErrors=@()

try{
  foreach($x in $targets){
    $sid=[string]$x.server_id
    $server=@($cfg.servers|Where-Object{[string]$_.id -eq $sid}|Select-Object -First 1)
    if($server.Count -ne 1){throw "Unknown server: $sid"}
    $dir=[string]$server[0].path
    $src=[string]$x.source_zip
    if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "Source missing: $src"}

    $kind=[string]$x.kind
    Test-PackZip $src $kind
    $sha=Get-Sha256 $src
    if($sha -ne ([string]$x.expected_sha256).ToLowerInvariant()){
      throw "SHA-256 mismatch: $($x.id)"
    }

    $bdir=Join-Path $txRoot $sid
    New-Item -ItemType Directory -Force -Path $bdir|Out-Null

    if($kind -eq "java_resourcepack"){
      if(-not([string]$x.public_url -match '^https://')){throw "HTTPS public_url required: $($x.id)"}
      $sha1=Get-Sha1 $src
      if($sha1 -ne ([string]$x.expected_sha1).ToLowerInvariant()){
        throw "SHA-1 mismatch: $($x.id)"
      }
      $props=Join-Path $dir "server.properties"
      if(-not(Test-Path -LiteralPath $props -PathType Leaf)){throw "server.properties missing: $sid"}
      $backup=Join-Path $bdir "server.properties.before"
      Copy-Item -LiteralPath $props -Destination $backup -Force

      $entry=[pscustomobject]@{
        id=[string]$x.id;server_id=$sid;kind="java_resourcepack"
        target_path=$props;backup_path=$backup;target_existed=$true
      }
      [void]$entries.Add($entry)
      Save-Transaction $txRoot @($entries) "applying"

      $text=Get-Content -LiteralPath $props -Raw
      $text=Set-PropertyLine $text "resource-pack" ([string]$x.public_url)
      $text=Set-PropertyLine $text "resource-pack-sha1" $sha1
      if([string]$x.resource_pack_id){
        $text=Set-PropertyLine $text "resource-pack-id" ([string]$x.resource_pack_id)
      }
      Write-AtomicText $props $text
      [void]$steps.Add([ordered]@{
        id=[string]$x.id;server_id=$sid;kind=$kind;pass=$true
        sha256=$sha;sha1=$sha1
      })
    }elseif($kind -eq "datapack"){
      $props=Join-Path $dir "server.properties"
      $level="world"
      foreach($line in Get-Content -LiteralPath $props -ErrorAction Stop){
        if($line -match '^level-name=(.+)$'){$level=$Matches[1].Trim()}
      }
      $datapackDir=Join-Path $dir ($level+"\datapacks")
      New-Item -ItemType Directory -Force -Path $datapackDir|Out-Null
      $name=[string]$x.target_file
      if([string]::IsNullOrWhiteSpace($name)){$name=[IO.Path]::GetFileName($src)}
      if([IO.Path]::GetFileName($name) -ne $name -or -not $name.ToLowerInvariant().EndsWith(".zip")){
        throw "unsafe target_file: $name"
      }
      $dst=Join-Path $datapackDir $name
      $existed=Test-Path -LiteralPath $dst -PathType Leaf
      $backup=Join-Path $bdir ($name+".before")
      if($existed){Copy-Item -LiteralPath $dst -Destination $backup -Force}

      $entry=[pscustomobject]@{
        id=[string]$x.id;server_id=$sid;kind="datapack"
        target_path=$dst;backup_path=$backup;target_existed=$existed
      }
      [void]$entries.Add($entry)
      Save-Transaction $txRoot @($entries) "applying"

      $staged=$dst+".day12-new"
      Copy-Item -LiteralPath $src -Destination $staged -Force
      if((Get-Sha256 $staged) -ne $sha){throw "staged datapack hash mismatch"}
      Move-Item -LiteralPath $staged -Destination $dst -Force
      [void]$steps.Add([ordered]@{
        id=[string]$x.id;server_id=$sid;kind=$kind;pass=$true
        file=$name;sha256=$sha
      })
    }else{
      throw "Unsupported live apply kind: $kind"
    }
  }

  Save-Transaction $txRoot @($entries) "applied_pending_restart_e2e"
  $result="APPLIED_PENDING_RESTART_E2E"
}catch{
  $failure=[string]$_.Exception.Message
  $rollbackErrors=@(Undo-Entries @($entries))
  if($rollbackErrors.Count -eq 0){
    Save-Transaction $txRoot @($entries) "failed_rolled_back"
    $result="FAILED_ROLLED_BACK"
  }else{
    Save-Transaction $txRoot @($entries) "failed_rollback_incomplete"
    $result="FAILED_ROLLBACK_INCOMPLETE"
  }
  [void]$steps.Add([ordered]@{pass=$false;error=$failure})
}

$report=[ordered]@{
  schema=1
  phase="12.1-apply"
  generated_at=(Get-Date).ToString("o")
  result=$result
  transaction_root=$txRoot
  steps=@($steps)
  rollback=[ordered]@{
    attempted=($result -like "FAILED*")
    errors=@($rollbackErrors)
  }
  servers_started_or_stopped=$false
  bedrock_geyser_apply_performed=$false
}
$report|ConvertTo-Json -Depth 12|Set-Content $out -Encoding UTF8
Write-Host ("RESULT: "+$result)
if($failure){Write-Host ("FAILURE: "+$failure)}
Write-Host ("REPORT: "+$out)

if($result -ne "APPLIED_PENDING_RESTART_E2E"){exit 2}
exit 0
){throw "MANDATORY_SHA256_INVALID"}
    if([string]::IsNullOrWhiteSpace([string]$x.source_zip)){throw "MANAGED_SOURCE_MISSING"}
    if($kind -eq "java_resourcepack"){
      if([string]$x.expected_sha1 -notmatch '^[0-9a-fA-F]{40} ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase1"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase1-ContentApply-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  $tmpRoot=Join-Path $env:TEMP ("Geumyi-Day12-Content-"+[guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmpRoot|Out-Null
  try{
    $target=Join-Path $tmpRoot "server.properties"
    $backup=Join-Path $tmpRoot "server.properties.before"
    [IO.File]::WriteAllText($target,"level-name=world"+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    Copy-Item $target $backup
    $text=Set-PropertyLine (Get-Content $target -Raw) "resource-pack-sha1" ("a"*40)
    Write-AtomicText $target $text
    $entries=@([pscustomobject]@{id="synthetic";kind="java_resourcepack";target_path=$target;backup_path=$backup;target_existed=$true})
    $changed=(Get-Content $target -Raw) -match "resource-pack-sha1="
    $undo=@(Undo-Entries $entries)
    $restored=((Get-Content $target -Raw) -notmatch "resource-pack-sha1=")
    $pass=$changed -and $restored -and $undo.Count -eq 0
    [ordered]@{
      schema=1;phase="12.1-apply";synthetic=$true
      result=$(if($pass){"SYNTHETIC_PASS"}else{"FAIL"})
      apply_test=$changed;rollback_test=$restored;rollback_errors=$undo
      production_files_touched=$false
    }|ConvertTo-Json -Depth 8|Set-Content $out -Encoding UTF8
    if(-not$pass){exit 2}
  }finally{
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host "SYNTHETIC APPLY + ROLLBACK PASS"
  exit 0
}

if($Confirm -ne "APPLY_DAY12_MANAGED_CONTENT"){
  Write-Host "[BLOCKED] -Confirm APPLY_DAY12_MANAGED_CONTENT required"
  exit 23
}

$m=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if([int]$m.schema -ne 1){throw "unsupported manifest schema"}

$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root=Join-Path $pd "GeumyiServerCenter"
$configPath=Join-Path $root "server.json"
if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw "server.json missing"}
$cfg=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json

$targets=@(@($m.resourcepacks)+@($m.datapacks)|Where-Object{[bool]$_.enabled})
if($targets.Count -eq 0){throw "No enabled managed-content entries"}
$serverIds=@($targets|ForEach-Object{[string]$_.server_id}|Select-Object -Unique)

try{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/status" -TimeoutSec 15}
catch{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/status" -TimeoutSec 15}
$online=@($status.servers|Where-Object{$serverIds -contains [string]$_.id -and [bool]$_.online})
if($online.Count -gt 0){throw ("Target servers must be OFFLINE: "+(($online|ForEach-Object{$_.id})-join ","))}

$txRoot=Join-Path $root ("ContentTransactions\"+(Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $txRoot|Out-Null
$entries=New-Object System.Collections.ArrayList
$steps=New-Object System.Collections.ArrayList
Save-Transaction $txRoot @($entries) "preflight"

$result=""
$failure=""
$rollbackErrors=@()

try{
  foreach($x in $targets){
    $sid=[string]$x.server_id
    $server=@($cfg.servers|Where-Object{[string]$_.id -eq $sid}|Select-Object -First 1)
    if($server.Count -ne 1){throw "Unknown server: $sid"}
    $dir=[string]$server[0].path
    $src=[string]$x.source_zip
    if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "Source missing: $src"}

    $kind=[string]$x.kind
    Test-PackZip $src $kind
    $sha=Get-Sha256 $src
    if([string]$x.expected_sha256 -and $sha -ne ([string]$x.expected_sha256).ToLowerInvariant()){
      throw "SHA-256 mismatch: $($x.id)"
    }

    $bdir=Join-Path $txRoot $sid
    New-Item -ItemType Directory -Force -Path $bdir|Out-Null

    if($kind -eq "java_resourcepack"){
      if(-not([string]$x.public_url -match '^https://')){throw "HTTPS public_url required: $($x.id)"}
      $sha1=Get-Sha1 $src
      if([string]$x.expected_sha1 -and $sha1 -ne ([string]$x.expected_sha1).ToLowerInvariant()){
        throw "SHA-1 mismatch: $($x.id)"
      }
      $props=Join-Path $dir "server.properties"
      if(-not(Test-Path -LiteralPath $props -PathType Leaf)){throw "server.properties missing: $sid"}
      $backup=Join-Path $bdir "server.properties.before"
      Copy-Item -LiteralPath $props -Destination $backup -Force

      $entry=[pscustomobject]@{
        id=[string]$x.id;server_id=$sid;kind="java_resourcepack"
        target_path=$props;backup_path=$backup;target_existed=$true
      }
      [void]$entries.Add($entry)
      Save-Transaction $txRoot @($entries) "applying"

      $text=Get-Content -LiteralPath $props -Raw
      $text=Set-PropertyLine $text "resource-pack" ([string]$x.public_url)
      $text=Set-PropertyLine $text "resource-pack-sha1" $sha1
      if([string]$x.resource_pack_id){
        $text=Set-PropertyLine $text "resource-pack-id" ([string]$x.resource_pack_id)
      }
      Write-AtomicText $props $text
      [void]$steps.Add([ordered]@{
        id=[string]$x.id;server_id=$sid;kind=$kind;pass=$true
        sha256=$sha;sha1=$sha1
      })
    }elseif($kind -eq "datapack"){
      $props=Join-Path $dir "server.properties"
      $level="world"
      foreach($line in Get-Content -LiteralPath $props -ErrorAction Stop){
        if($line -match '^level-name=(.+)$'){$level=$Matches[1].Trim()}
      }
      $datapackDir=Join-Path $dir ($level+"\datapacks")
      New-Item -ItemType Directory -Force -Path $datapackDir|Out-Null
      $name=[string]$x.target_file
      if([string]::IsNullOrWhiteSpace($name)){$name=[IO.Path]::GetFileName($src)}
      if([IO.Path]::GetFileName($name) -ne $name -or -not $name.ToLowerInvariant().EndsWith(".zip")){
        throw "unsafe target_file: $name"
      }
      $dst=Join-Path $datapackDir $name
      $existed=Test-Path -LiteralPath $dst -PathType Leaf
      $backup=Join-Path $bdir ($name+".before")
      if($existed){Copy-Item -LiteralPath $dst -Destination $backup -Force}

      $entry=[pscustomobject]@{
        id=[string]$x.id;server_id=$sid;kind="datapack"
        target_path=$dst;backup_path=$backup;target_existed=$existed
      }
      [void]$entries.Add($entry)
      Save-Transaction $txRoot @($entries) "applying"

      $staged=$dst+".day12-new"
      Copy-Item -LiteralPath $src -Destination $staged -Force
      if((Get-Sha256 $staged) -ne $sha){throw "staged datapack hash mismatch"}
      Move-Item -LiteralPath $staged -Destination $dst -Force
      [void]$steps.Add([ordered]@{
        id=[string]$x.id;server_id=$sid;kind=$kind;pass=$true
        file=$name;sha256=$sha
      })
    }else{
      throw "Unsupported live apply kind: $kind"
    }
  }

  Save-Transaction $txRoot @($entries) "applied_pending_restart_e2e"
  $result="APPLIED_PENDING_RESTART_E2E"
}catch{
  $failure=[string]$_.Exception.Message
  $rollbackErrors=@(Undo-Entries @($entries))
  if($rollbackErrors.Count -eq 0){
    Save-Transaction $txRoot @($entries) "failed_rolled_back"
    $result="FAILED_ROLLED_BACK"
  }else{
    Save-Transaction $txRoot @($entries) "failed_rollback_incomplete"
    $result="FAILED_ROLLBACK_INCOMPLETE"
  }
  [void]$steps.Add([ordered]@{pass=$false;error=$failure})
}

$report=[ordered]@{
  schema=1
  phase="12.1-apply"
  generated_at=(Get-Date).ToString("o")
  result=$result
  transaction_root=$txRoot
  steps=@($steps)
  rollback=[ordered]@{
    attempted=($result -like "FAILED*")
    errors=@($rollbackErrors)
  }
  servers_started_or_stopped=$false
  bedrock_geyser_apply_performed=$false
}
$report|ConvertTo-Json -Depth 12|Set-Content $out -Encoding UTF8
Write-Host ("RESULT: "+$result)
if($failure){Write-Host ("FAILURE: "+$failure)}
Write-Host ("REPORT: "+$out)

if($result -ne "APPLIED_PENDING_RESTART_E2E"){exit 2}
exit 0
){throw "MANDATORY_JAVA_SHA1_INVALID"}
      if([string]$x.public_url -notmatch '^https://[^/\s]+/'){throw "JAVA_PACK_PUBLIC_HTTPS_URL_REQUIRED"}
      if($javaTargets.ContainsKey($server)){throw "MULTIPLE_JAVA_PACK_PROPERTY_WRITERS"}
      $javaTargets[$server]=$true
    }else{
      $target=[string]$x.target_file
      if($target -eq ""){$target=[IO.Path]::GetFileName([string]$x.source_zip)}
      if($target -eq "." -or $target -eq ".." -or [IO.Path]::GetFileName($target) -ne $target -or
         $target -notmatch '(?i)^[^/:\\]+\.zip ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase1"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase1-ContentApply-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  $tmpRoot=Join-Path $env:TEMP ("Geumyi-Day12-Content-"+[guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmpRoot|Out-Null
  try{
    $target=Join-Path $tmpRoot "server.properties"
    $backup=Join-Path $tmpRoot "server.properties.before"
    [IO.File]::WriteAllText($target,"level-name=world"+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    Copy-Item $target $backup
    $text=Set-PropertyLine (Get-Content $target -Raw) "resource-pack-sha1" ("a"*40)
    Write-AtomicText $target $text
    $entries=@([pscustomobject]@{id="synthetic";kind="java_resourcepack";target_path=$target;backup_path=$backup;target_existed=$true})
    $changed=(Get-Content $target -Raw) -match "resource-pack-sha1="
    $undo=@(Undo-Entries $entries)
    $restored=((Get-Content $target -Raw) -notmatch "resource-pack-sha1=")
    $pass=$changed -and $restored -and $undo.Count -eq 0
    [ordered]@{
      schema=1;phase="12.1-apply";synthetic=$true
      result=$(if($pass){"SYNTHETIC_PASS"}else{"FAIL"})
      apply_test=$changed;rollback_test=$restored;rollback_errors=$undo
      production_files_touched=$false
    }|ConvertTo-Json -Depth 8|Set-Content $out -Encoding UTF8
    if(-not$pass){exit 2}
  }finally{
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host "SYNTHETIC APPLY + ROLLBACK PASS"
  exit 0
}

if($Confirm -ne "APPLY_DAY12_MANAGED_CONTENT"){
  Write-Host "[BLOCKED] -Confirm APPLY_DAY12_MANAGED_CONTENT required"
  exit 23
}

$m=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if([int]$m.schema -ne 1){throw "unsupported manifest schema"}

$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root=Join-Path $pd "GeumyiServerCenter"
$configPath=Join-Path $root "server.json"
if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw "server.json missing"}
$cfg=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json

$targets=@(@($m.resourcepacks)+@($m.datapacks)|Where-Object{[bool]$_.enabled})
if($targets.Count -eq 0){throw "No enabled managed-content entries"}
$serverIds=@($targets|ForEach-Object{[string]$_.server_id}|Select-Object -Unique)

try{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/status" -TimeoutSec 15}
catch{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/status" -TimeoutSec 15}
$online=@($status.servers|Where-Object{$serverIds -contains [string]$_.id -and [bool]$_.online})
if($online.Count -gt 0){throw ("Target servers must be OFFLINE: "+(($online|ForEach-Object{$_.id})-join ","))}

$txRoot=Join-Path $root ("ContentTransactions\"+(Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $txRoot|Out-Null
$entries=New-Object System.Collections.ArrayList
$steps=New-Object System.Collections.ArrayList
Save-Transaction $txRoot @($entries) "preflight"

$result=""
$failure=""
$rollbackErrors=@()

try{
  foreach($x in $targets){
    $sid=[string]$x.server_id
    $server=@($cfg.servers|Where-Object{[string]$_.id -eq $sid}|Select-Object -First 1)
    if($server.Count -ne 1){throw "Unknown server: $sid"}
    $dir=[string]$server[0].path
    $src=[string]$x.source_zip
    if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "Source missing: $src"}

    $kind=[string]$x.kind
    Test-PackZip $src $kind
    $sha=Get-Sha256 $src
    if([string]$x.expected_sha256 -and $sha -ne ([string]$x.expected_sha256).ToLowerInvariant()){
      throw "SHA-256 mismatch: $($x.id)"
    }

    $bdir=Join-Path $txRoot $sid
    New-Item -ItemType Directory -Force -Path $bdir|Out-Null

    if($kind -eq "java_resourcepack"){
      if(-not([string]$x.public_url -match '^https://')){throw "HTTPS public_url required: $($x.id)"}
      $sha1=Get-Sha1 $src
      if([string]$x.expected_sha1 -and $sha1 -ne ([string]$x.expected_sha1).ToLowerInvariant()){
        throw "SHA-1 mismatch: $($x.id)"
      }
      $props=Join-Path $dir "server.properties"
      if(-not(Test-Path -LiteralPath $props -PathType Leaf)){throw "server.properties missing: $sid"}
      $backup=Join-Path $bdir "server.properties.before"
      Copy-Item -LiteralPath $props -Destination $backup -Force

      $entry=[pscustomobject]@{
        id=[string]$x.id;server_id=$sid;kind="java_resourcepack"
        target_path=$props;backup_path=$backup;target_existed=$true
      }
      [void]$entries.Add($entry)
      Save-Transaction $txRoot @($entries) "applying"

      $text=Get-Content -LiteralPath $props -Raw
      $text=Set-PropertyLine $text "resource-pack" ([string]$x.public_url)
      $text=Set-PropertyLine $text "resource-pack-sha1" $sha1
      if([string]$x.resource_pack_id){
        $text=Set-PropertyLine $text "resource-pack-id" ([string]$x.resource_pack_id)
      }
      Write-AtomicText $props $text
      [void]$steps.Add([ordered]@{
        id=[string]$x.id;server_id=$sid;kind=$kind;pass=$true
        sha256=$sha;sha1=$sha1
      })
    }elseif($kind -eq "datapack"){
      $props=Join-Path $dir "server.properties"
      $level="world"
      foreach($line in Get-Content -LiteralPath $props -ErrorAction Stop){
        if($line -match '^level-name=(.+)$'){$level=$Matches[1].Trim()}
      }
      $datapackDir=Join-Path $dir ($level+"\datapacks")
      New-Item -ItemType Directory -Force -Path $datapackDir|Out-Null
      $name=[string]$x.target_file
      if([string]::IsNullOrWhiteSpace($name)){$name=[IO.Path]::GetFileName($src)}
      if([IO.Path]::GetFileName($name) -ne $name -or -not $name.ToLowerInvariant().EndsWith(".zip")){
        throw "unsafe target_file: $name"
      }
      $dst=Join-Path $datapackDir $name
      $existed=Test-Path -LiteralPath $dst -PathType Leaf
      $backup=Join-Path $bdir ($name+".before")
      if($existed){Copy-Item -LiteralPath $dst -Destination $backup -Force}

      $entry=[pscustomobject]@{
        id=[string]$x.id;server_id=$sid;kind="datapack"
        target_path=$dst;backup_path=$backup;target_existed=$existed
      }
      [void]$entries.Add($entry)
      Save-Transaction $txRoot @($entries) "applying"

      $staged=$dst+".day12-new"
      Copy-Item -LiteralPath $src -Destination $staged -Force
      if((Get-Sha256 $staged) -ne $sha){throw "staged datapack hash mismatch"}
      Move-Item -LiteralPath $staged -Destination $dst -Force
      [void]$steps.Add([ordered]@{
        id=[string]$x.id;server_id=$sid;kind=$kind;pass=$true
        file=$name;sha256=$sha
      })
    }else{
      throw "Unsupported live apply kind: $kind"
    }
  }

  Save-Transaction $txRoot @($entries) "applied_pending_restart_e2e"
  $result="APPLIED_PENDING_RESTART_E2E"
}catch{
  $failure=[string]$_.Exception.Message
  $rollbackErrors=@(Undo-Entries @($entries))
  if($rollbackErrors.Count -eq 0){
    Save-Transaction $txRoot @($entries) "failed_rolled_back"
    $result="FAILED_ROLLED_BACK"
  }else{
    Save-Transaction $txRoot @($entries) "failed_rollback_incomplete"
    $result="FAILED_ROLLBACK_INCOMPLETE"
  }
  [void]$steps.Add([ordered]@{pass=$false;error=$failure})
}

$report=[ordered]@{
  schema=1
  phase="12.1-apply"
  generated_at=(Get-Date).ToString("o")
  result=$result
  transaction_root=$txRoot
  steps=@($steps)
  rollback=[ordered]@{
    attempted=($result -like "FAILED*")
    errors=@($rollbackErrors)
  }
  servers_started_or_stopped=$false
  bedrock_geyser_apply_performed=$false
}
$report|ConvertTo-Json -Depth 12|Set-Content $out -Encoding UTF8
Write-Host ("RESULT: "+$result)
if($failure){Write-Host ("FAILURE: "+$failure)}
Write-Host ("REPORT: "+$out)

if($result -ne "APPLIED_PENDING_RESTART_E2E"){exit 2}
exit 0
){throw "UNSAFE_DATAPACK_TARGET"}
      $key=$server+"|"+$target.ToLowerInvariant()
      if($datapackTargets.ContainsKey($key)){throw "DUPLICATE_DATAPACK_TARGET"}
      $datapackTargets[$key]=$true
    }
    $checked++
  }
  return $checked
}

if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase1"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase1-ContentApply-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

if($Synthetic){
  $tmpRoot=Join-Path $env:TEMP ("Geumyi-Day12-Content-"+[guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmpRoot|Out-Null
  try{
    $target=Join-Path $tmpRoot "server.properties"
    $backup=Join-Path $tmpRoot "server.properties.before"
    [IO.File]::WriteAllText($target,"level-name=world"+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    Copy-Item $target $backup
    $text=Set-PropertyLine (Get-Content $target -Raw) "resource-pack-sha1" ("a"*40)
    Write-AtomicText $target $text
    $entries=@([pscustomobject]@{id="synthetic";kind="java_resourcepack";target_path=$target;backup_path=$backup;target_existed=$true})
    $changed=(Get-Content $target -Raw) -match "resource-pack-sha1="
    $undo=@(Undo-Entries $entries)
    $restored=((Get-Content $target -Raw) -notmatch "resource-pack-sha1=")
    $pass=$changed -and $restored -and $undo.Count -eq 0
    [ordered]@{
      schema=1;phase="12.1-apply";synthetic=$true
      result=$(if($pass){"SYNTHETIC_PASS"}else{"FAIL"})
      apply_test=$changed;rollback_test=$restored;rollback_errors=$undo
      production_files_touched=$false
    }|ConvertTo-Json -Depth 8|Set-Content $out -Encoding UTF8
    if(-not$pass){exit 2}
  }finally{
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host "SYNTHETIC APPLY + ROLLBACK PASS"
  exit 0
}

if($Confirm -ne "APPLY_DAY12_MANAGED_CONTENT"){
  Write-Host "[BLOCKED] -Confirm APPLY_DAY12_MANAGED_CONTENT required"
  exit 23
}

$m=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if([int]$m.schema -ne 1){throw "unsupported manifest schema"}

$pd=if($env:PROGRAMDATA){$env:PROGRAMDATA}else{"C:\ProgramData"}
$root=Join-Path $pd "GeumyiServerCenter"
$configPath=Join-Path $root "server.json"
if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw "server.json missing"}
$cfg=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json

$targets=@(@($m.resourcepacks)+@($m.datapacks)|Where-Object{[bool]$_.enabled})
if($targets.Count -eq 0){throw "No enabled managed-content entries"}
$serverIds=@($targets|ForEach-Object{[string]$_.server_id}|Select-Object -Unique)

try{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8790/api/status" -TimeoutSec 15}
catch{$status=Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/status" -TimeoutSec 15}
$online=@($status.servers|Where-Object{$serverIds -contains [string]$_.id -and [bool]$_.online})
if($online.Count -gt 0){throw ("Target servers must be OFFLINE: "+(($online|ForEach-Object{$_.id})-join ","))}

$txRoot=Join-Path $root ("ContentTransactions\"+(Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $txRoot|Out-Null
$entries=New-Object System.Collections.ArrayList
$steps=New-Object System.Collections.ArrayList
Save-Transaction $txRoot @($entries) "preflight"

$result=""
$failure=""
$rollbackErrors=@()

try{
  foreach($x in $targets){
    $sid=[string]$x.server_id
    $server=@($cfg.servers|Where-Object{[string]$_.id -eq $sid}|Select-Object -First 1)
    if($server.Count -ne 1){throw "Unknown server: $sid"}
    $dir=[string]$server[0].path
    $src=[string]$x.source_zip
    if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "Source missing: $src"}

    $kind=[string]$x.kind
    Test-PackZip $src $kind
    $sha=Get-Sha256 $src
    if([string]$x.expected_sha256 -and $sha -ne ([string]$x.expected_sha256).ToLowerInvariant()){
      throw "SHA-256 mismatch: $($x.id)"
    }

    $bdir=Join-Path $txRoot $sid
    New-Item -ItemType Directory -Force -Path $bdir|Out-Null

    if($kind -eq "java_resourcepack"){
      if(-not([string]$x.public_url -match '^https://')){throw "HTTPS public_url required: $($x.id)"}
      $sha1=Get-Sha1 $src
      if([string]$x.expected_sha1 -and $sha1 -ne ([string]$x.expected_sha1).ToLowerInvariant()){
        throw "SHA-1 mismatch: $($x.id)"
      }
      $props=Join-Path $dir "server.properties"
      if(-not(Test-Path -LiteralPath $props -PathType Leaf)){throw "server.properties missing: $sid"}
      $backup=Join-Path $bdir "server.properties.before"
      Copy-Item -LiteralPath $props -Destination $backup -Force

      $entry=[pscustomobject]@{
        id=[string]$x.id;server_id=$sid;kind="java_resourcepack"
        target_path=$props;backup_path=$backup;target_existed=$true
      }
      [void]$entries.Add($entry)
      Save-Transaction $txRoot @($entries) "applying"

      $text=Get-Content -LiteralPath $props -Raw
      $text=Set-PropertyLine $text "resource-pack" ([string]$x.public_url)
      $text=Set-PropertyLine $text "resource-pack-sha1" $sha1
      if([string]$x.resource_pack_id){
        $text=Set-PropertyLine $text "resource-pack-id" ([string]$x.resource_pack_id)
      }
      Write-AtomicText $props $text
      [void]$steps.Add([ordered]@{
        id=[string]$x.id;server_id=$sid;kind=$kind;pass=$true
        sha256=$sha;sha1=$sha1
      })
    }elseif($kind -eq "datapack"){
      $props=Join-Path $dir "server.properties"
      $level="world"
      foreach($line in Get-Content -LiteralPath $props -ErrorAction Stop){
        if($line -match '^level-name=(.+)$'){$level=$Matches[1].Trim()}
      }
      $datapackDir=Join-Path $dir ($level+"\datapacks")
      New-Item -ItemType Directory -Force -Path $datapackDir|Out-Null
      $name=[string]$x.target_file
      if([string]::IsNullOrWhiteSpace($name)){$name=[IO.Path]::GetFileName($src)}
      if([IO.Path]::GetFileName($name) -ne $name -or -not $name.ToLowerInvariant().EndsWith(".zip")){
        throw "unsafe target_file: $name"
      }
      $dst=Join-Path $datapackDir $name
      $existed=Test-Path -LiteralPath $dst -PathType Leaf
      $backup=Join-Path $bdir ($name+".before")
      if($existed){Copy-Item -LiteralPath $dst -Destination $backup -Force}

      $entry=[pscustomobject]@{
        id=[string]$x.id;server_id=$sid;kind="datapack"
        target_path=$dst;backup_path=$backup;target_existed=$existed
      }
      [void]$entries.Add($entry)
      Save-Transaction $txRoot @($entries) "applying"

      $staged=$dst+".day12-new"
      Copy-Item -LiteralPath $src -Destination $staged -Force
      if((Get-Sha256 $staged) -ne $sha){throw "staged datapack hash mismatch"}
      Move-Item -LiteralPath $staged -Destination $dst -Force
      [void]$steps.Add([ordered]@{
        id=[string]$x.id;server_id=$sid;kind=$kind;pass=$true
        file=$name;sha256=$sha
      })
    }else{
      throw "Unsupported live apply kind: $kind"
    }
  }

  Save-Transaction $txRoot @($entries) "applied_pending_restart_e2e"
  $result="APPLIED_PENDING_RESTART_E2E"
}catch{
  $failure=[string]$_.Exception.Message
  $rollbackErrors=@(Undo-Entries @($entries))
  if($rollbackErrors.Count -eq 0){
    Save-Transaction $txRoot @($entries) "failed_rolled_back"
    $result="FAILED_ROLLED_BACK"
  }else{
    Save-Transaction $txRoot @($entries) "failed_rollback_incomplete"
    $result="FAILED_ROLLBACK_INCOMPLETE"
  }
  [void]$steps.Add([ordered]@{pass=$false;error=$failure})
}

$report=[ordered]@{
  schema=1
  phase="12.1-apply"
  generated_at=(Get-Date).ToString("o")
  result=$result
  transaction_root=$txRoot
  steps=@($steps)
  rollback=[ordered]@{
    attempted=($result -like "FAILED*")
    errors=@($rollbackErrors)
  }
  servers_started_or_stopped=$false
  bedrock_geyser_apply_performed=$false
}
$report|ConvertTo-Json -Depth 12|Set-Content $out -Encoding UTF8
Write-Host ("RESULT: "+$result)
if($failure){Write-Host ("FAILURE: "+$failure)}
Write-Host ("REPORT: "+$out)

if($result -ne "APPLIED_PENDING_RESTART_E2E"){exit 2}
exit 0
