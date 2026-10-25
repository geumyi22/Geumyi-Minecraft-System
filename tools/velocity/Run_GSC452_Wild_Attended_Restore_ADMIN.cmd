@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ================================================================
echo  GSC 4.5.2 Wild Velocity - ORIGINAL TASK RECOVERY
echo  DANGER: May re-enable and start the original Wild proxy.
echo  Never run while GSC owns or may have an orphaned Java process.
echo  Use only after protected evidence and port checks pass.
echo ================================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run_GSC452_Wild_Attended_Restore_ADMIN.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo RESTORE BLOCKED: do not force start any Java process.
if "%RC%"=="0" echo Original task started; check Java and Bedrock login on Wild.
pause
exit /b %RC%
