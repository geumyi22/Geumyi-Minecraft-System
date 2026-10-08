@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12.10 LAN Reachability - READ ONLY
echo This is a TCP reachability check from ANOTHER Windows PC.
echo Do NOT run this on the Minecraft host itself.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_LAN_Proof_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-LAN-Proof
echo Exit code: %EC%
pause
exit /b %EC%
