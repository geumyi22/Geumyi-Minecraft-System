@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title Geumyi Day12 - Cloud Path Diagnostic v4 [READ ONLY]
echo =======================================================================
echo Day12 Cloud path diagnostic v4 - Google Drive / OneDrive
echo This does NOT back up, upload, restore, stop or restart ANY server.
echo Other Paper stays intentionally OFFLINE. It will not be started.
echo =======================================================================
echo.
echo [1/2] v4 Windows synthetic path and privacy tests (temporary fixtures)...
set "SCRIPT=%~dp0Day12_Cloud_Recovery_Preflight_READ_ONLY.ps1"
if not exist "%SCRIPT%" (
  echo [BLOCKED] The PowerShell script is missing. Extract the entire ZIP.
  pause
  exit /b 2
)
if not exist "%~dp0Test_Cloud_Preflight_V4.ps1" (
  echo [BLOCKED] v4 test file is missing. Extract the entire NEW v4 ZIP.
  pause
  exit /b 2
)
powershell.exe -STA -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%" -Synthetic
if errorlevel 1 (
  echo [BLOCKED] Cloud read-only preflight self-test failed.
  pause
  exit /b 3
)
echo.
echo [2/2] Select the EXISTING Google Drive folder, then confirm OneDrive.
echo Choose the signed-in Drive folders, NOT your live server folders.
echo OneDrive candidates are shown locally. Enter a number or browse.
echo This confirms a path only, not account ownership or cloud synchronization.
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Interactive
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" (
  echo [BLOCKED] Discovery failed before a report was written.
  echo Do NOT change cloud accounts or copy live worlds yet.
)
echo Send ONLY: DAY12-CLOUD-PREFLIGHT-V4-SHARE-ONLY-THIS.json
echo Never share server.json, token, cloud login or raw world ZIP here.
pause
exit /b %RESULT%
