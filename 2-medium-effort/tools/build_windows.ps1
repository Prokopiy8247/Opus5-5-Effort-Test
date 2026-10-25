# Builds the Windows release: build\VerdantRidgeFestival.exe (single file, data pack embedded).
# Usage (from the project folder):  powershell -ExecutionPolicy Bypass -File tools\build_windows.ps1
$godot = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$project = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $project "build") | Out-Null
& $godot --headless --path $project --import
& $godot --headless --path $project --export-release "Windows Desktop" (Join-Path $project "build\VerdantRidgeFestival.exe")
Get-Item (Join-Path $project "build\VerdantRidgeFestival.exe") | Select-Object FullName, Length, LastWriteTime
