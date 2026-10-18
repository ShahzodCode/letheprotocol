# One command: 3 runs of tests/perf_probe.gd with the war-torn city, 3 with LETHE_PLAIN=1, merged into tests/perf_baseline.json.
#   powershell -File tests/perf_baseline.ps1 [-Godot "C:\Program Files\Godot\Godot.exe"] [-Runs 3] [-Frames 600]
# Linux/macOS: loop the same two godot commands by hand (see CLAUDE.md "Testing"). Do not run anything else heavy meanwhile.
param([string]$Godot = "C:\Program Files\Godot\Godot.exe", [int]$Runs = 3, [int]$Frames = 600)
$proj = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $proj ".shots\perf"
New-Item -ItemType Directory -Force $dir | Out-Null
$env:LETHE_SEED = "12345"
$spots = ""
$files = @{ full = @(); plain = @() }
foreach ($mode in "full", "plain") {
    if ($mode -eq "plain") { $env:LETHE_PLAIN = "1" } else { Remove-Item Env:LETHE_PLAIN -ErrorAction SilentlyContinue }
    for ($i = 1; $i -le $Runs; $i++) {
        $out = Join-Path $dir "$mode$i.json"
        $a = @("--path", $proj, "--rendering-driver", "opengl3", "--resolution", "1280x720", "--", "--script", "res://tests/perf_probe.gd", "out=$out", "frames=$Frames")
        if ($spots -ne "") { $a += "spots=$spots" }
        Write-Host "run $mode $i ..."
        Start-Process -Wait -FilePath $Godot -ArgumentList $a -RedirectStandardOutput "$dir\$mode$i.log" -RedirectStandardError "$dir\$mode$i.err"
        if (-not (Test-Path $out)) { Write-Host "FAILED: see $dir\$mode$i.err"; exit 1 }
        if ($spots -eq "") { $spots = $out }       # every later run uses the first run's spot positions (the fire spot needs the full city)
        $files[$mode] += $out
    }
}
Remove-Item Env:LETHE_PLAIN -ErrorAction SilentlyContinue
$m = Start-Process -Wait -PassThru -NoNewWindow -FilePath $Godot -ArgumentList @("--headless", "--path", $proj, "-s", "res://tests/perf_merge.gd", "--", "out=res://tests/perf_baseline.json", ("full=" + (($files.full -join ",") -replace "\\","/")), ("plain=" + (($files.plain -join ",") -replace "\\","/"))) -RedirectStandardOutput "$dir\merge.log"
Get-Content "$dir\merge.log"
