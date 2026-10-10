@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 - REMAINING 9 PHASES - READ ONLY
echo ===============================================================
echo  GEUMYI DAY 12 / REMAINING 9 PHASES / ONE-CLICK READ ONLY
echo ===============================================================
echo  RUN ON THE MINECRAFT SERVER PC ONLY. Not the SubPC.
echo  Previously verified LAN/Tailnet/Golden/health/DR scans are SKIPPED.
echo  No server restart, firewall edits, updates, content apply,
echo  world changes, backup deletion, credentials or Stable release.
echo  This collects 12.1/12.2 and reviews all still-open phases.
echo  A REVIEW_REQUIRED result is expected and is NOT a Day12 PASS.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\day12\Day12_Remaining_OneClick_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo  Output folder: Desktop\Geumyi-Day12-Remaining-YYYYMMDD-HHMMSS
echo  Upload ONLY the Day12-Remaining-Summary.json file.
echo  Private child reports stay on your computer.
echo  Exit code: %EC%
pause
exit /b %EC%
