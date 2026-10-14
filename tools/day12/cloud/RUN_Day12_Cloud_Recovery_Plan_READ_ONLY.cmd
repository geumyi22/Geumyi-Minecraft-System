@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title Geumyi Day12 - Recovery destination and consistency plan v5 [READ ONLY]
echo ======================================================================
echo v5 separates provider containers, actual archive candidates and staging.
echo No backup, upload, restore, directory creation at candidates or server stop.
echo Other stays intentionally OFFLINE. Originals and sync settings stay as-is.
echo ======================================================================
set "SCRIPT=%~dp0Day12_Cloud_Recovery_Plan_READ_ONLY.ps1"
if not exist "%SCRIPT%" exit /b 2
if not exist "%~dp0Day12_Cloud_Recovery_Preflight_READ_ONLY.ps1" exit /b 2
if not exist "%~dp0Test_Cloud_Recovery_Plan_V5.ps1" exit /b 2
echo [1/2] Disposable Windows path / alias / privacy tests...
powershell.exe -STA -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%" -Synthetic -QuietSynthetic
if errorlevel 1 (
  echo [BLOCKED] Self-test failed. Do not run an older diagnostic again.
  pause
  exit /b 3
)
echo [2/2] Select archive PARENT containers. No candidate folder is created.
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Interactive
set "RESULT=%ERRORLEVEL%"
echo Send only DAY12-CLOUD-RECOVERY-PLAN-V5-SHARE-ONLY-THIS.json if requested.
echo A plan is not permission or proof for backup, upload or restore.
pause
exit /b %RESULT%
