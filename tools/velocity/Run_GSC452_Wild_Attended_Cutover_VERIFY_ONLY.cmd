@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  GSC 4.5.2 Wild -- ACTION TOKEN + CUTOVER GATES READ ONLY
echo  NO Scheduler changes, NO Java stop, NO Host restart.
echo  Never accepts live-disconnect approval in this mode.
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run_GSC452_Wild_Attended_Cutover_ADMIN.ps1" -VerifyOnly
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo READ-ONLY GATE DID NOT PASS. DO NOT RUN LIVE CUTOVER.
pause
exit /b %RC%
