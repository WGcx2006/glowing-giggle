@echo off
setlocal
cd /d "%~dp0"

echo ============================================
echo   Battlefield 2035 - One-Click Launcher
echo ============================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js not found. Install it from: https://nodejs.org/
  pause
  exit /b 1
)

powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:5199/' -UseBasicParsing -TimeoutSec 2; exit 0 } catch { exit 1 }" >nul 2>nul
if not errorlevel 1 (
  echo [INFO] Game server is already running on port 5199. Opening browser...
  start "" "http://localhost:5199"
  exit /b 0
)

set "PM=npm"
where npm >nul 2>nul
if errorlevel 1 (
  if exist pnpm-lock.yaml (
    where pnpm >nul 2>nul
    if not errorlevel 1 set "PM=pnpm"
  )
)

if not exist "node_modules\three\package.json" (
  echo [INFO] First run detected. Installing dependencies...
  if "%PM%"=="pnpm" (
    call pnpm install
    if errorlevel 1 (
      echo [INFO] pnpm reported a build-script warning; rebuilding esbuild...
      call pnpm rebuild esbuild
    )
  ) else (
    call npm install
  )
  if errorlevel 1 (
    echo [ERROR] Dependency installation failed. Check your network and retry.
    pause
    exit /b 1
  )
)

echo [INFO] Starting game server: http://localhost:5199
echo [INFO] A server window will open. The browser will open once the server is ready.
echo.

if "%PM%"=="pnpm" (
  start "Battlefield 2035 - Dev Server" cmd /k "pnpm dev"
) else (
  start "Battlefield 2035 - Dev Server" cmd /k "npm run dev"
)

powershell -NoProfile -Command "$ok = $false; for ($i = 0; $i -lt 40; $i++) { try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:5199/' -UseBasicParsing -TimeoutSec 1; if ($r.StatusCode -eq 200) { $ok = $true; break } } catch {}; Start-Sleep -Milliseconds 500 }; if ($ok) { Start-Process 'http://localhost:5199' } else { Write-Host '[ERROR] Server did not become ready.' }"

pause
