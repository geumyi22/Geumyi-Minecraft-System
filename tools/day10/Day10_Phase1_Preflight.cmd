@echo off
setlocal EnableExtensions
if /I "%~1"=="--selftest" exit /b 0

where git.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Git was not found. Install Git for Windows first.
  pause
  exit /b 10
)

set "WORK=%TEMP%\Geumyi-Day10-Phase1"
if exist "%WORK%" rmdir /s /q "%WORK%"
if exist "%WORK%" (
  echo [FAIL] Previous temporary checkout could not be removed: "%WORK%"
  pause
  exit /b 11
)

echo.
echo ============================================================
echo  Geumyi Minecraft System - Day 10 Phase 1 / READ ONLY
echo ============================================================
echo - Reads Wild, Playground, Other, GSC and occupied ports.
echo - Does NOT stop servers, change world data or deploy plugins.
echo - The old Day10_Final_E2E.cmd is blocked for safety.
echo.
echo [1/2] Fetching latest main...
git clone --depth 1 --branch main https://github.com/geumyi22/Geumyi-Minecraft-System.git "%WORK%"
if errorlevel 1 (
  echo [FAIL] Repository checkout failed.
  pause
  exit /b 12
)

cd /d "%WORK%"
echo Main commit:
git rev-parse HEAD

echo.
echo [2/2] Checking existing servers...
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\day10\preflight_four_servers.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\day10\preflight_four_servers.ps1" -ServerRoot "%~1"
)
if errorlevel 1 (
  echo [FAIL] Inspection could not finish. Send the full screen.
  pause
  exit /b 13
)

echo.
echo [DONE] Inspection only. Send the generated JSON report.
pause
exit /b 0
