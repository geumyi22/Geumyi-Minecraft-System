@echo off
setlocal
chcp 65001 >nul
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo [DAY11] Administrator access is required. Requesting UAC...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day11_Phase1_Install_Host_Test.ps1"
set ERR=%ERRORLEVEL%
echo.
if "%ERR%"=="0" (
  echo [DAY11] Host-test deployment completed.
) else (
  echo [DAY11] Host-test deployment failed or was rolled back. Exit code: %ERR%
)
pause
exit /b %ERR%
