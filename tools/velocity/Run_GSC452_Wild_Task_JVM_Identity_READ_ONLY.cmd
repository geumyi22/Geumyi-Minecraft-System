@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo GSC 4.5.2 WILD Task-JVM identity - STRICT READ ONLY
echo No task stop, Java operation, port change or ACL edits.
echo ============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Wild_Task_JVM_Identity_READ_ONLY.ps1"
set "result=%errorlevel%"
echo.
echo This report NEVER authorizes cutover or a process stop.
pause
exit /b %result%
