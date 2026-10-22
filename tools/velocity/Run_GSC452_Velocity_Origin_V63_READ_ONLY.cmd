@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =========================================================
echo GSC 4.5.2 Velocity V6.3 - PROCESS ORIGIN - READ ONLY
echo No server, ACL, firewall, Scheduled Task, Java changes.
echo Run as administrator. No automatic privilege elevation.
echo =========================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Velocity_Origin_V63_READ_ONLY.ps1"
set "result=%errorlevel%"
echo.
echo Share ONLY the sanitized JSON above.
echo Exit 0=collected, 2=incomplete, 3=admin needed, 4=environment mismatch.
echo No report authorizes JVM stop, Scheduler change or migration.
pause
exit /b %result%
