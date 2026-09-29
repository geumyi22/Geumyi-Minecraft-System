@echo off
setlocal EnableExtensions
if /I "%~1"=="--selftest" exit /b 0

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo [Day8] Requesting Administrator privileges...
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

where git.exe >nul 2>&1
if not "%errorlevel%"=="0" (
  echo [FAIL] Git was not found.
  pause
  exit /b 11
)

gh auth status >nul 2>&1
if errorlevel 1 (
  echo [Day8] GitHub login is required.
  gh auth login
  gh auth status >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] GitHub login failed or credentials were not saved.
    pause
    exit /b 12
  )
  echo [Day8] GitHub login verified.
)

set "WORK=%TEMP%\Geumyi-Day8-Final"
if exist "%WORK%" rmdir /s /q "%WORK%"

echo.
echo ============================================================
echo  Geumyi Minecraft System - Day 8 Final E2E
echo ============================================================
echo.
echo [1/3] Cloning latest main...
gh repo clone geumyi22/Geumyi-Minecraft-System "%WORK%"
if not "%errorlevel%"=="0" (
  echo [FAIL] Repository clone failed.
  pause
  exit /b 13
)

cd /d "%WORK%"
git checkout main >nul 2>&1
git pull --ff-only
if not "%errorlevel%"=="0" (
  echo [FAIL] Updating main failed.
  pause
  exit /b 14
)

echo.
echo [2/3] Safety:
echo - Wild must have zero online players.
echo - The script uses graceful stop/start only.
echo - Technology 0.1.4 is tested on Wild only.
echo - Playground must remain without Technology.
echo.

set "ADBARG="
where adb.exe >nul 2>&1
if "%errorlevel%"=="0" (
  choice /C YN /N /M "Run Android ADB install test too? [Y/N] "
  if errorlevel 2 goto NOADB
  if errorlevel 1 set "ADBARG=-TryAndroidADB"
)
:NOADB

echo.
echo [3/3] Starting Day 8 final E2E...
echo If GSC Setup opens, keep the existing server paths and role, then finish the upgrade.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\release\finish_day8.ps1" -RunServerE2E %ADBARG%
set "RC=%errorlevel%"

echo.
echo ============================================================
if "%RC%"=="0" (
  echo  DAY 8 FINALIZER: PASS
  echo ============================================================
  echo Signed Release, manifest verification, artifact hashes,
  echo GSC updater, Wild update, and Playground isolation passed.
) else if "%RC%"=="3" (
  echo  DAY 8: SERVER PASS / ANDROID ACTION REQUIRED
  echo ============================================================
  echo Server E2E passed, but Android needs manual follow-up.
  echo Do not uninstall automatically; preserve app data.
) else (
  echo  DAY 8 FINALIZER: STOPPED ^(code %RC%^)
  echo ============================================================
  echo Send the final screen plus day8-result.json and day8-e2e.log.
)
echo.
pause
exit /b %RC%
