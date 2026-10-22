extends Node
## Animation LOD stress: `-- --script res://tests/perf_anim.gd [n=80] [frames=360] [out=<json>] [shots=<png>]`
## Packs n clip soldiers (blade / rifleman / gunner / marksman in turn) into the player's view down the central avenue, 10 to ~160 m
## away in 4 columns, held in the HOLD state so they keep their idle / aim clips running, and measures frame ms. Run it twice, with and
## without LETHE_NOANIMLOD=1 (the animation update-rate LOD off), and compare. Same window / vsync / quality as perf_probe.gd.
var n := 80
var measure := 360
var out_path := ""
var shot_path := ""
var ablate := ""
var _saved := {}
var _ticks0 := 0
const KINDS := ["blade", "rifleman", "gunner", "marksman"]


func run(m) -> void:
	Game.force_input = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			n = int(a.substr(2))
		elif a.begins_with("frames="):
			measure = int(a.substr(7))
		elif a.begins_with("out="):
			out_path = a.substr(4)
		elif a.begins_with("tps="):
			Engine.physics_ticks_per_second = int(a.substr(4))       # a low rate keeps a slow frame from running 8 catch-up ticks (the death spiral hides gains)
		elif a.begins_with("ablate="):
			ablate = a.substr(7)       # anim | boxes | ai: switch that one thing off to see what it costs
		elif a.begins_with("shot="):
			shot_path = a.substr(5)
	Settings.fullscreen = false
	Settings.vsync = false
	Settings.shadows = 2
	Settings.aa = 0
	Settings.scale_pct = 100
	Settings.view = 1
	Settings.apply(get_tree(), m)
	Engine.max_fps = 0
	m.hud.visible = false
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var pl: Player = m.player
	for i in 30:
		await get_tree().physics_frame
	# the squad: reuse the clip soldiers that exist, spawn the rest; everybody else is parked far away
	var squad: Array = []
	for e in Game.enemies:
		if is_instance_valid(e) and e.kind != "soldier" and squad.size() < n:
			squad.append(e)
		elif is_instance_valid(e):
			e.global_position = Vector3(260.0 + 3.0 * (squad.size() % 10), 5.0, 3.0 * (squad.size() / 10))
			e.stun = 999.0
	var spawn_i := 0
	while squad.size() < n:
		var e: Enemy = m._spawn_enemy_at(Vector3(0, 0, 0), KINDS[spawn_i % KINDS.size()])
		spawn_i += 1
		squad.append(e)
	var slots: Array = []
	var cols := [-6.0, -2.0, 2.0, 6.0]
	var rows := int(ceil(float(n) / 4.0))
	for i in n:
		var row := i / 4
		var z := 85.0 - (10.0 + 150.0 * pow(float(row) / float(maxi(rows - 1, 1)), 1.3))
		slots.append(Vector3(cols[i % 4], World.height_at(cols[i % 4], z) + 0.1, z))
	var f := Vector3(0, World.height_at(0, 95) + 0.1, 95)
	for k in 120 + measure:
		_hold(pl, f)
		for i in n:
			var e: Enemy = squad[i]
			if not is_instance_valid(e):
				continue
			e.stun = 0.0
			e.health = e.cfg.get("health", 100.0) if e.health < 1.0 else e.health
			if e.global_position.distance_to(slots[i]) > 0.5 or e.state != Enemy.State.HOLD:
				e.global_position = slots[i]
				e.velocity = Vector3.ZERO
				e.home = slots[i]
				e.state = Enemy.State.HOLD
			e.rotation.y = 0.0
			match ablate:
				"anim":
					if e.model != null and e.model.player != null:
						e.model.player.active = false
				"boxes":
					if not e._bone_boxes.is_empty():
						_saved[e] = e._bone_boxes
						e._bone_boxes = []
				"ai":
					e.set_physics_process(false)
		if k == 120:
			_reset_stats()
			_ticks0 = Engine.get_physics_frames()
		await get_tree().process_frame
		if k >= 120:
			_sample()
	var vis := 0
	var manual := 0
	var active := 0
	for e in squad:
		if pl.camera.is_position_in_frustum(e.global_position + Vector3(0, 1.0, 0)):
			vis += 1
		if e.model != null and e.model.player != null:
			if e.model._lod_manual:
				manual += 1
			if e.model.player.active:
				active += 1
	_ft.sort()
	_pr.sort()
	_ph.sort()
	var res := {"n": n, "ablate": ablate, "lod": not Enemy.ANIM_LOD_OFF, "frames": _ft.size(), "visible": vis, "ticks_per_frame": float(Engine.get_physics_frames() - _ticks0) / float(measure), "anim_active": active, "stepped_by_hand": manual,
		"frame_ms_mean": _mean(_ft), "frame_ms_median": _ft[_ft.size() / 2], "frame_ms_p95": _ft[int(_ft.size() * 0.95)], "script_ms": _pr[_pr.size() / 2], "physics_ms": _ph[_ph.size() / 2],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(vp), "gpu": String(Game.gpu.get("name", "?"))}
	print("PERF_ANIM ", JSON.stringify(res))
	if out_path != "":
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		fa.store_string(JSON.stringify(res, "\t"))
		fa.close()
	if shot_path != "":
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit()


var _ft: Array = []
var _pr: Array = []
var _ph: Array = []
var _last := 0


func _reset_stats() -> void:
	_ft.clear()
	_pr.clear()
	_ph.clear()
	_last = Time.get_ticks_usec()


func _sample() -> void:
	var now := Time.get_ticks_usec()
	_ft.append(float(now - _last) / 1000.0)
	_last = now
	_pr.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(maxi(a.size(), 1))


func _hold(pl: Player, f: Vector3) -> void:
	pl.health = 100.0
	pl.velocity = Vector3.ZERO
	pl.global_position = f
	pl.yaw = 0.0
	pl.pitch = 0.0
	pl.rotation.y = 0.0
	pl.head.rotation = Vector3.ZERO
