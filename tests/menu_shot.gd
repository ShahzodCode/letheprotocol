extends Node
## Screenshot of the pause menu: `-- --script res://tests/menu_shot.gd out=<png>`
func run(m) -> void:
	Game.force_input = true
	var out := "res://.shots/menu.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	for k in 40:
		await get_tree().physics_frame
	m.hud._set_paused(true)
	for k in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("size ", get_viewport().get_visible_rect().size)
	get_tree().quit()
