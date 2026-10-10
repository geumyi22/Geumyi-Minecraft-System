@echo off
setlocal
cd /d "%~dp0"
echo ==================================================
echo  Day12 three remaining tests: 2, 12, 17
echo  Host portion: READ ONLY / process census
echo  12 and 17: disposable GitHub CI evidence only
echo ==================================================
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_Three_Remaining_OneClick_READ_ONLY.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Collection failed; do NOT change production services.
echo The Desktop\Geumyi-Day12-Three-Tests JSON is the ONLY file to share.
pause
exit /b %RC%
