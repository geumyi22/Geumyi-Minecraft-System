[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Offline encrypted-archive verification only.
# Does NOT touch GSC, OneDrive, Google Drive or any server process.
function Refuse([string]$Reason){throw ('P0_VERIFY_'+$Reason)}
function Private-SecureString([Security.SecureString]$Secret) {
  $ptr=[IntPtr]::Zero
  try {
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
  }
}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Refuse 'WINDOWS_ONLY'}
  $exe=Join-Path $PSScriptRoot 'p0-offline-verify.exe'
  if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){Refuse 'VERIFIER_MISSING'}
  $base=Join-Path $env:LOCALAPPDATA 'Geumyi-P0-Encrypted-Staging'
  $baseItem=Get-Item -LiteralPath $base -Force -ErrorAction Stop
  if(-not $baseItem.PSIsContainer -or
      (([long]$baseItem.Attributes -band 0x00000400) -ne 0)){
    Refuse 'STAGING_DIRECTORY_REPARSE_OR_MISSING'
  }
  $candidates=@(Get-ChildItem -LiteralPath $base -Directory -Filter 'P0-*' -ErrorAction Stop |
    Where-Object{Test-Path -LiteralPath (Join-Path $_.FullName 'LOCAL_CAPTURE_VERIFIED.txt') -PathType Leaf} |
    Sort-Object CreationTimeUtc -Descending)
  if($candidates.Count -eq 0){Refuse 'NO_LOCAL_COMPLETE_CAPTURE_FOUND'}
  # If multiple were created, use newest COMPLETED capture, never create another.
  $latest=$candidates[0]
  if(([long]$latest.Attributes -band 0x00000400) -ne 0){
    Refuse 'ARCHIVE_DIRECTORY_IS_REPARSE'
  }
  Write-Host '===================================================='
  Write-Host 'Day12 P0 Offline verification of EXISTING encrypted backup'
  Write-Host 'NO new backup, cloud upload, plaintext extraction or service change.'
  Write-Host 'Only LOCALAPPDATA private P0 archive folder is read.'
  Write-Host 'Enter the SAME recovery passphrase used during capture.'
  Write-Host 'Do NOT share the recovery passphrase or private files.'
  Write-Host '===================================================='
  $secure=Read-Host 'Recovery passphrase (hidden)' -AsSecureString
  $pass=Private-SecureString $secure
  $secure.Dispose()
  $secure=$null
  if($pass.Length -lt 20 -or $pass.Length -gt 256){Refuse 'PASSPHRASE_LENGTH_INVALID'}
  $request=@{archive=$latest.FullName;passphrase=$pass} |
    ConvertTo-Json -Compress -Depth 3
  $pass=$null
  $OutputEncoding=New-Object System.Text.UTF8Encoding($false)
  $result=@($request|& $exe --verify)
  $request=$null
  if($LASTEXITCODE -ne 0 -or
     @($result|Where-Object{$_ -ceq 'P0_OFFLINE_VERIFY_PASS'}).Count -ne 1){
    $result|ForEach-Object{
      if($_ -match '^P0_OFFLINE_VERIFY_(BLOCKED|ARGUMENTS_REFUSED|PRIVATE_INPUT_INVALID)'){
        Write-Host $_
      }
    }
    Refuse 'AUTHENTICATION_OR_ARCHIVE_INTEGRITY_FAILED'
  }
  Write-Host 'P0_OFFLINE_VERIFY_PASS'
  Write-Host 'P0_ENCRYPTED_FILES_VERIFIED=20'
  Write-Host 'P0_NO_PLAINTEXT_OUTPUT=true'
  Write-Host 'P0_REMOTE_CLOUD_DOWNLOAD_VERIFIED=false'
  Write-Host 'P0_LIVE_APPLICATION_RESTORE_VERIFIED=false'
  Write-Host 'SEND_ONLY: the P0_OFFLINE_VERIFY_PASS line, NOT files or password'
} catch {
  Write-Host 'P0_OFFLINE_VERIFY_NOT_ACCEPTED_NO_ORIGINAL_CHANGES'
  if($_.Exception.Message -match '^P0_VERIFY_[A-Z_]+$'){
    Write-Host $_.Exception.Message
  }
  exit 2
}
