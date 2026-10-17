@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12 Recovery Capacity - READ ONLY
cd /d "%~dp0"
echo ========================================================
echo  Day12 Recovery Capacity Metadata [READ ONLY]
echo  No backup, server restart, cloud upload or config edit
echo  Local metadata walk may be INCOMPLETE for cloud files
echo ========================================================
if not exist "%~dp0Day12_Recovery_Capacity_Metadata_READ_ONLY.ps1" (
  echo [BLOCKED] Script is missing.
  pause
  exit /b 2
)
if not exist "%~dp0Day12_Cloud_Recovery_Plan_READ_ONLY.ps1" (
  echo [BLOCKED] v5 dependency is missing.
  pause
  exit /b 2
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_Recovery_Capacity_Metadata_READ_ONLY.ps1" -MeasureSourceMetadata -MaxEntries 25000 -MaxSeconds 45
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
  echo [BLOCKED] Capacity metadata could not be collected safely. Exit: %CODE%
) else (
  echo [CAPTURED] Read-only report saved locally. Capacity is NOT yet verified.
)
echo.
echo Send ONLY the generated SHARE-ONLY-THIS.json report.
pause
exit /b %CODE%
