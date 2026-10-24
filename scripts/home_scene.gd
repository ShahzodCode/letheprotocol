class_name HomeScene
extends Node
## Chapter One "VI. The Basement", "VII. Five More" and "VIII. The Locked Door": Noah finds the flat empty, hears knocking under the floor,
## finds his mother and Mira in the cellar, four soldiers break in (he stops three, the fourth slips down to the cellar and shoots the mother),
## five more come, and at the end he hides Mira behind the locked cellar door and blocks it with the hallway cabinet. Small scenes told with
## voiced lines (Voice, Cartesia clips) and a short black-out for the parts the book tells rather than shows; no camera is taken away.
##
## Objectives (ChapterOne): search_home -> go_cellar -> reunion -> raid -> cellar_door -> mother -> five_more -> back_to_mira -> locked_door.
## Roles (Main.story_roles): home_raid (the four in the flat, group RAID_GROUP), home_fourth (the one in the cellar), home_hunt / home_post
## (the five more, group FIVE_GROUP: two come straight for the player, three search the rooms). The mother and Mira are not Civilians
## (no hit boxes, soldiers do not see them): two Actors driven only by this script.

const RAID_GROUP := 210
const FIVE_GROUP := 211
const KITCHEN_POS := Vector3(19.4, 0.0, -33.9)
const MOTHER_AT := Vector3(21.1, -2.7, -22.1)
const MIRA_AT := Vector3(21.75, -2.7, -21.55)
const MIRA_HIDE := Vector3(22.35, -2.7, -21.6)       # between the crate and the south shelves
const FOURTH_AT := Vector3(19.2, -2.7, -23.4)
## the four in the flat: [position, facing]
const RAID_SPOTS := [
	[Vector3(26.9, 0.0, -31.1), -PI * 0.5],         # living room: the one who speaks into his helmet
	[Vector3(17.9, 0.0, -33.4), 0.0],               # kitchen
	[Vector3(24.4, 0.0, -27.1), PI],                # parents' bedroom
	[Vector3(17.9, 0.0, -27.6), PI],                # bathroom
]
const FIVE_HUNT := [Vector3(19.5, 0.0, -30.5), Vector3(17.2, 0.0, -30.6)]
const FIVE_POST := [[Vector3(17.9, 0.0, -27.6), PI], [Vector3(25.5, 0.0, -32.0), -PI * 0.5], [Vector3(26.0, 0.0, -27.4), PI]]
const FOURTH_HEALTH := 40.0
const FOURTH_WAIT_MAX := 6.0          # the last of the four is moved to the cellar out of the player's sight; after this long, anyway
const KNOCK_AFTER := 2.5              # seconds inside the empty flat before the knocking
const BARRICADE := Vector3(20.2, 0.0, -29.35)        # the hallway cabinet in front of the stair door
const AFTER_SPOT := Vector3(21.8, 0.0, -30.7)        # where Noah stands when the black-out lifts
const BED_TOP := Vector3(29.0, 0.6, -27.35)
const FADE_TIME := 0.8

