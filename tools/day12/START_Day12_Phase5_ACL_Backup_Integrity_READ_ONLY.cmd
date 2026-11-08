@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12.5 - ACL Backup Integrity [READ ONLY]
echo ============================================================
echo  GSC ACL BACKUP INTEGRITY + LIVE DACL COMPARISON [READ ONLY]
echo ============================================================
echo No ACL apply, restore, service restart, firewall or world change.
echo PRIVATE files stay on this PC. Only SHARE-ONLY-THIS JSON may be sent.
echo.
set "TOOL=%~dp0Day12_Phase5_ACL_Backup_Integrity_READ_ONLY.ps1"
if not exist "%TOOL%" (
  echo [BLOCKED] Missing PowerShell tool beside this CMD.
  pause
  exit /b 2
)
echo [1/2] Read-only integrity self-test...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%" -SelfTest
if errorlevel 1 (
  echo [BLOCKED] Self-test failed.
  pause
  exit /b 3
)
echo [2/2] Checking local private backup hashes and unchanged live ACLs...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%"
if errorlevel 1 (
  echo [BLOCKED] Source backup changed, live ACL drifted, or audit cannot continue.
  echo Do NOT apply permissions. Please send a screenshot of this message.
  echo NEVER upload PRIVATE manifests or DACL archives.
  pause
  exit /b 4
)
echo.
echo [DONE] Upload ONLY the NEW:
echo DAY12-ACL-INTEGRITY-SHARE-ONLY-THIS-*.json
echo NEVER upload PRIVATE-*.dacl or PRIVATE-*.json
explorer.exe "%LOCALAPPDATA%\Geumyi-Day12-ACL-Backup"
pause
exit /b 0
