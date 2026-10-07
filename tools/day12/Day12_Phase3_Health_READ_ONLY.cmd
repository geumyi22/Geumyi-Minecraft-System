@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Phase 3 - Whole System Health READ ONLY
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase3_Health_READ_ONLY.ps1"
set EC=%ERRORLEVEL%
echo.
echo Exit code: %EC%
pause
exit /b %EC%
