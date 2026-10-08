[CmdletBinding()]
param(
  [string]$OutputDir="",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) ("Geumyi-Day12-READONLY-"+(Get-Date -Format "yyyyMMdd-HHmmss"))
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$steps=New-Object System.Collections.ArrayList

function Run([string]$name,[string]$script,[string[]]$scriptArgs){
  Write-Host ""
  Write-Host ("==== "+$name+" ====")
  $path=Join-Path $root $script
  $ec=1
  $note=""
  try{
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
      $note="Required script missing: "+$path
      Write-Host ("[ERROR] "+$note)
    }else{
      # Child PowerShell process isolates each script's exit and terminating errors.
      # Never infer PASS from an old / unset LASTEXITCODE.
      $childArgs=@($scriptArgs)
      if($Synthetic){$childArgs+= "-Synthetic"}
      & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $path @childArgs
      $ec=[int]$LASTEXITCODE
      if($ec -eq 0){
        $outputIndex=[Array]::IndexOf($childArgs,"-OutputDir")
        if($outputIndex -lt 0 -or $outputIndex+1 -ge $childArgs.Count){
          $ec=1
          $note="No output directory specified"
        }else{
          $phaseDir=[string]$childArgs[$outputIndex+1]
          $reports=@(Get-ChildItem -LiteralPath $phaseDir -Filter "*.json" -File -ErrorAction SilentlyContinue)
          if($reports.Count -eq 0){
            $ec=1
            $note="Script returned success but produced no JSON report"
          }
        }
      }
    }
  }catch{
    $ec=1
    $note=[string]$_.Exception.Message
    Write-Host ("[ERROR] "+$note)
  }
  if($ec -ne 0 -and -not $note){$note="Phase returned exit "+$ec}
  [void]$steps.Add([ordered]@{
    name=$name
    exit_code=[int]$ec
    status=$(if($ec -eq 0){"CAPTURED"}else{"CHECK"})
    detail=$note
  })
}

Run "12.0A Golden Baseline" "Day12_Phase0_Golden_Baseline_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.0A"))
Run "12.1 Content Preflight" "Day12_Phase1_Content_Preflight_READ_ONLY.ps1" @("-ManifestPath",(Join-Path $root "..\..\deploy\day12-managed-content.json"),"-OutputDir",(Join-Path $OutputDir "12.1"))
Run "12.2 Component Inventory" "Day12_Phase2_Component_Inventory_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.2"))
Run "12.3 Whole-System Health" "Day12_Phase3_Health_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.3"))
Run "12.4 Storage/Log Dry-Run" "Day12_Phase4_Storage_Log_DRY_RUN.ps1" @("-PolicyPath",(Join-Path $root "..\..\deploy\day12-lifecycle-policy.json"),"-OutputDir",(Join-Path $OutputDir "12.4"))
Run "12.5 Runtime Security" "Day12_Phase5_Security_Audit_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.5"))
Run "12.7 Known-Good Cache Audit" "Day12_Phase7_KnownGood_Cache.ps1" @("-Mode","Audit","-OutputDir",(Join-Path $OutputDir "12.7"))
Run "12.10 Final Verification" "Day12_Final_Verification_READ_ONLY.ps1" @("-OutputDir",(Join-Path $OutputDir "12.10"))

$checks=@($steps | Where-Object {[int]$_.exit_code -ne 0})
$allOK=$checks.Count -eq 0
$summary=[ordered]@{
  schema=2
  tool="Day12 Collect All READ-ONLY"
  generated_at=(Get-Date).ToString("o")
  synthetic=[bool]$Synthetic
  output_dir=$OutputDir
  result=$(if($allOK){"CAPTURED"}else{"CHECK_REQUIRED"})
  collector_exit_code=$(if($allOK){0}else{2})
  mutation_performed=$false
  steps=@($steps)
  note="CHECK is expected when later live gates require Golden backups or the known-good cache. Missing scripts and failed phase processes are never CAPTURED."
}
$summary|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutputDir "Day12-READONLY-SUMMARY.json") -Encoding UTF8
Write-Host ""
Write-Host "============================================================"
Write-Host " DAY 12 READ-ONLY COLLECTION FINISHED"
Write-Host "============================================================"
foreach($x in @($steps)){
  Write-Host ("{0,-34} {1} (exit {2})" -f $x.name,$x.status,$x.exit_code)
}
Write-Host ("Folder: "+$OutputDir)
Write-Host ("Result: "+$summary.result)
Write-Host "No mutation step was executed."
if(-not $allOK){exit 2}
exit 0
