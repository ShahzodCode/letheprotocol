class_name Civilian
extends CharacterBody3D
## A civilian running from the soldiers. A skinned person from the people pack (one outfit each, CharModel), no glow.
## States: PANIC (run along City.path to a point at least 80 m from the nearest soldier, then another; avoid the wide
## avenues while a soldier is in sight), HIDE (crouch behind the nearest car or at a building wall for 5-15 s, then back to
## PANIC; triggered by a soldier with a clear line within 25 m or a gunshot / explosion within 20 m, but only sometimes),
## FOLLOW (children stay within 2 m of their adult), DEAD (a body: falls down, stays, shares the cap of Enemy.bodies).
## Over the first 5 minutes the crowd thins out: each civilian has a moment (`leave_t`) after which he runs away from the
## player and is removed once he is more than 150 m away and out of sight. Nobody new appears after that.
## Far civilians (> 150 m) update every 0.2 s, beyond 230 m they are hidden.

enum State { PANIC, HIDE, FOLLOW, DEAD }

const RUN_SPEED := 5.5
const CHILD_SPEED := 5.0
const MAX_HEALTH := 40.0
const FLEE_MIN := 80.0              # his next running goal is at least this far from the nearest soldier
const SIGHT := 40.0                 # he notices soldiers with a clear line up to here
const HIDE_RADIUS_SOLDIER := 25.0
const HIDE_RADIUS_NOISE := 20.0
const HIDE_CHANCE := 0.5
const HIDE_MIN := 5.0
const HIDE_MAX := 15.0
const FOLLOW_DIST := 2.0            # a child stays this close to his adult
const LOD_DIST := 150.0
const LOD_STEP := 0.2
const HIDE_DIST := 230.0            # beyond this they are not drawn at all
const SHADOW_DIST := 32.0           # people farther than this cast no shadow (a skinned mesh costs three passes with the shadow splits)
const MID_DIST := 70.0              # between this and LOD_DIST he updates every MID_STEP s (the walk is scaled to cover the same ground)
const MID_STEP := 0.05
const LOD_CHECK := 0.1              # visibility, shadows and animation are re-decided this often (staggered), not every physics tick
const SEP_STEP := 0.1               # the push away from other civilians is recomputed this often (it loops over every civilian)
const REPATH_TIME := 2.5            # a whole-map A* per civilian: his goal does not move, so a new path every 2.5 s (it was 0.8 s) is plenty
const BODY_VIS := 100.0             # scenery bodies (lie_down) are not drawn beyond this
const FAR_DETAIL := 110.0           # beyond this (13 px tall) the head and feet meshes (7 of his 11 draw calls) are not drawn
const LEAVE_SPAN := 300.0           # the first 5 minutes: they flee out of the area
const DESPAWN_DIST := 150.0
const STEP_ASIDE := 2.4             # keeps this far from the player

static var clock := 0.0             # seconds since the story mission started (Main advances it)

var state := State.PANIC
var player: Player
var is_child := false
var leader: Civilian = null
var look_seed := 0
var body_scale := 1.0
var health := MAX_HEALTH
var leave_t := 0.0
var target := Vector3.INF
var last_pick_soldier_dist := -1.0  # distance from the target he picked to the nearest soldier at that moment
var soldier_seen := false
var threat_pos := Vector3.ZERO
var hide_spot := Vector3.INF
var hide_phase := 0
var hide_t := 0.0
var hide_dur := 8.0
var hide_cd := 0.0
var crouching := false
var nav_path := PackedVector3Array()
var nav_i := 0
var nav_goal := Vector3.INF
var repath_t := 0.0
var scan_t := 0.0
var stuck_t := 0.0
var despawn_t := 0.0
var lod_acc := 0.0
var lod_slow := false
var lod_t := 0.0
var sep := Vector3.ZERO
var sep_t := 0.0
var _meshes: Array[MeshInstance3D] = []
var _shadows_on := true
var _detail_meshes: Array[MeshInstance3D] = []     # head + feet: hidden when far
var _far := false
var updates := 0                    # number of full updates so far (tests compare near and far)
var phase := 0.0
var flinch := 0.0
var dead_t := 0.0
var knock := Vector3.ZERO
var facing := 0.0
var rig: Node3D
var tilt: Node3D
var spin: Node3D                    # pivots the whole body about the chest (explosion tumble)
var model: CharModel
var hit_t := 0.0
var hitboxes: Array[Area3D] = []
var _rng := RandomNumberGenerator.new()


