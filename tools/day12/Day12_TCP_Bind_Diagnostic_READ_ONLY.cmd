@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 TCP Bind Diagnostic - READ ONLY
echo ==========================================================
echo  DAY 12 - TCP BIND DIAGNOSTIC (READ ONLY)
echo ==========================================================
echo Checks Windows TCP listener sources without changing ports.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_TCP_Bind_Diagnostic_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Exit code: %EC%
pause
exit /b %EC%
