@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =============================================================
echo  GSC 4.5.2 HOST managed Velocity opt-in PLAN [READ ONLY]
echo  No Host restart, registry write, task stop or Java operations.
echo  The old Wild/Playground/Other proxies remain unchanged.
echo =============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Managed_OptIn.ps1" -Mode Plan
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo PLAN BLOCKED. No production changes were performed.
pause
exit /b %RC%
