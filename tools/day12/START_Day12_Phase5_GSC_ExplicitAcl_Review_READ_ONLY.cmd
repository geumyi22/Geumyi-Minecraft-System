@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12.5 - Explicit ACL Review [READ ONLY]
echo ============================================================
echo  GSC EXPLICIT / PROTECTED ACL REVIEW [READ ONLY]
echo ============================================================
echo This inspection NEVER edits GSC ACLs, services, worlds or backups.
echo Only counts are saved to a new JSON under LOCALAPPDATA.
echo Effective standard-user permission is NOT tested or claimed.
echo.
set "TOOL=%~dp0Day12_Phase5_GSC_ExplicitAcl_Review_READ_ONLY.ps1"
if not exist "%TOOL%" (
  echo [BLOCKED] Missing the .ps1 file beside this CMD.
  pause
  exit /b 2
)
echo [1/2] Static classifier self-test...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%" -SelfTest
if errorlevel 1 (
  echo [BLOCKED] Self-test failed. Do not change ACLs.
  pause
  exit /b 3
)
echo [2/2] Inspecting GSC ACL metadata WITHOUT changing GSC...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%"
if errorlevel 1 (
  echo [BLOCKED] Read-only ACL review failed. Send this screen.
  pause
  exit /b 4
)
echo.
echo [DONE] Send ONLY the NEW:
echo DAY12-GSC-EXPLICIT-ACL-SHARE-ONLY-THIS-*.json
echo NO filenames, paths, raw SDDL, token, service config or backups.
explorer.exe "%LOCALAPPDATA%\Geumyi-Day12-ACL-ExplicitReview"
pause
exit /b 0
