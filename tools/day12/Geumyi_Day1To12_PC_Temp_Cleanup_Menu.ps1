[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$script=Join-Path $PSScriptRoot "Geumyi_Day1To12_PC_Temp_Cleanup.ps1"
$plans=Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "Geumyi-Day1To12-Cleanup\Plans"
function Run([string[]]$Arguments){
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script @Arguments
  if($LASTEXITCODE -ne 0){Write-Host ("[CHECK REQUIRED] Exit code "+$LASTEXITCODE)}
}
while($true){
  Write-Host ""
  Write-Host "====================================================" -ForegroundColor Cyan
  Write-Host " Geumyi Day1-12 PC Temporary File Cleanup"
  Write-Host " Current Day12 live gates: NOT FINISHED - Day12 HOLD"
  Write-Host "===================================================="
  Write-Host " 1. Preview only (recommended: safe, no file movement)"
  Write-Host " 2. Quarantine previously reviewed eligible Day1-11 TEMP"
  Write-Host " 3. Restore quarantined files"
  Write-Host " 4. Permanently delete ONE quarantine after 14 days"
  Write-Host " 0. Exit"
  $option=(Read-Host "Select").Trim()
  switch($option){
    "1" {
      Write-Host "Use default minimum age 7 days. Day12 and Desktop/Downloads stay protected."
      Run @("-Mode","Preview","-MinimumAgeDays","7")
    }
    "2" {
      $latest=@(Get-ChildItem -LiteralPath $plans -Filter "plan-*.json" -File -ErrorAction SilentlyContinue|
        Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1)
      if($latest.Count -lt 1){Write-Host "No plan yet. Run Preview first.";continue}
      Write-Host ("Most recent private plan: "+$latest[0].Name)
      Write-Host "Files will MOVE to a recoverable local quarantine, NOT permanently delete."
      $approval=(Read-Host "Type QUARANTINE_GEUMYI_TEMP to approve").Trim()
      if($approval -cne "QUARANTINE_GEUMYI_TEMP"){Write-Host "Cancelled";continue}
      Run @("-Mode","Quarantine","-PlanPath",$latest[0].FullName,"-Confirm",$approval)
    }
    "3" {
      $id=(Read-Host "Enter quarantine RunId from report").Trim()
      $approval=(Read-Host "Type RESTORE_GEUMYI_TEMP to confirm").Trim()
      if($approval -cne "RESTORE_GEUMYI_TEMP"){Write-Host "Cancelled";continue}
      Run @("-Mode","Restore","-RunId",$id,"-Confirm",$approval)
    }
    "4" {
      Write-Host "[WARNING] Irreversible deletion only of existing quarantined items."
      Write-Host "This action is blocked until quarantine has existed for 14 days."
      $id=(Read-Host "Enter quarantine RunId").Trim()
      $approval=(Read-Host "Type PURGE_GEUMYI_QUARANTINE_14D to confirm").Trim()
      if($approval -cne "PURGE_GEUMYI_QUARANTINE_14D"){Write-Host "Cancelled";continue}
      Run @("-Mode","Purge","-RunId",$id,"-Confirm",$approval)
    }
    "0" {exit 0}
    default {Write-Host "Invalid selection"}
  }
}
