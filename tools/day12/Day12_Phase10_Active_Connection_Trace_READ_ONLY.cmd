@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Phase10 - ACTIVE CONNECTION TRACE READ ONLY
echo ============================================================
echo Day12 12.10 - Active TCP Endpoint Trace - READ ONLY
echo ============================================================
echo Server PC only. Run normally; administrator is not required.
echo Checks four GSC-online ports missing from prior LISTEN tables.
echo Opens four short-lived loopback TCP connections, sends no commands.
echo No server restart or firewall/config/ACL/backup modifications.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Active_Connection_Trace_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Active-Connections
echo Exit code: %EC%
pause
exit /b %EC%
