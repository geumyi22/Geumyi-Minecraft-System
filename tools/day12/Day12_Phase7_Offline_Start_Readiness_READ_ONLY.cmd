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
echo - Supports detected GSC Host 4.3.8 or 4.5.1, zero jobs, zero Playground players
echo - Checks protected+verified Playground full backup
echo - Checks explicit non-managed update policy and safe phase
echo - Does NOT start the actual offline test or change managed update policy.
echo - Other Paper remains intentionally OFFLINE throughout this precheck.
echo - Host version and update policy guard failures are REVIEW, not server crash.
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
