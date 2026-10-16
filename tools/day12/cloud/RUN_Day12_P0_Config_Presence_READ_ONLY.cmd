@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12 P0 Config Presence - READ ONLY
cd /d "%~dp0"
echo ========================================================
echo Day12 P0 Config Presence [READ ONLY]
echo Exact-file metadata only: NO contents, backup, upload
echo Will not start/stop Minecraft, GSC or cloud sync.
echo ========================================================
if not exist "%~dp0Day12_P0_Config_Presence_READ_ONLY.ps1" (
  echo [BLOCKED] Missing script.
  pause
  exit /b 2
)
if not exist "%~dp0Day12_Cloud_Recovery_Plan_READ_ONLY.ps1" (
  echo [BLOCKED] Missing v5 dependency.
  pause
  exit /b 2
)
if not exist "%~dp0Day12_Cloud_Recovery_Preflight_READ_ONLY.ps1" (
  echo [BLOCKED] Missing v4 dependency.
  pause
  exit /b 2
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_P0_Config_Presence_READ_ONLY.ps1"
set "RET=%ERRORLEVEL%"
if not "%RET%"=="0" (
  echo [BLOCKED] Safely declined. No server change. Exit %RET%
) else (
  echo [RESULT] File presence metadata only. No backup was made.
)
echo.
echo Send ONLY DAY12-P0-PRESENCE-V1-SHARE-ONLY-THIS.json
pause
exit /b %RET%
