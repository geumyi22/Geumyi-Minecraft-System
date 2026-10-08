@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 - Build Known-Good Cache
echo ============================================================
echo  DAY 12 PHASE 12.7 - KNOWN-GOOD CACHE BUILD
echo ============================================================
echo Automatically finds the latest PASS GoldenCheckpoint JSON.
echo If not found, select the JSON in the file picker.
echo Does NOT stop servers or alter source files.
echo.
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0Day12_Phase7_KnownGood_Build.ps1" -ReportPath "%~1"
set "EC=%ERRORLEVEL%"
echo.
echo Exit code: %EC%
pause
exit /b %EC%
