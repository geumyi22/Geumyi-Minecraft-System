[CmdletBinding()]
param([switch]$Synthetic)
# Read-only known-path Geyser/Floodgate JAR fingerprints. Does not inspect
# Floodgate key.pem, Geyser config, user data, players, process command lines,
# runtime memory, or any arbitrary filesystem locations.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ids=@('wild','playground','other')
$out=[ordered]@{
    schema=1
    collector='GSC-v4.5.2-GeyserFloodgate-READ-ONLY'
    collected_at_utc=[DateTimeOffset]::UtcNow.ToString('o')
    synthetic=[bool]$Synthetic
    host_state_changed=$false
    jar_or_config_changed=$false
    actual_plugin_loading_verified=$false
    result='NOT_VERIFIED'
    instances=@()
}
function JarStatus([object[]]$files,[string]$name) {
    $regex = switch ($name) {
        'geyser' { '^(?i:geyser-velocity)(?:-[a-z0-9._-]+)?\.jar$' }
        'floodgate' { '^(?i:floodgate-velocity)(?:-[a-z0-9._-]+)?\.jar$' }
        default { '^$' }
    }
    $matches = @($files | Where-Object { [string]$_.Name -match $regex })
    $item=[ordered]@{
        candidate_count=[int]$matches.Count
        sha256=''
        bytes=[int64]0
        result='NOT_FOUND_OR_UNVERIFIED'
    }
    if($matches.Count -eq 1) {
        try {
            $f=$matches[0]
            if($f.Length -gt 0 -and $f.Length -lt 150000000) {
                $hash=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                if($hash -match '^[a-f0-9]{64}$') {
                    $item.sha256=$hash
                    $item.bytes=[int64]$f.Length
                    $item.result='SINGLE_ARTIFACT_CAPTURED_LOADING_UNVERIFIED'
                }
            }
        } catch {
            # Fail closed and avoid exporting paths or exception details.
            $item.sha256=''
            $item.bytes=[int64]0
        }
    } elseif ($matches.Count -gt 1) {
        $item.result='MULTIPLE_JARS_LOADING_UNVERIFIED'
    }
    return $item
}
if($Synthetic){
    foreach($id in $ids){
        $sample=@()
        foreach($kind in @('geyser','floodgate')){
            $sample += [ordered]@{
                kind=$kind
                candidate_count=1
                sha256=('0' * 64)
                bytes=[int64]100
                result='SYNTHETIC_ONLY'
            }
        }
        $out.instances += [ordered]@{id=$id; plugin_directory_present=$false; jars=$sample}
    }
    $out.result='SYNTHETIC_STRUCTURE_PASS_NOT_LIVE'
    $out | ConvertTo-Json -Depth 7 -Compress
    exit 0
}
$root=Join-Path $env:ProgramData 'GeumyiServerCenter\Network\FourServer'
foreach($id in $ids) {
    $pluginDir=Join-Path (Join-Path $root $id) 'plugins'
    $present=Test-Path -LiteralPath $pluginDir -PathType Container
    $files=@()
    if($present){
        try {
            $files=@(Get-ChildItem -LiteralPath $pluginDir -Filter '*.jar' -File -ErrorAction Stop)
        } catch { $files=@() }
    }
    $geyser=JarStatus $files 'geyser'
    $floodgate=JarStatus $files 'floodgate'
    $out.instances += [ordered]@{
        id=$id
        plugin_directory_present=[bool]$present
        jars=@(
            [ordered]@{kind='geyser'; candidate_count=$geyser.candidate_count;sha256=$geyser.sha256;bytes=$geyser.bytes;result=$geyser.result}
            [ordered]@{kind='floodgate';candidate_count=$floodgate.candidate_count;sha256=$floodgate.sha256;bytes=$floodgate.bytes;result=$floodgate.result}
        )
    }
}
$good=@($out.instances | Where-Object {
    -not $_.plugin_directory_present -or
    @($_.jars | Where-Object { $_.result -ne 'SINGLE_ARTIFACT_CAPTURED_LOADING_UNVERIFIED' }).Count -gt 0
})
if($good.Count -eq 0){$out.result='SIX_ARTIFACT_FINGERPRINTS_CAPTURED_LOADING_UNVERIFIED'}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)){
    Write-Host 'Desktop unavailable. No report written.'; exit 2
}
$dir=Join-Path $desktop 'Geumyi-Velocity-ReadOnly-Reports'
[void](New-Item -ItemType Directory -Path $dir -Force)
$file=Join-Path $dir ('GeyserFloodgate-READ-ONLY-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$json=$out | ConvertTo-Json -Depth 7
[IO.File]::WriteAllText($file,$json,(New-Object Text.UTF8Encoding($false)))
Write-Host ('READ-ONLY result: '+$out.result)
Write-Host ('Sanitized report: '+$file)
Write-Host 'Share only this JSON. No settings, keys, worlds, or processes were changed.'
