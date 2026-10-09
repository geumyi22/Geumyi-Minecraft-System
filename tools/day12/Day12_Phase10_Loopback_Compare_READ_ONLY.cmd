@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Phase10 - LOOPBACK PORT COMPARE READ ONLY
echo ===========================================================
echo Day12 - Online Java and RCON local loopback reachability
echo ===========================================================
echo Run on SERVER PC; no admin privileges required.
echo One TCP handshake for each Java/RCON port of GSC-online servers.
echo No RCON authentication, command or production settings changes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Loopback_Compare_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Loopback
echo Exit code: %EC%
pause
exit /b %EC%
