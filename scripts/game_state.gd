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
const FALL_DAMAGE_PER_MS := 5.0
const MOUSE_SENS := 0.0022
const BASE_FOV := 75.0
const MAX_HEALTH := 100.0

# ---------- world ----------
const WORLD_SIZE := 600.0         # terrain is a square of this many metres, centred on the origin
const WORLD_CELL := 4.0

# ---------- physics layers (bit values) ----------
const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_HITBOX := 8

# ---------- shared state ----------
var player: Node3D = null
var enemies: Array = []
var kills := 0
var shots_fired := 0
var shots_hit := 0
var dead := false
var paused := false
var force_input := false   # tests: headless has no real mouse capture

signal player_died
signal enemy_killed(enemy)
signal gunshot(position: Vector3, loudness: float)


func _ready() -> void:
	_register_inputs()


## True while the game should react to mouse/keyboard play input (mouse captured, not paused).
func has_focus() -> bool:
	return force_input or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func reset_stats() -> void:
	kills = 0
	shots_fired = 0
	shots_hit = 0
	dead = false
	paused = false
	enemies.clear()


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
	_key("cycle_weapon", KEY_Q)
	_key("restart", KEY_R)
	_key("pause", KEY_ESCAPE)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)
	_mouse("wheel_up", MOUSE_BUTTON_WHEEL_UP)
	_mouse("wheel_down", MOUSE_BUTTON_WHEEL_DOWN)
