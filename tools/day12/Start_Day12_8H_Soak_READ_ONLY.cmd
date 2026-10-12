@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title Geumyi Day12 - 8 hour read-only soak / production host
echo ===========================================================
echo   Geumyi Day 12.12 - 8h real HOST stability monitor
echo   Four localhost TCP controls, process identity + resources
echo   READ ONLY: no server start, stop, restart, ACL or world change
echo   IMPORTANT: keep this window OPEN for eight full hours.
echo ===========================================================
echo.
set "TOOL=%~dp0Day12_Phase12_Continuous_Soak_READ_ONLY.ps1"
if not exist "%TOOL%" (
  echo [BLOCKED] Soak PS1 missing. Extract the ZIP first.
  pause
  exit /b 2
)
echo [1/3] Temporary local TCP probe self-test...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%" -ProbeSelfTest
if errorlevel 1 (
  echo [BLOCKED] Native TCP self-test failed. Send this screen.
  pause
  exit /b 3
)
echo [2/3] Confirm existing GSC Host and four local TCP controls...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%" -LivePreflight
if errorlevel 1 (
  echo [BLOCKED] One or more required listeners is not reachable.
  echo Please send the screen. No eight-hour soak was started.
  pause
  exit /b 4
)
echo [3/3] Starting continuous 8 hours. DO NOT CLOSE THIS WINDOW.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%" -DurationHours 8 -IntervalMinutes 5
set "CODE=%ERRORLEVEL%"
echo.
echo Soak exit code: %CODE%
echo If a completed report was written, send ONLY:
echo DAY12-SOAK-SUMMARY-SHARE-ONLY-THIS.json
echo NEVER send PRIVATE-SAMPLES-DO-NOT-UPLOAD.ndjson.
echo.
pause
exit /b %CODE%
