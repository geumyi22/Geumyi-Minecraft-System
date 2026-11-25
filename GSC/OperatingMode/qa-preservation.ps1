[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Baseline','Compare')][string]$Mode,
    [string]$EvidenceFolder = (Join-Path $PSScriptRoot 'qa'),
    [string]$OriginalV2 = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads/GMS_OperatingMode_v2.0.0.exe')
)
$ErrorActionPreference = 'Stop'
$evidence = [IO.Directory]::CreateDirectory($EvidenceFolder).FullName
$baseline = Join-Path $evidence 'preservation-baseline.local.json'
$summaryFile = Join-Path $evidence 'preservation-summary.json'
$utf8 = New-Object Text.UTF8Encoding($false)
$script:samples = New-Object 'Collections.Generic.List[object]'
$script:seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:skipped = 0
if (-not ('GmsSampleMeta' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GmsSampleMeta {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct FindData {
        public uint Attr; public System.Runtime.InteropServices.ComTypes.FILETIME Created, Accessed, Written;
        public uint SizeHigh, SizeLow, Tag, Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=14)] public string AlternateName;
    }
    [DllImport("kernel32",CharSet=CharSet.Unicode)] static extern IntPtr FindFirstFile(string filename,out FindData data);
    [DllImport("kernel32")] static extern bool FindClose(IntPtr handle);
    public static bool IsCloudMetadata(string path) {
        FindData data; IntPtr handle=FindFirstFile(path,out data);
        if (handle==new IntPtr(-1)) return false;
        try { return (data.Tag & 0xffff0fffU)==0x9000001aU; }
        finally { FindClose(handle); }
    }
}
'@
}

function Is-PlainLocal([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path) -or $path -notmatch '^[a-zA-Z]:[\\/]') { return $false }
    try {
        for ($at=[IO.Path]::GetFullPath($path); $at; $at=[IO.Path]::GetDirectoryName($at)) {
            $flags=[int][IO.File]::GetAttributes($at)
            if (($flags -band 0x441000) -ne 0) { return $false } # Offline, recall-on-open, recall-on-data access
            if (($flags -band 0x400) -ne 0 -and -not [GmsSampleMeta]::IsCloudMetadata($at)) { return $false }
        }
        return $true
    } catch { return $false }
}
function Add-Sample([string]$group,[string]$key,[string]$path) {
    if (-not (Is-PlainLocal $path) -or -not [IO.File]::Exists($path)) { return }
    if (-not $script:seen.Add([IO.Path]::GetFullPath($path))) { return }
    try {
        $size=(Get-Item -LiteralPath $path -ErrorAction Stop).Length
        if ($size -gt 100MB) { $script:skipped++; return }
        $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
        $script:samples.Add([pscustomobject]@{ group=$group; key=$key; bytes=$size; sha256=$hash })
    } catch { $script:skipped++ }
}
function First-LocalFile([string]$dir,[string]$pattern) {
    if (-not (Is-PlainLocal $dir) -or -not [IO.Directory]::Exists($dir)) { return }
    return Get-ChildItem -LiteralPath $dir -Filter $pattern -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -le 100MB -and (Is-PlainLocal $_.FullName) } |
        Sort-Object Name | Select-Object -First 1 -ExpandProperty FullName
}

$base=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'GeumyiServerCenter'
foreach ($file in @('server.json','instances.json','lifecycle-schedules.json','automations.json','role.json')) {
    Add-Sample 'GSC configuration' $file (Join-Path $base $file)
}
$roots=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$catalog=Join-Path $base 'server.json'
if ((Is-PlainLocal $catalog) -and (Get-Item -LiteralPath $catalog).Length -le 4MB) {
    $cfg=[IO.File]::ReadAllText($catalog) | ConvertFrom-Json
    foreach($entry in $cfg.servers) {
        $candidates=@([string]$entry.path)
        if ((Is-PlainLocal $entry.path_file) -and (Get-Item -LiteralPath $entry.path_file).Length -le 8192) {
            $candidates+=([IO.File]::ReadAllText($entry.path_file).Trim())
        }
        foreach($dir in $candidates) {
            if ((Is-PlainLocal $dir) -and (Test-Path -LiteralPath (Join-Path $dir 'server.properties') -PathType Leaf)) {
                [void]$roots.Add([IO.Path]::GetFullPath($dir))
            }
        }
    }
}
$index=0
foreach ($root in ($roots|Sort-Object)) {
    $index++
    $key="server-$index"
    Add-Sample 'Server properties' $key (Join-Path $root 'server.properties')
    Add-Sample 'Plugin JAR' $key (First-LocalFile (Join-Path $root 'plugins') '*.jar')
    $worldDirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { (Is-PlainLocal $_.FullName) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'level.dat') -PathType Leaf) } |
        Sort-Object Name | Select-Object -First 2)
    $n=0
    foreach($world in $worldDirs) {
        $n++
        Add-Sample 'World level.dat' "$key-world-$n" (Join-Path $world.FullName 'level.dat')
        Add-Sample 'Player .dat' "$key-world-$n" (First-LocalFile (Join-Path $world.FullName 'playerdata') '*.dat')
        Add-Sample 'World region .mca' "$key-world-$n" (First-LocalFile (Join-Path $world.FullName 'region') '*.mca')
        # Recent server versions store player saves, chunks or both in world subdirectories.
        Add-Sample 'Player .dat' "$key-world-$n-players" (First-LocalFile (Join-Path $world.FullName 'players/data') '*.dat')
        Add-Sample 'World region .mca' "$key-world-$n-modern" (First-LocalFile (Join-Path $world.FullName 'dimensions/minecraft/overworld/region') '*.mca')
    }
}
foreach ($pf in @([Environment]::GetFolderPath('ProgramFiles'),[Environment]::GetFolderPath('ProgramFilesX86'))) {
    $install=Join-Path $pf 'Geumyi Server Center'
    foreach($binary in @('GeumyiServerHost.exe','GeumyiServerCenter.exe')) {
        Add-Sample 'GSC program' (($pf -eq [Environment]::GetFolderPath('ProgramFiles')).ToString()+'-'+$binary) (Join-Path $install $binary)
    }
}
Add-Sample 'Original v2 EXE' 'v2-original' $OriginalV2
$sampleArray=@($script:samples | Sort-Object group,key)
if ($sampleArray.Count -eq 0) { throw 'No samples were available.' }
if ($Mode -eq 'Baseline') {
    if ([IO.File]::Exists($baseline)) { throw 'A preservation baseline already exists in this evidence folder.' }
    [IO.File]::WriteAllText($baseline,(ConvertTo-Json -InputObject $sampleArray -Depth 4),$utf8)
    [pscustomobject]@{ mode=$Mode; sampled=$sampleArray.Count; skipped=$script:skipped; groups=@($sampleArray|Group-Object group|Select-Object Name,Count) } | ConvertTo-Json -Depth 4
} else {
    $before=@([IO.File]::ReadAllText($baseline)|ConvertFrom-Json)
    $diff=@(Compare-Object $before $sampleArray -Property group,key,bytes,sha256)
    $result=[ordered]@{ mode=$Mode; unchanged=($diff.Count -eq 0); before=$before.Count; after=$sampleArray.Count; skipped=$script:skipped; groups=@($sampleArray|Group-Object group|Select-Object Name,Count); mismatchedIds=@($diff|ForEach-Object {$_.group+'/'+$_.key}|Select-Object -Unique) }
    $json=$result|ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($summaryFile,$json,$utf8)
    $json
    if ($diff.Count -gt 0) { throw 'At least one sample or digest changed. Inspect the local environment before attributing a cause.' }
}
