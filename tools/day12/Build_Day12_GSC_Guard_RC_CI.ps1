[CmdletBinding()]
param([string]$OutputDir="")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# RC preview build is restricted to temporary GitHub-hosted Windows runners.
# DO NOT RUN ON THE PRODUCTION MINECRAFT PC. Review binaries are unsigned.
if($env:GITHUB_ACTIONS -ne "true" -or
   $env:GITHUB_REPOSITORY -ne "geumyi22/Geumyi-Minecraft-System" -or
   $env:GEUMYI_GSC_RC_STAGE -ne "isolated_ci_review_only" -or
   -not $env:GITHUB_SHA -or -not $env:RUNNER_TEMP -or
   [Environment]::OSVersion.Platform.ToString() -ne "Win32NT"){
  throw "REFUSED_OUTSIDE_DISPOSABLE_GITHUB_CI"
}
$version="4.3.9-rc.1"
$root=(Resolve-Path "GSC/ServerCenter").Path
$work=Join-Path $env:RUNNER_TEMP "Geumyi-Day12-GSC-RC-Source"
if(Test-Path -LiteralPath $work){throw "STAGING_PATH_ALREADY_EXISTS"}
Copy-Item -LiteralPath $root -Destination $work -Recurse -Force
function Replace-Exact([string]$Relative,[string]$From,[string]$To){
  $path=Join-Path $work $Relative
  $raw=Get-Content -LiteralPath $path -Raw -Encoding UTF8
  $parts=$raw.Split([string[]]@($From),[StringSplitOptions]::None)
  if($parts.Count -ne 2){throw "VERSION_TOKEN_MISSING_OR_DUPLICATE: $Relative"}
  Set-Content -LiteralPath $path -Value ($parts[0]+$To+$parts[1]) -NoNewline -Encoding UTF8
}
Replace-Exact "cmd/host/main.go" 'const appVersion = "4.3.8"' 'const appVersion = "4.3.9-rc.1"'
Replace-Exact "cmd/client/main.go" 'const appVersion = "4.3.8"' 'const appVersion = "4.3.9-rc.1"'
Replace-Exact "cmd/setup/main.go" 'const version = "4.3.8"' 'const version = "4.3.9-rc.1"'
Replace-Exact "cmd/setup/main.go" 'payload/README-v4.3.8.txt' 'payload/README-v4.3.9-rc.1.txt'
Replace-Exact "cmd/setup/main.go" 'README-v4.3.8.txt"))' 'README-v4.3.9-rc.1.txt"))'
Replace-Exact "cmd/setup/main.go" 'server-before-v4.3.8-' 'server-before-v4.3.9-rc.1-'
Replace-Exact "build.ps1" '-o dist/GeumyiServerCenter-v4.3.8-Setup.exe ./cmd/setup' '-o dist/GeumyiServerCenter-v4.3.9-rc.1-Setup.exe ./cmd/setup'
Replace-Exact "build.ps1" 'Created dist/GeumyiServerCenter-v4.3.8-Setup.exe' 'Created dist/GeumyiServerCenter-v4.3.9-rc.1-Setup.exe'
$baseReadme=Join-Path $work "cmd/setup/payload/README-v4.3.8.txt"
$newReadme=Join-Path $work "cmd/setup/payload/README-v4.3.9-rc.1.txt"
if(-not (Test-Path -LiteralPath $baseReadme)){throw "BASELINE_PAYLOAD_README_MISSING"}
$orig=Get-Content -LiteralPath $baseReadme -Raw -Encoding UTF8
$warning="UNSIGNED DAY12 GSC GUARD 4.3.9-rc.1 PREVIEW ONLY. DO NOT INSTALL."
Set-Content -LiteralPath $newReadme -Value ($warning+[Environment]::NewLine+$orig.Replace("4.3.8","4.3.9-rc.1")) -Encoding UTF8
foreach($name in @("GeumyiStatusAgent-0.5.4.jar",
 "GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar",
 "GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar")){
 if(-not (Test-Path -LiteralPath (Join-Path $work "cmd/setup/payload/$name"))){
   throw "VERIFIED_JAR_PAYLOAD_MISSING"
 }
}
Push-Location $work
try{
  & go test ./...
  if($LASTEXITCODE -ne 0){throw "GO_TEST_FAILED"}
  & .\build.ps1
  if($LASTEXITCODE -ne 0){throw "PREVIEW_SETUP_BUILD_FAILED"}
  $hostExe=Join-Path $work "cmd/setup/payload/GeumyiServerHost.exe"
  $p=Start-Process -FilePath $hostExe -ArgumentList "--day10-selftest" -Wait -PassThru -NoNewWindow
  if($p.ExitCode -ne 0){throw "PREVIEW_HOST_SELFTEST_FAILED"}
}finally{Pop-Location}
if(-not $OutputDir){$OutputDir=Join-Path $env:RUNNER_TEMP "Geumyi-Day12-GSC-RC-Review"}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$map=@(
 @("dist/GeumyiServerCenter-v4.3.9-rc.1-Setup.exe","GeumyiServerCenter-v4.3.9-rc.1-Setup.exe"),
 @("cmd/setup/payload/GeumyiServerHost.exe","GeumyiServerHost-v4.3.9-rc.1.exe"),
 @("cmd/setup/payload/GeumyiServerCenter.exe","GeumyiServerCenter-v4.3.9-rc.1.exe")
)
foreach($m in $map){
 $srcFile=Join-Path $work $m[0]
 if(-not (Test-Path -LiteralPath $srcFile) -or (Get-Item -LiteralPath $srcFile).Length -lt 100000){
   throw "MISSING_OR_SMALL_PREVIEW_BINARY"
 }
 Copy-Item -LiteralPath $srcFile -Destination (Join-Path $OutputDir $m[1]) -ErrorAction Stop
}
$metadata=[ordered]@{
 schema=1;candidate_version=$version;deployed_baseline_version="4.3.8"
 source_commit=$env:GITHUB_SHA;review_only=$true;unsigned=$true
 go_test_pass=$true;day10_host_selftest_pass=$true
 operator_install_approved=$false;production_host_modified=$false
 stable_published=$false;backend_ports_private="UNCHANGED_FAIL"
 note="Built in disposable CI from version-stamped TEMP copy. Not a signed release or approved production update."
}
$metadata|ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDir "RC-METADATA.json") -Encoding UTF8
$readme=@'
GSC 4.3.9-rc.1 PREVIEW BUILD — UNSIGNED, REVIEW ONLY.
DO NOT INSTALL OR DOUBLE-CLICK THESE EXECUTABLES ON YOUR SERVER.
A production update requires verified signing, explicit user consent,
player/backup preflight and documented rollback.
The server PC and GSC 4.3.8 are unchanged. Day12.10 strict bind
proof and stable promotion remain BLOCKED.
'@
Set-Content -LiteralPath (Join-Path $OutputDir "DO-NOT-INSTALL-README.txt") -Value $readme -Encoding UTF8
$files=@(Get-ChildItem -LiteralPath $OutputDir -File|Where-Object{$_.Name -ne "SHA256SUMS.txt"})
$hashLines=@($files|ForEach-Object {"$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"})
Set-Content -LiteralPath (Join-Path $OutputDir "SHA256SUMS.txt") -Value $hashLines -Encoding ascii
Write-Host "CI-only unsigned GSC $version package staged. DO NOT INSTALL."
