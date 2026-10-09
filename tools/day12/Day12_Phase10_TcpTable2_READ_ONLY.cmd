@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 12.10 - GetTcpTable2 IPv4 READ ONLY
echo ============================================================
echo Day12 12.10 - Windows GetTcpTable2 LISTEN evidence
echo ============================================================
echo Run on SERVER PC, ordinary user permissions.
echo IPv4 only. Does not open TCP connections or change any server data.
echo Collects three closely spaced snapshots of six online ports.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_TcpTable2_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-TcpTable2
echo Exit code: %EC%
pause
exit /b %EC%
