@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  Geumyi GSC 4.5.2 Task Scheduler COM Read-Only Hints
echo  NO server restart, task change, log enable or privilege escalation.
echo ============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_TaskInstance_COM_READ_ONLY.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" echo [CAPTURED] Sanitized report saved to Desktop.
if not "%EXIT_CODE%"=="0" echo [INCOMPLETE] Do not change live scheduler settings.
pause
exit /b %EXIT_CODE%
