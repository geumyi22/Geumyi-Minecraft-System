@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =============================================================
echo  GSC HOST MANAGED CONTROL OPT-IN - ATTENDED ADMIN OPERATION
echo  WARNING: This writes service-only environment and RESTARTS
echo  the GSC HOST service. It does NOT restart Velocity or Paper.
echo  Requires protected original Host/Velocity recovery evidence.
echo  RUN ONLY AFTER reviewing approved maintenance and Plan PASS.
echo =============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Managed_OptIn.ps1" -Mode Apply -Approved
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo HOST OPT-IN UNCONFIRMED. Do not run Wild cutover.
pause
exit /b %RC%
