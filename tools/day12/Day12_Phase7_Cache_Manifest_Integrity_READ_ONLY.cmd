@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Phase7 Cache Bytes / READ ONLY
echo ===============================================================
echo Day12.7 READ ONLY - existing known-good cache SHA256
echo MINECRAFT SERVER PC ONLY - never run on SubPC.
echo No cache rebuild, no reboot, no network disconnection,
echo no server start/stop, no world or Golden modification.
echo This DOES NOT complete offline startup / Stable release.
echo ===============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase7_Cache_Manifest_Integrity_READ_ONLY.ps1"
set "CODE=%ERRORLEVEL%"
echo.
echo Upload only Desktop\Geumyi-Day12-Cache-Integrity-*\Day12-Cache-Integrity-READ-ONLY.json
echo Exit code: %CODE%
pause
exit /b %CODE%
