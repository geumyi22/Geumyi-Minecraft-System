@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  Geumyi Velocity LIVE LAUNCH AUDIT [READ ONLY]
echo  3 tasks: execution type, working directory class, Java/JAR
echo  NEVER displays passwords, XML, user paths, SIDs or command lines
echo  NO TASK STOP / START / MODIFICATION
echo ============================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_Actual_Launch_Audit_READ_ONLY.ps1" -Target all
echo.
echo This report does NOT authorize Cutover or force-killing Java.
pause
exit /b 0
