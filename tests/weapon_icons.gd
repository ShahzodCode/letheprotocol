extends Node
## Renders the HUD weapon pictures from our own models, side-on with the muzzle to the right, on a transparent background:
## -- --script res://tests/weapon_icons.gd [ids=rifle,knife]     (windowed, opengl3). Writes res://ui/weapons/<id>.png.

const SIZE := Vector2i(512, 192)
const SUPER := 3                # rendered this many times larger, then scaled down for clean edges
const MARGIN := 1.08
const PALE_LOW := 0.5           # the darkest parts of a gun come out this bright


func run(_m) -> void:
	var ids: Array = WeaponsDB.ORDER.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ids="):
			ids = Array(a.substr(4).split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/weapons"))
	var vp := SubViewport.new()
	vp.size = SIZE * SUPER
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0, 0, 0, 0)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color.WHITE
	we.environment.ambient_light_energy = 0.75
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-50, 70, 0)
	vp.add_child(key)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.current = true
	for id in ids:
		var g := GunModels.build(id, 2)
		vp.add_child(g)
		var box: AABB = g.get_aabb()
		var mid := box.get_center()
		cam.size = maxf(box.size.y, box.size.z * float(SIZE.y) / float(SIZE.x)) * MARGIN
		cam.global_position = mid + Vector3(3, 0, 0)
		cam.look_at(mid)
		for i in 3:
			await RenderingServer.frame_post_draw
		var im: Image = vp.get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		im.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		_pale(im)
		im.save_png("res://ui/weapons/%s.png" % id)
		print("icon ", id, " ", box.size)
		vp.remove_child(g)
		g.queue_free()
	get_tree().quit()


## Our guns are dark and the HUD is dark: lifts the greys into a pale range (keeping the shading) and leaves the glowing colours in.
func _pale(im: Image) -> void:
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var grey := remap(clampf(c.get_luminance(), 0.05, 0.7), 0.05, 0.7, PALE_LOW, 1.0)
			var pale := Color(grey * 0.96, grey * 0.98, grey, c.a)
			var keep := clampf((c.s * c.v) * 2.5, 0.0, 1.0)
			var lit := c.lightened(0.3)
			lit.a = c.a
			im.set_pixel(x, y, pale.lerp(lit, keep))
