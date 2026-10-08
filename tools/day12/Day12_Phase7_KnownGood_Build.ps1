[CmdletBinding()]
param([string]$ReportPath="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$desktop=[Environment]::GetFolderPath("Desktop")
if([string]::IsNullOrWhiteSpace($ReportPath)){
  $folder=Join-Path $desktop "Geumyi-Day12-Phase0"
  if(-not(Test-Path -LiteralPath $folder -PathType Container)){
    throw "Phase 12.0B report folder not found: $folder"
  }
  $candidates=@(Get-ChildItem -LiteralPath $folder -Filter 'Geumyi-Day12-Phase0B-GoldenCheckpoint-*.json' -File | Sort-Object LastWriteTime -Descending)
  $approved=$null
  foreach($candidate in $candidates){
    try{
      $j=Get-Content -LiteralPath $candidate.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      if([string]$j.phase -eq "12.0B" -and [string]$j.result -eq "PASS" -and @($j.steps).Count -eq 4){
        $approved=$candidate
        break
      }
    }catch{}
  }
  if($null -eq $approved){throw "No Phase 12.0B PASS JSON in: $folder"}
  $ReportPath=$approved.FullName
}
if(-not(Test-Path -LiteralPath $ReportPath -PathType Leaf)){throw "Report file missing"}
Write-Host ("Verified input report: "+$ReportPath)
Write-Host "Only the known-good artifact cache is written; source files, worlds, backups and server processes are not changed."
$confirmation=Read-Host "Type BUILD_DAY12_KNOWN_GOOD_CACHE to confirm"
if($confirmation -cne "BUILD_DAY12_KNOWN_GOOD_CACHE"){
  Write-Host "[BLOCKED] Confirmation text did not match."
  exit 23
}
$global:LASTEXITCODE=0
& (Join-Path $PSScriptRoot "Day12_Phase7_KnownGood_Cache.ps1") -Mode Build -Phase0BReport $ReportPath -Confirm $confirmation
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
exit 0
