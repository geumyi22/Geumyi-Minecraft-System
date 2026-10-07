@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Phase 4 - Storage Log DRY RUN
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase4_Storage_Log_DRY_RUN.ps1" -PolicyPath "%~dp0..\..\deploy\day12-lifecycle-policy.json"
set EC=%ERRORLEVEL%
echo.
echo Exit code: %EC%
pause
exit /b %EC%
