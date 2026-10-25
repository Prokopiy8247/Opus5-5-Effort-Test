# Runs the project's Godot console executable with a hard timeout and filtered output.
# Only the process tree started here is ever killed.
# Usage: powershell -File tools/run_godot.ps1 -Timeout 120 -Filter "SHOT|ERROR" -A "--headless --path . ..."
param(
    [int]$Timeout = 300,
    [string]$Filter = "",
    [string]$A = "",
    [int]$Tail = 120
)
$G = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$root = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path $root "qa\tmp"
New-Item -ItemType Directory -Force $tmp | Out-Null
$stamp = Get-Date -Format "HHmmssfff"
$out = Join-Path $tmp "godot_$stamp.out.txt"
$err = Join-Path $tmp "godot_$stamp.err.txt"
$p = Start-Process -FilePath $G -ArgumentList $A -WorkingDirectory $root -NoNewWindow -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
$null = $p.Handle
if (-not $p.WaitForExit($Timeout * 1000)) {
    & taskkill /PID $p.Id /T /F | Out-Null
    Write-Output "TIMEOUT after $Timeout s (killed process tree $($p.Id))"
}
$lines = @()
if (Test-Path $out) { $lines += Get-Content $out }
if (Test-Path $err) { $lines += Get-Content $err }
if ($Filter -ne "") { $lines = $lines | Where-Object { $_ -match $Filter } }
$lines | Where-Object { $_ -notmatch '^\s*$' } | Select-Object -Last $Tail
Write-Output "EXIT $($p.ExitCode)"
Remove-Item $out, $err -ErrorAction SilentlyContinue
