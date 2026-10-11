@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12 Phase 5 ACL Original Backup - READ ONLY
echo =============================================================
echo  Geumyi Day12.5 GSC ORIGINAL ACL BACKUP [READ ONLY]
echo =============================================================
echo GSC ACLs and server files are READ ONLY.
echo Creates private ACL archives ONLY under current LOCALAPPDATA.
echo Does not modify GSC, servers, firewall, backups, or services.
echo.
set "TOOL=%~dp0Day12_Phase5_Production_ACL_Backup_READ_ONLY.ps1"
if not exist "%TOOL%" (
  echo [BLOCKED] PS1 file not found next to CMD.
  pause
  exit /b 2
)
echo [1/2] Windows PowerShell self-test...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%" -SelfTest
if errorlevel 1 (
  echo [BLOCKED] Self-test failed. No ACL backup attempted.
  pause
  exit /b 3
)
echo.
echo [2/2] Reading exact GSC ACLs and saving PRIVATE DACL archives...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%"
if errorlevel 1 (
  echo [BLOCKED] Read-only ACL backup failed. Please share this screen ONLY.
  echo Do not share PRIVATE DACL files or SDDL manifests.
  pause
  exit /b 4
)
echo.
echo [DONE] Choose the newest 'backup-*' folder in Explorer.
echo Upload ONLY: DAY12-ACL-BACKUP-SHARE-ONLY-THIS.json
echo NEVER upload: PRIVATE-*.dacl or PRIVATE-*.json
explorer.exe "%LOCALAPPDATA%\Geumyi-Day12-ACL-Backup"
pause
exit /b 0
