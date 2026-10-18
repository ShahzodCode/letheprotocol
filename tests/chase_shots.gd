extends Node
## Screenshots of Noah's neighbourhood and the wound: the west lane, the drainpipe, the roof edge over the courtyard with the circle, the wounded
## left-handed view.   -- --script res://tests/chase_shots.gd out=<dir>
func run(m) -> void:
	Game.force_input = true
	var outdir := "res://.shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			outdir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(outdir)
	var pl: Player = m.player
	var w := pl.weapons
	for e in Game.enemies.duplicate():
		e.stun = 999.0
		e.global_position = Vector3(260.0, 0.1, 0.0)
	m.chase.phase = ChaseFight.Phase.CHASE
	m.chase.gather()                    # four soldiers appear in the ring of the courtyard
	for e in m.chase.court():
		e.stun = 0.0
		e.global_position = e.hold_spot + Vector3(0, 0.1, 0)
		e.hold_walk_max = 0.0
	for k in 90:
		await get_tree().physics_frame
	var shots := [
		["lane", Vector3(71.5, 0.1, 14.0), PI, -0.05, false],
		["pipe", Vector3(70.6, 0.1, 20.0), -PI * 0.5, 0.35, false],
		["gate", Vector3(70.5, 0.1, 36.0), -PI * 0.5, 0.0, false],
		["roof", Vector3(84.0, 4.7, 28.4), PI, -0.65, false],
		["roof_far", Vector3(84.0, 4.7, 25.0), PI, -0.45, false],
		["wounded", Vector3(84.0, 4.7, 24.0), PI, -0.3, true],
	]
	for s in shots:
		if bool(s[4]):
			Game.arm_injured = true
			w.wound_arm()
			Game.grenades = 2
			for i in 6:
				pl.place_drip(Vector3(84.0, 4.6, 24.0 - float(i) * 0.8))
		for k in 70:
			pl.global_position = s[1]
			pl.velocity = Vector3.ZERO
			pl.health = 100.0
			pl.yaw = s[2]
			pl.pitch = s[3]
			for e in m.chase.court():
				e.stun = 0.0
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, s[0]])
		print("shot ", s[0])
	get_tree().quit()
