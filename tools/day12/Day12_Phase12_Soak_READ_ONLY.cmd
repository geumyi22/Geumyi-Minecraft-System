@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Soak Test
echo 1. Start snapshot
echo 2. End snapshot
set /p C=Select: 
if "%C%"=="1" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase12_Soak_READ_ONLY.ps1" -Mode Start
if "%C%"=="2" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase12_Soak_READ_ONLY.ps1" -Mode End
pause
