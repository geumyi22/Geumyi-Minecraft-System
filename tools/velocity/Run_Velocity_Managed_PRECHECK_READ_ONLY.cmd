@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  Geumyi GSC v4.5.2 Velocity migration PRECHECK [READ ONLY]
echo  No task edits, Java commands, DPAPI, ACL edits or restarts.
echo ============================================================
for %%T in (wild playground other) do (
  echo.
  echo [%%T] Windows Scheduler and port cutover readiness
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_Managed_Cutover.ps1" -Mode Preflight -Target %%T
)
echo.
echo A Ready result is NOT an approval to modify the live server.
echo Do not share task XML, service paths, SIDs or any passwords.
pause
exit /b 0
