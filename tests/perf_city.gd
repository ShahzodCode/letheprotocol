extends Node
## City-pass performance baseline: `-- --script res://tests/perf_city.gd [tag=before] [out=<json>] [speed=6] [check=1]`   (windowed, vsync off)
## Measures, for the CURRENT tree: the frame time (mean / median / p95 / worst) on the Chapter One walk (Institute exit -> home door along
## `City.path`, the player teleported along it at `speed` m/s with the AI live) and in the densest area (most buildings / cars / trees
## within 100 m, four headings), draw calls, primitives, the static triangle count of the whole scene, node and physics body counts, the
## nav grid sizes, the hitch log (frames over 25 ms) and the AI tick cost (`Enemy._physics_process` timed by hand, microseconds per
## soldier per tick). Use `LETHE_SEED=12345` so the soldiers stand in the same places. `check=1` asserts the budgets of docs/performance.md
## ("city pass: before") and exits 1 on a failure. Same window / quality as perf_probe.gd.
const WARM := 120
const DENSE_FRAMES := 150
const AI_TICKS := 240
const BUDGET_SLACK := 1.25               # check=1: frame time may be at most this much of the recorded "before" number (noise)
var tag := "before"
var out_path := ""
var speed := 6.0
var check := false
var _sc: Array = []
var _ph: Array = []


func run(m) -> void:
	Game.force_input = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
		elif a.begins_with("out="):
			out_path = a.substr(4)
		elif a.begins_with("speed="):
			speed = float(a.substr(6))
		elif a == "check=1":
			check = true
	if out_path == "":
		out_path = "res://.shots/perf_city_%s.json" % tag
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
	var pl: Player = m.player
	for i in 90:
		await get_tree().physics_frame
	var res := {"tag": tag, "meta": {"cpu": OS.get_processor_name(), "gpu": String(Game.gpu.get("name", "?")), "seed": OS.get_environment("LETHE_SEED"),
		"plain": OS.get_environment("LETHE_PLAIN") != "", "physics_hz": Engine.physics_ticks_per_second}}
	res["static"] = _static_counts(m)
	# prime the shaders at the start and the end of the walk
	var path := City.path(City.INSTITUTE_EXIT, City.HOME_POS)
	var pts: Array = [City.INSTITUTE_EXIT]
	for p in path:
		pts.append(p)
	pts.append(City.HOME_POS)
	for k in WARM:
		_hold(pl, City.INSTITUTE_EXIT, 0.0)
		await get_tree().process_frame
	# ---- the walk
	var h0 := Game.hitch_total
	var walk := await _walk(pl, pts, vp)
	res["walk"] = walk
	walk["script_ms"] = _pct(_sc, 0.5)
	walk["physics_ms"] = _pct(_ph, 0.5)
	_sc.clear()
	_ph.clear()
	walk["hitches"] = Game.hitch_total - h0
	walk["hitch_worst_ms"] = walk["frame_ms_max"]          # Game.hitches keeps only the newest 300: the worst frame is measured here
	# ---- the densest area
	var dense := _densest()
	res["dense_at"] = [snappedf(dense.x, 0.1), snappedf(dense.z, 0.1)]
	h0 = Game.hitch_total
	var dres := await _dense(pl, dense, vp)
	res["dense"] = dres
	dres["script_ms"] = _pct(_sc, 0.5)
	dres["physics_ms"] = _pct(_ph, 0.5)
	res["hitch_stats"] = Game.hitch_stats.duplicate(true)
	dres["hitches"] = Game.hitch_total - h0
	dres["hitch_worst_ms"] = dres["frame_ms_max"]
	# ---- the AI tick, timed by hand with the soldiers' own processing off
	res["ai"] = await _ai_cost(m, pl, dense)
	res["static_after"] = _static_counts(m)
	print("PERF_CITY ", JSON.stringify(res))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(res, "\t"))
		fa.close()
	_print(res)
	var fails := 0
	if check:
		fails = _check(res)
	get_tree().quit(1 if fails > 0 else 0)


func _hold(pl: Player, f: Vector3, yaw: float) -> void:
	pl.health = 100.0
	pl.velocity = Vector3.ZERO
	pl.global_position = f
	pl.yaw = yaw
	pl.pitch = 0.0
	Game.dead = false


