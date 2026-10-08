@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 - Build Known-Good Cache
echo ============================================================
echo  DAY 12 PHASE 12.7 - KNOWN-GOOD CACHE BUILD
echo ============================================================
echo Uses the latest PASS Phase 12.0B GoldenCheckpoint report.
echo Does NOT stop servers or alter source files.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase7_KnownGood_Build.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Exit code: %EC%
pause
exit /b %EC%