## the lines (the subtitle text is also the key of the voice clip, see Voice)
const L_CALL := "@MUM? MIRA?"
const L_CALL2 := "@MUM! MIRA! WHERE ARE YOU?"
const L_KNOCK := "@KNOCKING. FROM BENEATH THE FLOOR."
const L_MUM1 := "@MUM: NOAH! OH, NOAH. YOU'RE HERE. YOU'RE REAL."
const L_MIRA1 := "@MIRA: NOAH!"
const L_MUM2 := "@MUM: YOU'RE STAYING HERE. ALL OF US ARE STAYING HERE, TOGETHER, UNTIL THIS IS OVER."
const L_MUM3 := "@MUM: THE CITY GUARD SAID TO STAY INDOORS. HELP WILL COME."
const L_LOCK := "@NOAH: LOCK IT BEHIND ME."
const L_ORDER := "COMMANDER'S ORDERS. EVERY HOUSE. EVERY ROOM. NOBODY LEFT BREATHING."
const L_THREE := "@THREE. THERE HAD BEEN FOUR."
const L_OPEN := "@THE CELLAR DOOR. IT'S OPEN."
const L_SCREAM := "@MIRA: MUM!"
const L_LAST := "@MUM: NOAH... LOOK AFTER YOUR SISTER."
const L_WAKE := "@MIRA: MUM? MUM, WAKE UP. PLEASE WAKE UP."
const L_WEPT := "@I HELD HER AND WEPT. THEN THE FRONT DOOR BANGED AGAIN."
const L_HIDE := "@NOAH: GET BEHIND THE SHELVES. COVER YOUR EARS. DON'T COME OUT UNTIL I SAY."
const L_WHO := "WHO FIRED? CHECK THE HOUSE!"
const L_OVER := "@NOAH: IT'S OVER, MIRA. YOU CAN COME OUT."
const L_CARRY := "@I CARRIED MY MOTHER UP THE STAIRS AND LAID HER ON HER BED, UNDER THE BLANKET SHE HAD KNITTED THE WINTER BEFORE."
const L_STAY := "@NOAH: STAY DOWN HERE. LOCK THE DOOR, AND DON'T OPEN IT FOR ANYONE. NOT FOR ANYONE, MIRA. ONLY ME, OR DAD."
const L_ONLY := "@MIRA: ONLY YOU, OR DAD."
const L_THINGS := "@WATER. BREAD. HER RABBIT. AND MUM'S PHONE, SO SHE COULD FOLLOW THE NEWS. I SHOWED HER HOW TO TURN THE SOUND OFF."
const L_DONE := "@MIRA: IT'S DONE."
const L_CABINET := "@THEN I DRAGGED THE CABINET IN FRONT OF THE DOOR, SO THAT NO ONE WOULD THINK THERE WAS A DOOR THERE AT ALL."
const L_ORDER2 := "@SOMEONE HAD GIVEN AN ORDER. EVERY HOUSE, EVERY ROOM, NOBODY LEFT BREATHING."
const L_MAN := "@SOMEWHERE IN THIS CITY WAS THE MAN WHO HAD GIVEN IT."


## The mother or Mira: one person of the people pack (the pack has no women, so both get long hair), driven only by HomeScene.
class Actor extends Node3D:
	const HAIR := Color(0.24, 0.15, 0.09)
	## hair boxes in the rig's frame (metres at full size, +z is the back of the head): [centre, size]
	const HAIR_BOXES := [
		[Vector3(0.0, 1.78, 0.02), Vector3(0.32, 0.08, 0.33)],
		[Vector3(0.0, 1.52, 0.15), Vector3(0.33, 0.5, 0.07)],
		[Vector3(0.16, 1.62, 0.03), Vector3(0.04, 0.32, 0.25)],
		[Vector3(-0.16, 1.62, 0.03), Vector3(0.04, 0.32, 0.25)],
	]
	var rig: Node3D
	var tilt: Node3D
	var model: CharModel
	var scale_k := 1.0
	var facing := 0.0
	var look_at_player := true
	var dead := false
	var crouched := false
	var player: Node3D
	var _hair: Node3D

	func setup(outfit: String, k: float, p: Node3D) -> void:
		scale_k = k
		player = p
		rig = Node3D.new()
		rig.scale = Vector3.ONE * k
		add_child(rig)
		tilt = Node3D.new()
		rig.add_child(tilt)
		model = CharModel.make("people", 1.75, outfit)
		tilt.add_child(model)
		model.play("idle")
		_hair = Node3D.new()
		model.head_node.add_child(_hair)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = HAIR
		mat.roughness = 0.9
		for hb in HAIR_BOXES:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = hb[1]
			mi.mesh = bm
			mi.material_override = mat
			mi.position = hb[0]
			_hair.add_child(mi)

	func _ready() -> void:
		_fit_hair.call_deferred()

	## The hair is built in the rig's frame and then hung on the head bone (whatever its axes), so it follows the head in every clip.
	func _fit_hair() -> void:
		await get_tree().process_frame
		if not is_instance_valid(_hair):
			return
		var want := rig.global_transform
		_hair.transform = model.head_node.global_transform.affine_inverse() * want

	func face(angle: float) -> void:
		facing = angle
		rig.rotation.y = angle

	func set_crouch(on: bool) -> void:
		crouched = on
		tilt.rotation.x = 0.35 if on else 0.0
		tilt.scale.y = 0.62 if on else 1.0

	## Shot: the fall plays, turned away from the shot.
	func fall(from: Vector3) -> void:
		if dead:
			return
		dead = true
		look_at_player = false
		set_crouch(false)
		var d := global_position - from
		model.rotation.y = atan2(d.x, d.z) - rig.rotation.y
		model.play_once("death", 1.0)

	func lie() -> void:
		dead = true
		look_at_player = false
		set_crouch(false)
		model.seek_end("death")

	func revive() -> void:
		dead = false
		look_at_player = true
		model.rotation.y = 0.0
		model.play("idle", 1.0, 0.0)

	func _process(delta: float) -> void:
		if dead or not look_at_player or player == null or not visible:
			return
		var d := player.global_position - global_position
		if Vector2(d.x, d.z).length() > 9.0:
			return
		var want := atan2(-d.x, -d.z)
		face(rotate_toward(facing, want, delta * 3.0))


