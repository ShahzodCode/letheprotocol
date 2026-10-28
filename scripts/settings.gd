class_name Settings
## Graphics / window settings the pause menu changes. Saved in user://settings.cfg, applied at start and on every change.
## Quality levels: shadows 0 off / 1 near and cheap / 2 full; anti-aliasing 0 off / 1 MSAA 2x / 2 MSAA 4x; render scale 50..100 %;
## view distance 0 short / 1 medium / 2 long (fog end and camera far).

const PATH := "user://settings.cfg"
const VIEW_FOG := [220.0, 430.0, 650.0]
const VIEW_FAR := [260.0, 520.0, 750.0]
const SHADOW_RANGE := [70.0, 25.0, 110.0]          # metres the sun's shadows reach: off / low (only just around the player) / high
const SHADOW_ATLAS := [2048, 1024, 6144]           # map size per level, about 56 texels a metre at high (it was 8192 for 150 m)

static var fullscreen := true
static var vsync := true
static var shadows := 2
static var aa := 0
static var scale_pct := 100
static var view := 1
static var sens := 1.0              # multiplier of Game.MOUSE_SENS
static var gpu_warned := ""         # adapter name the "not on the NVIDIA GPU" pause-menu warning was already shown for
static var subtitles := true
static var sub_size := 1            # 0 small / 1 medium / 2 large
static var sub_box := 70            # opacity of the box behind the subtitles, %
static var sub_names := true        # the speaker's name before the line
static var compass := true
static var fov := 75.0              # horizontal-ish camera FOV in degrees when not aiming (the old Game.BASE_FOV)
static var invert_y := false
static var toggle_aim := false      # false = hold the key, true = press once to start, again to stop
static var toggle_crouch := false
static var toggle_sprint := false
static var vol_master := 100        # %
static var vol_voice := 100         # % of the voiced lines (their own bus, under the master)
static var colorblind := false      # warning red / healing green / the laser become magenta / blue (safe for red-green colour blindness)
static var keys := {}               # action -> "k<physical keycode>" / "m<mouse button>": only the ones the player changed
static var loaded := false

