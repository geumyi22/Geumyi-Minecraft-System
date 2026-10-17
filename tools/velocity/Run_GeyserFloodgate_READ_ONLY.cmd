@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ===========================================================
echo  Geumyi GSC 4.5.2 Geyser/Floodgate Fingerprint READ ONLY
echo  No restarts, commands, secrets, firewall, worlds or backups.
echo ===========================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_GeyserFloodgate_READ_ONLY.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" echo [CAPTURED] Sanitized JSON is on your Desktop.
if not "%EXIT_CODE%"=="0" echo [INCOMPLETE] Do not change server state; send only this screen.
echo.
pause
exit /b %EXIT_CODE%
