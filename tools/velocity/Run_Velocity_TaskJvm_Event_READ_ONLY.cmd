@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  Geumyi GSC v4.5.2 Task-JVM Evidence [READ ONLY]
echo  No task modifications, Java restarts or secret exports.
echo ============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_TaskJvm_Event_READ_ONLY.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" echo [CAPTURED] Sanitized Task-JVM report saved on Desktop.
if not "%EXIT_CODE%"=="0" echo [INCOMPLETE] Do not change server or share private logs.
pause
exit /b %EXIT_CODE%
