class_name Enemy
extends CharacterBody3D
## Enemy soldier: low-poly model from boxes, wanders far away until the player gets close or shoots, then runs
## at him and strikes with the rifle butt. Same kind of physics as the player (gravity, slopes, knockback, stun).

enum State { WANDER, ALERT, CHASE, ATTACK, DEAD }

# ---------- tuning ----------
const MAX_HEALTH := 100.0
const WALK_SPEED := 1.5
const RUN_SPEED := 6.4
const SIGHT_RANGE := 34.0
const SIGHT_FOV := 130.0          # degrees, full cone
const HEAR_WALK := 11.0           # a walking player is noticed this close from any direction
const HEAR_SPRINT := 20.0
const HEAR_CROUCH := 5.0
const GIVE_UP_DIST := 75.0
const GIVE_UP_TIME := 6.0
const MELEE_RANGE := 1.9
const MELEE_DAMAGE := 16.0
const MELEE_WINDUP := 0.5
const MELEE_COOLDOWN := 0.9
const ALERT_TIME := 0.45
const ALLY_ALERT_RADIUS := 22.0
const KNOCK_DECAY := 6.0
const ROAM_RADIUS := 22.0

var state := State.WANDER
var health := MAX_HEALTH
var player: Player
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var wait_t := 0.0
var alert_t := 0.0
var attack_t := 0.0
var cooldown := 0.0
var lost_t := 0.0
var stun := 0.0
var knock := Vector3.ZERO
var facing := 0.0                 # yaw
var phase := 0.0
var flinch := 0.0
var stuck_t := 0.0
var side_t := 0.0
var side_dir := 1.0
var step_dist := 0.0
var strike_done := false
var dead_t := 0.0

var rig: Node3D
var tilt: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var head_node: Node3D
var hitboxes: Array[Area3D] = []
var _rng := RandomNumberGenerator.new()


## Call BEFORE add_child: the physics body must enter the world already at its spawn point
## (changing global_position after add_child reaches the physics server one frame late).
func setup(p: Player, home_pos: Vector3) -> void:
	player = p
	home = home_pos
	position = home_pos


func _ready() -> void:
	_rng.randomize()
	collision_layer = Game.L_ENEMY
	collision_mask = Game.L_WORLD | Game.L_ENEMY | Game.L_PLAYER
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	floor_stop_on_slope = true
	max_slides = 5
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	_build_model()
	Game.enemies.append(self)
	facing = _rng.randf() * TAU
	_pick_wander_point()
	wait_t = _rng.randf_range(0.5, 3.0)
	Game.gunshot.connect(_on_gunshot)


# ---------------------------------------------------------------- model

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, pivot: Vector3, size: Vector3, color: Color, end_color: Color) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	parent.add_child(p)
	_box(p, size, Vector3(0, -size.y * 0.5, 0), color)
	_box(p, Vector3(size.x * 1.05, size.y * 0.22, size.z * 1.05), Vector3(0, -size.y * 0.89, 0), end_color)
	return p


