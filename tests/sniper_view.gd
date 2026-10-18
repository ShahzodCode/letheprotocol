extends Node
## The LR-9 on the balcony: viewmodel at the hip, then scoped (HUD on), with the guards at the ramp: `-- --script res://tests/sniper_view.gd out=<dir>`
func run(m) -> void:
	Game.force_input = true
	var outdir := "res://.shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			outdir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(outdir)
	var pl: Player = m.player
	var w := pl.weapons
	m.world.lander.land_now()
	m.park_fight.spawn_guards()
	for e in Game.enemies:
		if (e as Enemy).group != ParkFight.GUARD_GROUP:
			e.stun = 999.0
			e.global_position = Vector3(260.0, 0.1, 0.0)
		else:
			e.stun = 999.0
	w.loadout["rifle"].append(Weapons.new_weapon("sniper"))
	w.switch_to("sniper")
	for k in 60:
		await get_tree().physics_frame
	var from := Vector3(75.5, City.BALCONY_Y + 0.1, -30.4)
	var target := Vector3(66.5, 1.4, -53.0)
	for step in 3:
		for k in 80:
			pl.global_position = from
			pl.velocity = Vector3.ZERO
			pl.health = 100.0
			var d := target - (from + Vector3(0, 1.6, 0))
			pl.yaw = atan2(-d.x, -d.z)
			pl.pitch = asin(d.y / d.length())
			if step >= 1:
				Input.action_press("aim")
			if step == 2:
				Input.action_press("sprint")
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/sniper%d.png" % [outdir, step])
		print("step ", step, " scoped ", w.is_scoped(), " breath ", w.breath, " held ", w.breath_held, " sway ", w.sway_view)
	Input.action_release("aim")
	Input.action_release("sprint")
	get_tree().quit()
