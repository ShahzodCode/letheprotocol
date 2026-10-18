extends Node
## Frame-cost probe: `-- --script res://tests/perf_probe.gd [out=<json>] [spots=<json>] [frames=600] [only=a,b]`
## Teleports the player to six fixed spots, holds still for WARM frames, then records FRAMES frames per spot:
##   lobby (Institute lobby), avenue (middle of the Institute avenue looking along it), site70 (central avenue, battle site z = 70),
##   fire (next to a burning building), roof (reachable tall roof, looking over the city), cellar.
## Per spot: median / p95 / p99 / max frame ms (wall clock per frame), script ms, physics ms, draw calls, primitives, objects,
## render cpu / gpu ms (viewport render time), enemies alive / hunting, hitches (> 25 ms) during the spot.
## Windowed 1280x720, vsync OFF, default quality (Settings defaults), so the numbers do not depend on user://settings.cfg.
## LETHE_PLAIN=1 skips the war-torn layer; LETHE_SEED=<n> fixes the soldiers' places. `tests/perf_baseline.ps1` runs it 3x per mode
## and `tests/perf_merge.gd` makes tests/perf_baseline.json (median of medians).
const WARM := 120
const PRIME := 90
const SPOT_ORDER := ["lobby", "avenue", "site70", "fire", "roof", "cellar", "sky", "balcony", "court"]
var frames := 600
var out_path := "res://.shots/perf_run.json"
var calm := false               # calm=1: soldiers and civilians stand frozen (no AI / animation), so the numbers isolate rendering + physics
var shots_dir := ""             # shots=<dir>: one PNG per spot (renderer comparisons)


