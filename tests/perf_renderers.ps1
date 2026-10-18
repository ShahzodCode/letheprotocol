# Renderer comparison: perf_probe under gl_compatibility, mobile and forward_plus. Runs are INTERLEAVED (round 1: A B C, round 2: A B C ...)
# so slow drift of the machine (clocks, thermals, background load) hits every renderer equally.
#   calm = soldiers / civilians frozen (isolates rendering + physics), live = normal game.
# Merged (median of run medians) into tests/perf_renderers.json; run 1 of each calm case saves screenshots to .shots/renderers/<renderer>/.
#   powershell -File tests/perf_renderers.ps1 [-Runs 3] [-Frames 400] [-Modes calm,live]
# Keep the machine idle while it runs, the game window visible (not minimised) and the charger plugged in.
param([string]$Godot = "C:\Program Files\Godot\Godot.exe", [int]$Runs = 3, [int]$Frames = 400, [string[]]$Renderers = @("gl_compatibility", "mobile", "forward_plus"), [string[]]$Modes = @("calm", "live"), [string]$Tag = "")
$proj = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $proj ".shots\renderers$Tag"
New-Item -ItemType Directory -Force $dir | Out-Null
$env:LETHE_SEED = "12345"
Remove-Item Env:LETHE_PLAIN -ErrorAction SilentlyContinue
$spots = Join-Path $proj ".shots\perf\full1.json"      # spot positions from tests/perf_baseline.ps1
$files = [ordered]@{}
foreach ($mode in $Modes) { foreach ($r in $Renderers) { $files["${mode}_$r"] = @() } }
for ($i = 1; $i -le $Runs; $i++) {
    foreach ($mode in $Modes) {
        foreach ($r in $Renderers) {
            $key = "${mode}_$r"
            $out = Join-Path $dir "$key$i.json"
            $a = @("--path", $proj, "--rendering-method", $r, "--resolution", "1280x720", "--", "--script", "res://tests/perf_probe.gd", "out=$out", "frames=$Frames", "spots=$spots")
            if ($mode -eq "calm") { $a += "calm=1" }
            if ($mode -eq "calm" -and $i -eq 1) { $a += "shots=$dir\$r" }
            if (-not (Test-Path $out)) {
                Write-Host "run $key $i ..."
                Start-Process -Wait -FilePath $Godot -ArgumentList $a -RedirectStandardOutput "$dir\$key$i.log" -RedirectStandardError "$dir\$key$i.err"
                if (-not (Test-Path $out)) { Write-Host "retry $key $i"; Start-Process -Wait -FilePath $Godot -ArgumentList $a -RedirectStandardOutput "$dir\$key$i.log" -RedirectStandardError "$dir\$key$i.err" }
                if (-not (Test-Path $out)) { Write-Host "FAILED: see $dir\$key$i.err"; exit 1 }
            }
            $files[$key] += ($out -replace "\\", "/")
        }
    }
}
$args2 = @("--headless", "--path", $proj, "-s", "res://tests/perf_merge.gd", "--", "out=res://tests/perf_renderers$Tag.json")
foreach ($k in $files.Keys) { $args2 += "$k=" + ($files[$k] -join ",") }
Start-Process -Wait -NoNewWindow -FilePath $Godot -ArgumentList $args2 -RedirectStandardOutput "$dir\merge.log"
Get-Content "$dir\merge.log" | Where-Object { $_ -notmatch '^\[hitch\]' }
