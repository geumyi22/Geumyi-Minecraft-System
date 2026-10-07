[CmdletBinding()]
param([string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Continue"
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) ("Geumyi-Day12-READONLY-"+(Get-Date -Format "yyyyMMdd-HHmmss"))}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$steps=New-Object System.Collections.ArrayList
function Run([string]$name,[string]$script,[string[]]$args){
  Write-Host "";Write-Host ("==== "+$name+" ====")
  $global:LASTEXITCODE=0
  & (Join-Path $root $script) @args
  $ec=$LASTEXITCODE
  if($null -eq $ec){$ec=0}
  [void]$steps.Add([ordered]@{name=$name;exit_code=[int]$ec;status=$(if([int]$ec -eq 0){"CAPTURED"}else{"CHECK"})})
}
Run "12.0A Golden Baseline" "Day12_Phase0_Golden_Baseline_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.0A"))
Run "12.1 Content Preflight" "Day12_Phase1_Content_Preflight_READ_ONLY.ps1" @("-ManifestPath",(Join-Path $root "..\..\deploy\day12-managed-content.json"),"-OutputDir",(Join-Path $OutputDir "12.1"))
Run "12.2 Component Inventory" "Day12_Phase2_Component_Inventory_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.2"))
Run "12.3 Whole-System Health" "Day12_Phase3_Health_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.3"))
Run "12.4 Storage/Log Dry-Run" "Day12_Phase4_Storage_Log_DRY_RUN.ps1" @("-PolicyPath",(Join-Path $root "..\..\deploy\day12-lifecycle-policy.json"),"-OutputDir",(Join-Path $OutputDir "12.4"))
Run "12.5 Runtime Security" "Day12_Phase5_Security_Audit_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.5"))
Run "12.7 Known-Good Cache Audit" "Day12_Phase7_KnownGood_Cache.ps1" @("-Mode","Audit","-OutputDir",(Join-Path $OutputDir "12.7"))
Run "12.10 Final Verification" "Day12_Final_Verification_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.10"))
$summary=[ordered]@{
 schema=1;tool="Day12 Collect All READ-ONLY";generated_at=(Get-Date).ToString("o");output_dir=$OutputDir
 mutation_performed=$false;steps=@($steps)
 note="CHECK is expected for gates that require 12.0B Golden backups or the known-good cache. No mutation step is included."
}
$summary|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutputDir "Day12-READONLY-SUMMARY.json") -Encoding UTF8
Write-Host "";Write-Host "============================================================"
Write-Host " DAY 12 READ-ONLY COLLECTION FINISHED"
Write-Host "============================================================"
foreach($x in @($steps)){Write-Host ("{0,-34} {1} (exit {2})" -f $x.name,$x.status,$x.exit_code)}
Write-Host ("Folder: "+$OutputDir)
Write-Host "No mutation step was executed."
