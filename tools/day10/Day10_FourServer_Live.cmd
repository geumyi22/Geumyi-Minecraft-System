@echo off
setlocal EnableExtensions DisableDelayedExpansion
if /I "%~1"=="--selftest" exit /b 0

echo.
echo ============================================================
echo Geumyi Day 10 - FOUR SERVER LIVE CUTOVER
echo ============================================================
echo - Requires already verified Phase 2 stage and latest GSC Host.
echo - STOPS all existing servers AFTER your explicit confirmation.
echo - Copies complete offline backups before changing any live files.
echo - Requires real Java and Bedrock login confirmation.
echo - Attempts automatic rollback if any cutover step fails.
echo - Do not use the retired Day10_Final_E2E.cmd.
echo.
where git.exe >nul 2>&1
if errorlevel 1 (echo [BLOCKED] Git for Windows is required. & pause & exit /b 10)
where gh.exe >nul 2>&1
if errorlevel 1 (echo [BLOCKED] GitHub CLI is required. & pause & exit /b 11)
gh auth status >nul 2>&1
if errorlevel 1 (
  echo [BLOCKED] GitHub CLI login required. Run gh auth login first.
  pause
  exit /b 12
)
set "STAGE=%TEMP%\Geumyi-Day10-FourServer-Assets-10865-16858"
if not exist "%STAGE%\four-server-network-plan.json" (
  echo [BLOCKED] Previously validated Phase 2 stage was not found:
  echo "%STAGE%"
  echo Specify the stage folder as the first command argument.
  pause
  exit /b 13
)
if not exist "%STAGE%\four-server-readiness.json" (
  echo [BLOCKED] The Phase 2 readiness report is missing.
  pause
  exit /b 14
)
set "WORK=%TEMP%\Geumyi-Day10-FourServer-Final-%RANDOM%-%RANDOM%"
echo Fetching latest verified source...
git clone --depth 1 --branch main https://github.com/geumyi22/Geumyi-Minecraft-System.git "%WORK%"
if errorlevel 1 (echo [BLOCKED] Could not clone current main. & pause & exit /b 15)
git -C "%WORK%" rev-parse HEAD

net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator permission for port and firewall changes...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '\"%STAGE%\"' -Verb RunAs"
  exit /b
)
if not "%~1"=="" set "STAGE=%~1"
echo.
echo Stage: "%STAGE%"
echo Full backup and cutover will require confirmation in PowerShell.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORK%\tools\day10\finish_four_servers.ps1" -StageRoot "%STAGE%"
if errorlevel 1 (
  echo.
  echo [STOPPED] Inspect the error above and retained Day10-Four backup.
  pause
  exit /b 20
)
echo.
echo [PASS] Java and Bedrock confirmations recorded. Reboot test is still required.
pause
exit /b 0
