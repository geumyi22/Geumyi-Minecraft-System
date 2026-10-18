@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ==============================================================
echo  Geumyi GSC v4.5.2 Windows Principal Scope [READ ONLY]
echo  NO ACL edits, DPAPI keys, restarts, log changes or elevation.
echo ==============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_PrincipalScope_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="0" echo [CAPTURED] Sanitized relationship JSON on your Desktop.
if not "%EC%"=="0" echo [INCOMPLETE] No server or account settings changed.
pause
exit /b %EC%
