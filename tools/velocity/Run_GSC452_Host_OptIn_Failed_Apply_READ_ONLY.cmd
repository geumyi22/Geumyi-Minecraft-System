@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ================================================================
echo  GSC 4.5.2 Host managed opt-in failed Apply -- READ ONLY
echo  Checks current Host service / service flag / private journal
echo  / localhost Canary API and 3 original Scheduler task states.
echo  No registry, service, Java, task or world changes.
echo  Only sanitized result JSON is printed; DO NOT paste secrets.
echo ================================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_OptIn_Failed_Apply_READ_ONLY.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo READ-ONLY CHECK COULD NOT VERIFY STATE. DO NOT RETRY APPLY OR RESTORE.
pause
exit /b %RC%
