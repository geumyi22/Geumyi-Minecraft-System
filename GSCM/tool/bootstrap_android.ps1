$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "Flutter가 PATH에 없습니다." }
$need = -not (Test-Path "android\gradlew.bat") -or -not (Test-Path "android\gradle\wrapper\gradle-wrapper.jar")
if ($need) {
  $tmp = Join-Path $env:TEMP ("gscm_flutter_" + [guid]::NewGuid().ToString("N"))
  flutter create --platforms=android --org com.geumyi --project-name gscm $tmp
  Copy-Item (Join-Path $tmp "android\gradlew") "android\gradlew" -Force
  Copy-Item (Join-Path $tmp "android\gradlew.bat") "android\gradlew.bat" -Force
  Copy-Item (Join-Path $tmp "android\gradle\wrapper\gradle-wrapper.jar") "android\gradle\wrapper\gradle-wrapper.jar" -Force
  Remove-Item $tmp -Recurse -Force
}
flutter pub get
Write-Host "GSCM Android bootstrap 완료"
