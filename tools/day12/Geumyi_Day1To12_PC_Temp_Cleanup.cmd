@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 1-12 PC Cleanup - SAFE MENU
echo.
echo Geumyi Minecraft System - Day 1 to Day 12 PC temporary cleanup
echo Default action PREVIEW. No world, plugin, backup, Golden, cache or service changes.
echo Day12 temp evidence remains protected until final completion.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Geumyi_Day1To12_PC_Temp_Cleanup_Menu.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Exit code: %EC%
pause
exit /b %EC%
