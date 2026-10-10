@echo off
setlocal
chcp 65001 >nul
title Geumyi Day12 Bedrock Proxy Packs - READ ONLY
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Day12_Bedrock_Proxy_Packs_Inventory_READ_ONLY.ps1"
echo.
echo Inventory only. No packs, mappings, proxies, worlds or settings were changed.
pause
