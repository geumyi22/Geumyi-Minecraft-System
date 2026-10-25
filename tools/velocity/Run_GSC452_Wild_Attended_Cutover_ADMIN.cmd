@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ================================================================
echo  GSC 4.5.2 Wild Velocity - ATTENDED DRAIN AND GSC START
echo  This CAN disconnect players and stop the original proxy.
echo  Only run with admin privileges and a tested recovery plan.
echo  Other servers, Paper, worlds and backups are not modified.
echo ================================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run_GSC452_Wild_Attended_Cutover_ADMIN.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo STOP: No further automatic action. Inspect local Wild recovery state.
if "%RC%"=="0" echo GSC start requested. Java AND Bedrock client join checks are still required.
pause
exit /b %RC%