## Spawn helper: position set BEFORE add_child (CLAUDE.md).
static func spawn(parent: Node, p: Player, pos: Vector3, seed_value: int, child: bool = false, adult: Civilian = null) -> Civilian:
	var c := Civilian.new()
	c.setup(p, pos, seed_value, child, adult)
	parent.add_child(c)
	return c


func setup(p: Player, pos: Vector3, seed_value: int, child: bool = false, adult: Civilian = null) -> void:
	player = p
	position = Vector3(pos.x, 0.3, pos.z)
	look_seed = seed_value
	is_child = child
	leader = adult
	_rng.seed = seed_value + 7
	leave_t = _rng.randf() * LEAVE_SPAN
	if is_child and adult != null:
		state = State.FOLLOW
		leave_t = adult.leave_t


func _ready() -> void:
	collision_layer = Game.L_CIVILIAN
	collision_mask = Game.L_WORLD
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	floor_stop_on_slope = true
	_build_model()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3 * body_scale
	cap.height = 1.7 * body_scale
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	Game.civilians.append(self)
	Game.gunshot.connect(_on_gunshot)
	facing = _rng.randf() * TAU
	rig.rotation.y = facing
	scan_t = _rng.randf() * 0.3
	repath_t = _rng.randf() * REPATH_TIME          # staggered: fifty A* searches must not land in one frame
	hide_cd = _rng.randf_range(0.0, 2.0)


func _exit_tree() -> void:
	Game.civilians.erase(self)
	Enemy.bodies.erase(self)


# ---------------------------------------------------------------- model

const OUTFITS := ["Adventurer", "Farmer", "Worker", "Punk", "Beach", "Casual", "Casual2", "Suit"]
const ANIM_DIST := 50.0             # animations of people farther than this are paused
const BLAST_IMPULSE := 10.0         # a hit this hard (grenade: 14 m/s push) throws the body into a tumble


func _build_model() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = look_seed
	var height := r.randf_range(0.93, 1.07)
	var width := r.randf_range(0.94, 1.08)
	body_scale = (0.7 if is_child else 1.0) * height
	rig = Node3D.new()
	rig.scale = Vector3.ONE * body_scale
	add_child(rig)
	tilt = Node3D.new()
	rig.add_child(tilt)
	spin = Node3D.new()
	spin.position.y = 0.9
	tilt.add_child(spin)
	model = CharModel.make("people", 1.75, OUTFITS[r.randi() % OUTFITS.size()])
	model.position.y = -0.9
	model.scale.x = width
	spin.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi as MeshInstance3D)
		if mi.name.ends_with("_Head") or mi.name.ends_with("_Feet"):
			_detail_meshes.append(mi as MeshInstance3D)
	model.play("idle")
	if model.player != null:
		model.player.seek(r.randf() * model.clip_length("idle"), true)
	_hitbox("legs", Vector3(0.4, 0.8, 0.3), Vector3(0, 0.4, 0))
	_hitbox("body", Vector3(0.6, 0.66, 0.36), Vector3(0, 1.13, 0))
	_hitbox("head", Vector3(0.3, 0.3, 0.3), Vector3(0, 1.64, 0))

func _hitbox(part: String, size: Vector3, pos: Vector3) -> void:
	var a := Area3D.new()
	a.collision_layer = Game.L_HITBOX
	a.collision_mask = 0
	a.monitoring = false
	a.set_meta("part", part)
	a.set_meta("civilian", true)
	a.set_meta("owner_civ", self)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	a.position = pos
	rig.add_child(a)
	hitboxes.append(a)


func chest_pos() -> Vector3:
	return global_position + Vector3(0, 1.1 * body_scale, 0)


