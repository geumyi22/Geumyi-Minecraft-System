@echo off
setlocal EnableExtensions

if /I "%~1"=="--selftest" exit /b 0

echo.
echo [BLOCKED] This Day 10 finalizer targets the retired 3-server topology.
echo The approved 4-server deployment includes Wild, Playground, Other and Lobby.
echo Java 25565/25566/25567 and Bedrock UDP 19132/19133/19134 must all start at Lobby.
echo Do NOT use this old cutover script. Run Day10_Phase1_Preflight.cmd first.
echo No server files or settings were changed.
echo.
pause
exit /b 60

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo [Day10] Requesting Administrator privileges...
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

where gh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] GitHub CLI ^(gh^) was not found.
  pause
  exit /b 10
)

gh auth status >nul 2>&1
if errorlevel 1 (
  echo [Day10] GitHub login is required.
  gh auth login
  gh auth status >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] GitHub login failed.
    pause
    exit /b 11
  )
)

set "WORK=%TEMP%\Geumyi-Day10-Final"
if exist "%WORK%" rmdir /s /q "%WORK%"

echo.
echo ============================================================
echo  Geumyi Minecraft System - Day 10 Final E2E
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
echo Main commit:
git rev-parse HEAD
echo.
echo [2/3] Safety:
echo - Wild and Playground world folders are not modified.
echo - Players online causes an immediate stop before cutover.
echo - Backend configs are backed up before changes.
echo - Failure after cutover triggers the Day 10 rollback script.
echo - Java and Bedrock movement require manual confirmation.
echo.
echo [3/3] Starting Day 10 finalizer...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\day10\finish_day10.ps1"
if errorlevel 1 goto FINAL_FAIL

echo.
echo ============================================================
echo  DAY 10 FINALIZER: PASS
echo ============================================================
echo.
pause
exit /b 0

:FINAL_FAIL
echo.
echo ============================================================
echo  DAY 10 FINALIZER: STOPPED
echo ============================================================
echo Send the final screen plus day10-result.json/day10-e2e.log if created.
echo.
pause
exit /b 1
