[CmdletBinding()]
param(
  [string]$ReportPath="",
  [string[]]$SearchRoots=@(),
  [switch]$ResolveOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Test-GoldenReport([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
  try {
    $j=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if([string]$j.phase -ne "12.0B" -or [string]$j.result -ne "PASS"){return $false}
    $ids=@("wild","playground","other","lobby")
    $steps=@($j.steps)
    if($steps.Count -ne 4){return $false}
    foreach($id in $ids){
      $matches=@($steps | Where-Object {
        [string]$_.server_id -eq $id -and
        [string]$_.step -eq "create_verify_protect" -and
        [bool]$_.pass -and
        [bool]$_.retention_exempt -and
        [string]$_.file -match '-full-backup-.*\.zip$' -and
        [string]$_.sha256 -match '^[0-9a-fA-F]{64}$'
      })
      if($matches.Count -ne 1){return $false}
    }
    return $true
  } catch {return $false}
}

$desktop=[Environment]::GetFolderPath("Desktop")
$downloads=Join-Path $env:USERPROFILE "Downloads"
if([string]::IsNullOrWhiteSpace($ReportPath)){
  if($SearchRoots.Count -eq 0){
    $SearchRoots=@($desktop,$downloads,(Join-Path $env:USERPROFILE "Documents"),$PSScriptRoot)
  }
  $seen=@{}
  $candidates=@()
  foreach($root in $SearchRoots){
    if([string]::IsNullOrWhiteSpace($root) -or -not(Test-Path -LiteralPath $root -PathType Container)){continue}
    # Bounded traversal: covers Desktop/Downloads/Day12-report and a few nested folders
    # without scanning the entire Windows user profile.
    foreach($f in @(Get-ChildItem -LiteralPath $root -Filter "Geumyi-Day12-Phase0B-GoldenCheckpoint-*.json" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue)){
      if(-not $seen.ContainsKey($f.FullName)){
        $seen[$f.FullName]=$true
        $candidates+= $f
      }
    }
  }
  $approved=@($candidates | Sort-Object LastWriteTime -Descending | Where-Object {Test-GoldenReport $_.FullName} | Select-Object -First 1)
  if($approved.Count -eq 1){$ReportPath=$approved[0].FullName}

  if([string]::IsNullOrWhiteSpace($ReportPath)){
    if($ResolveOnly){
      Write-Host "[CHECK] No verified Phase 12.0B report found under supplied search roots."
      exit 22
    }
    Write-Host "Phase 12.0B report not found automatically. Select the PASS JSON file."
    try{
      Add-Type -AssemblyName System.Windows.Forms
      $picker=New-Object System.Windows.Forms.OpenFileDialog
      $picker.Title="Select the successful Geumyi Day 12 Phase 0B GoldenCheckpoint JSON"
      $picker.Filter="JSON reports (*.json)|*.json"
      $picker.CheckFileExists=$true
      if(Test-Path -LiteralPath $downloads -PathType Container){$picker.InitialDirectory=$downloads}
      if($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$ReportPath=$picker.FileName}
      $picker.Dispose()
    }catch{
      Write-Host ("File picker unavailable: "+$_.Exception.Message)
    }
    if([string]::IsNullOrWhiteSpace($ReportPath)){
      $ReportPath=Read-Host "Enter or paste the complete path to the Phase 12.0B PASS JSON"
      $ReportPath=$ReportPath.Trim('"')
    }
  }
}
if(-not(Test-GoldenReport $ReportPath)){
  throw "The selected file is not a valid four-server Phase 12.0B PASS report: $ReportPath"
}
Write-Host ("Verified input report: "+$ReportPath)
if($ResolveOnly){
  Write-Output ("RESOLVED_REPORT="+(Resolve-Path -LiteralPath $ReportPath).Path)
  exit 0
}
Write-Host "Only the known-good artifact cache is written; worlds, source files, existing backups and server processes are not changed."
$confirmation=Read-Host "Type BUILD_DAY12_KNOWN_GOOD_CACHE to confirm"
if($confirmation -cne "BUILD_DAY12_KNOWN_GOOD_CACHE"){
  Write-Host "[BLOCKED] Confirmation text did not match."
  exit 23
}
$global:LASTEXITCODE=0
& (Join-Path $PSScriptRoot "Day12_Phase7_KnownGood_Cache.ps1") -Mode Build -Phase0BReport $ReportPath -Confirm $confirmation
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
exit 0
