@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =======================================================
echo GSC452 Velocity Java process roles READ ONLY - schema 5
echo No change to GSC, Velocity, Scheduled Tasks or Java.
echo Private process paths, PIDs, XML and args not exported.
echo =======================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Three_Proxy_JVM_Roles_READ_ONLY.ps1"
set "ec=%errorlevel%"
echo.
echo Share ONLY the sanitized JSON output. Never share task XML.
pause
exit /b %ec%
