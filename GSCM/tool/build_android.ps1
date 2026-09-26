$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root
& "$PSScriptRoot\bootstrap_android.ps1"
flutter analyze
flutter test
flutter build apk --release
Write-Host "APK: build\app\outputs\flutter-apk\app-release.apk"
