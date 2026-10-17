@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ===========================================================
echo  Geumyi GSC v4.5.2 Canary Compatibility Check [READ ONLY]
echo  No server/process/scheduler/config/world changes.
echo  Only sanitized Velocity JAR fingerprint and manifest hints.
echo ===========================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_Compatibility_READ_ONLY.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" echo [CAPTURED] Read-only report saved to your Desktop.
if not "%EXIT_CODE%"=="0" echo [INCOMPLETE] Do not change any server settings. Share only this screen.
echo.
pause
exit /b %EXIT_CODE%
