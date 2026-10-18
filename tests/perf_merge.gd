extends SceneTree
## Merges perf_probe runs: `godot --headless -s res://tests/perf_merge.gd -- out=tests/perf_baseline.json full=a.json,b.json,c.json plain=d.json,e.json,f.json`
## Each metric becomes the median of the runs' per-spot medians ("median of medians"); max / hitch counts take the worst run.
## Prints the table (full, plain and what the war-torn layer costs) and writes the JSON (with the individual runs).
const METRICS := ["frame_ms_median", "frame_ms_p95", "frame_ms_p99", "frame_ms_max", "script_ms", "physics_ms", "draw_calls", "primitives", "objects", "render_cpu_ms", "render_gpu_ms", "video_mem_mb", "enemies", "hunting", "hitches", "hitch_worst_ms"]
const WORST := ["frame_ms_max", "hitches", "hitch_worst_ms"]


func _initialize() -> void:
	var out := "res://tests/perf_baseline.json"
	var modes := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif "=" in a and ".json" in a:         # any label: full=a,b,c  calm_mobile=...
			var kv := a.split("=")
			var runs: Array = []
			for f in kv[1].split(","):
				runs.append(JSON.parse_string(FileAccess.get_file_as_string(f)))
			modes[kv[0]] = runs
	var result := {"meta": {}, "modes": {}}
	for mode in modes:
		var runs: Array = modes[mode]
		if result["meta"].is_empty():
			result["meta"] = runs[0]["meta"]
		var merged := {}
		for spot in runs[0]["spots"]:
			var row := {}
			for k in METRICS:
				var vals: Array = []
				for r in runs:
					if r["spots"].has(spot):
						vals.append(float(r["spots"][spot][k]))
				vals.sort()
				row[k] = vals[vals.size() - 1] if k in WORST else vals[vals.size() / 2]
			merged[spot] = row
		result["modes"][mode] = {"runs": runs.size(), "spots": merged, "per_run_median_ms": _per_run(runs)}
	_table(result)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_string(JSON.stringify(result, "\t"))
	fa.close()
	print("wrote ", ProjectSettings.globalize_path(out))
	quit()


func _per_run(runs: Array) -> Dictionary:
	var d := {}
	for spot in runs[0]["spots"]:
		d[spot] = runs.map(func(r): return snappedf(float(r["spots"][spot]["frame_ms_median"]), 0.01))
	return d


func _table(result: Dictionary) -> void:
	var m: Dictionary = result["meta"]
	print("\nAdapter: %s [%s] vendor %s | %s (%s) | %s | Godot %s | %s, %d threads | window %s vsync %s" % [m.get("name"), m.get("type"), m.get("vendor"), m.get("driver"), m.get("method"), m.get("os"), m.get("godot"), m.get("cpu"), int(m.get("cores", 0)), m.get("window"), m.get("vsync")])
	for mode in result["modes"]:
		var d: Dictionary = result["modes"][mode]
		print("\n== %s (median of %d run medians) ==" % [mode.to_upper(), d["runs"]])
		print("%-7s %7s %7s %7s %8s %7s %7s %6s %9s %7s %7s %5s %5s" % ["spot", "med ms", "p95", "p99", "max", "script", "phys", "draws", "prims", "rcpu", "rgpu", "enem", "hitch"])
		for spot in d["spots"]:
			var r: Dictionary = d["spots"][spot]
			print("%-7s %7.2f %7.2f %7.2f %8.1f %7.2f %7.2f %6d %9d %7.2f %7.2f %5d %5d" % [spot, r["frame_ms_median"], r["frame_ms_p95"], r["frame_ms_p99"], r["frame_ms_max"], r["script_ms"], r["physics_ms"], int(r["draw_calls"]), int(r["primitives"]), r["render_cpu_ms"], r["render_gpu_ms"], int(r["enemies"]), int(r["hitches"])])
	if result["modes"].has("full") and result["modes"].has("plain"):
		print("\n== war-torn layer cost (full - plain, median frame ms / draw calls / primitives) ==")
		for spot in result["modes"]["full"]["spots"]:
			if result["modes"]["plain"]["spots"].has(spot):
				var a: Dictionary = result["modes"]["full"]["spots"][spot]
				var b: Dictionary = result["modes"]["plain"]["spots"][spot]
				print("%-7s %+7.2f ms   %+6d draws   %+9d prims" % [spot, a["frame_ms_median"] - b["frame_ms_median"], int(a["draw_calls"] - b["draw_calls"]), int(a["primitives"] - b["primitives"])])
