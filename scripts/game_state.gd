extends Node
## Autoload "Game": tunables, shared state and the input map (registered in code so project.godot stays small).

# ---------- player tunables ----------
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const PLAYER_RADIUS := 0.4
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.4
const GROUND_ACCEL := 14.0
const AIR_ACCEL := 3.0
const JUMP_SPEED := 7.0
const GRAVITY := 24.0
const FALL_GRAVITY_MULT := 1.25   # heavier falling
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const STEP_HEIGHT := 0.55
const FALL_DAMAGE_SPEED := 15.0   # impact speed above which a landing hurts
const FALL_DAMAGE_PER_MS := 5.5   # per m/s above the threshold: 2 storeys (6.8 m) ~29, 4 storeys ~74, 6 storeys ~110 (deadly)
const FALL_DAMAGE_MAX := 220.0
const CLIMB_SPEED := 2.5          # ladders, m/s
const MOUSE_SENS := 0.0022
const BASE_FOV := 75.0
const MAX_HEALTH := 100.0
const MAX_GRENADES := 4

# ---------- world ----------
const WORLD_SIZE := 600.0         # terrain is a square of this many metres, centred on the origin
const WORLD_CELL := 4.0

# ---------- physics layers (bit values) ----------
const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_HITBOX := 8
const L_CIVILIAN := 16
const L_KERB := 32            # raised pavement edges: only the player collides with them (stepped over automatically)

# ---------- shared state ----------
var player: Node3D = null
var enemies: Array = []
var pickups: Array = []     # Pickup nodes lying on the ground
var kills := 0
var shots_fired := 0
var shots_hit := 0
var civilians: Array = []      # living Civilian nodes
var civilians_lost := 0    # civilians who died (shot by soldiers, by the player, blown up)
var takedowns := 0         # silent knife kills from behind
var grenades := 0          # frag grenades carried (the story starts with none)
var arm_injured := false   # "The Lander" part two: the right arm is wounded for the rest of the chapter (no rifle, no knife, pistol in the left hand)
var dead := false
var won := false           # reached the goal house
var paused := false
var force_input := false   # tests: headless has no real mouse capture
var frozen := false        # the Commander scene: the player's keys and mouse do nothing (has_focus() is false)
var invulnerable := false  # the Commander scene: nothing can hurt the player
var invisible := false     # cheat (pause menu): no soldier sees or hears the player
var sandbox := false       # `-- --sandbox`: the sandbox mission (enemies respawn)
var mission: Mission = null
var has_checkpoint := false   # Main has saved a checkpoint (the death screen offers R = restart from it)

signal player_died
signal goal_reached
signal objective_changed(id)
signal objective_completed(id, text)
signal checkpoint_requested        # death screen: R
signal enemy_killed(enemy)
signal gunshot(position: Vector3, loudness: float)
signal grenade_landed(position: Vector3)      # a thrown grenade touched the ground (squads watch this)
signal exploded(position: Vector3)
signal radio_line(text: String)           # soldiers talking to each other (HUD subtitle)
signal enemy_fired(enemy)                 # a soldier fired a bolt (ChaseFight watches the courtyard soldiers' shots)
signal arm_wounded                        # the story wound happened


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # the hitch detector also times the pause menu
	_register_inputs()
	_probe_gpu()
	_start_us = Time.get_ticks_usec()


# ---------- diagnostics: video adapter + hitch detector ----------
const HITCH_MS := 25.0            # a frame longer than this is logged with the tags that were marked during it
const HITCH_KEEP := 300           # newest hitches kept in memory
const HITCH_LOG := "user://hitches.log"
const WARMUP_S := 3.0             # hitches before this many seconds are tagged "warmup" (first-view shader compiles)
const NVIDIA_WORDS := ["nvidia", "geforce", "rtx", "gtx"]
const ADAPTER_TYPES := ["other", "integrated", "discrete", "virtual", "cpu"]   # RenderingDevice.DeviceType order

var gpu := {}                     # name, vendor, type, driver, method, os, godot (filled by _probe_gpu)
var gpu_is_nvidia := true         # false = the game is NOT drawing on the NVIDIA card (see README "Which GPU")
var hitches: Array = []           # {t, ms, tags, pos}
var hitch_total := 0              # all hitches ever (hitches itself keeps only the newest HITCH_KEEP)
var hitch_stats := {}             # tag -> {count, max, total}
var _tags: Array = []
var _tag_count := {}
var _last_us := 0
var _start_us := 0


