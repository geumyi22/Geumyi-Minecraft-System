@echo off
setlocal
chcp 65001 >nul
title GSC 4.3.9-rc.2 Client-Only Canary - EXPLICIT CONSENT
echo ============================================================
echo GSC 4.3.9-rc.2 - SUB PC CLIENT ONLY TEST
echo ============================================================
echo This is an actual update on THIS PC. It is NOT read only.
echo NEVER run on the Minecraft SERVER PC.
echo Ed25519 signature and pinned setup/rollback SHA must verify first.
echo You must type UPDATE CLIENT ONLY and approve Windows UAC.
echo Expected GSC Client interruption only, no Minecraft Host changes.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_GSC_RC2_SubPC_Apply_APPROVAL_REQUIRED.ps1"
echo.
echo JSON report saved on DesktopGeumyi-Day12-SubPC-GSC
pause
exit /b %ERRORLEVEL%
