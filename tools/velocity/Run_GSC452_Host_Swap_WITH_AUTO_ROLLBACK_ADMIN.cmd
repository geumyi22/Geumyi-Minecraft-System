@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo =======================================================
echo  GSC 4.5.2 CANARY Host swap - guarded AUTO ROLLBACK
echo  Changes ONLY the GSC Windows service binary target.
echo  WARNING: GSC Host service temporarily stops/restarts.
echo  Some GSC-managed background functions may restart.
echo  NO direct Velocity Task/Paper/Java process commands.
echo =======================================================
fltmc >nul 2>&1
if errorlevel 1 (
  echo [BLOCKED] Run CMD as administrator.
  pause
  exit /b 5
)
echo.
echo [STEP 1] Revalidating verified 4.5.1 Host, 4.5.2 canary,
echo          task snapshot, agent/backend startup readiness.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Service_Reversible_Swap.ps1" -Mode Plan
if errorlevel 1 (
  echo [BLOCKED] Plan is not clean. NO service change.
  pause
  exit /b 2
)
echo.
echo  This will momentarily stop the current GSC Host SERVICE.
echo  It will update ONLY its configured executable path.
echo  Failure triggers a best-effort automated 4.5.1 restore.
echo  If rollback is unconfirmed, do not launch another Host.
set /p "approval=Type APPLY to change the live GSC Host service: "
if /I not "%approval%"=="APPLY" (
  echo [CANCELLED] No service change requested.
  pause
  exit /b 0
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0GSC452_Host_Service_Reversible_Swap.ps1" -Mode Apply -OperatorConfirmed
set "result=%errorlevel%"
if not "%result%"=="0" echo [NOT VERIFIED] Preserve private journal. See printed status.
echo [DONE] Share ONLY the sanitized JSON result, never private Host journals.
pause
exit /b %result%