func run(m) -> void:
	Game.force_input = true
	var only: PackedStringArray = []
	var spots_file := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_path = a.substr(4)
		elif a.begins_with("frames="):
			frames = int(a.substr(7))
		elif a.begins_with("spots="):
			spots_file = a.substr(6)
		elif a.begins_with("only="):
			only = a.substr(5).split(",")
		elif a.begins_with("shots="):
			shots_dir = a.substr(6)
		elif a == "calm=1":
			calm = true
	# fixed settings: windowed, no vsync (vsync would clamp every frame to 16.7 ms and hide the headroom)
	Settings.fullscreen = false
	Settings.vsync = false
	Settings.shadows = 2
	Settings.aa = 0
	Settings.scale_pct = 100
	Settings.view = 1
	Settings.apply(get_tree(), m)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1280, 720))
	Engine.max_fps = 0
	m.hud.visible = false
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var defs := _load_spots(spots_file) if spots_file != "" else _find_spots(m)
	if calm:
		for n in Game.enemies + Game.civilians:
			if is_instance_valid(n):
				n.process_mode = Node.PROCESS_MODE_DISABLED
	var result := {"meta": _meta(), "frames": frames, "spots_def": {}, "spots": {}}
	result["meta"]["calm"] = calm
	var pl: Player = m.player
	for i in 60:
		await get_tree().physics_frame
	# prime: look at every spot once so shader variants / pipelines compile before anything is measured (Vulkan renderers hitch hard on first use)
	for name in SPOT_ORDER:
		if defs.has(name) and (only.is_empty() or only.has(name)):
			var pf: Vector3 = defs[name]["from"]
			var pd: Vector3 = defs[name]["look"] - (pf + Vector3(0, 1.6, 0))
			for k in PRIME:
				_hold(pl, pf, atan2(-pd.x, -pd.z), asin(pd.y / pd.length()))
				await get_tree().process_frame
	for name in SPOT_ORDER:
		if not defs.has(name) or (not only.is_empty() and not only.has(name)):
			continue
		if name == "balcony":          # the last spot: the landing craft stands and its ten guards are about (the worst case of "The Lander")
			if OS.get_environment("LETHE_NOLANDER") == "":          # LETHE_NOLANDER=1: the same view without the craft and the guards (A/B), LETHE_NOGUARDS=1: the craft alone
				m.world.lander.land_now()
				if OS.get_environment("LETHE_NOGUARDS") == "":
					m.park_fight.spawn_guards()
			if OS.get_environment("LETHE_BSTAND") == "":          # the sniper lies low (crouched: the guards do not see him at 25 m+); LETHE_BSTAND=1: he stands in plain view, the ten guards shoot at him
				Input.action_press("crouch")
			if calm:
				for g in m.park_fight.guards():
					g.process_mode = Node.PROCESS_MODE_DISABLED
		if name == "court" and OS.get_environment("LETHE_NOCOURT") == "":          # the four soldiers hold their circle (LETHE_NOCOURT=1: the empty courtyard, A/B)
			m.chase.phase = ChaseFight.Phase.CHASE
			m.chase.gather()
			for e in m.chase.court():
				e.global_position = (e as Enemy).hold_spot + Vector3(0, 0.1, 0)
				if calm:
					e.process_mode = Node.PROCESS_MODE_DISABLED
		var d: Dictionary = defs[name]
		result["spots_def"][name] = {"from": _v(d["from"]), "look": _v(d["look"])}
		var f: Vector3 = d["from"]
		var l: Vector3 = d["look"]
		var dir := l - (f + Vector3(0, 1.6, 0))
		var yaw := atan2(-dir.x, -dir.z)
		var pitch := asin(dir.y / dir.length())
		for k in WARM:
			_hold(pl, f, yaw, pitch)
			await get_tree().process_frame
		var h0 := Game.hitches.size()
		var ft: Array = []
		var sc: Array = []
		var ph: Array = []
		var dc: Array = []
		var pr: Array = []
		var ob: Array = []
		var rc: Array = []
		var rg: Array = []
		var last := Time.get_ticks_usec()
		for k in frames:
			_hold(pl, f, yaw, pitch)
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			ft.append(float(now - last) / 1000.0)
			last = now
			sc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			dc.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			pr.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			ob.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			rc.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			rg.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		if shots_dir != "":
			_hold(pl, f, yaw, pitch)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(shots_dir)
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])
		var hunting := 0
		var alive := 0
		for e in Game.enemies:
			if is_instance_valid(e) and e.state != Enemy.State.DEAD:
				alive += 1
				if e.state != Enemy.State.WANDER and e.state != Enemy.State.SUSPICIOUS:
					hunting += 1
		var worst := 0.0
		var tags := {}
		for hi in range(h0, Game.hitches.size()):
			worst = maxf(worst, float(Game.hitches[hi]["ms"]))
			for tg in Game.hitches[hi]["tags"]:
				tags[tg] = int(tags.get(tg, 0)) + 1
		result["spots"][name] = {
			"frame_ms_median": _pct(ft, 0.5), "frame_ms_p95": _pct(ft, 0.95), "frame_ms_p99": _pct(ft, 0.99), "frame_ms_max": _pct(ft, 1.0),
			"script_ms": _pct(sc, 0.5), "physics_ms": _pct(ph, 0.5),
			"draw_calls": _pct(dc, 0.5), "primitives": _pct(pr, 0.5), "objects": _pct(ob, 0.5),
			"render_cpu_ms": _pct(rc, 0.5), "render_gpu_ms": _pct(rg, 0.5),
			"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			"enemies": alive, "hunting": hunting, "hitches": Game.hitches.size() - h0, "hitch_worst_ms": worst, "hitch_tags": tags,
		}
		print("%-7s median %.2f ms  p95 %.2f  p99 %.2f  max %.1f | script %.2f phys %.2f | draws %d prims %d | render cpu %.2f gpu %.2f | enemies %d (%d hunting)" % [
			name, _pct(ft, 0.5), _pct(ft, 0.95), _pct(ft, 0.99), _pct(ft, 1.0), _pct(sc, 0.5), _pct(ph, 0.5), _pct(dc, 0.5), _pct(pr, 0.5), _pct(rc, 0.5), _pct(rg, 0.5), alive, hunting])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(result, "\t"))
		fa.close()
	print("wrote ", ProjectSettings.globalize_path(out_path))
	get_tree().quit()


func _hold(pl: Player, f: Vector3, yaw: float, pitch: float) -> void:
	pl.health = 100.0
	pl.velocity = Vector3.ZERO
	pl.global_position = f
	pl.yaw = yaw
	pl.pitch = pitch
	Game.dead = false


