@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Phase 1 - Managed Content
echo Use the READ-ONLY preflight first.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase1_Content_Preflight_READ_ONLY.ps1"
set EC=%ERRORLEVEL%
echo.
echo Exit code: %EC%
pause
exit /b %EC%
