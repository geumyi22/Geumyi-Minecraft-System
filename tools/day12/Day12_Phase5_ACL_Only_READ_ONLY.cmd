@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Phase 5 - ACL ONLY READ ONLY
echo =========================================================
echo Day12 12.5 - GSC ACL-only evidence (no firewall rescan)
echo =========================================================
echo Run on SERVER PC as Administrator.
echo This reads only ACL metadata for 5 known targets.
echo No firewall, ACL, configuration, server or backup changes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase5_Rule_ACL_Review_READ_ONLY.ps1" -AclOnly
set "EC=%ERRORLEVEL%"
echo.
echo Output: Desktop\Geumyi-Day12-Rule-ACL-Review
echo Exit code: %EC%
pause
exit /b %EC%
