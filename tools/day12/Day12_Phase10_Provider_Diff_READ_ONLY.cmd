@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 12.10 - TCP Provider Differential - READ ONLY
echo ======================================================
echo Day12 12.10 - Windows TCP LISTENER vs ALL comparison
echo ======================================================
echo Run on SERVER PC. Regular user privileges are enough.
echo No server restarts, network connection probes or setting changes.
echo Only compares four still-unresolved internal ports.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Provider_Diff_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Provider-Diff
echo Exit code: %EC%
pause
exit /b %EC%
