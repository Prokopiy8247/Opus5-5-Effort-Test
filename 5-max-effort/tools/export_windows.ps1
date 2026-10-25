# Builds the standalone Windows game: build/RidgelineFestival/RidgelineFestival.exe (data pack embedded).
# Needs the Godot 4.7.2 export templates (Editor > Manage Export Templates), already installed on this machine.
# Usage (PowerShell, from the project folder):  powershell -ExecutionPolicy Bypass -File tools/export_windows.ps1
param(
    [string]$Godot = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Out = "build/RidgelineFestival/RidgelineFestival.exe"
)
# Godot prints progress on stderr; native stderr must not abort the script, so check exit codes instead
$ErrorActionPreference = "Continue"
$project = Split-Path -Parent $PSScriptRoot
Set-Location $project
New-Item -ItemType Directory -Force (Split-Path -Parent $Out) | Out-Null
& $Godot --headless --path . --import 2>&1 | Out-Null
& $Godot --headless --path . --export-release "Windows Desktop" $Out 2>&1 | Out-File -Encoding utf8 "build/export_log.txt"
if ($LASTEXITCODE -ne 0) { throw "export failed ($LASTEXITCODE), see build/export_log.txt" }
$size = (Get-Item $Out).Length / 1MB
Write-Host ("Exported {0} ({1:N0} MB)" -f (Resolve-Path $Out), $size)
