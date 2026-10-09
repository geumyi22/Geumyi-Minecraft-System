@echo off
setlocal
chcp 65001 >nul
title GSC 4.3.9-rc.2 - SUB PC READ ONLY POSTCHECK
echo ==========================================================
echo DAY12 GSC RC2 - SECONDARY PC CLIENT RUNTIME POSTCHECK
echo ==========================================================
echo ONLY on your secondary PC, never the Minecraft server PC.
echo First start the GSC Client normally via the Windows Start menu.
echo Then run THIS tool. It never starts/stops/updates any process.
echo It verifies the installed RC2 hash, Client process, localhost
echo dashboard icon, and official 4.3.8 backup; NO credentials read.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_GSC_RC2_SubPC_Postcheck_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-SubPC-GSC\Day12-SubPC-GSC-RC2-Postcheck-*.json
echo Exit code: %EC%
pause
exit /b %EC%
