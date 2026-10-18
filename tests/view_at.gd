extends Node
## Teleport the player and take pictures: `-- --script res://tests/view_at.gd 1,2,3>4,5,6 ... out=<dir>`  (from>look; "site0" = the first battle site)
var _acc := [0.0, 0.0, 0.0, 0]     # script process ms, physics ms, frame ms, frames (summed while a view settles)

func _process(delta: float) -> void:
	_acc[0] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_acc[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_acc[2] += delta * 1000.0
	_acc[3] += 1


func run(m) -> void:
	Game.force_input = true
	var outdir := "res://.shots"
	var views := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			outdir = a.substr(4)
		elif a == "lander":            # the landing craft in the park already stands (as after its descent)
			m.world.lander.land_now()
		elif a == "guards":            # ...and the ten guards stand round its ramp
			m.park_fight.spawn_guards()
		elif ">" in a:
			views.append(a)
	DirAccess.make_dir_recursive_absolute(outdir)
	m.hud.visible = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var pl: Player = m.player
	for k in 40:
		await get_tree().physics_frame
	var i := 0
	for v in views:
		var parts: PackedStringArray = v.split(">")
		var f := _vec(parts[0], m)
		var l := _vec(parts[1], m)
		pl.global_position = f
		pl.velocity = Vector3.ZERO
		var d := l - (f + Vector3(0, 1.6, 0))
		pl.yaw = atan2(-d.x, -d.z)
		pl.pitch = asin(d.y / d.length())
		for k in 50:
			pl.velocity = Vector3.ZERO
			pl.global_position = f
			await get_tree().physics_frame
		_acc = [0.0, 0.0, 0.0, 0]
		for k in 90:
			pl.health = 100.0
			pl.velocity = Vector3.ZERO
			pl.global_position = f          # stay where we are put (also high in the air: a free camera)
			Game.dead = false
			await get_tree().physics_frame
		pl.yaw = atan2(-d.x, -d.z)
		pl.pitch = asin(d.y / d.length())
		await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var vp := get_viewport().get_viewport_rid()
		var n := maxf(1.0, float(_acc[3]))
		print("view ", i, " frame %.1f ms (scripts %.1f, physics %.1f)" % [_acc[2] / n, _acc[0] / n, _acc[1] / n], " fps ", Engine.get_frames_per_second(), " enemies ", Game.enemies.size(), " civilians ", Game.civilians.size(), " | render cpu %.1f ms gpu %.1f ms | draw calls %d, objects %d, primitives %d" % [RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
		get_viewport().get_texture().get_image().save_png("%s/v%d.png" % [outdir, i])
		i += 1
	get_tree().quit()

func _vec(s: String, m) -> Vector3:
	if s.begins_with("site"):         # "site2" or "site2+dx,dy,dz" (offset from the site's centre)
		var plus := s.find("+")
		var c: Vector3 = City.sites[int(s.substr(4, plus - 4) if plus >= 0 else s.substr(4))]["center"]
		if plus >= 0:
			var o := s.substr(plus + 1).split(",")
			c += Vector3(float(o[0]), float(o[1]), float(o[2]))
		return c
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