# ---------------------------------------------------------------- damage

## Returns true when this hit killed him. No gore: a flinch, or the fall.
func take_hit(damage: float, part: String, impulse: Vector3, _point: Vector3) -> bool:
	if state == State.DEAD:
		return false
	health -= damage
	knock += Vector3(impulse.x, 0.0, impulse.z) * 0.3
	flinch = 1.0
	if health <= 0.0:
		die(true, impulse, part)
		return true
	if hit_t <= 0.0:
		model.play_once("hit" if _rng.randf() < 0.5 else "hit2", 1.2)
		hit_t = 0.45
	if state == State.HIDE:
		state = State.PANIC          # found: run
		_pick_target()
	return false


## `count` false = scenery (a body that was already there when the story began). The fall plays the pack's death clip,
## turned so he drops away from the shot (a headshot is quicker, a blast throws him into a tumble first).
func die(count: bool = true, impulse: Vector3 = Vector3.ZERO, part: String = "body") -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	if count:
		Game.civilians_lost += 1
	Game.civilians.erase(self)
	for h in hitboxes:
		h.queue_free()
	hitboxes.clear()
	collision_layer = 0
	collision_mask = Game.L_WORLD
	Enemy.add_body(self)
	for dm in _detail_meshes:                # a body that dies far away still gets his head back
		dm.visible = true
	var flat := Vector3(impulse.x, 0.0, impulse.z)
	var yaw := _rng.randf() * TAU - rig.rotation.y
	if flat.length() > 0.1:
		yaw = atan2(flat.x, flat.z) - rig.rotation.y          # his head ends up along the shot
	dead_t = 0.0
	crouching = false
	if model.player != null:
		model.player.active = true          # far people had their animation paused: the fall must play
	rig.scale.y = body_scale
	tilt.rotation.x = 0.0
	if flat.length() > BLAST_IMPULSE:
		spin.rotation.y = yaw
		velocity.y = 4.0
		var tw := create_tween()
		tw.tween_property(spin, "rotation:x", TAU, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func():
			spin.rotation = Vector3.ZERO
			model.rotation.y = yaw
			model.play_once("death", 1.6))
	else:
		model.rotation.y = yaw
		model.play_once("death", 1.6 if part == "head" else 1.0)


## Scenery: a body lying on the ground at once (no animation, not counted).
func lie_down() -> void:
	die(false)
	model.rotation.y = _rng.randf() * TAU
	spin.rotation = Vector3.ZERO
	model.seek_end("death")
	_set_shadows(false)                  # scenery bodies are cheap: no shadow, not drawn beyond BODY_VIS
	for m in _meshes:
		m.visibility_range_end = BODY_VIS
		m.visibility_range_end_margin = 10.0

func _dead_step(delta: float) -> void:
	knock = knock.move_toward(Vector3.ZERO, 5.0 * delta)
	velocity.x = knock.x
	velocity.z = knock.z
	if not is_on_floor():
		velocity.y -= Game.GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	dead_t += delta
	if dead_t > 3.0 and knock.length() < 0.05 and is_on_floor():
		model.stop()
		set_physics_process(false)


# ---------------------------------------------------------------- behaviour

func _on_gunshot(pos: Vector3, _loudness: float) -> void:
	if state != State.PANIC or hide_cd > 0.0 or global_position.distance_to(pos) > HIDE_RADIUS_NOISE:
		return
	_maybe_hide(pos)


func _nearest_soldier() -> Enemy:
	var best: Enemy = null
	var best_d := 1.0e9
	for e in Game.enemies:
		var en := e as Enemy
		if not is_instance_valid(en) or en.state == Enemy.State.DEAD:
			continue
		var d := global_position.distance_squared_to(en.global_position)
		if d < best_d:
			best_d = d
			best = en
	return best


