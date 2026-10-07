@echo off
setlocal
title Geumyi Day 11 Phase 7 - Disposable Backup E2E
echo.
echo ============================================================
echo  Day 11 Phase 7 - DISPOSABLE CONFIG BACKUP E2E
echo ============================================================
echo  This test NEVER stops/restarts Minecraft and NEVER restores server data.
echo  It creates one disposable CONFIG backup and leaves it recoverable in Trash.
echo.
set /p OK=Type RUN to continue: 
if /I not "%OK%"=="RUN" (
  echo Cancelled.
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day11_Phase7_Disposable_Backup_E2E.ps1" -Confirm "RUN_DISPOSABLE_BACKUP_E2E"
set ERR=%ERRORLEVEL%
echo.
echo Exit code: %ERR%
pause
exit /b %ERR%
