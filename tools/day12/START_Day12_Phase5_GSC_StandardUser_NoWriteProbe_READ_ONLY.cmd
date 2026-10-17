@echo off
setlocal EnableExtensions DisableDelayedExpansion
title GSC Day12.5 - REAL Standard User No-Write Access Probe
echo ============================================================
echo  GSC REAL STANDARD USER ACCESS PROBE [NO PRODUCTION WRITES]
echo ============================================================
echo Uses CreateFile OPEN_EXISTING on GSC root. No child is created.
echo Refuses admin / UAC-filtered admin / system tokens (BLOCKED).
echo Requires an EXISTING real Windows standard-user login.
echo Never creates local users or modifies any GSC ACLs, services or files.
echo.
set "TOOL=%~dp0Day12_Phase5_GSC_StandardUser_NoWriteProbe_READ_ONLY.ps1"
set "CORE=%~dp0Day12_GSC_NoWrite_AccessCore.ps1"
if not exist "%TOOL%" (
  echo [BLOCKED] Missing probe PS1. Unzip all files together.
  pause
  exit /b 2
)
if not exist "%CORE%" (
  echo [BLOCKED] Missing core PS1. Unzip all files together.
  pause
  exit /b 2
)
echo [1/2] Scratch-only native call self-test ...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%" -SelfTest
if errorlevel 1 (
  echo [BLOCKED] Self-test failure; do not change ACLs.
  pause
  exit /b 3
)
echo [2/2] Checking current REAL user token against existing GSC root ...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TOOL%"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" (
  echo [BLOCKED] A true standard-user session was not confirmed or an error occurred.
  echo Do not change accounts, ACLs, services, or files to force this test.
)
echo Share ONLY the new DAY12-GSC-STANDARD-USER-NOWRITE-SHARE-ONLY-THIS-*.json
explorer.exe "%LOCALAPPDATA%\Geumyi-Day12-StandardUser-AccessProbe"
pause
exit /b %RESULT%