func _build_model() -> void:
	var uniform := Color(0.33, 0.37, 0.22)
	var pants := Color(0.26, 0.29, 0.2)
	var skin := Color(0.85, 0.66, 0.52)
	var helmet := Color(0.22, 0.27, 0.17)
	var boot := Color(0.1, 0.09, 0.08)
	var vest := Color(0.2, 0.22, 0.16)

	rig = Node3D.new()
	add_child(rig)
	tilt = Node3D.new()
	rig.add_child(tilt)

	_box(tilt, Vector3(0.5, 0.62, 0.27), Vector3(0, 1.14, 0), uniform)               # torso
	_box(tilt, Vector3(0.54, 0.4, 0.31), Vector3(0, 1.2, 0), vest)                     # plate carrier
	_box(tilt, Vector3(0.46, 0.2, 0.25), Vector3(0, 0.86, 0), pants)                   # hips
	head_node = Node3D.new()
	head_node.position = Vector3(0, 1.63, 0)
	tilt.add_child(head_node)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.27
	sm.radial_segments = 8
	sm.rings = 5
	var hm := StandardMaterial3D.new()
	hm.albedo_color = skin
	sm.material = hm
	head.mesh = sm
	head_node.add_child(head)
	var helm := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.155
	hs.height = 0.2
	hs.radial_segments = 8
	hs.rings = 4
	var hsm := StandardMaterial3D.new()
	hsm.albedo_color = helmet
	hs.material = hsm
	helm.mesh = hs
	helm.position = Vector3(0, 0.07, 0)
	head_node.add_child(helm)
	_box(head_node, Vector3(0.05, 0.03, 0.02), Vector3(-0.05, 0.02, -0.12), Color(0.1, 0.1, 0.1))   # eyes
	_box(head_node, Vector3(0.05, 0.03, 0.02), Vector3(0.05, 0.02, -0.12), Color(0.1, 0.1, 0.1))

	leg_l = _limb(tilt, Vector3(-0.13, 0.86, 0), Vector3(0.17, 0.86, 0.2), pants, boot)
	leg_r = _limb(tilt, Vector3(0.13, 0.86, 0), Vector3(0.17, 0.86, 0.2), pants, boot)
	arm_l = _limb(tilt, Vector3(-0.33, 1.4, 0), Vector3(0.13, 0.6, 0.13), uniform, skin)
	arm_r = _limb(tilt, Vector3(0.33, 1.4, 0), Vector3(0.13, 0.6, 0.13), uniform, skin)

	# rifle prop in the right hand (used as a club)
	var gun := Node3D.new()
	gun.position = Vector3(0, -0.55, -0.05)
	arm_r.add_child(gun)
	_box(gun, Vector3(0.07, 0.1, 0.75), Vector3(0, 0, -0.2), Color(0.1, 0.1, 0.1))
	_box(gun, Vector3(0.05, 0.07, 0.25), Vector3(0, -0.01, 0.3), Color(0.25, 0.18, 0.1))

	# hit boxes (never overlap each other, so a ray picks exactly one part)
	_hitbox("legs", BoxShape3D.new(), Vector3(0.42, 0.8, 0.32), Vector3(0, 0.4, 0))
	_hitbox("body", BoxShape3D.new(), Vector3(0.7, 0.66, 0.4), Vector3(0, 1.13, 0))
	var sph := SphereShape3D.new()
	sph.radius = 0.17
	_hitbox("head", sph, Vector3.ZERO, Vector3(0, 1.64, 0))


func _hitbox(part: String, shape: Shape3D, size: Vector3, pos: Vector3) -> void:
	var a := Area3D.new()
	a.collision_layer = Game.L_HITBOX
	a.collision_mask = 0
	a.monitoring = false
	a.set_meta("part", part)
	a.set_meta("enemy", self)
	if shape is BoxShape3D:
		(shape as BoxShape3D).size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	a.position = pos
	rig.add_child(a)
	hitboxes.append(a)


# ---------------------------------------------------------------- damage

func take_hit(damage: float, part: String, impulse: Vector3, point: Vector3) -> bool:
	if state == State.DEAD:
		return false
	health -= damage
	_blood(point, impulse)
	knock += Vector3(impulse.x, 0.0, impulse.z) + Vector3(0, minf(impulse.length() * 0.25, 1.5), 0)
	stun = maxf(stun, 0.1 + minf(damage / 250.0, 0.25))
	flinch = 1.0
	if health <= 0.0:
		_die(impulse)
		return true
	_aggravate()
	# friends nearby hear the commotion
	for e in Game.enemies:
		var o := e as Enemy
		if o != self and o.state == State.WANDER and o.global_position.distance_to(global_position) < ALLY_ALERT_RADIUS:
			o._aggravate()
	return false


func _aggravate() -> void:
	if state == State.WANDER:
		state = State.ALERT
		alert_t = ALERT_TIME * _rng.randf_range(0.6, 1.2)
		Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 1.6, 0), "hurt", -2.0, _rng.randf_range(0.6, 0.8), 70.0)


func _on_gunshot(pos: Vector3, loudness: float) -> void:
	if state != State.WANDER:
		return
	if global_position.distance_to(pos) < loudness * 0.45:
		_aggravate()


func _blood(point: Vector3, dir: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 12
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -10, 0)
	var m := BoxMesh.new()
	m.size = Vector3(0.04, 0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.05, 0.05)
	m.material = mat
	p.mesh = m
	p.finished.connect(p.queue_free)
	get_tree().current_scene.add_child(p)
	p.global_position = point


