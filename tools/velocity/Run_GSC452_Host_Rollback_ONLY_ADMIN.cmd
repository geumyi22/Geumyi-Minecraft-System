@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =======================================================
echo  GSC Host restore - private original 4.5.1 service target
echo  MAY stop/restart GSC Host; NO Velocity/Paper task edits.
echo  Only for reversing completed service-only Canary swap.
echo =======================================================
fltmc >nul 2>&1
if errorlevel 1 (echo [BLOCKED] Run as administrator.& pause & exit /b 5)
set /p "approval=Type ROLLBACK to restore old GSC Host: "
if /I not "%approval%"=="ROLLBACK" (echo [CANCELLED]& pause & exit /b 0)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Service_Reversible_Swap.ps1" -Mode Rollback -OperatorConfirmed
set "result=%errorlevel%"
pause
exit /b %result%