## Walks the player along the waypoints at `speed` m/s (one position per frame), looking where he goes.
func _walk(pl: Player, pts: Array, vp: RID) -> Dictionary:
	var ft: Array = []
	var dc: Array = []
	var pr: Array = []
	var rc: Array = []
	var rg: Array = []
	var seg := 0
	var pos: Vector3 = pts[0]
	var last := Time.get_ticks_usec()
	var dist := 0.0
	while seg < pts.size() - 1:
		var tgt: Vector3 = pts[seg + 1]
		var to := tgt - pos
		to.y = 0.0
		var now := Time.get_ticks_usec()
		var dt := minf(float(now - last) / 1e6, 0.1)
		ft.append(float(now - last) / 1000.0)
		last = now
		var step := speed * dt
		if to.length() <= step:
			pos = Vector3(tgt.x, 0.1, tgt.z)
			dist += to.length()
			seg += 1
		else:
			pos += to.normalized() * step
			pos.y = 0.1
			dist += step
		var look := (pts[mini(seg + 1, pts.size() - 1)] as Vector3) - pos
		_hold(pl, pos, atan2(-look.x, -look.z))
		await get_tree().process_frame
		dc.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		pr.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		rc.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		rg.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_sc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	return {"metres": snappedf(dist, 0.1), "frames": ft.size(), "frame_ms_mean": _mean(ft), "frame_ms_median": _pct(ft, 0.5), "frame_ms_p95": _pct(ft, 0.95),
		"frame_ms_p99": _pct(ft, 0.99), "frame_ms_max": _pct(ft, 1.0), "draw_calls_median": _pct(dc, 0.5), "draw_calls_max": _pct(dc, 1.0),
		"primitives_median": _pct(pr, 0.5), "primitives_max": _pct(pr, 1.0), "render_cpu_ms": _pct(rc, 0.5), "render_gpu_ms": _pct(rg, 0.5)}


## The free street point with the most buildings, cars, trees and obstacles within 100 m.
func _densest() -> Vector3:
	var best := Vector3(0, 0.1, 0)
	var best_n := -1
	var x := -120.0
	while x <= 120.0:
		var z := -260.0
		while z <= 240.0:
			var p := Vector3(x, 0.1, z)
			if City.is_free(p) and City.layer_of(p) < 0:
				var n := 0
				for b in City.buildings:
					var c: Vector2 = (b["rect"] as Rect2).get_center()
					if absf(c.x - x) < 100.0 and absf(c.y - z) < 100.0 and not b.has("border"):
						n += 1
				for c2 in City.cars:
					if absf(c2["pos"].x - x) < 100.0 and absf(c2["pos"].z - z) < 100.0:
						n += 1
				for t in City.trees:
					if absf(t["pos"].x - x) < 100.0 and absf(t["pos"].y - z) < 100.0:
						n += 1
				if n > best_n:
					best_n = n
					best = p
			z += 20.0
		x += 20.0
	return best


func _dense(pl: Player, at: Vector3, vp: RID) -> Dictionary:
	var ft: Array = []
	var dc: Array = []
	var pr: Array = []
	var rc: Array = []
	var rg: Array = []
	for heading in 4:
		var yaw := float(heading) * PI * 0.5
		for k in WARM / 2:
			_hold(pl, at, yaw)
			await get_tree().process_frame
		var last := Time.get_ticks_usec()
		for k in DENSE_FRAMES:
			_hold(pl, at, yaw)
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			ft.append(float(now - last) / 1000.0)
			last = now
			dc.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			pr.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			rc.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			rg.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			_sc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	return {"frames": ft.size(), "frame_ms_mean": _mean(ft), "frame_ms_median": _pct(ft, 0.5), "frame_ms_p95": _pct(ft, 0.95), "frame_ms_p99": _pct(ft, 0.99),
		"frame_ms_max": _pct(ft, 1.0), "draw_calls_median": _pct(dc, 0.5), "draw_calls_max": _pct(dc, 1.0), "primitives_median": _pct(pr, 0.5),
		"primitives_max": _pct(pr, 1.0), "render_cpu_ms": _pct(rc, 0.5), "render_gpu_ms": _pct(rg, 0.5)}