## The actions the CONTROLS tab can rebind, in the order it lists them: [action, label]. Pause (Esc), F3 and the death screen's R stay fixed.
const BINDABLE := [
	["move_forward", "Forward"], ["move_back", "Back"], ["move_left", "Left"], ["move_right", "Right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["crouch", "Crouch / slide"],
	["fire", "Fire"], ["aim", "Aim"], ["reload", "Reload"], ["grenade", "Grenade (hold)"],
	["slot_1", "Pistol slot"], ["slot_2", "Rifle slot"], ["slot_3", "Melee slot"], ["cycle_weapon", "Next weapon"],
	["pickup", "Pick up"], ["interact", "Interact / takedown"], ["map", "Map and objectives"],
]
static var defaults := {}           # action -> code, taken from the input map before any saved binding is applied


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
	subtitles = bool(cf.get_value("sub", "on", subtitles))
	sub_size = int(cf.get_value("sub", "size", sub_size))
	sub_box = int(cf.get_value("sub", "box", sub_box))
	sub_names = bool(cf.get_value("sub", "names", sub_names))
	compass = bool(cf.get_value("g", "compass", compass))
	fov = float(cf.get_value("g", "fov", fov))
	invert_y = bool(cf.get_value("g", "invert_y", invert_y))
	toggle_aim = bool(cf.get_value("g", "toggle_aim", toggle_aim))
	toggle_crouch = bool(cf.get_value("g", "toggle_crouch", toggle_crouch))
	toggle_sprint = bool(cf.get_value("g", "toggle_sprint", toggle_sprint))
	vol_master = int(cf.get_value("g", "vol_master", vol_master))
	vol_voice = int(cf.get_value("g", "vol_voice", vol_voice))
	colorblind = bool(cf.get_value("g", "colorblind", colorblind))
	if cf.has_section("keys"):
		for a in cf.get_section_keys("keys"):
			keys[a] = String(cf.get_value("keys", a))


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
	cf.set_value("sub", "on", subtitles)
	cf.set_value("sub", "size", sub_size)
	cf.set_value("sub", "box", sub_box)
	cf.set_value("sub", "names", sub_names)
	cf.set_value("g", "compass", compass)
	cf.set_value("g", "fov", fov)
	cf.set_value("g", "invert_y", invert_y)
	cf.set_value("g", "toggle_aim", toggle_aim)
	cf.set_value("g", "toggle_crouch", toggle_crouch)
	cf.set_value("g", "toggle_sprint", toggle_sprint)
	cf.set_value("g", "vol_master", vol_master)
	cf.set_value("g", "vol_voice", vol_voice)
	cf.set_value("g", "colorblind", colorblind)
	for a in keys:
		cf.set_value("keys", a, keys[a])
	cf.save(PATH)


# ---------------------------------------------------------------- key bindings

## The first key / mouse event of an action as a short code ("k87" = W, "m1" = left button), "" when it has none.
static func code_of(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return "k%d" % int((ev as InputEventKey).physical_keycode)
		if ev is InputEventMouseButton:
			return "m%d" % int((ev as InputEventMouseButton).button_index)
	return ""


static func _event(code: String) -> InputEvent:
	if code.begins_with("k"):
		var k := InputEventKey.new()
		k.physical_keycode = int(code.substr(1)) as Key
		return k
	if code.begins_with("m"):
		var m := InputEventMouseButton.new()
		m.button_index = int(code.substr(1)) as MouseButton
		return m
	return null


## A code as the player reads it: "W", "SPACE", "LMB".
static func code_name(code: String) -> String:
	if code.begins_with("k"):
		return OS.get_keycode_string(int(code.substr(1)) as Key).to_upper()
	if code.begins_with("m"):
		match int(code.substr(1)):
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_WHEEL_UP: return "WHEEL UP"
			MOUSE_BUTTON_WHEEL_DOWN: return "WHEEL DOWN"
			_: return "MOUSE %s" % code.substr(1)
	return "-"


## The key the player presses for an action, for prompts ("E - TAKEDOWN").
static func key_name(action: String) -> String:
	return code_name(code_of(action))


static func _set_code(action: String, code: String) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			InputMap.action_erase_event(action, ev)
	var ev2 := _event(code)
	if ev2 != null:
		InputMap.action_add_event(action, ev2)


## Called once by Game after the default input map exists: remember the defaults, then put the saved bindings on top.
static func apply_keys() -> void:
	load_settings()
	if defaults.is_empty():
		for b in BINDABLE:
			defaults[b[0]] = code_of(b[0])
	for a in keys:
		if InputMap.has_action(a) and defaults.has(a):
			_set_code(a, String(keys[a]))


## Give `action` the key `code`. Another action that had it gets this one's old key (a swap), so nothing is left unbound.
static func bind(action: String, code: String) -> void:
	var old := code_of(action)
	for b in BINDABLE:
		var other: String = b[0]
		if other != action and code_of(other) == code:
			_set_code(other, old)
			keys[other] = old
	_set_code(action, code)
	keys[action] = code
	save()


static func reset_keys() -> void:
	for a in defaults:
		_set_code(a, String(defaults[a]))
	keys.clear()
	save()


## A preset: 0 low, 1 medium, 2 high.
static func preset(level: int) -> void:
	shadows = [0, 1, 2][level]
	aa = [0, 0, 1][level]
	scale_pct = [75, 100, 100][level]
	view = [0, 1, 2][level]


## Warning colour (low health, low ammo, an alerted eye, a kill marker): red, or magenta in colour-blind mode.
static func danger(a: float = 1.0) -> Color:
	var c := Color(1.0, 0.3, 0.9) if colorblind else Color(0.9, 0.25, 0.22)
	c.a = a
	return c


## Healing colour: green, or blue in colour-blind mode.
static func good(a: float = 1.0) -> Color:
	var c := Color(0.35, 0.65, 1.0) if colorblind else Color(0.45, 0.95, 0.5)
	c.a = a
	return c


## The marksman's laser: red, or a bright magenta-white in colour-blind mode (it is also drawn thicker there).
static func laser_color() -> Color:
	return Color(1.0, 0.45, 1.0) if colorblind else Color(1.0, 0.15, 0.12)


## The voiced lines play on their own bus "Voice" (made here the first time), under Master.
static func apply_audio() -> void:
	if AudioServer.get_bus_index("Voice") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Voice")
		AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol_master / 100.0, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(maxf(vol_voice / 100.0, 0.0001)))


static func apply(tree: SceneTree, scene: Node = null) -> void:
	apply_audio()
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[clampi(shadows, 0, 2)], true)          # sized to the shadow range so the sharpness is the same (about 56 texels a metre) but the map costs less to fill
	var vp := tree.root
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa]
	vp.scaling_3d_scale = clampf(float(scale_pct) / 100.0, 0.5, 1.0)
	if scene == null:
		scene = tree.current_scene
	if scene != null and scene.get("world") != null:
		var w = scene.world
		if w != null and w.sun != null:
			w.sun.shadow_enabled = shadows > 0
			w.sun.directional_shadow_max_distance = SHADOW_RANGE[clampi(shadows, 0, 2)]
			w.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL          # one map at one resolution everywhere: the detail no longer changes with where the camera points
			w.sun.directional_shadow_blend_splits = true          # no visible seam where the near map hands over to the far one
			w.sun.directional_shadow_pancake_size = 400.0          # tall buildings far towards the sun still cast: a short pancake size culled them, more of them the narrower the view (scoped in)
			w.sun.directional_shadow_split_1 = 0.35
			w.sun.directional_shadow_fade_start = 0.85          # shadows fade out softly at the far end instead of ending in a moving edge
		if w != null and w.env_ref != null:
			w.env_ref.fog_depth_end = VIEW_FOG[view]
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and pl.camera != null:
		pl.camera.far = VIEW_FAR[view]
	HoldInput.clear()          # a hold / toggle mode changed: nothing stays latched from the old mode
