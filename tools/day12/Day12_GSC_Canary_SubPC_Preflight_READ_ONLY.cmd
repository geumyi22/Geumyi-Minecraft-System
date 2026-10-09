@echo off
setlocal
chcp 65001 >nul
title Day12 GSC Canary - SUB PC Client Only READ ONLY
echo ===========================================================
echo DAY12 GSC 4.3.9-rc.1 SUB PC PRECHECK - READ ONLY
echo ===========================================================
echo Use ONLY on the intended SUB PC, NOT Minecraft SERVER PC.
echo Verifies 4.3.8 client build/role without exposing credentials.
echo Does not launch installer, stop or restart GSC, modify registry,
echo update channel, firewall, server, plugins or worlds.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_GSC_Canary_SubPC_Preflight_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo JSON: Desktop\Geumyi-Day12-SubPC-GSC\Day12-SubPC-GSC-Preflight-*.json
echo Code: %EC%
pause
exit /b %EC%