## `Enemy._physics_process` called by hand for every living soldier, AI_TICKS ticks, with the soldiers' own processing switched off:
## microseconds per soldier per tick (their state is whatever the walk left: some hunt, most wander).
func _ai_cost(m, pl: Player, at: Vector3) -> Dictionary:
	var list: Array = []
	for e in Game.enemies:
		if is_instance_valid(e) and (e as Enemy).state != Enemy.State.DEAD:
			list.append(e)
			(e as Enemy).set_physics_process(false)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var total := 0
	for t in AI_TICKS:
		_hold(pl, at, 0.0)
		AiBudget.new_tick()
		var t0 := Time.get_ticks_usec()
		for e in list:
			(e as Enemy)._physics_process(dt)
		total += Time.get_ticks_usec() - t0
		await get_tree().physics_frame
	for e in list:
		(e as Enemy).set_physics_process(true)
	return {"soldiers": list.size(), "ticks": AI_TICKS, "us_per_soldier_tick": snappedf(float(total) / float(maxi(list.size(), 1) * AI_TICKS), 0.1),
		"ms_per_tick_all": snappedf(float(total) / float(AI_TICKS) / 1000.0, 0.001), "ticks_per_second": Engine.physics_ticks_per_second}


# ---------------------------------------------------------------- static counts