## Every 0.3 s: is a soldier in view (clear line, within SIGHT)? Near ones may send him into hiding.
func _scan(delta: float) -> void:
	scan_t -= delta
	hide_cd -= delta
	if scan_t > 0.0:
		return
	scan_t = 0.3
	soldier_seen = false
	var best := 1.0e9
	var eye := global_position + Vector3(0, 1.5 * body_scale, 0)
	var space := get_world_3d().direct_space_state
	for e in Game.enemies:
		var en := e as Enemy
		if not is_instance_valid(en) or en.state == Enemy.State.DEAD:
			continue
		var d := global_position.distance_to(en.global_position)
		if d > SIGHT or d >= best:
			continue
		var chest := en.global_position + Vector3(0, 1.2, 0)
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, chest, Game.L_WORLD)).is_empty():
			soldier_seen = true
			best = d
			threat_pos = en.global_position
	if soldier_seen and best < HIDE_RADIUS_SOLDIER and state == State.PANIC and hide_cd <= 0.0:
		_maybe_hide(threat_pos)


func _maybe_hide(threat: Vector3) -> void:
	hide_cd = 6.0
	if _rng.randf() >= HIDE_CHANCE:
		return
	var spot := find_hide(threat)
	if spot == Vector3.INF:
		return
	state = State.HIDE
	hide_spot = spot
	hide_phase = 0
	hide_t = 0.0
	hide_dur = _rng.randf_range(HIDE_MIN, HIDE_MAX)
	nav_goal = Vector3.INF


