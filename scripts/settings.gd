class_name Settings
## Graphics / window settings the pause menu changes. Saved in user://settings.cfg, applied at start and on every change.
## Quality levels: shadows 0 off / 1 near and cheap / 2 full; anti-aliasing 0 off / 1 MSAA 2x / 2 MSAA 4x; render scale 50..100 %;
## view distance 0 short / 1 medium / 2 long (fog end and camera far).

const PATH := "user://settings.cfg"
const VIEW_FOG := [220.0, 430.0, 650.0]
const VIEW_FAR := [260.0, 520.0, 750.0]

static var fullscreen := true
static var vsync := true
static var shadows := 2
static var aa := 0
static var scale_pct := 100
static var view := 1
static var sens := 1.0              # multiplier of Game.MOUSE_SENS
static var gpu_warned := ""         # adapter name the "not on the NVIDIA GPU" pause-menu warning was already shown for
static var loaded := false


static func load_settings() -> void:
	if loaded:
		return
	loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	fullscreen = bool(cf.get_value("g", "fullscreen", fullscreen))
	vsync = bool(cf.get_value("g", "vsync", vsync))
	shadows = int(cf.get_value("g", "shadows", shadows))
	aa = int(cf.get_value("g", "aa", aa))
	scale_pct = int(cf.get_value("g", "scale", scale_pct))
	view = int(cf.get_value("g", "view", view))
	sens = float(cf.get_value("g", "sens", sens))
	gpu_warned = String(cf.get_value("g", "gpu_warned", gpu_warned))


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("g", "fullscreen", fullscreen)
	cf.set_value("g", "vsync", vsync)
	cf.set_value("g", "shadows", shadows)
	cf.set_value("g", "aa", aa)
	cf.set_value("g", "scale", scale_pct)
	cf.set_value("g", "view", view)
	cf.set_value("g", "sens", sens)
	cf.set_value("g", "gpu_warned", gpu_warned)
	cf.save(PATH)


## A preset: 0 low, 1 medium, 2 high.
static func preset(level: int) -> void:
	shadows = [0, 1, 2][level]
	aa = [0, 0, 1][level]
	scale_pct = [75, 100, 100][level]
	view = [0, 1, 2][level]


static func apply(tree: SceneTree, scene: Node = null) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp := tree.root
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa]
	vp.scaling_3d_scale = clampf(float(scale_pct) / 100.0, 0.5, 1.0)
	if scene == null:
		scene = tree.current_scene
	if scene != null and scene.get("world") != null:
		var w = scene.world
		if w != null and w.sun != null:
			w.sun.shadow_enabled = shadows > 0
			w.sun.directional_shadow_max_distance = 70.0 if shadows == 1 else 110.0
			w.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if shadows == 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		if w != null and w.env_ref != null:
			w.env_ref.fog_depth_end = VIEW_FOG[view]
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and pl.camera != null:
		pl.camera.far = VIEW_FAR[view]
