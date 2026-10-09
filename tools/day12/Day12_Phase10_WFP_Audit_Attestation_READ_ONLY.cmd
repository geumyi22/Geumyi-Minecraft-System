@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 12.10 WFP Historical Bind Audit READ ONLY
echo ==========================================================
echo Day12 Phase10 - Windows Security WFP 5154 / 5158 AUDIT
echo ==========================================================
echo Reads existing Windows Security events only (no audit policy changes).
echo Run on the Minecraft SERVER PC; event log reading may require admin.
echo Does NOT scan TCP tables, connect ports, restart servers or edit files.
echo Missing events are UNKNOWN, not PASS. No Stable promotion.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_WFP_Audit_Attestation_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo JSON: Desktop\Geumyi-Day12-WFP\Day12-WFP-Bind-*.json
echo Exit code: %EC%
pause
exit /b %EC%
