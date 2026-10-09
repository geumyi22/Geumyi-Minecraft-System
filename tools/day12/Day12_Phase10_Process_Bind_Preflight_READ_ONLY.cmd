@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 12.10 - Process and Bind Preflight - READ ONLY
echo =========================================================
echo Day12 12.10 - Server process/config provenance preflight
echo =========================================================
echo Run on actual Minecraft SERVER PC (regular privileges).
echo Reads GSC server.properties allowlist, Java process metadata
echo and network interface compartments. Does NOT collect TCP scans.
echo Does NOT export usernames, PIDs, command lines or secret keys.
echo Does NOT restart servers or modify any world, setting or backup.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Process_Bind_Preflight_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Process-Bind
echo Exit code: %EC%
pause
exit /b %EC%
