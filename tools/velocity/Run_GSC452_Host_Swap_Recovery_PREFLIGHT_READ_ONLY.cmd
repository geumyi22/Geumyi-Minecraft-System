@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ===========================================================
echo  GSC 4.5.2 Host Swap and Recovery PREFLIGHT - READ ONLY
echo  Existing GSC Host, Canary staging and rollback backup.
echo  NO host swap, service restart, task or Java operations.
echo ===========================================================
fltmc >nul 2>&1
if errorlevel 1 (
  echo [BLOCKED] Right-click this CMD and choose Run as administrator.
  pause
  exit /b 5
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Swap_Recovery_PREFLIGHT_READ_ONLY.ps1"
if errorlevel 1 (
  echo [FAILED] The read-only report could not be generated.
  pause
  exit /b 2
)
echo [READ ONLY] This is NOT permission to install Canary or stop Velocity.
echo Share only the JSON displayed above; never share private backup files.
pause
exit /b 0
