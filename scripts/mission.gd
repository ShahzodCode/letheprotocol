class_name Mission
extends RefCounted
## An ordered list of objectives. Main creates one (ChapterOne.build() for the story, Mission.sandbox() for `-- --sandbox`),
## calls `begin()` and then `update(player, delta)` every frame. Completing an objective starts the next one; finishing the
## last one wins the game.
##
## An objective is a Dictionary made with Mission.obj(): id, text (HUD), type (reach | kill_group | interact | script),
## pos (optional Vector3: distance + default marker spot), marker_pos (optional marker override), radius, vertical (max height
## difference for reach / interact, optional), group (kill_group), label (interact prompt), on_start / on_complete (Callables
## that receive the Mission).

const INTERACT_RANGE := 2.0
const CHIME_VOLUME := -4.0

static var current: Mission = null
static var silent := false          # Main fast-forwarding to a chapter-select place: no chime per objective

var id := "mission"
var win_title := "MISSION COMPLETE"
var objectives: Array = []
var respawn_enemies := false
var index := -1
var finished := false
var age := 0.0                     # seconds since the current objective started
var in_interact_range := false     # HUD: show "E - label"


static func obj(oid: String, text: String, opts: Dictionary = {}) -> Dictionary:
	var o := {"id": oid, "text": text, "type": "reach", "pos": null, "marker_pos": null, "radius": 7.0, "vertical": -1.0,
		"group": -1, "label": "", "on_start": Callable(), "on_complete": Callable()}
	for k in opts:
		o[k] = opts[k]
	return o


## What `-- --sandbox` starts: the old game. One goal, soldiers come back 25 s after they die.
static func sandbox() -> Mission:
	var m := Mission.new()
	m.id = "sandbox"
	m.win_title = "HOME REACHED"
	m.respawn_enemies = true
	m.objectives = [obj("get_home", "GET HOME", {"pos": City.HOME_POS, "marker_pos": City.HOME_POS, "radius": 3.0})]
	return m


static func story() -> Mission:
	return ChapterOne.build()


## Ask the running mission to finish objective `oid` (only has an effect while it is the active one).
static func complete(oid: String) -> void:
	if current != null:
		current.complete_id(oid)


func begin() -> void:
	current = self
	index = -1
	finished = false
	_start(0)


func active() -> Dictionary:
	if finished or index < 0 or index >= objectives.size():
		return {}
	return objectives[index]


func _start(i: int) -> void:
	index = i
	age = 0.0
	in_interact_range = false
	var o: Dictionary = objectives[i]
	var cb: Callable = o["on_start"]
	if cb.is_valid():
		cb.call(self)
	Game.objective_changed.emit(String(o["id"]))


func complete_id(oid: String) -> void:
	var o := active()
	if not o.is_empty() and String(o["id"]) == oid:
		_complete()


func _complete() -> void:
	var o := active()
	if o.is_empty():
		return
	var cb: Callable = o["on_complete"]
	if cb.is_valid():
		cb.call(self)
	Game.objective_completed.emit(String(o["id"]), String(o["text"]))
	if Game.player != null and not silent:
		Sfx.play(Game.player, "chime", CHIME_VOLUME)
	if index + 1 < objectives.size():
		_start(index + 1)
	else:
		finished = true
		in_interact_range = false
		Game.objective_changed.emit("")
		Game.won = true
		Game.goal_reached.emit()


## Where the world marker should hang (null = hidden).
func marker_pos() -> Variant:
	var o := active()
	if o.is_empty():
		return null
	return o["marker_pos"] if o["marker_pos"] != null else o["pos"]


func _near(player: Node3D, p: Vector3, radius: float, vertical: float) -> bool:
	var d := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
	if d > radius:
		return false
	return vertical < 0.0 or absf(player.global_position.y - p.y) <= vertical


func update(player: Player, delta: float) -> void:
	var o := active()
	if o.is_empty() or Game.dead:
		return
	age += delta
	in_interact_range = false
	match String(o["type"]):
		"reach":
			if o["pos"] != null and _near(player, o["pos"], float(o["radius"]), float(o["vertical"])) and player.is_on_floor():
				_complete()
		"kill_group":
			if age > 0.5 and not _group_alive(int(o["group"])):
				_complete()
		"interact":
			if o["pos"] != null and _near(player, o["pos"], INTERACT_RANGE, maxf(float(o["vertical"]), 2.0)):
				in_interact_range = true
				if Game.has_focus() and Input.is_action_just_pressed("interact"):
					_complete()


func _group_alive(g: int) -> bool:
	for e in Game.enemies:
		if is_instance_valid(e) and e.group == g and e.state != Enemy.State.DEAD:
			return true
	return false


## "GET HOME - 240 m", or only the text when the objective has no position.
func hud_text(player: Node3D) -> String:
	var o := active()
	if o.is_empty():
		return ""
	if o["pos"] == null:
		return String(o["text"])
	var p: Vector3 = o["pos"]
	var d := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
	return "%s  -  %d m" % [o["text"], int(d)]


func interact_prompt() -> String:
	var o := active()
	if in_interact_range and not o.is_empty():
		return Settings.key_name("interact") + " - " + String(o["label"])
	return ""
