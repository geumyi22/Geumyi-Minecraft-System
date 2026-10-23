@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ==========================================================
echo  GSC Velocity - ORIGINAL TASK SNAPSHOT ONLY - ADMIN
echo  Three tasks: wild, playground, other
echo  Does NOT stop or disable any task. NO Java restart.
echo  Original Task XML is protected locally. NEVER SHARE IT.
echo ==========================================================
fltmc >nul 2>&1
if errorlevel 1 (
 echo [BLOCKED] Right-click this CMD and Run as administrator.
 pause
 exit /b 5
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_Snapshot_Three_Before_Cutover.ps1"
if errorlevel 1 (
 echo [NOT COMPLETED] No task changes were requested.
 echo Preserve any partial private backups for manual inspection.
 pause
 exit /b 2
)
echo [SUCCESS] Three original task definitions saved locally.
echo The Java proxies have NOT been shut down.
pause
exit /b 0
