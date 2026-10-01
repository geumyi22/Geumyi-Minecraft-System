@echo off
setlocal EnableExtensions DisableDelayedExpansion
if /I "%~1"=="--selftest" exit /b 0

echo.
echo ============================================================
echo  Geumyi Minecraft System - Day 10 Phase 2 / STAGING ONLY
echo ============================================================
echo - Downloads verified official Velocity, Geyser, Floodgate and Via JARs.
echo - Builds three proxy configurations for Java and Bedrock.
echo - Does NOT stop servers, touch existing worlds or modify live ports.
echo - Does NOT install plugins to live servers or change GSC profiles.
echo - The retired Day10_Final_E2E.cmd remains BLOCKED.
echo.
where git.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Git for Windows was not found.
  pause
  exit /b 10
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Windows PowerShell was not found.
  pause
  exit /b 11
)
set "WORK=%TEMP%\Geumyi-Day10-Stage-Source-%RANDOM%-%RANDOM%"
set "ASSETS=%TEMP%\Geumyi-Day10-FourServer-Assets-%RANDOM%-%RANDOM%"
echo [1/3] Fetching latest main into "%WORK%" ...
git clone --depth 1 --branch main https://github.com/geumyi22/Geumyi-Minecraft-System.git "%WORK%"
if errorlevel 1 (
  echo [FAIL] Could not fetch repository. Existing servers were not changed.
  pause
  exit /b 12
)
echo Latest main commit:
git -C "%WORK%" rev-parse HEAD
echo.
echo [2/3] Staging official dependencies. This can take a while ...
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORK%\tools\day10\stage_four_server_network.ps1" -OutputRoot "%ASSETS%" -DownloadDependencies
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORK%\tools\day10\stage_four_server_network.ps1" -OutputRoot "%ASSETS%" -ServerRoot "%~1" -DownloadDependencies
)
if errorlevel 1 (
  echo [FAIL] Staging failed. No live server files were changed.
  echo Keep the console output for troubleshooting.
  pause
  exit /b 13
)
echo.
echo.
echo [3/3] Checking staged files and live server configuration [READ ONLY]...
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORK%\tools\day10\validate_four_server_cutover.ps1" -StageRoot "%ASSETS%"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORK%\tools\day10\validate_four_server_cutover.ps1" -StageRoot "%ASSETS%" -ServerRoot "%~1"
)
if errorlevel 1 (
  echo [CHECK REQUIRED] Stage files remain available in "%ASSETS%".
  echo Send the generated four-server-readiness.json and the console output.
  pause
  exit /b 14
)
echo.
echo [DONE] Staged and inspected only. No live ports were changed.
echo Plans: "%ASSETS%\four-server-network-plan.json"
echo Report: "%ASSETS%\four-server-readiness.json"
echo Do NOT run the old Day10_Final_E2E.cmd.
pause
exit /b 0
