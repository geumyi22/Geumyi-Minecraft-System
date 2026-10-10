@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12.10 Tailscale OVERLAY READ ONLY - SUBPC
echo ==========================================================
echo Day 12.10 / Tailscale OVERLAY only / read-only
echo Run on SUBPC, not the Minecraft SERVER PC.
echo Physical LAN IPv4 and IPv6 already checked. Do not repeat.
echo ==========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_SubPC_Tailnet_Exposure_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Tailnet-Proof
echo Exit code: %EC%
pause
exit /b %EC%
