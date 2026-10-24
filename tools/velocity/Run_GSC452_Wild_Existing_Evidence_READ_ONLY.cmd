@echo off
setlocal EnableExtensions DisableDelayedExpansion
echo ============================================================
echo  GSC 4.5.2 - EXISTING wild cutover evidence [READ ONLY]
echo  Reads protected task XML, receipt and launcher manifest.
echo  NO backup creation, task changes, JVM stop or host restart.
echo ============================================================
echo.
echo If private Recovery ACL denies access, run this CMD elevated.
echo NEVER share the private ticket, XML, manifest or Java paths.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Velocity_Managed_Cutover.ps1" -Mode VerifyExisting -Target wild
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" (
  echo BLOCKED: protected evidence could not be verified.
  echo No server changes were performed. Do not proceed to Cutover.
) else (
  echo REPORT ONLY. This does NOT authorize stopping a task or cutover.
  echo A running legacy parent AND child must be safely accounted for.
)
echo.
pause
exit /b %EXIT_CODE%
