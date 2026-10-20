@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =======================================================
echo GSC 4.5.2 Canary WILD Endpoint differential READ ONLY
echo TCP 25565 / UDP 19132 diagnosed independently.
echo NO Java, task, GSC service, ACL or config changes.
echo =======================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Wild_Endpoint_Differential_READ_ONLY.ps1"
set "result=%errorlevel%"
echo.
echo Even matching evidence does NOT authorize stop or cutover.
pause
exit /b %result%