var main
var player: Player
var mother: Actor
var mira: Actor
var _barricade: Node3D
var _blanket: Node3D
var _steps: Array = []                # [time, String (a line) | Callable]
var _step_i := 0
var _scene_t := 0.0
var _running := false
var _in_t := 0.0                      # search_home: seconds inside the flat
var _knocked := false
var _third := false                   # raid: three of the four are down
var _fourth_t := 0.0
var _shot := false                    # cellar_door: the mother has been shot
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _fade_a := 0.0
var _fade_to := 0.0


func setup(m) -> void:
	main = m
	player = m.player
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 40
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)


# ---------------------------------------------------------------- where the story is

func _idx(oid: String) -> int:
	return main._objective_index(oid)


func _active() -> String:
	if main.mission == null or main.mission.finished:
		return ""
	return String(main.mission.active().get("id", ""))


func _ensure_actors() -> void:
	if mother != null:
		return
	mother = Actor.new()
	mother.position = MOTHER_AT
	mother.setup("Casual", 1.0, player)
	add_child(mother)
	mira = Actor.new()
	mira.position = MIRA_AT
	mira.setup("Casual2", 0.68, player)
	add_child(mira)


## The flat, the cellar and the two of them as they are at the objective the player is on (a checkpoint restore, or the story moving on).
func _apply_world() -> void:
	var i: int = main.mission.index if main.mission != null else -1
	var first := _idx("search_home")
	if first < 0:
		return
	var last := _idx("locked_door")
	var after := i > last
	_set_barricade(after)
	if i < first or after:
		if mother != null:
			mother.visible = false
			mira.visible = false
		return
	_ensure_actors()
	mother.visible = true
	mira.visible = true
	mother.position = MOTHER_AT
	if i <= _idx("cellar_door"):
		mother.revive()
		mother.face(0.0)
	else:
		mother.lie()
	mira.revive()
	if i >= _idx("five_more"):
		mira.position = MIRA_HIDE
		mira.set_crouch(true)
		mira.look_at_player = false
		mira.face(PI * 0.75)
	else:
		mira.position = MIRA_AT
		mira.set_crouch(false)
		mira.face(0.0)


## After a checkpoint restore (Main._sync_story_world).
func sync() -> void:
	_running = false
	_set_fade(0.0, 0.0)
	_apply_world()
	match _active():
		"search_home":
			begin_search()
		"reunion":
			begin_reunion()
		"raid":
			_third = false
			_fourth_t = 0.0
		"cellar_door":
			_shot = false
		"mother":
			begin_mother()
		"locked_door":
			begin_locked()


# ---------------------------------------------------------------- the little scripts

func _line_time(text: String) -> float:
	var spoken: float = main.voice.duration(text)
	if spoken > 0.0:
		return spoken + 0.35
	return clampf(1.2 + float(text.length()) * 0.05, 1.8, 5.0)