func _meta() -> Dictionary:
	var g: Dictionary = Game.gpu.duplicate()
	g["plain"] = OS.get_environment("LETHE_PLAIN") != ""
	g["seed"] = OS.get_environment("LETHE_SEED")
	g["window"] = str(DisplayServer.window_get_size())
	g["vsync"] = Settings.vsync
	g["shadows"] = Settings.shadows
	g["aa"] = Settings.aa
	g["scale_pct"] = Settings.scale_pct
	g["view"] = Settings.view
	g["video_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	g["cpu"] = OS.get_processor_name()
	g["cores"] = OS.get_processor_count()
	return g


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _load_spots(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out := {}
	for k in data["spots_def"]:
		var d: Dictionary = data["spots_def"][k]
		out[k] = {"from": Vector3(d["from"][0], d["from"][1], d["from"][2]), "look": Vector3(d["look"][0], d["look"][1], d["look"][2])}
	return out


## Works out the six spots from the generated city (the same seed gives the same city; `spots=` reuses an earlier run's positions,
## which matters for "fire" because LETHE_PLAIN has no burning buildings).
func _find_spots(m) -> Dictionary:
	var out := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	out["lobby"] = {"from": City.START_POS, "look": City.START_POS + Vector3(0, 1.6, -30)}
	out["avenue"] = {"from": Vector3(-60, 0.1, 235), "look": Vector3(150, 1.6, 235)}
	var s0: Vector3 = Vector3(0, 0, 70)
	var best := 1e9
	for s in City.sites:
		var d := Vector2(s["center"].x, s["center"].z - 70.0).length()
		if d < best:
			best = d
			s0 = s["center"]
	out["site70"] = {"from": s0 + Vector3(0, 0.1, 22), "look": s0 + Vector3(0, 1.6, 0)}
	# the burning building nearest to the central avenue
	var fire_pos := Vector3.INF
	var fbest := 1e9
	if m.world.fires != null:
		for e in m.world.fires.entries:
			if e["kind"] == "build":
				var dd := Vector2(e["pos"].x, e["pos"].z).length()
				if dd < fbest:
					fbest = dd
					fire_pos = e["pos"]
	if fire_pos != Vector3.INF:
		var spot := Vector3.INF
		for tries in 40:
			spot = City.random_point_near(rng, Vector3(fire_pos.x, 0.0, fire_pos.z), 9.0, 16.0)
			if spot != Vector3.INF:
				break
		if spot == Vector3.INF:
			spot = Vector3(fire_pos.x, 0.0, fire_pos.z)
		out["fire"] = {"from": Vector3(spot.x, 0.1, spot.z), "look": fire_pos}
	# the tallest reachable roof near the middle, standing 2 m in from the edge facing the city centre
	var roof_b := {}
	var rbest := 0.0
	for b in City.buildings:
		if bool(b.get("access", false)) and not b.has("border") and float(b["h"]) > rbest:
			var c: Vector2 = (b["rect"] as Rect2).get_center()
			if absf(c.x) < 120.0 and absf(c.y) < 220.0:
				rbest = float(b["h"])
				roof_b = b
	if not roof_b.is_empty():
		var r: Rect2 = roof_b["rect"]
		var c2 := r.get_center()
		var to_mid := (Vector2.ZERO - c2).normalized()
		var edge := c2 + Vector2(to_mid.x * (r.size.x * 0.5 - 2.0), to_mid.y * (r.size.y * 0.5 - 2.0))
		out["roof"] = {"from": Vector3(edge.x, rbest + 0.1, edge.y), "look": Vector3(0, 10, 0)}
	out["cellar"] = {"from": City.CELLAR_POS + Vector3(0, 0.1, 0), "look": City.CELLAR_POS + Vector3(-3, 1.2, 0)}
	# straight up the central avenue at the wound and the landers (the sky shader, 8 hulls and their shimmer at their most visible)
	out["sky"] = {"from": Vector3(0, 0.1, 40), "look": Vector3(0, 400, -10)}
	# on the balcony looking at the landing craft and the guards at its ramp (west end of the ledge, as the sniper lies)
	out["balcony"] = {"from": Vector3(75.5, City.BALCONY_Y + 0.1, -30.4), "look": City.LANDER_POS + Vector3(-8.0, 3.0, 0.0)}
	# on the low roof over the courtyard of Noah's neighbourhood, three metres back from the edge, looking down at the four soldiers back to back
	out["court"] = {"from": Vector3(84.0, City.COURT_ROOF_Y + 0.1, 26.0), "look": City.COURT_POS + Vector3(0.0, 0.5, 0.0)}
	return out


## Percentile of an unsorted array (p = 0.5 median, 1.0 max).
func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(floor(p * float(s.size() - 1) + 0.5)))])
