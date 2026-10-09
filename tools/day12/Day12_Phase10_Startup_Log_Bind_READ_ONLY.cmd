@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 12.10 - STARTUP LOG BINDS - READ ONLY
echo ===================================================
echo Day 12.10 - Paper Java/RCON startup bind log review
echo ===================================================
echo Run on Minecraft SERVER PC as regular user.
echo Reads ONLY first 6MiB of each current latest.log.
echo Does NOT open TCP connections or restart/edit services.
echo No raw logs, IPs, passwords or usernames in JSON.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Startup_Log_Bind_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Startup-Bind
echo Exit code: %EC%
pause
exit /b %EC%
