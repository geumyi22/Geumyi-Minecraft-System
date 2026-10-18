@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  Geumyi GSC 4.5.2 Host Principal [READ ONLY]
echo  No restart, ACL changes, DPAPI access, elevation or exports.
echo ============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_GSC_HostPrincipal_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="0" echo [CAPTURED] Sanitized host-account comparison on Desktop.
if not "%EC%"=="0" echo [INCOMPLETE] Host identity was not changed or probed with elevated rights.
pause
exit /b %EC%
