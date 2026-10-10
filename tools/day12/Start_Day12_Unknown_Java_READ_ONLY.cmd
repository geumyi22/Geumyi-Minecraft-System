@echo off
setlocal
cd /d "%~dp0"
echo Day12 case 2: UNKNOWN JAVA ROLE -- READ ONLY
echo Windows processes + local GSC snapshot GET only.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_Unknown_Java_Role_READ_ONLY.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Could not complete process reading; no game service was changed.
echo Share only the new Day12-Unknown-Java-Role-READ-ONLY JSON from Desktop\Geumyi-Day12-Three-Tests
pause
exit /b %RC%
