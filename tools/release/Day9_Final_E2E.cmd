@echo off
setlocal EnableExtensions
if /I "%~1"=="--selftest" exit /b 0

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo [Day9] Requesting Administrator privileges...
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

where gh.exe >nul 2>&1
if not "%errorlevel%"=="0" (
  echo [FAIL] GitHub CLI ^(gh^) was not found.
  echo Install GitHub CLI, then run this file again.
  pause
  exit /b 10
)

gh auth status >nul 2>&1
if errorlevel 1 (
  echo [Day9] GitHub login is required.
  gh auth login
  gh auth status >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] GitHub login failed.
    pause
    exit /b 11
  )
)

set "WORK=%TEMP%\Geumyi-Day9-Final"
if exist "%WORK%" rmdir /s /q "%WORK%"

echo.
echo ============================================================
echo  Geumyi Minecraft System - Day 9 Final E2E
echo ============================================================
echo.
echo [1/3] Cloning latest main...
gh repo clone geumyi22/Geumyi-Minecraft-System "%WORK%"
if errorlevel 1 (
  echo [FAIL] Repository clone failed.
  pause
  exit /b 12
)

cd /d "%WORK%"
git checkout main >nul 2>&1
git pull --ff-only
if errorlevel 1 (
  echo [FAIL] Updating main failed.
  pause
  exit /b 13
)

echo.
echo [2/3] Safety:
echo - Host transaction rollback self-test uses a TEMP test server only.
echo - Wild live test is graceful stop/start only.
echo - Wild live test refuses to run when players are online.
echo - GitHub failure is simulated by a temporary invalid repository setting.
echo - Original update settings and Wild runtime state are restored automatically.
echo.

echo [3/3] Starting Day 9 final E2E...
echo If GSC Setup opens, keep the existing role and server paths, then finish the upgrade.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\release\finish_day9.ps1" -RunWildFailOpen
if errorlevel 1 goto FINAL_FAIL

echo.
echo ============================================================
echo  DAY 9 FINALIZER: PASS
echo ============================================================
echo GSC 4.2.4 artifact verification, transaction rollback
echo self-test, install/API, live fail-open restart, and state restore passed.
echo.
pause
exit /b 0

:FINAL_FAIL
echo.
echo ============================================================
echo  DAY 9 FINALIZER: STOPPED
echo ============================================================
echo Send the final screen plus day9-result.json and day9-e2e.log.
echo.
pause
exit /b 1
