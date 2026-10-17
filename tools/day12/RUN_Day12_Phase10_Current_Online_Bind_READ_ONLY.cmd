@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12.10 Online Java/RCON Native Owner - READ ONLY
echo ============================================================
echo  Day 12.10: Online Java/RCON owner and loopback bind audit
echo  Other Paper: EXPECTED OFFLINE; never starts it.
echo  Does NOT stop, update or restart any Minecraft/GSC service.
echo  Native listener-class fix supports Windows state 0 reports.
echo ============================================================
set "SCRIPT=%~dp0Day12_Phase10_Online_Bind_Owner_Scoped_READ_ONLY.ps1"
set "NATIVE=%~dp0Day12_Native_TCP_Provider_READ_ONLY.ps1"
if not exist "%SCRIPT%" (
  echo [BLOCKED] Missing main PS1. Extract ALL files together.
  pause
  exit /b 2
)
if not exist "%NATIVE%" (
  echo [BLOCKED] Missing native helper. Extract ALL files together.
  pause
  exit /b 2
)
echo [1/2] Static Windows synthetic positive/negative tests...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%" -Synthetic -ExpectedOtherBackendState OFFLINE
if errorlevel 1 (
  echo [BLOCKED] Synthetic checks did not pass. Do NOT change server.
  pause
  exit /b 3
)
echo [2/2] Live read-only native loopback listener-owner capture...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%" -ExpectedOtherBackendState OFFLINE
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" (
  echo [BLOCKED OR REVIEW] Missing or uncertain evidence; no automatic PASS.
  echo Do not start Other, restart Java, change ACL/firewall or rerun repeatedly.
)
echo Send ONLY DAY12-NATIVE-BIND-SHARE-ONLY-THIS.json from Desktop report folder.
echo If no JSON was created, send only this error screen.
pause
exit /b %RESULT%
