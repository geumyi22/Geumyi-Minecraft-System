@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =============================================================
echo  GSC HOST MANAGED CONTROL OPT-IN - ORIGINAL ENV RESTORE
echo  Requires old Scheduler tasks still RUNNING and no owned JVM.
echo  RESTARTS GSC HOST ONLY. NEVER after any Velocity cutover.
echo =============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Managed_OptIn.ps1" -Mode Restore -Approved
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo HOST RESTORE UNCONFIRMED. Follow private recovery guide.
pause
exit /b %RC%
