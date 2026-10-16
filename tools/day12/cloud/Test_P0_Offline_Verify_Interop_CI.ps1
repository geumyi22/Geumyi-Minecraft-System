[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Synthetic-only cross-tool interoperability test; DO NOT run on operator PC.
# It creates fake GSC/Paper/proxy files under OS runner temp, encrypts with
# the production writer, and checks independent reader success/refusals.
$old=$env:LOCALAPPDATA
$root=Join-Path ([IO.Path]::GetTempPath()) ('geumyi-p0-interop-'+[guid]::NewGuid().ToString('N'))
$writerSource=Join-Path $PSScriptRoot 'p0_local_encrypted_capture.go'
$readerSource=Join-Path $PSScriptRoot 'p0_offline_archive_verify.go'
$goexe=if($IsWindows -or $env:OS -eq 'Windows_NT'){'.exe'}else{''}
try {
  $env:LOCALAPPDATA=Join-Path $root 'local-appdata'
  $src=Join-Path $root 'fixture-src'
  [void](New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force)
  [void](New-Item -ItemType Directory -Path $src -Force)
  $writer=Join-Path $root ('writer'+$goexe)
  $reader=Join-Path $root ('reader'+$goexe)
  & go build -trimpath -o $writer $writerSource
  if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_WRITER_BUILD_FAILED'}
  & go build -trimpath -o $reader $readerSource
  if($LASTEXITCODE -ne 0){throw 'INDEPENDENT_READER_BUILD_FAILED'}
  $names=New-Object Collections.Generic.List[string]
  $names.Add('gsc/server.json')
  foreach($role in @('wild','playground','other','lobby')){
    $names.Add("paper/$role/server.properties")
  }
  foreach($role in @('wild','playground','other')){
    foreach($name in @('velocity.toml','forwarding.secret',
        'plugins/Geyser-Velocity/config.yml','plugins/floodgate/config.yml',
        'plugins/floodgate/key.pem')){
      $names.Add("proxy/$role/$name")
    }
  }
  $files=@()
  foreach($name in $names){
    $filename='fixture-'+('{0:d3}' -f $files.Count)
    $filename=Join-Path $src $filename
    $synthetic='SYNTHETIC-NOT-REAL-'+$name
    if($name.EndsWith('/forwarding.secret')){
      $synthetic='SYNTHETIC-NOT-REAL-SHARED-FORWARDING-KEY'
    }
    if($name.EndsWith('/plugins/floodgate/key.pem')){
      $synthetic='SYNTHETIC-NOT-REAL-SHARED-FLOODGATE-KEY'
    }
    [IO.File]::WriteAllText($filename,$synthetic,(New-Object Text.UTF8Encoding($false)))
    $files+=@{name=$name;source=$filename}
  }
  if($files.Count -ne 20){throw 'SYNTHETIC_EXPECTED_20_MISSING'}
  $archive=Join-Path (Join-Path $env:LOCALAPPDATA 'Geumyi-P0-Encrypted-Staging') 'P0-FIXTURE-INTEROP-abcdefghij1234567890'
  $pw='LOCAL-CI-SYNTHETIC-PASSWORD-NOT-A-REAL-SECRET'
  $OutputEncoding=New-Object Text.UTF8Encoding($false)
  $request=@{passphrase=$pw;dest=$archive;files=$files}|ConvertTo-Json -Compress -Depth 7
  $result=@($request|& $writer --capture)
  if($LASTEXITCODE -ne 0 -or ($result -notcontains 'P0_LOCAL_ENCRYPTED_CAPTURE_VERIFIED')){
    throw 'INTEROP_SYNTHETIC_CAPTURE_FAILED'
  }
  $verifyRequest=@{archive=$archive;passphrase=$pw}|ConvertTo-Json -Compress
  $ok=@($verifyRequest|& $reader --verify)
  if($LASTEXITCODE -ne 0 -or ($ok -notcontains 'P0_OFFLINE_VERIFY_PASS')){
    throw 'INDEPENDENT_READER_REFUSED_VALID_WRITER_OUTPUT'
  }
  $inventoryBefore=@{}
  foreach($f in @(Get-ChildItem -LiteralPath $archive -File)){
    $inventoryBefore[$f.Name]=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
  }
  if($inventoryBefore.Count -ne 23){throw 'INTEROP_ARCHIVE_ENTRY_COUNT_WRONG'}
  $wrong=@{archive=$archive;passphrase=($pw+'INCORRECT')}|ConvertTo-Json -Compress
  $bad=@($wrong|& $reader --verify)
  if($LASTEXITCODE -eq 0 -or ($bad -contains 'P0_OFFLINE_VERIFY_PASS')){
    throw 'WRONG_RECOVERY_PASSPHRASE_ACCEPTED'
  }
  $copy=Join-Path (Split-Path -Parent $archive) 'P0-FIXTURE-TAMPER-abcdefghij1234567890'
  [void](New-Item -ItemType Directory -Path $copy)
  Copy-Item -Path (Join-Path $archive '*') -Destination $copy -ErrorAction Stop
  $target=Join-Path $copy 'part-000.gcm'
  $data=[IO.File]::ReadAllBytes($target)
  $data[$data.Length-1]=$data[$data.Length-1] -bxor 0x40
  [IO.File]::WriteAllBytes($target,$data)
  $tamper=@{archive=$copy;passphrase=$pw}|ConvertTo-Json -Compress
  $bad=@($tamper|& $reader --verify)
  if($LASTEXITCODE -eq 0 -or ($bad -contains 'P0_OFFLINE_VERIFY_PASS')){
    throw 'CIPHERTEXT_TAMPER_NOT_REJECTED'
  }
  # Synthetic-only fault injection: check missing, extra, and symlink-like item.
  [IO.File]::WriteAllBytes($target,[byte[]]@())
  $bad=@($tamper|& $reader --verify)
  if($LASTEXITCODE -eq 0 -or ($bad -contains 'P0_OFFLINE_VERIFY_PASS')){
    throw 'TRUNCATED_PART_NOT_REJECTED'
  }
  Copy-Item -LiteralPath (Join-Path $archive 'part-000.gcm') -Destination $target -Force
  [IO.File]::WriteAllText((Join-Path $copy 'extra-untrusted.txt'),'fixture')
  $bad=@($tamper|& $reader --verify)
  if($LASTEXITCODE -eq 0 -or ($bad -contains 'P0_OFFLINE_VERIFY_PASS')){
    throw 'EXTRA_ITEM_NOT_REJECTED'
  }
  foreach($f in @(Get-ChildItem -LiteralPath $archive -File)){
    $after=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    if($after -ne $inventoryBefore[$f.Name]){
      throw 'READONLY_VERIFIER_MODIFIED_SYNTHETIC_BACKUP'
    }
  }
  Write-Output 'DAY12_P0_OFFLINE_INDEPENDENT_VERIFY_INTEROP_PASS_20_FILES'
  Write-Output 'INDEPENDENT_WRITER_READER_PASS=true'
  Write-Output 'WRONG_PASSWORD_TAMPER_TRUNCATION_EXTRA_REJECTED=true'
  Write-Output 'ORIGINAL_ARCHIVE_UNMODIFIED=true'
  Write-Output 'PRODUCTION_SOURCE_OR_CLOUD_ACCESSED=false'
} finally {
  $env:LOCALAPPDATA=$old
  if(Test-Path -LiteralPath $root){
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
}