func _die(impulse: Vector3) -> void:
	state = State.DEAD
	Game.kills += 1
	Game.enemy_killed.emit(self)
	Game.enemies.erase(self)
	for h in hitboxes:
		h.queue_free()
	hitboxes.clear()
	collision_layer = 0
	collision_mask = Game.L_WORLD
	Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 1.2, 0), "death", 0.0, _rng.randf_range(0.8, 1.0), 60.0)
	# fall backwards if shot from the front, forwards if shot from behind
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var back := Vector3(impulse.x, 0, impulse.z).dot(fwd) < 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(tilt, "rotation:x", (PI * 0.5) if back else (-PI * 0.5), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(tilt, "position:y", 0.12, 0.55)
	tw.tween_property(arm_l, "rotation:z", 1.4, 0.4)
	tw.tween_property(arm_r, "rotation:z", -1.4, 0.4)
	knock += Vector3(impulse.x, 0, impulse.z) * 1.5
	dead_t = 0.0


# ---------------------------------------------------------------- AI

func _pick_wander_point() -> void:
	var half := World.HALF - 12.0
	for i in 8:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(6.0, ROAM_RADIUS)
		var p := home + Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x) < half and absf(p.z) < half:
			wander_target = p
			return
	wander_target = home


func _eye_pos() -> Vector3:
	return global_position + Vector3(0, 1.65, 0)


func _notices_player() -> bool:
	if player == null or Game.dead:
		return false
	var chest := player.global_position + Vector3(0, 1.2 if player.crouch_k < 0.5 else 0.8, 0)
	var to := chest - _eye_pos()
	var d := to.length()
	var hear := HEAR_WALK
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_sprinting():
		hear = HEAR_SPRINT
	elif player.crouch_k > 0.5:
		hear = HEAR_CROUCH
	elif hspeed < 0.5:
		hear = HEAR_CROUCH * 1.2
	var sight := SIGHT_RANGE * (0.6 if player.crouch_k > 0.5 else 1.0)
	var flat := Vector3(to.x, 0, to.z).normalized()
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var in_cone := fwd.dot(flat) > cos(deg_to_rad(SIGHT_FOV * 0.5))
	if not ((d < sight and in_cone) or d < hear):
		return false
	var q := PhysicsRayQueryParameters3D.create(_eye_pos(), chest, Game.L_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_dead_step(delta)
		return
	if player == null:
		return
	cooldown = maxf(0.0, cooldown - delta)
	flinch = move_toward(flinch, 0.0, delta * 5.0)
	knock = knock.move_toward(Vector3.ZERO, KNOCK_DECAY * delta * maxf(1.0, knock.length() * 0.6))

	var want := Vector3.ZERO     # desired horizontal velocity
	var anim_speed := 0.0
	var turn_rate := 7.0
	var to_player := player.global_position - global_position
	var dist := Vector2(to_player.x, to_player.z).length()

	if stun > 0.0:
		stun -= delta
	else:
		match state:
			State.WANDER:
				if _notices_player():
					_aggravate()
				elif wait_t > 0.0:
					wait_t -= delta
				else:
					var to_t := wander_target - global_position
					to_t.y = 0
					if to_t.length() < 1.5:
						wait_t = _rng.randf_range(1.5, 5.0)
						_pick_wander_point()
					else:
						want = to_t.normalized() * WALK_SPEED
						_face(to_t, delta, 3.0)
						anim_speed = WALK_SPEED
						turn_rate = 3.0
			State.ALERT:
				_face(to_player, delta, 10.0)
				alert_t -= delta
				if alert_t <= 0.0:
					state = State.CHASE
					lost_t = 0.0
			State.CHASE:
				var d3 := Vector3(to_player.x, 0, to_player.z)
				var dirv := d3.normalized()
				dirv += _separation() * 0.8
				# stuck on something? sidestep around it for a moment
				if side_t > 0.0:
					side_t -= delta
					dirv = dirv.rotated(Vector3.UP, side_dir * 1.2)
				dirv = dirv.normalized()
				var spd := RUN_SPEED
				if is_on_floor():
					var n := get_floor_normal()
					var nh := Vector3(n.x, 0, n.z)
					if nh.length() > 0.001:
						spd *= clampf(1.0 + dirv.dot(nh.normalized()) * nh.length() * 0.9, 0.6, 1.2)
				want = dirv * spd
				_face(dirv, delta, 9.0)
				anim_speed = spd
				if Vector2(velocity.x, velocity.z).length() < RUN_SPEED * 0.3 and is_on_floor():
					stuck_t += delta
					if stuck_t > 0.5:
						stuck_t = 0.0
						side_t = 0.7
						side_dir = 1.0 if _rng.randf() < 0.5 else -1.0
				else:
					stuck_t = 0.0
				if dist < MELEE_RANGE and absf(to_player.y) < 2.0:
					state = State.ATTACK
					attack_t = 0.0
					strike_done = false
				if dist > GIVE_UP_DIST:
					lost_t += delta
					if lost_t > GIVE_UP_TIME:
						state = State.WANDER
						home = global_position
						_pick_wander_point()
						wait_t = 2.0
				else:
					lost_t = 0.0
			State.ATTACK:
				_face(to_player, delta, 12.0)
				if cooldown <= 0.0:
					attack_t += delta
					if attack_t >= MELEE_WINDUP and not strike_done:
						strike_done = true
						_strike(dist)
				if strike_done and cooldown <= 0.0:
					cooldown = MELEE_COOLDOWN
					attack_t = 0.0
					strike_done = false
					if dist > MELEE_RANGE + 0.8:
						state = State.CHASE

	# ---- physics ----
	var accel := 16.0 if is_on_floor() else 2.5
	var k := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, want.x + knock.x, k if stun <= 0.0 else 1.0 - exp(-3.0 * delta))
	velocity.z = lerpf(velocity.z, want.z + knock.z, k if stun <= 0.0 else 1.0 - exp(-3.0 * delta))
	if not is_on_floor():
		velocity.y -= Game.GRAVITY * delta
	elif knock.y > 0.0:
		velocity.y = knock.y
		knock.y = 0.0
	else:
		velocity.y = maxf(velocity.y, -1.0)
	knock.y = 0.0
	move_and_slide()

	# ---- animation / footsteps ----
	_animate(delta, anim_speed)
	if is_on_floor() and anim_speed > 0.5:
		step_dist += Vector2(velocity.x, velocity.z).length() * delta
		if step_dist > (2.6 if state == State.CHASE else 1.2):
			step_dist = 0.0
			if global_position.distance_to(player.global_position) < 45.0:
				Sfx.play_at(get_tree().current_scene, global_position, "step", -8.0, _rng.randf_range(0.8, 1.1), 40.0)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	var target := atan2(-dir.x, -dir.z)
	facing = lerp_angle(facing, target, 1.0 - exp(-rate * delta))
	rig.rotation.y = facing


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in Game.enemies:
		var o := e as Enemy
		if o == self or o.state == State.DEAD:
			continue
		var d := global_position - o.global_position
		d.y = 0
		var l := d.length()
		if l < 1.6 and l > 0.01:
			push += d / l * (1.6 - l)
	return push


