extends Node
## Cost attribution: `-- --script res://tests/perf_ablate.gd spots=<perf_run.json> [frames=240] [only=lobby,site70] [out=<json>]`
## At each spot, measures the median frame ms with everything on, then with ONE thing switched off at a time, and prints the
## saving. Measurement only: nothing in the game is changed. Same window / vsync / quality as perf_probe.gd.
const WARM := 60
var frames := 240
var m
var vp: RID


func run(main_node) -> void:
	m = main_node
	Game.force_input = true
	var spots_file := ""
	var out_path := "res://.shots/perf_ablate.json"
	var only: PackedStringArray = ["lobby", "site70", "fire", "cellar"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("spots="):
			spots_file = a.substr(6)
		elif a.begins_with("frames="):
			frames = int(a.substr(7))
		elif a.begins_with("only="):
			only = a.substr(5).split(",")
		elif a.begins_with("out="):
			out_path = a.substr(4)
	Settings.fullscreen = false
	Settings.vsync = false
	Settings.shadows = 2
	Settings.aa = 0
	Settings.scale_pct = 100
	Settings.view = 1
	Settings.apply(get_tree(), m)
	Engine.max_fps = 0
	m.hud.visible = false
	vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var defs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spots_file))["spots_def"]
	var pl: Player = m.player
	for i in 60:
		await get_tree().physics_frame
	var ablations := _ablations()
	var result := {}
	for name in only:
		if not defs.has(name):
			continue
		var f := Vector3(defs[name]["from"][0], defs[name]["from"][1], defs[name]["from"][2])
		var l := Vector3(defs[name]["look"][0], defs[name]["look"][1], defs[name]["look"][2])
		var dir := l - (f + Vector3(0, 1.6, 0))
		var yaw := atan2(-dir.x, -dir.z)
		var pitch := asin(dir.y / dir.length())
		result[name] = {}
		var base := await _measure(pl, f, yaw, pitch)
		result[name]["all on"] = base
		print("== %s: all on  %.2f ms (script %.2f phys %.2f draws %d rcpu %.2f rgpu %.2f)" % [name, base["ms"], base["script"], base["phys"], base["draws"], base["rcpu"], base["rgpu"]])
		for ab in ablations:
			var undo: Callable = ab["do"].call()
			var r := await _measure(pl, f, yaw, pitch)
			undo.call()
			result[name][ab["name"]] = r
			print("   %-26s %7.2f ms  (%+6.2f)  script %6.2f phys %6.2f draws %4d rcpu %5.2f rgpu %5.2f" % [ab["name"], r["ms"], r["ms"] - base["ms"], r["script"], r["phys"], r["draws"], r["rcpu"], r["rgpu"]])
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(result, "\t"))
	fa.close()
	get_tree().quit()


func _measure(pl: Player, f: Vector3, yaw: float, pitch: float) -> Dictionary:
	var ft: Array = []
	var sc: Array = []
	var ph: Array = []
	var dc: Array = []
	var rc: Array = []
	var rg: Array = []
	var last := 0
	for k in WARM + frames:
		_hold(pl, f, yaw, pitch)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if k >= WARM:
			ft.append(float(now - last) / 1000.0)
			sc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			dc.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			rc.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			rg.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		last = now
	return {"ms": _med(ft), "p95": _pct(ft, 0.95), "script": _med(sc), "phys": _med(ph), "draws": _med(dc), "rcpu": _med(rc), "rgpu": _med(rg)}


func _hold(pl: Player, f: Vector3, yaw: float, pitch: float) -> void:
	pl.health = 100.0
	pl.velocity = Vector3.ZERO
	pl.global_position = f
	pl.yaw = yaw
	pl.pitch = pitch
	Game.dead = false


func _med(a: Array) -> float:
	return _pct(a, 0.5)


func _pct(a: Array, p: float) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(floor(p * float(s.size() - 1) + 0.5)))])


func _each(nodes: Array, prop: String, value) -> Callable:
	var old := []
	for n in nodes:
		if is_instance_valid(n):
			old.append([n, n.get(prop)])
			n.set(prop, value)
	return func() -> void:
		for o in old:
			if is_instance_valid(o[0]):
				o[0].set(prop, o[1])


func _collect(root: Node, cls: String, out: Array) -> void:
	if root.is_class(cls):
		out.append(root)
	for c in root.get_children():
		_collect(c, cls, out)


func _ablations() -> Array:
	return [
		{"name": "enemy AI+anim off", "do": func() -> Callable: return _each(Game.enemies, "process_mode", Node.PROCESS_MODE_DISABLED)},
		{"name": "enemies hidden", "do": func() -> Callable: return _each(Game.enemies, "visible", false)},
		{"name": "enemies AI off+hidden", "do": func() -> Callable:
			var u1 := _each(Game.enemies, "process_mode", Node.PROCESS_MODE_DISABLED)
			var u2 := _each(Game.enemies, "visible", false)
			return func() -> void:
				u1.call()
				u2.call()},
		{"name": "civilians off+hidden", "do": func() -> Callable:
			var u1 := _each(Game.civilians, "process_mode", Node.PROCESS_MODE_DISABLED)
			var u2 := _each(Game.civilians, "visible", false)
			return func() -> void:
				u1.call()
				u2.call()},
		{"name": "fires off+hidden", "do": func() -> Callable:
			if m.world.fires == null:
				return func() -> void: pass
			var u1 := _each([m.world.fires], "process_mode", Node.PROCESS_MODE_DISABLED)
			var u2 := _each([m.world.fires], "visible", false)
			return func() -> void:
				u1.call()
				u2.call()},
		{"name": "battle sites hidden", "do": func() -> Callable: return _each(m.world.sites, "visible", false)},
		{"name": "sun shadows off", "do": func() -> Callable: return _each([m.world.sun], "shadow_enabled", false)},
		{"name": "all omni lights off", "do": func() -> Callable:
			var l: Array = []
			_collect(m.world, "OmniLight3D", l)
			_collect(m, "OmniLight3D", l)
			return _each(l, "visible", false)},
		{"name": "all particles off", "do": func() -> Callable:
			var l: Array = []
			_collect(m, "CPUParticles3D", l)
			_collect(m, "GPUParticles3D", l)
			return _each(l, "visible", false)},
		{"name": "all MultiMesh scenery hidden", "do": func() -> Callable:
			var l: Array = []
			_collect(m.world, "MultiMeshInstance3D", l)
			return _each(l, "visible", false)},
		{"name": "physics 60 Hz", "do": func() -> Callable:
			var old := Engine.physics_ticks_per_second
			Engine.physics_ticks_per_second = 60
			return func() -> void: Engine.physics_ticks_per_second = old},
		{"name": "render scale 50%", "do": func() -> Callable:
			get_tree().root.scaling_3d_scale = 0.5
			return func() -> void: get_tree().root.scaling_3d_scale = 1.0},
		{"name": "view distance short", "do": func() -> Callable:
			Settings.view = 0
			Settings.apply(get_tree(), m)
			return func() -> void:
				Settings.view = 1
				Settings.apply(get_tree(), m)},
	]
