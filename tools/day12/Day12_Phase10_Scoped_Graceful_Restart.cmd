@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 - ONE playground graceful restart and evidence
echo ==============================================================
echo Day12 12.10 - ONE scoped GSC PLAYGROUND graceful restart
echo ==============================================================
echo PRECONDITIONS enforced by script:
echo   GSC 4.3.8, target ONLINE, 0 active jobs, 0 players,
echo   verified PROTECTED FULL Golden backup, safe update phase.
echo.
echo GSC will do a graceful lifecycle restart with 15s countdown.
echo Existing automatic prestart update policy may apply at startup.
echo No world restore, forced stop, firewall edit or backup deletion.
echo If a guard fails, restart is NOT performed.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_Phase10_Scoped_Graceful_Restart.ps1"
set "EC=%ERRORLEVEL%"
echo.
echo Report: Desktop\Geumyi-Day12-Scoped-Restart
echo Exit code: %EC%
pause
exit /b %EC%
