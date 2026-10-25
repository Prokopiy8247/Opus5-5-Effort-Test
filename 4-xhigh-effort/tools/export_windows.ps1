# Builds the standalone Windows game: exports/windows/VALORIA.exe (data pack embedded, baked world included).
# Usage: powershell -ExecutionPolicy Bypass -File tools/export_windows.ps1 [-SelfTest]
#   -SelfTest  launches the fresh exe with --selftest and prints its status line from the log.
param([switch]$SelfTest)
$G = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "exports\windows\VALORIA.exe"
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
if (-not (Test-Path (Join-Path $root "world\generated\world_data.res"))) {
    # ship the baked world so the first launch does not have to generate it
    & $G --headless --path $root --script res://tools/world_bake.gd | Out-Null
}
& $G --headless --path $root --export-release Windows $out | Out-Null
if (-not (Test-Path $out)) { Write-Output "Export failed"; exit 1 }
Write-Output ("Exported {0} ({1:N1} MB)" -f $out, ((Get-Item $out).Length / 1MB))
if ($SelfTest) {
    $p = Start-Process -FilePath $out -ArgumentList "-- --selftest=30" -PassThru
    if (-not $p.WaitForExit(180000)) { & taskkill /PID $p.Id /T /F | Out-Null; Write-Output "Self-test timed out"; exit 2 }
    $log = Join-Path $env:APPDATA "Godot\app_userdata\VALORIA- Open Road Festival\logs\godot.log"
    Get-Content $log | Where-Object { $_ -match "SELFTEST|ERROR|SCRIPT ERROR" }
}
