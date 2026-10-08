@echo off
setlocal
chcp 65001 >nul
title Geumyi Day 12 Phase 2+5 - Integrity and Security READ ONLY
echo =============================================================
echo Day12 12.2 + 12.5 - READ ONLY FINGERPRINT and FIREWALL / ACL
echo =============================================================
echo Run on the SERVER PC. Windows administrator privileges recommended.
echo This reads files, ACL and firewall rules but does not modify them.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase2_5_Integrity_Security_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Integrity-Security
echo Exit code: %EC%
pause
exit /b %EC%
