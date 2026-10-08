@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Phase 5 - FIREWALL SCOPE READ ONLY
echo Firewall effective policy context - READ ONLY
echo Run on the SERVER PC with administrator privileges.
echo Does not change firewall rules, ACLs, server processes or backups.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase5_Firewall_Scope_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Firewall-Scope
echo Exit code: %EC%
pause
exit /b %EC%
