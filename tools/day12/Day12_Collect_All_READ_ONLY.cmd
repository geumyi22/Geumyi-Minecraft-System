@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 - Collect All READ ONLY
echo ============================================================
echo  GEUMYI DAY 12 - COLLECT ALL READ-ONLY EVIDENCE
echo ============================================================
echo This does NOT create backups, apply content, restart servers,
echo modify firewall/configs, or build the known-good cache.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Collect_All_READ_ONLY.ps1"
set EC=%ERRORLEVEL%
echo.
echo Collection finished. Exit=%EC%
pause
exit /b %EC%
