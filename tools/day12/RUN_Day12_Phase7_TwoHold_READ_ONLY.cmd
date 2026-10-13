@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title Geumyi Day12.7 - Two known holds / READ ONLY
echo ============================================================
echo Day12.7 - Already-known TWO holds only, no repeat E2E
echo GSC 4.5.1 Playground / Other deliberately OFFLINE
echo Checks updater policy classification + backup inventory counts
echo READ ONLY: no server restart, no world/backup/config changes
echo ============================================================
echo.
set "SCRIPT=%~dp0Day12_Phase7_TwoHold_RootCause_READ_ONLY.ps1"
if not exist "%SCRIPT%" (
  echo [BLOCKED] PS1 is missing. Extract ALL kit files together.
  pause
  exit /b 2
)
echo [1/2] Synthetic safe/blocked classification fixtures
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%" -Synthetic
if errorlevel 1 (
  echo [BLOCKED] Probe synthetic controls failed. Stop without changing GSC.
  pause
  exit /b 3
)
echo [2/2] Existing GSC localhost GETs (no writes)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RESULT=%ERRORLEVEL%"
echo.
echo Send ONLY file: DAY12-OFFLINE-TWO-HOLD-SHARE-ONLY-THIS.json
echo If blocked before a JSON is created, send only the screen.
echo Do NOT change policy or create/delete backup just to pass a probe.
pause
exit /b %RESULT%
