[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$TransactionRoot,
  [string]$Confirm="",
  [string]$OutputDir=""
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

if($Confirm -ne "ROLLBACK_DAY12_MANAGED_CONTENT"){
  Write-Host "[BLOCKED] -Confirm ROLLBACK_DAY12_MANAGED_CONTENT required"
  exit 23
}
$tx=Join-Path $TransactionRoot "transaction.json"
if(-not(Test-Path -LiteralPath $tx -PathType Leaf)){throw "transaction.json missing"}
$j=Get-Content -LiteralPath $tx -Raw -Encoding UTF8|ConvertFrom-Json
$entries=@($j.entries)
if($entries.Count -eq 0){throw "No transaction entries to roll back"}

if([string]::IsNullOrWhiteSpace($OutputDir)){
  $OutputDir=Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-Phase1"
}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("Geumyi-Day12-Phase1-ManualRollback-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")

$errors=New-Object System.Collections.ArrayList
$done=New-Object System.Collections.ArrayList
for($i=$entries.Count-1;$i -ge 0;$i--){
  $e=$entries[$i]
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
    }else{
      throw ("unsupported transaction kind: "+[string]$e.kind)
    }
    [void]$done.Add([ordered]@{id=[string]$e.id;kind=[string]$e.kind;pass=$true})
  }catch{
    [void]$errors.Add([ordered]@{id=[string]$e.id;kind=[string]$e.kind;error=[string]$_.Exception.Message})
  }
}
$result=if($errors.Count -eq 0){"ROLLBACK_COMPLETE"}else{"ROLLBACK_INCOMPLETE"}
$r=[ordered]@{
  schema=1;phase="12.1-rollback";generated_at=(Get-Date).ToString("o");result=$result
  transaction_root=$TransactionRoot;restored=@($done);errors=@($errors)
  server_lifecycle_action_performed=$false
}
$r|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("RESULT: "+$result);Write-Host ("REPORT: "+$out)
if($errors.Count -gt 0){exit 2}
exit 0
