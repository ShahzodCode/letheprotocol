extends Node
## Gallery of our own gun models: -- --script res://tests/gun_gallery.gd out=<png>
func run(m) -> void:
	m.hud.visible = false
	for en0 in Game.enemies.duplicate():
		en0.stun = 999.0
		en0.global_position = Vector3(260.0, 0.1, 0.0)
	m.player.global_position = Vector3(0.0, 0.1, 40.0)
	for k in 20:
		await get_tree().physics_frame
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.current = true
	var ids := ["rifle", "carbine", "railgun", "hmg"]
	for a in OS.get_cmdline_user_args():          # ids=sniper,rifle shows other guns
		if a.begins_with("ids="):
			ids = a.substr(4).split(",")
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	var k := 0
	for id in ids:
		var g := GunModels.build(id, 2)
		g.position = Vector3(0, 1.5, 0)
		add_child(g)
		for view in 2:
			g.rotation.y = deg_to_rad(90.0) if view == 0 else deg_to_rad(40.0)
			cam.global_position = Vector3(0, 1.55, 1.7)
			cam.look_at(Vector3(0, 1.45, 0))
			await RenderingServer.frame_post_draw
			var im: Image = get_viewport().get_texture().get_image(); im.convert(Image.FORMAT_RGBA8); im.resize(480, 360)
			sheet.blit_rect(im, Rect2i(0, 0, 480, 360), Vector2i((k % 4) * 480, (k / 4) * 360))
			k += 1
		g.queue_free()
	var out := "res://shots_guns.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	sheet.save_png(out)
	get_tree().quit()
