@echo off
setlocal
chcp 65001 >nul
title Geumyi Final Verification - READ ONLY
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Final_Verification_READ_ONLY.ps1"
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="0" (
  echo [DAY12] READ-ONLY verification finished without mandatory FAIL.
) else (
  echo [DAY12] Verification found mandatory FAIL or could not complete. Exit=%EC%
)
pause
exit /b %EC%
