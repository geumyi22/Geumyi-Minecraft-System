param([Parameter(Mandatory=$true)][string]$ManifestPath,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference="Stop";$m=Get-Content $ManifestPath -Raw|ConvertFrom-Json;$bad=@()
foreach($x in @($m.files)){$p=Join-Path $Root ([string]$x.cache_name);if(-not(Test-Path $p)){$bad+=$x.cache_name;continue};$h=(Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant();if($h -ne [string]$x.sha256){$bad+=$x.cache_name}}
if($bad.Count){Write-Error ("Verification failed: "+($bad -join ","));exit 2};Write-Host "KNOWN-GOOD VERIFY PASS"
