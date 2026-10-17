@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ===============================================================
echo  GSC 4.5.2 Canary Velocity Task Policy [READ ONLY]
echo  NO task edits, server start/stop, secret exports or restarts.
echo ===============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_TaskPolicy_READ_ONLY.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" echo [CAPTURED] Sanitized task-policy JSON saved to your Desktop.
if not "%EXIT_CODE%"=="0" echo [INCOMPLETE] Leave server untouched; share this screen only.
echo.
pause
exit /b %EXIT_CODE%
