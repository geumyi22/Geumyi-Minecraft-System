@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Phase10 - NATIVE TCP CLASS CROSSCHECK READ ONLY
echo ======================================================
echo Day12 Phase10 - Windows Native TCP Listener CROSSCHECK
echo ======================================================
echo Run on SERVER PC as Administrator. READ ONLY.
echo No firewall edits, ACL changes, backup updates or restarts.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Native_Listener_Crosscheck_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Native-TCP
echo Exit code: %EC%
pause
exit /b %EC%
