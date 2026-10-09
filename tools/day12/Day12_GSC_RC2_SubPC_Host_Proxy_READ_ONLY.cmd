@echo off
setlocal
chcp 65001 >nul
title Day12 GSC RC2 - SubPC Host connection READ ONLY
echo ==========================================================
echo DAY12 RC2 SUB PC - AUTHENTICATED HOST STATUS CHECK
echo ==========================================================
echo Run ONLY on the secondary PC, with GSC Client OPEN.
echo Sends GET /api/health and GET /api/status via local GSC Client.
echo Uses already-paired GSC Client proxy. Does NOT read tokens,
echo change pairing/config, or issue any Minecraft action.
echo NO installer, restart, firewall or RCON changes.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_GSC_RC2_SubPC_Host_Proxy_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-SubPC-GSC\Day12-SubPC-GSC-RC2-HostProxy-*.json
echo Exit code: %EC%
pause
exit /b %EC%
