extends Node
## Battle profile: `-- --script res://tests/perf_battle.gd [secs=24] [out=<json>] [shots=<dir>] [calm=1]`
## The player stands 22 m from the central-avenue battle site, invulnerable, fires 8 shots a second at it and throws a grenade at
## 6 s, 12 s and 18 s. Reports frame ms (median / p95 / p99 / max), script ms per frame by section (Prof), hitches with their tags.
## Same window / vsync / quality as perf_probe.gd. LETHE_SEED=<n> fixes the soldiers' places.
var secs := 24.0
var out_path := "res://.shots/perf_battle.json"


func run(m) -> void:
	Game.force_input = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("secs="):
			secs = float(a.substr(5))
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
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var pl: Player = m.player
	var s0: Vector3 = Vector3(0, 0, 70)
	var best := 1e9
	for s in City.sites:
		var d := Vector2(s["center"].x, s["center"].z - 70.0).length()
		if d < best:
			best = d
			s0 = s["center"]
	var f := s0 + Vector3(0, 0.1, 22)
	var dir := (s0 + Vector3(0, 1.4, 0)) - (f + Vector3(0, 1.6, 0))
	var yaw := atan2(-dir.x, -dir.z)
	var pitch := asin(dir.y / dir.length())
	for i in 60:
		await get_tree().physics_frame
	# warm up (shaders, first-use costs) without firing, then measure
	for k in 150:
		_hold(pl, f, yaw, pitch)
		await get_tree().process_frame
	var h0: int = Game.hitch_total
	Prof.reset()
	Prof.on = true
	var ft: Array = []
	var sc: Array = []
	var ph: Array = []
	var dc: Array = []
	var t_start := Time.get_ticks_usec()
	var last := t_start
	var shot_i := 0
	var grenade_at := [6.0, 12.0, 18.0]
	var thrown := 0
	var frames := 0
	var hunting_max := 0
	var alive_start := _alive()
	while float(Time.get_ticks_usec() - t_start) / 1e6 < secs:
		var t := float(Time.get_ticks_usec() - t_start) / 1e6
		_hold(pl, f, yaw, pitch)
		var w: Weapons = pl.weapons
		if frames % 12 == 0:
			w.state[w.current]["ammo"] = 15
			w.cooldown = 0.0
			w.reloading = false
			w.switching = 0.0
			w._fire_shot()
			shot_i += 1
		if thrown < grenade_at.size() and t >= grenade_at[thrown]:
			Game.grenades = 1
			w.throw_grenade()
			thrown += 1
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ft.append(float(now - last) / 1000.0)
		last = now
		sc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		dc.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		frames += 1
		hunting_max = maxi(hunting_max, _hunting())
	Prof.on = false
	var secs_real := float(last - t_start) / 1e6
	var res := {"frames": frames, "secs": secs_real, "shots": shot_i, "grenades": thrown, "alive_start": alive_start, "alive_end": _alive(), "hunting_max": hunting_max,
		"frame_ms_median": _pct(ft, 0.5), "frame_ms_p95": _pct(ft, 0.95), "frame_ms_p99": _pct(ft, 0.99), "frame_ms_max": _pct(ft, 1.0),
		"process_monitor_ms": _pct(sc, 0.5), "physics_monitor_ms": _pct(ph, 0.5), "draw_calls": _pct(dc, 0.5),
		"hitches": Game.hitch_total - h0, "sections": {}}
	var ticks := secs_real * float(Engine.physics_ticks_per_second)
	print("battle: %d frames in %.1f s | frame median %.2f p95 %.2f p99 %.2f max %.1f | enemies alive %d -> %d, hunting max %d | hitches %d" % [frames, secs_real, res["frame_ms_median"], res["frame_ms_p95"], res["frame_ms_p99"], res["frame_ms_max"], alive_start, res["alive_end"], hunting_max, res["hitches"]])
	var names: Array = Prof.usec.keys()
	names.sort_custom(func(a, b): return Prof.usec[a] > Prof.usec[b])
	print("%-26s %10s %9s %10s" % ["section", "ms/frame", "calls", "us/call"])
	for n in names:
		var per_frame := float(Prof.usec[n]) / 1000.0 / float(frames)
		var calls := int(Prof.calls[n])
		res["sections"][n] = {"ms_per_frame": per_frame, "calls": calls, "us_per_call": float(Prof.usec[n]) / float(maxi(calls, 1))}
		print("%-26s %10.3f %9d %10.2f" % [n, per_frame, calls, float(Prof.usec[n]) / float(maxi(calls, 1))])
	var tags := {}
	for i in range(maxi(0, Game.hitches.size() - (Game.hitch_total - h0)), Game.hitches.size()):
		for tg in Game.hitches[i]["tags"]:
			tags[tg] = int(tags.get(tg, 0)) + 1
	res["hitch_tags"] = tags
	print("hitch tags: ", tags, "  (physics ticks/s %d)" % Engine.physics_ticks_per_second)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(res, "\t"))
	fa.close()
	get_tree().quit()


func _alive() -> int:
	var n := 0
	for e in Game.enemies:
		if is_instance_valid(e) and e.state != Enemy.State.DEAD:
			n += 1
	return n


func _hunting() -> int:
	var n := 0
	for e in Game.enemies:
		if is_instance_valid(e) and e.state != Enemy.State.DEAD and e.state != Enemy.State.WANDER and e.state != Enemy.State.SUSPICIOUS:
			n += 1
	return n


func _hold(pl: Player, f: Vector3, yaw: float, pitch: float) -> void:
	pl.health = 100.0
	pl.velocity = Vector3.ZERO
	pl.global_position = f
	pl.yaw = yaw
	pl.pitch = pitch
	Game.dead = false


func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(floor(p * float(s.size() - 1) + 0.5)))])
