extends Node
## The lookout: from the roof of the old block, the landing craft coming down over the park (3 s in, touchdown, a moment later) and the
## settled craft in the far squares: `-- --script res://tests/lander_shots.gd out=<dir>`
func run(m) -> void:
	Game.force_input = true
	var outdir := "res://.shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			outdir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(outdir)
	m.hud.visible = false
	var pl: Player = m.player
	var roof: Vector3 = CityStory.lookout["roof"] + Vector3(0, 0.1, 0)
	for k in 60:
		pl.global_position = roof
		await get_tree().physics_frame
	m.begin_lookout()
	var look := City.LANDER_POS + Vector3(0, 8, 0)
	var shots := [[3.0, "descent"], [6.5, "late"], [3.0, "down"]]
	var i := 0
	for s in shots:
		var frames := int(float(s[0]) * 120.0)
		for k in frames:
			pl.global_position = roof
			pl.velocity = Vector3.ZERO
			var d := look - (roof + Vector3(0, 1.6, 0))
			pl.yaw = atan2(-d.x, -d.z)
			pl.pitch = asin(d.y / d.length())
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/roof_%s.png" % [outdir, String(s[1])])
		print("shot ", s[1], " landed ", m.world.lander.landed, " hull y ", m.world.lander.hull.position.y, " guards ", m.park_fight.guards().size())
		i += 1
	# the far craft: look at the nearest one from the roof
	if not CityStory.far_landers.is_empty():
		var fl: Vector3 = CityStory.far_landers[0]["pos"]
		for k in 60:
			pl.global_position = roof
			var d2 := fl + Vector3(0, 3, 0) - (roof + Vector3(0, 1.6, 0))
			pl.yaw = atan2(-d2.x, -d2.z)
			pl.pitch = asin(d2.y / d2.length())
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/roof_far.png" % outdir)
	get_tree().quit()
