param([switch]$Test)
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'
$bin = Join-Path $PSScriptRoot 'bin'
$compiler = Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows x64용 .NET Framework 4.x 컴파일러가 필요합니다.' }
[IO.Directory]::CreateDirectory($bin) | Out-Null
$common = @('/nologo','/warn:4','/warnaserror+','/platform:x64','/optimize+','/codepage:65001',
  '/reference:System.dll,System.Core.dll,System.Drawing.dll,System.Windows.Forms.dll,System.Management.dll,System.ServiceProcess.dll,System.Xml.dll,Microsoft.CSharp.dll,System.Web.Extensions.dll,System.Runtime.Serialization.dll,System.Security.dll')
$sources = @(Get-ChildItem -LiteralPath $src -Filter '*.cs' -File | Sort-Object Name | ForEach-Object FullName)
$exe = Join-Path $bin 'GMS_OperatingMode_v3.0.1.exe'
& $compiler @common '/target:winexe' "/win32manifest:$src\app.manifest" "/out:$exe" @sources
if ($LASTEXITCODE) { throw "EXE compile failed ($LASTEXITCODE)." }
Write-Output "BUILT $exe"
if ($Test) {
    foreach ($suite in @('TransactionTests','WindowsAdapterTests','AppIntegrationTests','RuntimeOpsTests')) {
        $entry = if ($suite -in @('WindowsAdapterTests','RuntimeOpsTests')) { "GmsMode.$suite" } else { $suite }
        $testExe = Join-Path $bin ($suite + '.exe')
        & $compiler @common '/target:exe' "/main:$entry" "/out:$testExe" @sources (Join-Path $PSScriptRoot "tests\$suite.cs")
        if ($LASTEXITCODE) { throw "$suite compile failed." }
        if ($suite -eq 'WindowsAdapterTests') { & $testExe $bin } else { & $testExe }
        if ($LASTEXITCODE) { throw "$suite failed." }
    }
}
