@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Phase 0B - Protected Golden Checkpoint
echo ============================================================
echo  DAY 12 PHASE 0B - GOLDEN RECOVERY CHECKPOINT
echo ============================================================
echo This creates protected FULL backups. It NEVER stops servers.
echo All four backend servers must already be OFFLINE.
echo.
set /p CONF=Type CREATE_PROTECTED_DAY12_GOLDEN to continue: 
if not "%CONF%"=="CREATE_PROTECTED_DAY12_GOLDEN" (
  echo [BLOCKED] Confirmation did not match.
  pause
  exit /b 23
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase0B_Golden_Checkpoint.ps1" -Confirm "CREATE_PROTECTED_DAY12_GOLDEN"
set EC=%ERRORLEVEL%
echo.
echo Exit code: %EC%
pause
exit /b %EC%
