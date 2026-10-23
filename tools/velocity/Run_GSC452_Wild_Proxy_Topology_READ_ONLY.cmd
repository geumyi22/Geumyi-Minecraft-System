@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ========================================================
echo GSC 4.5.2 CANARY WILD proxy port topology READ ONLY
echo Existing tasks, GSC Host, Java, ports, ACL, worlds unchanged
echo ========================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Wild_Proxy_Topology_READ_ONLY.ps1"
set "code=%errorlevel%"
echo.
echo SHARE ONLY THE SANITIZED JSON. No PID, path, XML or secrets.
echo No process stop or cutover is authorized by this result.
pause
exit /b %code%
