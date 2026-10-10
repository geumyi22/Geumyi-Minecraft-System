@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 - 8 hour read-only soak
echo ===========================================================
echo   Day 12.12 - Continuous Soak READ ONLY
echo   8 hours, sample every 5 minutes, no production changes
echo   Keep window OPEN during the entire monitor session
echo ===========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase12_Continuous_Soak_READ_ONLY.ps1" -DurationHours 8 -IntervalMinutes 5
set CODE=%ERRORLEVEL%
echo Soak exit: %CODE%
echo Upload ONLY DAY12-SOAK-SUMMARY-SHARE-ONLY-THIS.json
pause
exit /b %CODE%
