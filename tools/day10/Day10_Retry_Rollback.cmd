@echo off
setlocal EnableExtensions DisableDelayedExpansion
if /I "%~1"=="--selftest" exit /b 0

echo.
echo ============================================================
echo Geumyi Day 10 - RETRY FAILED FOUR-SERVER ROLLBACK
echo ============================================================
echo - Uses the latest retained Day10-Four backup.
echo - Does NOT start a new cutover.
echo - Never force-kills a Minecraft server.
echo - Retries graceful shutdown with a direct standard RCON fallback.
echo.
where git.exe >nul 2>&1
if errorlevel 1 (echo [BLOCKED] Git for Windows is required. & pause & exit /b 10)

net session >nul 2>&1
if errorlevel 1 (
  if /I "%~1"=="--elevated" (echo [BLOCKED] Administrator elevation failed. & pause & exit /b 11)
  echo Requesting Administrator permission...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
  if errorlevel 1 (echo [BLOCKED] Administrator elevation was declined or failed. & pause & exit /b 12)
  exit /b 0
)

set "WORK=%TEMP%\Geumyi-Day10-RollbackRetry-%RANDOM%-%RANDOM%"
echo Fetching latest main...
git clone --depth 1 --branch main https://github.com/geumyi22/Geumyi-Minecraft-System.git "%WORK%"
if errorlevel 1 (echo [BLOCKED] Could not clone current main. & pause & exit /b 13)
echo Current main:
git -C "%WORK%" rev-parse HEAD

set "BACKUP_FILE=%TEMP%\Geumyi-Day10-RollbackBackup-%RANDOM%-%RANDOM%.txt"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORK%\tools\day10\resolve_four_server_backup.ps1" > "%BACKUP_FILE%"
if errorlevel 1 (
  echo [BLOCKED] Could not resolve a Day10-Four rollback backup.
  del /q "%BACKUP_FILE%" >nul 2>&1
  pause
  exit /b 14
)
set "BACKUP="
set /p "BACKUP="<"%BACKUP_FILE%"
del /q "%BACKUP_FILE%" >nul 2>&1
if not defined BACKUP (
  echo [BLOCKED] Rollback backup resolver returned an empty path.
  pause
  exit /b 14
)
if not exist "%BACKUP%\four-rollback-state.json" (
  echo [BLOCKED] four-rollback-state.json missing in "%BACKUP%".
  pause
  exit /b 14
)

echo Rollback backup:
echo   %BACKUP%
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORK%\tools\day10\rollback_four_servers.ps1" -BackupRoot "%BACKUP%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo [STOPPED] Rollback retry did not complete. Do not start servers manually.
  echo Send this entire window back to ChatGPT.
  pause
  exit /b %RC%
)

echo.
echo [PASS] Four-server rollback retry completed and verified.
pause
exit /b 0