func _probe_gpu() -> void:
	var tname := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var t := int(RenderingServer.get_video_adapter_type())
	gpu = {
		"name": tname, "vendor": vendor,
		"type": ADAPTER_TYPES[t] if t >= 0 and t < ADAPTER_TYPES.size() else str(t),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"method": RenderingServer.get_current_rendering_method(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"godot": Engine.get_version_info()["string"],
	}
	var hay := (tname + " " + vendor).to_lower()
	gpu_is_nvidia = DisplayServer.get_name() == "headless"      # headless has no adapter: never warn
	for w in NVIDIA_WORDS:
		if w in hay:
			gpu_is_nvidia = true
	print("[gpu] %s | vendor %s | type %s | driver %s (%s) | %s | Godot %s" % [tname, vendor, gpu["type"], gpu["driver"], gpu["method"], gpu["os"], gpu["godot"]])
	if not gpu_is_nvidia:
		push_warning("Not running on the NVIDIA GPU (%s). See README 'Which GPU is the game using?'" % tname)


## Tag the frame being worked on (call it where a first-use or burst cost could land: first shot, explosion, spawns...).
## Cheap: a dictionary bump and a short array. The hitch detector prints the tags of any frame over HITCH_MS.
func mark(tag: String) -> void:
	var n: int = _tag_count.get(tag, 0) + 1
	_tag_count[tag] = n
	if n == 1:
		tag += "(first)"
	if _tags.size() < 10 and not _tags.has(tag):
		_tags.append(tag)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us != 0:
		var ms := float(now - _last_us) / 1000.0
		if ms > HITCH_MS:
			_log_hitch(ms, now)
	_last_us = now
	_tags.clear()


func _log_hitch(ms: float, now: int, write: bool = true) -> void:
	var t := float(now - _start_us) / 1000000.0
	var tags: Array = _tags.duplicate()
	if t < WARMUP_S:
		tags.append("warmup")
	if tags.is_empty():
		tags.append("untagged")
	var pl := player as Node3D
	var pos := pl.global_position if pl != null and is_instance_valid(pl) and pl.is_inside_tree() else Vector3.ZERO
	hitch_total += 1
	hitches.append({"t": t, "ms": ms, "tags": tags, "pos": pos})
	if hitches.size() > HITCH_KEEP:
		hitches.pop_front()
	for tg in tags:
		var base := String(tg).replace("(first)", "")
		var st: Dictionary = hitch_stats.get(base, {"count": 0, "max": 0.0, "total": 0.0, "first": 0.0})
		st["count"] += 1
		st["max"] = maxf(st["max"], ms)
		st["total"] += ms
		if "(first)" in String(tg):
			st["first"] = ms
		hitch_stats[base] = st
	var line := "[hitch] t=%.1fs %.1f ms  %s  at (%.0f, %.0f, %.0f)" % [t, ms, ", ".join(tags), pos.x, pos.y, pos.z]
	if not write:
		return
	print(line)
	var f := FileAccess.open(HITCH_LOG, FileAccess.READ_WRITE if FileAccess.file_exists(HITCH_LOG) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)


## True while the game should react to mouse/keyboard play input (mouse captured, not paused).
func has_focus() -> bool:
	return not frozen and (force_input or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)


func reset_stats() -> void:
	kills = 0
	shots_fired = 0
	shots_hit = 0
	takedowns = 0
	civilians_lost = 0
	grenades = 0
	arm_injured = false
	frozen = false
	invulnerable = false
	invisible = false
	dead = false
	won = false
	paused = false
	mission = null
	has_checkpoint = false
	enemies.clear()
	civilians.clear()
	pickups.clear()


func _key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _register_inputs() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("crouch", KEY_CTRL)
	_key("reload", KEY_R)
	_key("slot_1", KEY_1)
	_key("slot_2", KEY_2)
	_key("slot_3", KEY_3)
	_key("pickup", KEY_Q)
	_key("interact", KEY_E)
	_key("grenade", KEY_G)
	_key("cycle_weapon", KEY_TAB)
	_key("restart", KEY_R)
	_key("pause", KEY_ESCAPE)
	_key("debug_overlay", KEY_F3)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)
	_mouse("wheel_up", MOUSE_BUTTON_WHEEL_UP)
	_mouse("wheel_down", MOUSE_BUTTON_WHEEL_DOWN)
