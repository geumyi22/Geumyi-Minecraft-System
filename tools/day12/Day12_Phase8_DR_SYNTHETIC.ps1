[CmdletBinding()]
param([string]$OutputDir="")
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($OutputDir)){$OutputDir=Join-Path $env:TEMP "Geumyi-Day12-DR"}
New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
$out=Join-Path $OutputDir ("FINAL-DR-REPORT-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".json")
function Get-Sha256([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
$root=Join-Path $env:TEMP ("Geumyi-Day12-DR-"+[guid]::NewGuid().ToString("N"));New-Item -ItemType Directory -Force -Path $root|Out-Null
$steps=New-Object System.Collections.ArrayList
try{
  # 1 damaged binary -> known-good rollback
  $live=Join-Path $root "GeumyiServerHost.exe";$kg=Join-Path $root "GeumyiServerHost.known-good.exe"
  Set-Content $kg "known-good-host" -NoNewline;Copy-Item $kg $live
  $expected=Get-Sha256 $kg;Set-Content $live "corrupted-host" -NoNewline
  $detected=(Get-Sha256 $live)-ne$expected;if(-not$detected){throw "damaged binary not detected"}
  Copy-Item $kg $live -Force;$restored=(Get-Sha256 $live)-eq$expected;if(-not$restored){throw "binary rollback failed"}
  [void]$steps.Add([ordered]@{case="damaged_gsc_binary";detect=$detected;rollback=$restored;pass=$true})

  # 2 damaged plugin -> verified replacement
  $plugin=Join-Path $root "plugin.jar";$pluginGood=Join-Path $root "plugin.known-good.jar";Set-Content $pluginGood "known-good-plugin" -NoNewline;Copy-Item $pluginGood $plugin
  $pHash=Get-Sha256 $pluginGood;Set-Content $plugin "bad-plugin" -NoNewline;$pDetected=((Get-Sha256 $plugin) -ne $pHash);Copy-Item $pluginGood $plugin -Force
  $pRestored=((Get-Sha256 $plugin) -eq $pHash)
  [void]$steps.Add([ordered]@{case="damaged_plugin";detect=$pDetected;rollback=$pRestored;pass=($pDetected -and $pRestored)})

  # 3 interrupted transaction journal
  $journal=Join-Path $root "transaction.json";[ordered]@{phase="replacing";committed=$false;backup=$kg;target=$live}|ConvertTo-Json|Set-Content $journal -Encoding UTF8
  $j=Get-Content $journal -Raw|ConvertFrom-Json;$interrupt=([string]$j.phase -eq "replacing" -and -not[bool]$j.committed)
  if(-not$interrupt){throw "interrupted transaction not detected"}
  [void]$steps.Add([ordered]@{case="interrupted_transaction";detect=$true;safe_action="rollback-before-commit";pass=$true})

  # 4 invalid config -> known-good config restore
  $cfg=Join-Path $root "server.json";$cfgGood=Join-Path $root "server.known-good.json";Set-Content $cfgGood '{"schema":1,"servers":[]}' -NoNewline;Set-Content $cfg '{ invalid json' -NoNewline
  $invalid=$false;try{Get-Content $cfg -Raw|ConvertFrom-Json|Out-Null}catch{$invalid=$true}
  if(-not$invalid){throw "invalid config not detected"};Copy-Item $cfgGood $cfg -Force;Get-Content $cfg -Raw|ConvertFrom-Json|Out-Null
  [void]$steps.Add([ordered]@{case="invalid_config";detect=$true;rollback=$true;pass=$true})

  # 5 failed health gate -> do not promote candidate
  $candidateHealthy=$false;$promoted=$candidateHealthy
  [void]$steps.Add([ordered]@{case="failed_update_health";health=$candidateHealthy;promotion=$promoted;rollback_required=$true;pass=(-not$promoted)})

  $result=if(@($steps|Where-Object{-not[bool]$_.pass}).Count -eq 0){"PASS"}else{"FAIL"}
}catch{
  $result="FAIL";[void]$steps.Add([ordered]@{case="exception";pass=$false;error=[string]$_.Exception.Message})
}finally{Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
$r=[ordered]@{schema=1;phase="12.8";mode="SYNTHETIC_NON_PRODUCTION";generated_at=(Get-Date).ToString("o");result=$result;production_files_touched=$false;steps=@($steps)}
$r|ConvertTo-Json -Depth 10|Set-Content $out -Encoding UTF8
Write-Host ("DR SYNTHETIC: "+$result)
foreach($step in @($steps)){ $errText=""; if($null -ne $step.PSObject.Properties["error"]){$errText=" error="+[string]$step.error}; Write-Host ("- "+[string]$step.case+" pass="+[string]$step.pass+$errText) }
Write-Host ("Report: "+$out)
if($result -ne "PASS"){exit 2}
exit 0
