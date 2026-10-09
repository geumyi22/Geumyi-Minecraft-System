@echo off
setlocal
chcp 65001 >nul
title Day12 GSC Guard Rollout Compatibility - READ ONLY
echo ===========================================================
echo DAY12 - GSC 4.3.8 SECURITY GUARD ROLLOUT PRECHECK
echo ===========================================================
echo Run ONCE on the Minecraft SERVER PC.
echo This checks ONLY existing GSC profile and server.properties.
echo It does NOT install, update, restart, modify config or firewall.
echo Even compatible result is NOT backend bind verification PASS.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_GSC_Guard_Rollout_Precheck_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Report: Desktop\Geumyi-Day12-GSC-Guard\Day12-GSC-Guard-Precheck-*.json
echo Exit code: %EC%
pause
exit /b %EC%
