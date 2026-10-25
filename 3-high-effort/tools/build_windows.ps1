# Builds the Windows release: build/windows/VeloraRoads.exe (+ data/world beside it).
# Usage: powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1
$godot = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$proj = Split-Path -Parent $PSScriptRoot
$out = Join-Path $proj "build\windows"
New-Item -ItemType Directory -Force (Join-Path $out "data\world") | Out-Null
& $godot --headless --path $proj --export-release "Windows Desktop" (Join-Path $out "VeloraRoads.exe")
foreach ($f in "height.bin", "surface.bin", "roaddist.bin", "world.json", "splat.png", "biome.png") {
    Copy-Item (Join-Path $proj "data\world\$f") (Join-Path $out "data\world\$f") -Force
}
Copy-Item (Join-Path $proj "tools\README_build.txt") (Join-Path $out "README.txt") -Force
Write-Output "Build ready: $out\VeloraRoads.exe"