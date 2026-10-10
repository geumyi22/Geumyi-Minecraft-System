@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Offline Sandbox Capability (READ ONLY)
echo ===============================================================
echo  Day 12.7 DISPOSABLE NETWORK-ISOLATED SANDBOX - CAPABILITY ONLY
echo ===============================================================
echo  SERVER PC ONLY. This does NOT run a second GSC Host,
echo  DOES NOT launch Sandbox, start Paper, or disconnect networking.
echo  No update policy/firewall/ACL, world, Golden, service changes.
echo  Checks whether offline Sandbox testing can safely be planned.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase7_Disposable_Sandbox_Capability_READ_ONLY.ps1"
set "RET=%ERRORLEVEL%"
echo.
echo Upload only:
echo Desktop\Geumyi-Day12-Sandbox-Capability-*\Day12-Sandbox-Capability-READ-ONLY.json
echo.
pause
exit /b %RET%
