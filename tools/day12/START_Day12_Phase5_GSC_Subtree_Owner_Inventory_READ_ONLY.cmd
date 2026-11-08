@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12.5 - GSC Subtree Owner/Reparse Inventory [READ ONLY]
echo ============================================================
echo  GSC SUBTREE OWNER / REPARSE / LEGACY-TEMP INVENTORY [READ ONLY]
echo ============================================================
echo No ACL apply, restore, delete, service restart, firewall or world change.
echo Junctions and symlinks are counted but NEVER followed.
echo Only the SHARE-ONLY-THIS JSON (counts only) may be sent.
echo.
set "TOOL=%~dp0Day12_Phase5_GSC_Subtree_Owner_Inventory_READ_ONLY.ps1"
if not exist "%TOOL%" (
  echo [BLOCKED] Missing PowerShell tool beside this CMD.
  pause
  exit /b 2
)
echo [1/2] Self-test...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%" -SelfTest
if errorlevel 1 (
  echo [BLOCKED] Self-test failed.
  pause
  exit /b 3
)
echo [2/2] Reading owners and reparse attributes under ProgramData\GeumyiServerCenter...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%"
if errorlevel 1 (
  echo [BLOCKED] Inventory could not complete. Do NOT change permissions.
  pause
  exit /b 4
)
echo.
echo [DONE] Upload ONLY the NEW DAY12-GSC-SUBTREE-INVENTORY-SHARE-ONLY-THIS-*.json
explorer.exe "%LOCALAPPDATA%\Geumyi-Day12-ACL-Inventory"
pause
exit /b 0
