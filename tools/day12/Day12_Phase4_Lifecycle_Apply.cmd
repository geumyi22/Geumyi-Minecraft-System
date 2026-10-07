@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Phase 4 - Lifecycle Apply to Trash
echo ============================================================
echo  DAY 12 PHASE 4 - LIFECYCLE APPLY
echo ============================================================
echo This moves eligible backups to GSC Trash and old logs to
echo LogTrash after creating a verified local ZIP archive.
echo NO permanent backup/log deletion is performed.
echo Review the DRY-RUN report first.
echo.
set /p CONF=Type APPLY_DAY12_LIFECYCLE_TO_TRASH to continue: 
if not "%CONF%"=="APPLY_DAY12_LIFECYCLE_TO_TRASH" (
  echo [BLOCKED] Confirmation did not match.
  pause
  exit /b 23
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase4_Lifecycle_Apply.ps1" -PolicyPath "%~dp0..\..\deploy\day12-lifecycle-policy.json" -Confirm "APPLY_DAY12_LIFECYCLE_TO_TRASH"
set EC=%ERRORLEVEL%
echo.
echo Exit code: %EC%
pause
exit /b %EC%
