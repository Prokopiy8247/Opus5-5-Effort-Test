# Runs the project's Godot console binary with a hard timeout and captures the log.
# Usage: powershell -File tools/run_godot.ps1 -Timeout 300 -A "--headless --script res://tools/x.gd" [-Log out.txt]
param(
    [int]$Timeout = 300,
    [string]$Log = "",
    [string]$A = ""
)
$godot = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$proj = Split-Path -Parent $PSScriptRoot
if ($Log -eq "") { $Log = Join-Path $env:TEMP ("godot_run_" + [guid]::NewGuid().ToString() + ".txt") }
$err = "$Log.err"
$argLine = "--path `"$proj`" " + $A
$p = Start-Process -FilePath $godot -ArgumentList $argLine -RedirectStandardOutput $Log -RedirectStandardError $err -PassThru -NoNewWindow
if (-not $p.WaitForExit($Timeout * 1000)) {
    # kill only the process tree we started
    Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $p.Id } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Write-Output "TIMEOUT after $Timeout s"
}
Get-Content $Log
if (Test-Path $err) { Get-Content $err }
