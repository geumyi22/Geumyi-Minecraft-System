@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Phase10 - Firewall Target Rule Review READ ONLY
echo ===============================================================
echo DAY12 12.10 - WINDOWS ACTIVESTORE RULE REVIEW (READ ONLY)
echo ===============================================================
echo Reads rules related to 8 private Java/RCON and 3 public TCP ports.
echo Includes enabled inbound Allow and Block candidates.
echo Does NOT modify firewall, port binding, audit policy or servers.
echo Candidate counts are NOT a firewall PASS or Stable approval.
echo Run ONLY on Minecraft SERVER PC, preferably as Administrator.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Firewall_Target_Rules_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Report: Desktop\Geumyi-Day12-Firewall-Target\Day12-Firewall-Target-*.json
echo Exit code: %EC%
pause
exit /b %EC%