## The nearest car (behind it, away from the threat) or building wall (a recess) within 25 m that blocks the line from the threat.
func find_hide(threat: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var up := Vector3(0, 1.0, 0)
	var me := Vector2(global_position.x, global_position.z)
	var best := Vector3.INF
	var best_d := 1.0e9
	for c in City.cars:
		var cp: Vector3 = c["pos"]
		var d := me.distance_to(Vector2(cp.x, cp.z))
		if d > 25.0 or d >= best_d:
			continue
		var away := Vector3(cp.x - threat.x, 0, cp.z - threat.z)
		away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
		var sz: Vector3 = c["size"]
		var spot := cp + away * (maxf(sz.x, sz.z) * 0.5 + 0.9)
		if City.is_free(spot) and not space.intersect_ray(PhysicsRayQueryParameters3D.create(threat + up, spot + up, Game.L_WORLD)).is_empty():
			best = spot
			best_d = d
	if best != Vector3.INF:
		return best
	for b in City.buildings:
		var r: Rect2 = b["rect"]
		if not r.grow(25.0).has_point(me):
			continue
		var cl := Vector2(clampf(me.x, r.position.x, r.end.x), clampf(me.y, r.position.y, r.end.y))
		var out := me - cl
		var d2 := out.length()
		if d2 > 25.0 or d2 >= best_d or d2 < 0.01:
			continue
		var spot2 := Vector3(cl.x + out.normalized().x * 0.9, 0.0, cl.y + out.normalized().y * 0.9)
		if City.is_free(spot2):
			best = spot2
			best_d = d2
	return best


## A new running goal: at least 80 m from the nearest soldier; while a soldier is in sight not on a wide avenue. Once it is time
## to leave, a goal far from the player instead (so the crowd thins out).
func _pick_target() -> void:
	var leaving := clock >= leave_t
	var soldier := _nearest_soldier()
	var avoid := player.global_position if leaving else (soldier.global_position if soldier != null else global_position)
	var min_d := DESPAWN_DIST + 15.0 if leaving else FLEE_MIN
	var best := Vector3.INF
	# strict first (far enough, and off the avenues while a soldier is in sight), then without the avenue rule
	for i in 90:
		var spot := City.random_spawn(_rng, avoid, min_d)
		var sp: Vector3 = spot["pos"]
		if Vector2(sp.x - avoid.x, sp.z - avoid.z).length() < min_d:
			continue
		if soldier_seen and not leaving and _on_avenue(sp) and i < 70:
			continue
		best = sp
		break
	if best == Vector3.INF:
		best = City.random_point_near(_rng, global_position, 30.0, 90.0)
	target = best
	last_pick_soldier_dist = Vector2(best.x - soldier.global_position.x, best.z - soldier.global_position.z).length() if soldier != null else -1.0
	nav_goal = Vector3.INF
	stuck_t = 0.0


## Is this point on one of the wide avenues (junction squares included)?
static func _on_avenue(p: Vector3) -> bool:
	for st in City.streets:
		if st["cls"] == "avenue" and (st["rect"] as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _nav_dir(goal: Vector3, delta: float) -> Vector3:
	var to := goal - global_position
	to.y = 0.0
	repath_t -= delta
	if repath_t <= 0.0 or nav_goal == Vector3.INF or nav_goal.distance_to(goal) > 5.0:
		repath_t = REPATH_TIME * _rng.randf_range(0.8, 1.3)
		nav_path = City.path(global_position, goal)
		nav_i = 0
		nav_goal = goal
	while nav_i < nav_path.size():
		var wp := nav_path[nav_i] - global_position
		wp.y = 0.0
		if wp.length() < 0.9:
			nav_i += 1
		else:
			return wp.normalized()
	return to.normalized() if to.length() > 0.6 else Vector3.ZERO


func _visible_to_player() -> bool:
	if player == null or player.camera == null:
		return false
	var chest := chest_pos()
	if not player.camera.is_position_in_frustum(chest):
		return false
	var q := PhysicsRayQueryParameters3D.create(player.camera.global_position, chest, Game.L_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Re-decides what he costs: drawn at all (HIDE_DIST), casting shadows (SHADOW_DIST), animation playing (ANIM_DIST and in view).
func _update_lod(d2: float) -> void:
	var show := d2 <= HIDE_DIST * HIDE_DIST
	if visible != show:
		visible = show
	var far := d2 > FAR_DETAIL * FAR_DETAIL
	if far != _far:
		_far = far
		for dm in _detail_meshes:
			dm.visible = not far
	var want_shadow := d2 <= SHADOW_DIST * SHADOW_DIST
	if want_shadow != _shadows_on:
		_set_shadows(want_shadow)
	if model.player != null:
		model.player.active = d2 < ANIM_DIST * ANIM_DIST and player.camera.is_position_in_frustum(global_position + Vector3(0, 1.0, 0))


func _set_shadows(on: bool) -> void:
	_shadows_on = on
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for m in _meshes:
		m.cast_shadow = mode


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_dead_step(delta)
		return
	if player == null:
		return
	var lod_scale := 1.0
	var d2 := global_position.distance_squared_to(player.global_position)
	lod_slow = d2 > LOD_DIST * LOD_DIST
	lod_t -= delta
	if lod_t <= 0.0:                    # visibility, shadows and animation are decided 10 times a second, staggered, not every tick
		lod_t = LOD_CHECK + _rng.randf() * 0.03
		_update_lod(d2)
	var step := LOD_STEP if lod_slow else (MID_STEP if d2 > MID_DIST * MID_DIST else 0.0)
	if step > 0.0:
		lod_acc += delta
		if lod_acc < step:
			return
		delta = lod_acc
		lod_acc = 0.0
		lod_scale = delta * float(Engine.physics_ticks_per_second)
	updates += 1
	flinch = move_toward(flinch, 0.0, delta * 5.0)
	knock = knock.move_toward(Vector3.ZERO, 6.0 * delta)
	_scan(delta)
	# leaving the area: gone once far from the player and out of his sight
	despawn_t -= delta
	if despawn_t <= 0.0:
		despawn_t = 0.5
		if clock >= leave_t and (leader == null or not is_instance_valid(leader)) and d2 > DESPAWN_DIST * DESPAWN_DIST and not _visible_to_player():
			queue_free()
			return
	var want := Vector3.ZERO
	var anim_speed := 0.0
	crouching = false
	match state:
		State.PANIC:
			var to_t := target - global_position
			to_t.y = 0.0
			if target == Vector3.INF or to_t.length() < 2.5:
				_pick_target()
			var dir := _nav_dir(target, delta)
			if dir == Vector3.ZERO:
				_pick_target()
			else:
				want = dir * RUN_SPEED
				anim_speed = RUN_SPEED
		State.HIDE:
			var to_s := hide_spot - global_position
			to_s.y = 0.0
			if hide_phase == 0:
				if to_s.length() < 0.9:
					hide_phase = 1
				else:
					var hd := _nav_dir(hide_spot, delta)
					want = hd * RUN_SPEED
					anim_speed = RUN_SPEED
			else:
				crouching = true
				hide_t += delta
				if hide_t >= hide_dur:
					state = State.PANIC
					hide_cd = 4.0
					_pick_target()
		State.FOLLOW:
			if leader == null or not is_instance_valid(leader) or leader.state == State.DEAD:
				leader = null
				state = State.PANIC
				leave_t = minf(leave_t, clock)
				_pick_target()
			else:
				var to_l := leader.global_position - global_position
				to_l.y = 0.0
				var dl := to_l.length()
				if leader.state == State.HIDE and leader.hide_phase == 1 and dl < 3.0:
					crouching = true
				elif dl > FOLLOW_DIST * 0.8:
					var sp := CHILD_SPEED if dl < 3.5 else RUN_SPEED * 1.15
					want = to_l.normalized() * sp
					anim_speed = sp
	# keep out of the player's way, and out of each other's
	var to_p := global_position - player.global_position
	to_p.y = 0.0
	if to_p.length() < STEP_ASIDE and to_p.length() > 0.01:
		var side := to_p.normalized()
		want += side * (STEP_ASIDE - to_p.length()) * 2.5
		anim_speed = maxf(anim_speed, 2.0)
	sep_t -= delta
	if sep_t <= 0.0:                    # the push away from the others loops over every civilian: 10 times a second is enough
		sep_t = SEP_STEP + _rng.randf() * 0.04
		sep = Vector3.ZERO
		for c in Game.civilians:
			var o := c as Civilian
			if o == self or not is_instance_valid(o):
				continue
			var dd := global_position - o.global_position
			dd.y = 0.0
			var l := dd.length()
			if l < 0.7 and l > 0.01:
				sep += dd / l * (0.7 - l) * 3.0
	want += sep
	if want.length() > 0.2 and state != State.HIDE:
		var fdir := want
		facing = lerp_angle(facing, atan2(-fdir.x, -fdir.z), 1.0 - exp(-9.0 * delta))
		rig.rotation.y = facing
	if state == State.PANIC and want.length() < 0.5 * RUN_SPEED and Vector2(velocity.x, velocity.z).length() < 1.0 and is_on_floor():
		stuck_t += delta
		if stuck_t > 0.8:
			_pick_target()
	else:
		stuck_t = 0.0
	# physics (same idea as the enemies')
	var k := 1.0 - exp(-14.0 * delta)
	velocity.x = lerpf(velocity.x, want.x + knock.x, k)
	velocity.z = lerpf(velocity.z, want.z + knock.z, k)
	if not is_on_floor():
		velocity.y -= Game.GRAVITY * delta
	else:
		velocity.y = maxf(velocity.y, -1.0)
	if lod_scale > 1.0:
		var vx := velocity.x
		var vz := velocity.z
		var vy := velocity.y
		velocity.y = maxf(velocity.y * lod_scale, -1.5 * lod_scale)
		velocity.x *= lod_scale
		velocity.z *= lod_scale
		move_and_slide()
		velocity.x = vx
		velocity.z = vz
		velocity.y = -1.0 if is_on_floor() else vy
		return
	move_and_slide()
	_animate(delta, anim_speed)


func _animate(delta: float, speed: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	if model.player == null:
		return
	if hit_t <= 0.0:
		if crouching:
			model.play("idle", 0.5)
		elif speed > 3.0:
			model.play("run", clampf(speed / 5.0, 0.7, 1.3))
		elif speed > 0.2:
			model.play("walk", clampf(speed / 1.6, 0.8, 2.2))
		else:
			model.play("idle")
	rig.scale.y = lerpf(rig.scale.y, body_scale * (0.66 if crouching else 1.0), 1.0 - exp(-12.0 * delta))
	tilt.rotation.x = lerpf(tilt.rotation.x, -0.4 if crouching else 0.0, 1.0 - exp(-10.0 * delta))
