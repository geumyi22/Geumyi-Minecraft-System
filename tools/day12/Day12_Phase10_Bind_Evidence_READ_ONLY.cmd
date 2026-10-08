@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12.10 Bind Evidence - READ ONLY
echo ==========================================================
echo  DAY 12.10 - BACKEND BIND EVIDENCE (READ ONLY)
echo ==========================================================
echo Reads selected server-ip / server-port settings and Windows TCP listeners.
echo Does NOT change server files, firewall, services or running processes.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Bind_Evidence_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Exit code: %EC%
echo Saved JSON: Desktop\Geumyi-Day12-Bind-Evidence
pause
exit /b %EC%
