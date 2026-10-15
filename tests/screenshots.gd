extends Node
## Visual check under a virtual display:  xvfb-run godot --path . --rendering-driver opengl3 -- --shots <outdir>
var main
var outdir := "/tmp/shots"

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [outdir, name])
	print("saved ", name, " ", img.get_size())

func aim_at(player: Player, target: Vector3) -> void:
	var d := target - player.camera.global_position
	player.yaw = atan2(-d.x, -d.z)
	player.pitch = asin(d.y / d.length())

func run(m) -> void:
	main = m
	Game.force_input = true
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		outdir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(outdir)
	var pl: Player = m.player
	for k in 40:
		await get_tree().physics_frame
	await shot("01_start")
	# an enemy in the distance and one close by
	var e1: Enemy = Game.enemies[0]
	var e2: Enemy = Game.enemies[1]
	e1.position = Vector3(18, World.height_at(18, -45) + 0.1, -45)
	e2.position = Vector3(-4, World.height_at(-4, -9) + 0.1, -9)
	e1.stun = 999
	e2.stun = 999
	e2.rig.rotation.y = PI
	pl.yaw = 0.0
	pl.pitch = 0.0
	for k in 30:
		await get_tree().physics_frame
	aim_at(pl, e2.global_position + Vector3(0, 1.3, 0))
	for k in 5:
		await get_tree().physics_frame
	await shot("02_enemy_close")
	pl.yaw = deg_to_rad(8)
	pl.pitch = deg_to_rad(5)
	for k in 5:
		await get_tree().physics_frame
	await shot("03_pistol_hip")
	pl.weapons.switch_to("rifle")
	for k in 90:
		await get_tree().physics_frame
	await shot("04_rifle_hip")
	Input.action_press("aim")
	for k in 90:
		await get_tree().physics_frame
	await shot("05_rifle_ads")
	Input.action_release("aim")
	# muzzle flash + tracer
	pl.weapons.cooldown = 0.0
	pl.weapons._fire_shot()
	await shot("06_rifle_fire")
	# pistol aimed + flash held for the camera
	pl.weapons.switch_to("pistol")
	for k in 60:
		await get_tree().physics_frame
	Input.action_press("aim")
	for k in 90:
		await get_tree().physics_frame
	await shot("06b_pistol_ads")
	Input.action_release("aim")
	pl.weapons.ads_k = 0.0
	pl.weapons.cooldown = 0.0
	pl.weapons._fire_shot()
	pl.weapons.flash_t = 9.0
	await get_tree().process_frame
	await shot("06c_pistol_flash")
	pl.weapons.flash_t = 0.01
	# dead enemy
	e2.take_hit(500.0, "body", Vector3(0, 0, -6), e2.global_position + Vector3(0, 1.2, 0))
	for k in 140:
		await get_tree().physics_frame
	pl.weapons.ads_k = 0.0
	aim_at(pl, e2.global_position + Vector3(0, 0.6, 0))
	for k in 30:
		await get_tree().physics_frame
	await shot("07_dead_enemy")
	# overview from above
	pl.global_position = Vector3(0, 25, 40)
	pl.velocity = Vector3.ZERO
	pl.pitch = deg_to_rad(-25)
	pl.yaw = 0.0
	pl.set_physics_process(false)
	pl.head.rotation = Vector3(pl.pitch, 0, 0)
	await get_tree().process_frame
	await shot("08_overview")
	get_tree().quit()
