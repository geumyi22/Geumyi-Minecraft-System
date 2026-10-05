@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title GSCM APK Builder - Fast

echo ============================================================
echo GSCM APK Builder - Fast
echo ============================================================
echo Installs/reuses build tools under LOCALAPPDATA only.
echo.
where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [GSCM] ERROR: Windows PowerShell was not found.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\build_apk_oneclick.ps1" -SkipChecks
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo [GSCM] Build failed. Check GSCM-build.log in this folder.
) else (
  echo [GSCM] Build completed. See dist\ for the versioned APK.
)
echo.
pause
exit /b %RC%
