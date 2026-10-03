@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day11_Phase0_ReadOnly_Preflight.ps1"
set ERR=%ERRORLEVEL%
echo.
if not "%ERR%"=="0" (
  echo [DAY11] Preflight failed with exit code %ERR%.
) else (
  echo [DAY11] Read-only preflight finished.
)
pause
exit /b %ERR%
