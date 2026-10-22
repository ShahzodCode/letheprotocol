extends Node
## Character viewer: `godot --path . --rendering-driver opengl3 -- --script res://tests/char_view.gd kind:mode ... out=<png>`
## modes: idle walk run aim reload melee dead (enemies)  |  civ-idle civ-run civ-walk civ-dead civ-hit (civilians, kind = outfit seed)
var main
var far := 1.0         # far=1.4: the camera stands farther back (tall kinds); look=1.1: it looks at that height
var look_y := 0.9
const CAM_SPOTS := [Vector3(2.0, 1.4, -3.2), Vector3(3.6, 1.4, 0.8)]

func run(m) -> void:
	main = m
	Game.force_input = true
	var out_path := "res://shots_char.png"
	var specs := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_path = a.substr(4)
		elif a.begins_with("far="):
			far = float(a.substr(4))
		elif a.begins_with("look=") :
			look_y = float(a.substr(5))
		elif ":" in a and not a.begins_with("out") and not a.begins_with("res:"):
			specs.append(a)
	main.hud.visible = false
	for en0 in Game.enemies.duplicate():
		en0.stun = 999.0
		en0.global_position = Vector3(260.0, 0.1, 0.0)
	for c0 in Game.civilians.duplicate():
		c0.global_position = Vector3(260.0, 0.1, 30.0)
	var pl: Player = main.player
	pl.global_position = Vector3(0.0, 0.1, 40.0)
	pl.visible = false
	for k in 20:
		await get_tree().physics_frame
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	var origin := Vector3(0.0, 0.0, 0.0)
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	var cols := mini(6, specs.size() * 2)
	var cw := 1920 / cols
	var ch := 720 / ((specs.size() * 2 + cols - 1) / cols)
	ch = mini(ch, cw * 9 / 8)
	var k := 0
	for sp in specs:
		var p: PackedStringArray = sp.split(":")
		var node: Node3D
		var speed := 0.0
		var mode := p[1]
		if mode.begins_with("civ-"):
			var cv := Civilian.spawn(main, pl, origin, int(p[0]))
			cv.set_physics_process(false)
			node = cv
			await get_tree().physics_frame
			match mode:
				"civ-run": speed = 5.5
				"civ-walk": speed = 1.5
				"civ-dead": cv.die(true, Vector3(0, 0, -3.0))
				"civ-blast": cv.die(true, Vector3(0, 0, -14.0))
				"civ-hit": cv.take_hit(1.0, "body", Vector3(0, 0, -3.0), origin)
			for i in (110 if mode in ["civ-blast", "civ-dead"] else 40):
				if mode == "civ-blast" and i % 20 == 0:
					print("blast t=", i, " state ", cv.state, " spin ", cv.spin.rotation, " anim ", cv.model.current, " pos ", cv.model.player.current_animation_position if cv.model.player else -1)
				if mode in ["civ-run", "civ-walk", "civ-idle", "civ-hit"]:
					cv._animate(0.03, speed)
				await get_tree().physics_frame
		else:
			var en: Enemy = main._spawn_enemy_at(origin, p[0])
			en.set_physics_process(false)
			node = en
			print("spawned ", en.kind, " model ", en.model.model_id, " weapon ", en.weapon_id)
			await get_tree().physics_frame
			match mode:
				"run": speed = 5.0; en.state = Enemy.State.CHASE
				"walk": speed = 1.3
				"aim": en.state = Enemy.State.SHOOT
				"reload": en.reloading = true; en.reload_left = 1.5
				"melee": en.state = Enemy.State.ATTACK; en.attack_t = 0.2
				"dead": en._die(Vector3(0, 0, -3.0))
			if mode == "melee":
				en.state = Enemy.State.ATTACK
			for i in (60 if mode == "dead" else 40):
				if mode != "dead":
					en._animate(0.03, speed)
				await get_tree().physics_frame
		if node is Enemy and (node as Enemy).model.model_id == "soldier":
			var cmod := (node as Enemy).model
			var sk := cmod.skeleton
			for side in ["R", "L"]:
				var h := sk.get_bone_global_pose(cmod.bone("hand." + side)).origin
				var a := sk.get_bone_global_pose(cmod.bone("arm." + side)).origin
				var fo := sk.get_bone_global_pose(cmod.bone("forearm." + side)).origin
				print(side, " arm ", a, " elbow ", fo, " hand ", h, " gun in skel ", sk.to_local((node as Enemy).gun.global_position), " unit ", cmod.unit())
		for v in CAM_SPOTS:
			cam.global_position = origin + Vector3(v.x * far, 1.4 + (look_y - 0.9) * 0.5, v.z * far)
			cam.look_at(origin + Vector3(0, look_y, 0))
			await RenderingServer.frame_post_draw
			var im: Image = get_viewport().get_texture().get_image()
			im.convert(Image.FORMAT_RGBA8)
			im.resize(cw, ch)
			sheet.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i((k % cols) * cw, (k / cols) * ch))
			k += 1
		Game.enemies.erase(node)
		node.queue_free()
		await get_tree().physics_frame
	sheet.save_png(out_path)
	print("saved ", out_path)
	get_tree().quit()
