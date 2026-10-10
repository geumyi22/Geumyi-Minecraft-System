@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12.7 - Offline Startup PRECHECK - READ ONLY
echo ===============================================================
echo GEUMYI DAY 12.7 / OFFLINE STARTUP - READINESS PRECHECK ONLY
echo ===============================================================
echo Run only on the Minecraft SERVER PC. Not on SubPC.
echo.
echo This is NOT an outage or restart. It:
echo - Checks GSC 4.3.8, zero active jobs, Playground player count
echo - Checks protected+verified Playground full backup
echo - Checks explicit non-managed update policy and safe phase
echo - DOES NOT disconnect network, change firewall, restart server
echo - DOES NOT modify world, Java/plugins, Golden, cache, ACL, GSC
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase7_Offline_Start_Readiness_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Upload only:
echo Desktop\Geumyi-Day12-Offline-Readiness-*\Day12-Offline-Readiness-READ-ONLY.json
echo A preflight PASS is NOT actual offline-start E2E completion.
echo Exit code: %EC%
pause
exit /b %EC%