func _static_counts(m) -> Dictionary:
	var out := {}
	out["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var bodies := {"static": 0, "character": 0, "rigid": 0, "area": 0}
	var shapes := 0
	var mm_nodes := 0
	var mm_instances := 0
	var mesh_nodes := 0
	var tris := 0
	var tris_mm := 0
	var stack: Array = [m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is StaticBody3D:
			bodies["static"] += 1
		elif n is CharacterBody3D:
			bodies["character"] += 1
		elif n is RigidBody3D:
			bodies["rigid"] += 1
		elif n is Area3D:
			bodies["area"] += 1
		if n is CollisionShape3D:
			shapes += 1
		if n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			mm_nodes += 1
			if mmi.multimesh != null:
				mm_instances += mmi.multimesh.instance_count
				var per := _mesh_tris(mmi.multimesh.mesh)
				tris_mm += per * mmi.multimesh.instance_count
				tris += per * mmi.multimesh.instance_count
		elif n is MeshInstance3D:
			mesh_nodes += 1
			tris += _mesh_tris((n as MeshInstance3D).mesh)
	out["bodies"] = bodies
	out["collision_shapes"] = shapes
	out["multimesh_nodes"] = mm_nodes
	out["multimesh_instances"] = mm_instances
	out["mesh_nodes"] = mesh_nodes
	out["triangles_scene"] = tris
	out["triangles_multimesh"] = tris_mm
	out["physics_active_objects"] = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	out["buildings"] = City.buildings.size()
	var closed := 0
	var border := 0
	for b in City.buildings:
		if b.has("border"):
			border += 1
	out["buildings_border"] = border
	out["streets"] = City.streets.size()
	out["cars"] = City.cars.size()
	out["props"] = City.props.size()
	out["trees"] = City.trees.size()
	out["enemies"] = Game.enemies.size()
	out["civilians"] = Game.civilians.size()
	var mg: Dictionary = City._main_grid
	var free_cells := 0
	var a: AStarGrid2D = mg["a"]
	for z in int(mg["nz"]):
		for x in int(mg["nx"]):
			if not a.is_point_solid(Vector2i(x, z)):
				free_cells += 1
	out["nav_main_cells"] = int(mg["nx"]) * int(mg["nz"])
	out["nav_main_free"] = free_cells
	var layer_cells := 0
	for l in City.layers:
		layer_cells += int(l["grid"]["nx"]) * int(l["grid"]["nz"])
	out["nav_layers"] = City.layers.size()
	out["nav_layer_cells"] = layer_cells
	return out


func _mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for s in am.get_surface_count():
			var il := am.surface_get_array_index_len(s)
			n += (il if il > 0 else am.surface_get_array_len(s)) / 3
		return n
	return mesh.get_faces().size() / 3


func _print(res: Dictionary) -> void:
	var s: Dictionary = res["static"]
	print("=== PERF CITY (%s) ===" % res["tag"])
	print("nodes %d, static bodies %d, character %d, rigid %d, areas %d, shapes %d, multimesh nodes %d (%d instances), mesh nodes %d" % [s["nodes"], s["bodies"]["static"], s["bodies"]["character"], s["bodies"]["rigid"], s["bodies"]["area"], s["collision_shapes"], s["multimesh_nodes"], s["multimesh_instances"], s["mesh_nodes"]])
	print("triangles in the scene %d (multimesh share %d); buildings %d (%d border); cars %d, props %d, trees %d; enemies %d, civilians %d" % [s["triangles_scene"], s["triangles_multimesh"], s["buildings"], s["buildings_border"], s["cars"], s["props"], s["trees"], s["enemies"], s["civilians"]])
	print("nav: main %d cells (%d free), %d layers with %d cells" % [s["nav_main_cells"], s["nav_main_free"], s["nav_layers"], s["nav_layer_cells"]])
	for k in ["walk", "dense"]:
		var w: Dictionary = res[k]
		print("%-5s %d frames: mean %.2f median %.2f p95 %.2f p99 %.2f max %.1f ms | draws %d (max %d) prims %d (max %d) | render cpu %.2f gpu %.2f | hitches %d worst %.1f ms" % [k, w["frames"], w["frame_ms_mean"], w["frame_ms_median"], w["frame_ms_p95"], w["frame_ms_p99"], w["frame_ms_max"], w["draw_calls_median"], w["draw_calls_max"], w["primitives_median"], w["primitives_max"], w["render_cpu_ms"], w["render_gpu_ms"], w["hitches"], w["hitch_worst_ms"]])
	var a: Dictionary = res["ai"]
	print("AI: %d soldiers, %.1f us per soldier per tick, %.3f ms per tick for all (%d ticks/s)" % [a["soldiers"], a["us_per_soldier_tick"], a["ms_per_tick_all"], a["ticks_per_second"]])


## check=1: the budgets are the "city pass: before" numbers in docs/performance.md, kept in tests/perf_city_before.json.
func _check(res: Dictionary) -> int:
	var f := FileAccess.open("res://tests/perf_city_before.json", FileAccess.READ)
	if f == null:
		print("CHECK: tests/perf_city_before.json missing")
		return 1
	var base = JSON.parse_string(f.get_as_text())
	f.close()
	var fails := 0
	for k in ["walk", "dense"]:
		var now: Dictionary = res[k]
		var was: Dictionary = base[k]
		for key in ["frame_ms_mean", "frame_ms_p95"]:
			var ok := float(now[key]) <= float(was[key]) * BUDGET_SLACK + 0.3
			print("%s %s: %s %.2f vs before %.2f (limit %.2f)" % ["PASS" if ok else "FAIL", k, key, now[key], was[key], float(was[key]) * BUDGET_SLACK + 0.3])
			fails += 0 if ok else 1
		var ok2 := float(now["hitch_worst_ms"]) <= maxf(float(was["hitch_worst_ms"]) * 1.25, 40.0)
		print("%s %s: worst hitch %.1f ms vs before %.1f" % ["PASS" if ok2 else "FAIL", k, now["hitch_worst_ms"], was["hitch_worst_ms"]])
		fails += 0 if ok2 else 1
	var ng: int = int(res["static"]["nav_main_cells"])
	var ok3 := ng <= int(int(base["static"]["nav_main_cells"]) * 1.10)
	print("%s nav grid %d cells vs before %d (+10%% max)" % ["PASS" if ok3 else "FAIL", ng, base["static"]["nav_main_cells"]])
	fails += 0 if ok3 else 1
	var ok4 := int(res["static"]["enemies"]) <= int(base["static"]["enemies"])
	print("%s soldier count %d vs before %d (must not rise)" % ["PASS" if ok4 else "FAIL", res["static"]["enemies"], base["static"]["enemies"]])
	fails += 0 if ok4 else 1
	return fails


func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(maxi(a.size(), 1))


func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(floor(p * float(s.size() - 1) + 0.5)))])
