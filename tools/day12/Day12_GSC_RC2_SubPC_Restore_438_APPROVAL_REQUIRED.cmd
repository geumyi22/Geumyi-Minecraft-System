@echo off
setlocal
chcp 65001 >nul
title GSC Client-Only Restore 4.3.8 - Admin and Consent Required
echo ============================================================
echo GSC OFFICIAL 4.3.8 CLIENT RESTORE - SUB PC ONLY
echo ============================================================
echo Right-click THIS CMD and choose Run as administrator.
echo This changes only the Client EXE after signature and role checks.
echo It requires typing RESTORE 4.3.8.
echo NEVER run on Minecraft SERVER PC.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_GSC_RC2_SubPC_Restore_438_APPROVAL_REQUIRED.ps1"
echo.
echo JSON report saved on DesktopGeumyi-Day12-SubPC-GSC
pause
exit /b %ERRORLEVEL%