## Runs a list of lines (String), pauses (float seconds) and actions (Callable) one after another; `done` at the end.
func _play(items: Array, done: Callable) -> void:
	_steps = []
	var t := 0.0
	for it in items:
		if it is float or it is int:
			t += float(it)
		elif it is String:
			_steps.append([t, it])
			t += _line_time(it)
		else:
			_steps.append([t, it])
	_steps.append([t, done])
	_step_i = 0
	_scene_t = 0.0
	_running = true


func _run_steps(delta: float) -> void:
	_scene_t += delta
	while _running and _step_i < _steps.size() and _scene_t >= float((_steps[_step_i] as Array)[0]):
		var it: Variant = (_steps[_step_i] as Array)[1]
		_step_i += 1
		if it is String:
			Game.radio_line.emit(it)
		elif it is Callable and (it as Callable).is_valid():
			(it as Callable).call()
	if _step_i >= _steps.size():
		_running = false


func _sound_over(id: String, db: float) -> void:
	Sfx.play_at(self, Vector3(18.0, 1.2, -30.6), id, db, 1.0, 40.0, 8.0)          # the front door / the hallway above the cellar


# ---------------------------------------------------------------- VI. the empty flat and the cellar

func begin_search() -> void:
	_apply_world()
	_in_t = 0.0
	_knocked = false
	Game.radio_line.emit(L_CALL)


func begin_reunion() -> void:
	_apply_world()
	_play([0.4, L_MUM1, L_MIRA1, L_MUM2, L_MUM3, 0.6,
		func() -> void:
			_sound_over("crash", 8.0)
			player.add_shake(22.0),
		1.0, func() -> void: _sound_over("boots", 4.0),
		0.8, func() -> void: _sound_over("laugh", -2.0),
		1.6, L_LOCK, 0.3],
		func() -> void: Mission.complete("reunion"))


## RAID starts: the four turn the flat over; one of them reports in.
func begin_raid() -> void:
	_third = false
	_fourth_t = 0.0
	for s in RAID_SPOTS:
		var e: Enemy = main._spawn_enemy_at(s[0], "soldier")
		main._assign_role(e, "home_raid")
	_play([1.5, L_ORDER], Callable())


func apply_role(e: Enemy, role: String) -> void:
	e.patrol = []
	match role:
		"home_raid":
			e.group = RAID_GROUP
			e.post = true
			e.post_facing = _nearest_facing(RAID_SPOTS, e.home)
		"home_fourth":
			e.group = -1
			e.post = true
			e.passive = true
			e.scripted_aim = MOTHER_AT + Vector3(0, 1.2, 0)
			e.state = Enemy.State.ALERT
			e.alert_t = 99.0
			e.max_health = FOURTH_HEALTH
			e.health = minf(e.health, FOURTH_HEALTH)
			var d := MOTHER_AT - e.home
			e.post_facing = atan2(-d.x, -d.z)
		"home_hunt":
			e.group = FIVE_GROUP
			e.post = false
			e.knows_player = true
			e._aggravate(true)
			e.alert_t = 0.8
			e.last_known = player.global_position
		"home_post":
			e.group = FIVE_GROUP
			e.post = true
			e.post_facing = _nearest_facing(FIVE_POST, e.home)
	if e.post:
		e.facing = e.post_facing
		e.rig.rotation.y = e.facing


func _nearest_facing(spots: Array, p: Vector3) -> float:
	var best := INF
	var f := 0.0
	for s in spots:
		var d := ((s[0] as Vector3) - p).length_squared()
		if d < best:
			best = d
			f = float(s[1])
	return f


func _with_role(role: String) -> Array:
	var out: Array = []
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and en.state != Enemy.State.DEAD and String(main.story_roles.get(en.uid, "")) == role:
			out.append(en)
	return out


func _seen_by_player(e: Enemy) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	return cam.is_position_in_frustum(e.global_position + Vector3(0, 1.2, 0)) and e._los_to_player()


