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

set "BACKUP="
for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$d=Get-ChildItem -LiteralPath (Join-Path $env:PROGRAMDATA 'GeumyiServerCenter\Backups') -Directory -Filter 'Day10-Four-*' -ErrorAction SilentlyContinue ^| Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'four-rollback-state.json') -PathType Leaf } ^| Sort-Object LastWriteTimeUtc -Descending ^| Select-Object -First 1; if($null -ne $d){[Console]::Write($d.FullName)}"`) do set "BACKUP=%%I"
if not defined BACKUP (echo [BLOCKED] No Day10-Four rollback backup was found. & pause & exit /b 14)

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
