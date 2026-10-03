@echo off
setlocal EnableExtensions DisableDelayedExpansion

if /I "%~1"=="--selftest" exit /b 0

echo.
echo ============================================================
echo Geumyi Day 10 - FAILED CUTOVER RECOVERY
echo ============================================================
echo - Restores ONLY the original GSC server profiles and startup state.
echo - Verifies live backend files against the retained Day10 backup hashes.
echo - Does NOT modify worlds or re-run the four-server cutover.
echo.

where git.exe >nul 2>&1
if errorlevel 1 (
  echo [BLOCKED] Git for Windows is required.
  pause
  exit /b 10
)

net session >nul 2>&1
if errorlevel 1 (
  if /I "%~1"=="--elevated" (
    echo [BLOCKED] Administrator elevation did not take effect.
    pause
    exit /b 11
  )
  echo Requesting Administrator permission...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
  if errorlevel 1 (
    echo [BLOCKED] Administrator elevation was declined or failed.
    pause
    exit /b 12
  )
  exit /b 0
)

set "WORK=%TEMP%\Geumyi-Day10-Recovery-%RANDOM%-%RANDOM%"
echo Fetching latest recovery script from main...
git clone --depth 1 --branch main https://github.com/geumyi22/Geumyi-Minecraft-System.git "%WORK%"
if errorlevel 1 (
  echo [BLOCKED] Could not clone current main.
  pause
  exit /b 13
)

echo Current main:
git -C "%WORK%" rev-parse HEAD
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORK%\tools\day10\recover_failed_four_server.ps1"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
  echo.
  echo [STOPPED] Recovery did not complete. Do not start servers manually.
  echo Send this whole window back to ChatGPT.
  pause
  exit /b %RC%
)

echo.
echo [PASS] Failed-cutover recovery completed.
pause
exit /b 0