## Three of the four are down: the last one is not where the player thinks. He goes to the cellar (out of sight) and the cellar door stands open.
func _tick_raid(delta: float) -> void:
	var alive := _with_role("home_raid")
	if not _third:
		if alive.size() <= 1:
			_third = true
			_fourth_t = 0.0
			Game.radio_line.emit(L_THREE)
		return
	_fourth_t += delta
	if _fourth_t < _line_time(L_THREE):
		return
	if not alive.is_empty():
		var last: Enemy = alive[0]
		if _seen_by_player(last) and _fourth_t < FOURTH_WAIT_MAX:
			return
		main.story_roles.erase(last.uid)
		Game.enemies.erase(last)
		last.queue_free()
	var f: Enemy = main._spawn_enemy_at(FOURTH_AT, "soldier")
	main._assign_role(f, "home_fourth")
	Mission.complete("raid")


func begin_cellar_door() -> void:
	_shot = false
	Game.radio_line.emit(L_OPEN)


## The player comes down the stairs (or hits the soldier first): the soldier fires, the mother falls in front of Mira, and he turns on Noah.
func _tick_cellar_door() -> void:
	var fourth: Enemy = null
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and String(main.story_roles.get(en.uid, "")) == "home_fourth":
			fourth = en
	if not _shot:
		var hit := fourth == null or fourth.state == Enemy.State.DEAD or fourth.health < fourth.max_health
		if player.global_position.y < -1.0 or hit:
			_do_shot(fourth)
		return
	if fourth == null or fourth.state == Enemy.State.DEAD:
		Mission.complete("cellar_door")


func _do_shot(fourth: Enemy) -> void:
	_shot = true
	var from := FOURTH_AT + Vector3(0, 1.4, 0)
	if fourth != null:
		from = fourth.global_position + Vector3(0, 1.4, 0)
	Sfx.play_at(self, from, "whip", 6.0, 1.0, 60.0, 10.0)
	if mother != null:
		mother.fall(from)
	Game.radio_line.emit(L_SCREAM)
	if fourth != null and fourth.state != Enemy.State.DEAD:
		fourth.passive = false
		fourth.scripted_aim = Vector3.INF
		fourth.post = false
		fourth.knows_player = true
		fourth.last_known = player.global_position
		fourth.state = Enemy.State.ALERT
		fourth.alert_t = 1.0


# ---------------------------------------------------------------- VII. five more

func begin_mother() -> void:
	_apply_world()
	_play([0.8, L_LAST, 0.5, L_WAKE, 0.6, L_WEPT,
		func() -> void:
			_sound_over("crash", 6.0)
			player.add_shake(24.0),
		0.6, func() -> void: _sound_over("boots", 4.0),
		0.6, L_HIDE,
		func() -> void:
			mira.look_at_player = false
			var tw := create_tween()
			tw.tween_property(mira, "position", MIRA_HIDE, 1.2)
			tw.tween_callback(func() -> void:
				mira.set_crouch(true)
				mira.face(PI * 0.75)),
		1.2],
		func() -> void: Mission.complete("mother"))


func begin_five() -> void:
	for p in FIVE_HUNT:
		main._assign_role(main._spawn_enemy_at(p, "soldier"), "home_hunt")
	for s in FIVE_POST:
		main._assign_role(main._spawn_enemy_at(s[0], "soldier"), "home_post")
	_play([0.6, L_WHO], Callable())


func begin_back() -> void:
	_play([0.8, L_OVER], Callable())


# ---------------------------------------------------------------- VIII. the locked door

func begin_locked() -> void:
	Game.frozen = true
	Game.invulnerable = true
	if mira != null:
		mira.set_crouch(false)
		mira.look_at_player = true
		mira.position = MIRA_AT
	_play([func() -> void: _set_fade(0.0, 1.0), FADE_TIME + 0.4,
		func() -> void: _after_black(),
		L_CARRY, 0.3, L_STAY, L_ONLY, 0.3, L_THINGS, 0.4, L_DONE, 0.4, L_CABINET, 0.5,
		func() -> void:
			_set_fade(1.0, 0.0)
			Game.frozen = false,
		FADE_TIME, L_ORDER2, L_MAN],
		func() -> void:
			Game.invulnerable = false
			Mission.complete("locked_door"))


