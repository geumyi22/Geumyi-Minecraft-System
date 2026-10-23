@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =========================================================
echo  GSC v4.5.2 Velocity CANARY - STAGE ONLY
echo  Copy Canary and original GSC Host to protected staging.
echo  NO service stop/restart, NO Velocity or Paper changes.
echo =========================================================
fltmc >nul 2>&1
if errorlevel 1 (
  echo [BLOCKED] Right-click CMD and Run as administrator.
  pause
  exit /b 5
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Stage_GSC452_Velocity_CANARY_NO_INSTALL.ps1"
if errorlevel 1 (
  echo [BLOCKED] No host service/task changes occurred.
  pause
  exit /b 2
)
echo [COMPLETE] Canary staged; NOT installed or activated.
echo DO NOT stop tasks or install Canary without verified host rollback.
pause
exit /b 0
