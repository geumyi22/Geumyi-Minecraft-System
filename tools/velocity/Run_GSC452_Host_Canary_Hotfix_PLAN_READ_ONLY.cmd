@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  GSC 4.5.2 Canary-to-Canary HOST HOTFIX PLAN
echo  READ ONLY. NO service restart, proxy, JVM, Paper or world change.
echo  This does NOT migrate any Velocity proxy.
echo ============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Canary_Hotfix_STAGE_ONLY.ps1" -Mode Plan
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo BLOCKED: leave existing Host and Velocity tasks untouched.
pause
exit /b %RC%
