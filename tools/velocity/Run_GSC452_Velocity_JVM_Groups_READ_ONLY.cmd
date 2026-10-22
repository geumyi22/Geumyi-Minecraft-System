@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =========================================================
echo GSC452 Velocity JVM groups READ ONLY - revision V6.2 / schema 7
echo No Scheduled Task, GSC, Java, firewall or port operations.
echo No private process details will be printed.
echo =========================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Velocity_JVM_Groups_READ_ONLY.ps1"
set "result=%errorlevel%"
echo.
echo Share only sanitized JSON; never share raw process commands.
echo Exit 0=collected; 2=incomplete; 3=admin required; 4=environment mismatch.
echo If result is incomplete do NOT stop or migrate a proxy.
pause
exit /b %result%
