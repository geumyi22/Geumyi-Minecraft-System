@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  GSC 4.5.2 Canary-to-Canary HOST HOTFIX STAGING ONLY
echo  WARNING: This copies files into NEW protected ProgramData staging.
echo  No Host restart, service reconfiguration, proxy/JVM/Paper changes.
echo  NEVER use prior 4.5.1-to-Canary Host swap on active Canary.
echo ============================================================
fltmc >nul 2>&1
if errorlevel 1 (
 echo BLOCKED: Run CMD as Administrator.
 pause
 exit /b 5
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Canary_Hotfix_STAGE_ONLY.ps1" -Mode Stage
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo NOT STAGED: preserve any partial immutable staging; do not retry blindly.
if "%RC%"=="0" echo NEW HOTFIX STAGED ONLY. Existing GSC Host service unchanged.
pause
exit /b %RC%
