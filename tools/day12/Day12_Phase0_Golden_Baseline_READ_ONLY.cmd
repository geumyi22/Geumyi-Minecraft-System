@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Phase 0A - Golden Baseline READ ONLY
echo.
echo ============================================================
echo  Geumyi Minecraft System - Day 12 Phase 0A READ ONLY
echo ============================================================
echo  Captures the final Day-11 runtime baseline.
echo  No server restart, backup creation, restore, delete, update,
echo  policy change, firewall change, or world/config edit occurs.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase0_Golden_Baseline_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="0" (
  echo [DAY12] Phase 0A capture is ready for review.
) else (
  echo [DAY12] Phase 0A found a mandatory CHECK. Do not create the Golden checkpoint yet. Exit=%EC%
)
pause
exit /b %EC%
