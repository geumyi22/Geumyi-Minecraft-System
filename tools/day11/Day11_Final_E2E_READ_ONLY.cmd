@echo off
setlocal
title Geumyi Day 11 Final E2E - READ ONLY
echo.
echo ============================================================
echo  GEUMYI DAY 11 FINAL E2E - READ ONLY
echo ============================================================
echo  No server restart, no update apply, no policy change,
echo  no Minecraft restore, and no backup delete/move.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day11_Final_E2E_READ_ONLY.ps1"
set ERR=%ERRORLEVEL%
echo.
echo Exit code: %ERR%
pause
exit /b %ERR%
