# Smoke check, about 10 s: starts the game headless, waits a few seconds, fails on any script error or missing basics.
#   powershell -ExecutionPolicy Bypass -File tests/smoke.ps1 [-Godot "C:\Program Files\Godot\Godot.exe"] [-Seconds 60]
# Godot.exe is a GUI build on Windows (no shell output), so output goes to files; a script error would leave Godot idling forever,
# so the run is killed after -Seconds and counted as a failure.
param([string]$Godot = "C:\Program Files\Godot\Godot.exe", [int]$Seconds = 60)
$proj = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $proj ".shots"
New-Item -ItemType Directory -Force $dir | Out-Null
$out = Join-Path $dir "smoke.out"
$err = Join-Path $dir "smoke.err"
# refresh the class cache first: a new `class_name` script is "not declared" until the project is imported
$imp = Start-Process -PassThru -FilePath $Godot -ArgumentList @("--headless", "--path", $proj, "--import") -RedirectStandardOutput "$dir\import.out" -RedirectStandardError "$dir\import.err"
if (-not $imp.WaitForExit(120000)) { $imp.Kill() }
$env:LETHE_SEED = "12345"
$a = @("--headless", "--fixed-fps", "120", "--path", $proj, "--", "--script", "res://tests/smoke.gd")
$p = Start-Process -PassThru -FilePath $Godot -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err
if (-not $p.WaitForExit($Seconds * 1000)) {
    $p.Kill()
    Write-Host "SMOKE FAIL: timed out after $Seconds s (usually a script error: see below)"
    $bad = Select-String -Path $err, $out -Pattern "SCRIPT ERROR|Parse Error|Compile Error" -Context 0, 2 | Select-Object -First 6
    $bad | ForEach-Object { $_.Line; $_.Context.PostContext }
    exit 1
}
$bad = Select-String -Path $err, $out -Pattern "SCRIPT ERROR|Parse Error|Compile Error" -Context 0, 2 | Select-Object -First 6
if ($bad) {
    Write-Host "SMOKE FAIL: script errors"
    $bad | ForEach-Object { $_.Line; $_.Context.PostContext }
    exit 1
}
Select-String -Path $out -Pattern "SMOKE" | ForEach-Object { $_.Line }
exit $p.ExitCode
