class_name HoldInput
## Aim, crouch and sprint as hold-the-key or press-to-toggle (Settings.toggle_*). The player feeds every input event in (`feed`);
## code that used Input.is_action_pressed for these three asks `held()` instead. A toggle is let go by the player's code when it no
## longer makes sense (sprint when he stops running forward, aim when he starts sprinting, all of them on death).

const ACTIONS := ["aim", "crouch", "sprint"]

static var _on := {}


static func is_toggle(action: String) -> bool:
	match action:
		"aim": return Settings.toggle_aim
		"crouch": return Settings.toggle_crouch
		"sprint": return Settings.toggle_sprint
	return false


static func held(action: String) -> bool:
	if is_toggle(action):
		return bool(_on.get(action, false))
	return Input.is_action_pressed(action)


static func feed(event: InputEvent) -> void:
	if event.is_echo():
		return
	for a in ACTIONS:
		if is_toggle(a) and event.is_action_pressed(a):
			_on[a] = not bool(_on.get(a, false))


static func release(action: String) -> void:
	_on[action] = false


static func clear() -> void:
	_on.clear()
