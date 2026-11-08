@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12 ACL Change Preflight - READ ONLY
echo ============================================================
echo  Geumyi Day12 ACL Change Preflight - READ ONLY
echo ============================================================
echo No production ACL, service, server, world or backup changes.
echo Writes sanitized and PRIVATE evidence ONLY under LOCALAPPDATA.
echo.
set "SCRIPT=%~dp0Day12_Phase5_ACL_Change_Preflight_READ_ONLY.ps1"
if not exist "%SCRIPT%" (
  echo [BLOCKED] PowerShell script not found next to CMD.
  pause
  exit /b 2
)
echo [1/2] Windows PowerShell 5.1 self-test...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%" -SelfTest
if errorlevel 1 (
  echo [BLOCKED] Self-test failed. Do not continue.
  pause
  exit /b 3
)
echo.
echo [2/2] Read current GSC ACL and service metadata...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%"
if errorlevel 1 (
  echo [BLOCKED] Inspection failed. Share only this screen, not PRIVATE file.
  pause
  exit /b 4
)
echo.
echo [DONE] Open newest folder and share ONLY:
echo DAY12-ACL-CHANGE-PREFLIGHT-SHARE-ONLY-THIS.json
echo Never share PRIVATE-ACL-SDDL-SNAPSHOT-DO-NOT-SHARE.json
explorer.exe "%LOCALAPPDATA%\Geumyi-Day12-ACL-Preflight"
pause
exit /b 0
