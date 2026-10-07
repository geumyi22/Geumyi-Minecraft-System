param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination,[Parameter(Mandatory=$true)][string]$ExpectedSHA256,[string]$Confirm="")
$ErrorActionPreference="Stop"
if($Confirm -ne "RESTORE_VERIFIED_FILE"){Write-Host "[BLOCKED] -Confirm RESTORE_VERIFIED_FILE required";exit 23}
if(-not(Test-Path $Source -PathType Leaf)){throw "Source missing"}
$h=(Get-FileHash $Source -Algorithm SHA256).Hash.ToLowerInvariant();if($h -ne $ExpectedSHA256.ToLowerInvariant()){throw "Source SHA-256 mismatch"}
$dir=Split-Path -Parent $Destination;New-Item -ItemType Directory -Force -Path $dir|Out-Null
$tmp=$Destination+".recovery-new";Copy-Item $Source $tmp -Force
if((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){Remove-Item $tmp -Force;throw "Staged SHA-256 mismatch"}
if(Test-Path $Destination){Copy-Item $Destination ($Destination+".recovery-before") -Force}
Move-Item $tmp $Destination -Force
Write-Host "RESTORE COMPLETE - run health verification before deleting .recovery-before"
