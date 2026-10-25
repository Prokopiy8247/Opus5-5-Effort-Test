@echo off
setlocal EnableExtensions
title Sunward Roads
cd /d "%~dp0"

set "GODOT_VERSION=4.7.2-stable"
set "GODOT_DIR=%LOCALAPPDATA%\OpusEffortTest\godot-%GODOT_VERSION%"
set "GODOT_EXE=%GODOT_DIR%\Godot_v%GODOT_VERSION%_win64.exe"
set "GODOT_URL=https://github.com/godotengine/godot-builds/releases/download/%GODOT_VERSION%/Godot_v%GODOT_VERSION%_win64.exe.zip"

echo ============================================================
echo   Sunward Roads
echo   Claude Opus 5.5 effort test: ultracode
echo ============================================================
echo.

if exist "%GODOT_EXE%" goto have_godot
echo [1/3] Downloading the Godot game engine, about 85 MB. This happens only once.
mkdir "%GODOT_DIR%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; $zip=Join-Path $env:GODOT_DIR 'godot.zip'; Invoke-WebRequest -UseBasicParsing -Uri $env:GODOT_URL -OutFile $zip; Expand-Archive -LiteralPath $zip -DestinationPath $env:GODOT_DIR -Force; Remove-Item $zip"
if not exist "%GODOT_EXE%" goto download_failed

:have_godot
if exist ".godot\opus_import_done" goto run_game
echo [2/3] First launch: preparing the game files. This can take 2-10 minutes. Please wait...
"%GODOT_EXE%" --headless --path "%~dp0." --import >nul 2>&1
if exist ".godot" echo done> ".godot\opus_import_done"

:run_game
echo [3/3] Starting the game...
"%GODOT_EXE%" --path "%~dp0."
if errorlevel 1 (
  echo.
  echo The game closed with an error. Please see README.md in the repository root.
  pause
)
exit /b 0

:download_failed
echo.
echo ERROR: could not download the Godot engine. Check your internet connection and try again.
echo Manual option: download Godot %GODOT_VERSION% from https://godotengine.org/download/archive/ and see README.md
echo.
pause
exit /b 1