## In the dark: the mother lies on her bed under the blanket, Mira is behind the bolted door, the cabinet is across it, Noah in the hallway.
func _after_black() -> void:
	if mother != null:
		mother.visible = false
		mira.visible = false
	_set_barricade(true)
	player.global_position = AFTER_SPOT + Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	var d := BARRICADE - AFTER_SPOT
	player.yaw = atan2(-d.x, -d.z)
	player.rotation.y = player.yaw
	player.pitch = -0.1
	player.fall_speed = 0.0


func _box(parent: Node3D, centre: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position = centre
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _set_barricade(on: bool) -> void:
	if not on:
		if _barricade != null:
			_barricade.queue_free()
			_blanket.queue_free()
			_barricade = null
			_blanket = null
		return
	if _barricade != null:
		return
	var wood := Color(0.42, 0.28, 0.17)
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	body.position = BARRICADE
	add_child(body)
	_barricade = body
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.8, 2.0, 0.5)
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	body.add_child(cs)
	_box(body, Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 0.5), wood)                                   # the hallway cabinet
	_box(body, Vector3(-0.45, 1.05, -0.26), Vector3(0.02, 1.7, 0.02), wood.darkened(0.4))          # its doors
	_box(body, Vector3(0.45, 1.05, -0.26), Vector3(0.02, 1.7, 0.02), wood.darkened(0.4))
	_box(body, Vector3(-0.5, 0.45, -0.55), Vector3(0.42, 0.05, 0.42), wood.lightened(0.1), Vector3(0.5, 0.3, 0.0))     # chairs piled against it
	_box(body, Vector3(-0.5, 0.75, -0.35), Vector3(0.42, 0.5, 0.05), wood.lightened(0.1), Vector3(0.5, 0.3, 0.0))
	_box(body, Vector3(0.45, 0.9, -0.5), Vector3(0.42, 0.05, 0.42), wood.lightened(0.05), Vector3(-0.9, -0.2, 0.3))
	_box(body, Vector3(0.75, 0.95, -0.35), Vector3(0.05, 1.9, 0.05), Color(0.2, 0.2, 0.22), Vector3(0.0, 0.0, 0.12))   # the coat stand
	_box(body, Vector3(0, 0.012, -0.65), Vector3(1.7, 0.012, 0.9), Color(0.55, 0.22, 0.2))         # the rug over the gap
	# the mother under her blanket, on her bed
	_blanket = Node3D.new()
	_blanket.position = BED_TOP
	add_child(_blanket)
	_box(_blanket, Vector3(0.95, 0.07, 0), Vector3(0.45, 0.12, 0.35), Color(0.92, 0.92, 0.9))     # the pillow
	_box(_blanket, Vector3(0.0, 0.12, 0), Vector3(1.8, 0.2, 0.62), Color(0.62, 0.32, 0.36))       # the knitted blanket over her
	_box(_blanket, Vector3(0.85, 0.2, 0), Vector3(0.3, 0.16, 0.3), Color(0.6, 0.3, 0.34))         # her head beneath it


func _set_fade(from_a: float, to_a: float) -> void:
	_fade_a = from_a
	_fade_to = to_a
	_fade.color = Color(0, 0, 0, from_a)


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	if not is_equal_approx(_fade_a, _fade_to):
		_fade_a = move_toward(_fade_a, _fade_to, delta / FADE_TIME)
		_fade.color.a = _fade_a
	if Game.dead or Game.won:
		return
	if _running:
		_run_steps(delta)
	match _active():
		"search_home":
			if City.HOME_RECT.has_point(Vector2(player.global_position.x, player.global_position.z)) and player.global_position.y > -0.5:
				_in_t += delta
			if not _knocked and _in_t >= KNOCK_AFTER:
				_knocked = true
				Game.radio_line.emit(L_CALL2)
				_play([_line_time(L_CALL2), func() -> void: Sfx.play_at(self, City.CELLAR_POS + Vector3(0, 2.2, 0), "knock", 6.0, 1.0, 30.0, 6.0),
					1.3, L_KNOCK, func() -> void: Sfx.play_at(self, City.CELLAR_POS + Vector3(0, 2.2, 0), "knock", 3.0, 1.05, 30.0, 6.0)],
					func() -> void: Mission.complete("search_home"))
		"raid":
			_tick_raid(delta)
		"cellar_door":
			_tick_cellar_door()
