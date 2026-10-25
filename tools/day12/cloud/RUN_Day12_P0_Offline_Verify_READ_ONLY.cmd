@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12 P0 Offline Verification READ ONLY
cd /d "%~dp0"
echo ========================================================
echo Geumyi P0: READ ONLY verify EXISTING encrypted archive
echo No world, service, cloud, backup creation or plaintext file.
echo ========================================================
if not exist "%~dp0p0-offline-verify.exe" (
  echo [BLOCKED] Missing p0-offline-verify.exe
  pause
  exit /b 2
)
if not exist "%~dp0Day12_P0_Offline_Verify_READ_ONLY.ps1" (
  echo [BLOCKED] Missing PowerShell verifier.
  pause
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_P0_Offline_Verify_READ_ONLY.ps1"
set "RET=%ERRORLEVEL%"
if not "%RET%"=="0" (
  echo [BLOCKED] No original, cloud or service change.
) else (
  echo [PASS] Local AES-GCM authentication verified.
)
echo.
pause
exit /b %RET%
