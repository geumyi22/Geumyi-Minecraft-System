@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =======================================================
echo  Geumyi Velocity - READ ONLY Host Inventory
echo  Checks only 3 Day10 tasks, JVM process census and ports.
echo  No Velocity / Paper / GSC / firewall / backup mutations.
echo  Writes a sanitized JSON to Desktop.
echo =======================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_Inventory_OnHost_READ_ONLY.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo [INCOMPLETE] Read-only inventory failed or was blocked.
if "%EXIT_CODE%"=="0" echo [CAPTURED] Read-only inventory captured. LIVE E2E NOT VERIFIED.
echo.
pause
exit /b %EXIT_CODE%
