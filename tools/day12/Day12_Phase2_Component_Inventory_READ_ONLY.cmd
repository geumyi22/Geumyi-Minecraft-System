@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Phase 2 - Component Inventory READ ONLY
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase2_Component_Inventory_READ_ONLY.ps1"
set EC=%ERRORLEVEL%
echo.
echo Exit code: %EC%
pause
exit /b %EC%
