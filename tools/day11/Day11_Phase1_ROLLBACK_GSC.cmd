@echo off
setlocal
chcp 65001 >nul
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day11_Phase1_Rollback_GSC.ps1"
set ERR=%ERRORLEVEL%
echo.
pause
exit /b %ERR%
