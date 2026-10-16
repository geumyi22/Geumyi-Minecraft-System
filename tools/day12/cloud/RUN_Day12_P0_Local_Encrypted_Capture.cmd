@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12 P0 Local Encrypted Backup - Explicit Consent
cd /d "%~dp0"
echo ===========================================================
echo DAY12 P0 LOCAL ENCRYPTED CAPTURE (OPERATOR APPROVAL REQUIRED)
echo 20 selected config/key files only; may hydrate 4 OneDrive files
echo NO worlds, server restart, Cloud upload or provider setting change
echo If blocked, do not retry or upload partial files.
echo ===========================================================
if not exist "%~dp0p0-local-capture.exe" (
  echo [BLOCKED] Missing validated encryption binary.
  pause
  exit /b 2
)
if not exist "%~dp0Day12_P0_Local_Encrypted_Capture.ps1" (
  echo [BLOCKED] Missing local operator script.
  pause
  exit /b 2
)
if not exist "%~dp0Day12_Cloud_Recovery_Plan_READ_ONLY.ps1" (
  echo [BLOCKED] Missing original path verification helper.
  pause
  exit /b 2
)
if not exist "%~dp0Day12_Cloud_Recovery_Preflight_READ_ONLY.ps1" (
  echo [BLOCKED] Missing API path verification helper.
  pause
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_P0_Local_Encrypted_Capture.ps1"
set "RET=%ERRORLEVEL%"
if not "%RET%"=="0" (
  echo [BLOCKED] P0 backup NOT accepted. No automatic cleanup or upload.
) else (
  echo [LOCAL VERIFIED] Do not send keys, files, folder or screenshots of password.
)
echo.
pause
exit /b %RET%
