@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 SubPC Tailscale GSC API Auth CHECK
echo =========================================================
echo DAY12 SubPC-only Tailnet API unauthorized access check
echo No repeat port scan. No token required.
echo Only GET requests. Routine rejected-request audit log may be written on GSC Host.
echo =========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_SubPC_Tailnet_GSC_Unauth_HTTP_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Tailnet-Auth
echo Exit code: %EC%
pause
exit /b %EC%
