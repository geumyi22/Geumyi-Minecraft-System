[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ArchiveZip,
  [Parameter(Mandatory=$true)][string]$LogTrashDir,
  [string]$Confirm="",
  [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

if(-not(Test-Path -LiteralPath $ArchiveZip -PathType Leaf)){throw "Archive ZIP missing"}
if(-not(Test-Path -LiteralPath $LogTrashDir -PathType Container)){throw "LogTrash directory missing"}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$tmp=Join-Path $env:TEMP ("Geumyi-Day12-LogRestore-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp|Out-Null
try{
  [IO.Compression.ZipFile]::ExtractToDirectory($ArchiveZip,$tmp)
  $manifestPath=Join-Path $tmp "manifest.json"
  if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Archive manifest missing"}
  $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
  $plan=New-Object System.Collections.ArrayList
  foreach($x in @($m.files)){
    $trashFile=Join-Path $LogTrashDir ([string]$x.archive_name)
    $archiveFile=Join-Path $tmp ([string]$x.archive_name)
    $available=(Test-Path -LiteralPath $trashFile -PathType Leaf) -or (Test-Path -LiteralPath $archiveFile -PathType Leaf)
    [void]$plan.Add([ordered]@{
      archive_name=[string]$x.archive_name
      original_name=[string]$x.original_name
      kind=[string]$x.kind
      available=$available
    })
  }
  $missing=@($plan|Where-Object{-not[bool]$_.available})
  if($DryRun){
    $plan|Format-Table|Out-String|Write-Host
    Write-Host ("Missing: "+$missing.Count)
    exit $(if($missing.Count){2}else{0})
  }
  if($Confirm -ne "RESTORE_DAY12_LOGTRASH"){
    Write-Host "[BLOCKED] Use -Confirm RESTORE_DAY12_LOGTRASH after DryRun review."
    exit 23
  }
  # Original absolute paths are intentionally not stored in the public/report manifest.
  # Therefore automatic blind restoration to production paths is refused.
  Write-Host "Archive verified and recoverable files found."
  Write-Host "Automatic restoration to original production paths is intentionally refused because"
  Write-Host "the manifest does not persist full local paths. Use the archive/LogTrash files only"
  Write-Host "for incident recovery after identifying the intended destination."
  exit 0
}finally{
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
