@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi P0 Google Transfer Preflight READ ONLY
cd /d "%~dp0"
echo ================================================
echo P0 Google Drive preflight - READ ONLY
echo No cloud write, no plaintext, no server changes.
echo ================================================
if not exist "%~dp0Day12_P0_Google_Transfer_Preflight_READ_ONLY.ps1" (
  echo [BLOCKED] Missing verified PowerShell script.
  pause
  exit /b 2
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_P0_Google_Transfer_Preflight_READ_ONLY.ps1"
set "RET=%ERRORLEVEL%"
echo.
echo Send only the safe status lines.
pause
exit /b %RET%
