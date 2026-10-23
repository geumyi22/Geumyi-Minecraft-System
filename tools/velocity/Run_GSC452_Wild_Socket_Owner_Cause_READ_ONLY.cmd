@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =============================================================
echo GSC 4.5.2 WILD TCP/UDP socket cause diagnostics - READ ONLY
echo Independent Get-NetTCPConnection and netstat TCP inspection.
echo No tasks, services, Java, ACL, firewall, config or world changes.
echo =============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Wild_Socket_Owner_Cause_READ_ONLY.ps1"
set "code=%errorlevel%"
echo.
echo Report is NOT permission for task stop or lifecycle cutover.
pause
exit /b %code%
