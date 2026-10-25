@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Geumyi Day12 P0 Google Mirror Encrypted Copy V2
cd /d "%~dp0"
echo ==========================================================
echo Geumyi P0 encrypted-only copy to verified Google MIRROR folder.
echo 23 archive entries. NO plaintext, no world, no restart.
echo New destination only. Never deletes or overwrites files.
echo C: mirror local hash DOES NOT PROVE remote sync completion.
echo ==========================================================
if not exist "%~dp0Day12_P0_Google_Encrypted_Copy.ps1" (
  echo [BLOCKED] Missing exact encrypted-copy PowerShell tool.
  pause
  exit /b 2
)
if not exist "%~dp0Day12_P0_Google_Transfer_Preflight_READ_ONLY.ps1" (
  echo [BLOCKED] Missing verified read-only preflight dependency.
  pause
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Day12_P0_Google_Encrypted_Copy.ps1"
set "RET=%ERRORLEVEL%"
if not "%RET%"=="0" (
  echo [BLOCKED] Cloud upload NOT confirmed. Leave any partial folder unchanged.
) else (
  echo [EXIT 0 ONLY] Verify actual P0_GOOGLE_MIRROR_COPY_HASH_VERIFIED=23 and P0_GOOGLE_MIRROR_COPY_COMPLETE=true above.
  echo Without BOTH P0 lines, count as NOT COPIED. Google remote still unverified.
)
echo.
echo Send only P0_ result lines; do NOT send password, config or archive.
pause
exit /b %RET%
