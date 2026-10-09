@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 SubPC Dual-Stack Exposure Proof - READ ONLY
echo ========================================================
echo Day12.10 - SECOND PC ONLY / IPv4 + IPv6 TCP checks
echo ========================================================
echo WARNING: Do not run this on Minecraft SERVER PC.
echo No service restart, firewall edits, credentials or files touched.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_SubPC_DualStack_Exposure_READ_ONLY.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Report folder: Desktop\Geumyi-Day12-DualStack-Proof
echo Exit code: %RESULT%
pause
exit /b %RESULT%