func _strike(dist: float) -> void:
	Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 1.3, 0), "swing", -4.0, 1.0, 30.0)
	var to := player.global_position - global_position
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var flat := Vector3(to.x, 0, to.z).normalized()
	if dist < MELEE_RANGE + 0.5 and fwd.dot(flat) > 0.35 and absf(to.y) < 2.2:
		player.take_damage(MELEE_DAMAGE, global_position)
		player.velocity += flat * 3.0


func _animate(delta: float, speed: float) -> void:
	var run := speed > 3.0
	phase += delta * speed * (1.5 if run else 2.6)
	var amp := 0.9 if run else 0.5
	if speed < 0.2:
		amp = 0.0
		phase = lerpf(phase, 0.0, 0.1)
	leg_l.rotation.x = sin(phase) * amp
	leg_r.rotation.x = -sin(phase) * amp
	var carry := -0.9          # arms hold the rifle across the chest
	arm_l.rotation.x = carry + sin(phase) * 0.2 * amp
	arm_r.rotation.x = carry - sin(phase) * 0.2 * amp
	arm_l.rotation.z = 0.0
	arm_r.rotation.z = 0.0
	tilt.position.y = absf(sin(phase)) * 0.04 * (amp * 2.0)
	var lean := 0.18 if run else 0.0
	tilt.rotation.x = lean - flinch * 0.25
	if state == State.ALERT:
		arm_r.rotation.x = -2.6      # shout / point
		arm_l.rotation.x = -0.4
	if state == State.ATTACK:
		var k := clampf(attack_t / MELEE_WINDUP, 0.0, 1.0)
		if strike_done:
			arm_r.rotation.x = -0.4
			arm_l.rotation.x = -0.4
		else:
			arm_r.rotation.x = lerpf(-0.9, -2.7, k)
			arm_l.rotation.x = lerpf(-0.9, -2.2, k)
			tilt.rotation.x = lerpf(0.0, -0.3, k)
	head_node.rotation.x = -flinch * 0.3


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
	if dead_t > 12.0:
		var s := maxf(0.01, 1.0 - (dead_t - 12.0) * 1.5)
		rig.scale = Vector3.ONE * s
		if s <= 0.011:
			queue_free()
