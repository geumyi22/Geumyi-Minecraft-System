@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12.10 - SubPC IPv6 Scope Only (READ ONLY)
echo =====================================================
echo SUBPC ONLY: IPv6 route + interface-scope + TCP check
echo No IPv4 retest. No server/firewall/service changes.
echo =====================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_SubPC_IPv6_Scope_Only_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Report: Desktop\Geumyi-Day12-IPv6-Scope
echo Exit code: %EC%
pause
exit /b %EC%
