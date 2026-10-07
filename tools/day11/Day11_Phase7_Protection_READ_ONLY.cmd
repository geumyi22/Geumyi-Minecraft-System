@echo off
setlocal
title Geumyi Day 11 Phase 7 - Protection READ ONLY
echo.
echo ============================================================
echo  Geumyi Minecraft System - Day 11 Phase 7 READ ONLY
echo ============================================================
echo  No backup/server/world mutation is performed.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day11_Phase7_Protection_READ_ONLY.ps1"
set ERR=%ERRORLEVEL%
echo.
echo Exit code: %ERR%
pause
exit /b %ERR%
