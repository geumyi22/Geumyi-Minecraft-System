@echo off
setlocal
chcp 65001 >nul
title Day12 Phase10 - Java Program / Firewall Scope REVIEW ONLY
echo ===========================================================
echo Day12 12.10 - READ ONLY JAVA APPLICATION RULE CORRELATION
echo ===========================================================
echo Compares current Java executable paths to active Windows
echo Firewall application filters LOCALLY without exporting paths.
echo Does NOT read Java command lines or server credentials.
echo Does NOT add or remove rules, change audit policy, restart
echo game servers, or touch backups/worlds.
echo This is NOT a private-port security PASS.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Java_Program_Rule_Match_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Java-Rule-Match\Day12-Java-Rule-Match-*.json
echo Exit code: %EC%
pause
exit /b %EC%
