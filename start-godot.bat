@echo off
setlocal
cd /d "%~dp0"

set "PS_SCRIPT=%~dp0scripts\godot.ps1"
if not exist "%PS_SCRIPT%" (
  echo [ERROR] Missing helper script: %PS_SCRIPT%
  pause
  exit /b 1
)

echo ============================================
echo   Battlefield 2035 - Godot One-Click
echo ============================================
echo [INFO] Launching Godot 4.7 project...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" --path "%~dp0godot"

echo.
echo [INFO] Godot exited. You can close this window.
pause
