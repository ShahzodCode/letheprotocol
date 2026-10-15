class_name Player
extends CharacterBody3D
## First-person player. Movement physics follow the Bot Shooter prototype: step-up over ledges, slope speed,
## coyote time, jump buffer, variable jump height, heavier falling, crouch-slide, fall damage, footsteps.

signal damaged(amount: float, from: Vector3)
signal died

var health := Game.MAX_HEALTH
var yaw := 0.0
var pitch := 0.0
var recoil_pitch := 0.0       # radians of view kick that settles back
var recoil_yaw := 0.0
var recoil_recover := 8.0
var crouch_k := 0.0           # 0 standing .. 1 crouched
var sliding := 0.0            # seconds of slide left
var slide_dir := Vector3.ZERO

var head: Node3D
var camera: Camera3D
var weapons: Weapons
var shape: CapsuleShape3D
var col: CollisionShape3D

var coyote := 0.0
var jump_buf := 0.0
var was_on_floor := true
var fall_speed := 0.0
var step_dist := 0.0
var cam_dy := 0.0             # eased camera offset after a step-up
var land_dip := 0.0
var roll := 0.0
var hurt_k := 0.0             # 0..1 for the red flash
var _look_delta := Vector2.ZERO
var _sprinting := false


func _ready() -> void:
	collision_layer = Game.L_PLAYER
	collision_mask = Game.L_WORLD | Game.L_ENEMY
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	floor_stop_on_slope = true
	floor_constant_speed = true
	max_slides = 6

	shape = CapsuleShape3D.new()
	shape.radius = Game.PLAYER_RADIUS
	shape.height = Game.STAND_HEIGHT
	col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = Game.STAND_HEIGHT * 0.5
	add_child(col)

	head = Node3D.new()
	head.position.y = Game.STAND_HEIGHT - 0.12
	add_child(head)
	camera = Camera3D.new()
	camera.fov = Game.BASE_FOV
	camera.near = 0.03
	camera.far = 700.0
	head.add_child(camera)
	camera.current = true

	weapons = Weapons.new()
	camera.add_child(weapons)
	weapons.setup(self, camera)
	Game.player = self


func is_sprinting() -> bool:
	return _sprinting


func consume_look_delta() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func add_recoil(pitch_deg: float, yaw_deg: float, recover: float) -> void:
	recoil_pitch += deg_to_rad(pitch_deg)
	recoil_yaw += deg_to_rad(yaw_deg)
	recoil_recover = recover


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not Game.dead:
		var scale := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(Game.BASE_FOV) * 0.5)
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		yaw -= rel.x * Game.MOUSE_SENS * scale
		pitch = clampf(pitch - rel.y * Game.MOUSE_SENS * scale, deg_to_rad(-89.0), deg_to_rad(89.0))
		_look_delta += rel


func take_damage(amount: float, from: Vector3 = Vector3.ZERO) -> void:
	if Game.dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	hurt_k = minf(1.0, hurt_k + 0.4 + amount / 40.0)
	roll += randf_range(-0.05, 0.05)
	Sfx.play(self, "hurt", -3.0)
	damaged.emit(amount, from)
	if health <= 0.0:
		Game.dead = true
		died.emit()
		Game.player_died.emit()


func _can_stand() -> bool:
	var up := Vector3.UP * (Game.STAND_HEIGHT - shape.height + 0.02)
	return not test_move(global_transform, up)


func _physics_process(delta: float) -> void:
	# view
	rotation.y = yaw
	recoil_pitch = lerpf(recoil_pitch, 0.0, 1.0 - exp(-recoil_recover * delta))
	recoil_yaw = lerpf(recoil_yaw, 0.0, 1.0 - exp(-recoil_recover * delta))

	if Game.dead:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		velocity.y -= Game.GRAVITY * delta
		move_and_slide()
		return

	var on_floor := is_on_floor()
	if on_floor:
		coyote = Game.COYOTE_TIME
	else:
		coyote = maxf(0.0, coyote - delta)
	jump_buf = Game.JUMP_BUFFER if Input.is_action_just_pressed("jump") else maxf(0.0, jump_buf - delta)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if not Game.has_focus():
		input = Vector2.ZERO
	var dir := (global_transform.basis * Vector3(input.x, 0, input.y)).normalized() if input != Vector2.ZERO else Vector3.ZERO

	# ---- crouch / slide ----
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var crouch_held := Input.is_action_pressed("crouch")
	if Input.is_action_just_pressed("crouch") and _sprinting and on_floor and hspeed > Game.WALK_SPEED + 0.5 and sliding <= 0.0:
		sliding = 0.85
		slide_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		velocity.x = slide_dir.x * Game.SPRINT_SPEED * 1.45
		velocity.z = slide_dir.z * Game.SPRINT_SPEED * 1.45
	if sliding > 0.0:
		sliding -= delta
		if not on_floor:
			sliding = 0.0
	var want_crouch := (crouch_held or sliding > 0.0)
	if not want_crouch and crouch_k > 0.01 and not _can_stand():
		want_crouch = true
	crouch_k = move_toward(crouch_k, 1.0 if want_crouch else 0.0, delta * 7.0)
	var h := lerpf(Game.STAND_HEIGHT, Game.CROUCH_HEIGHT, crouch_k)
	shape.height = h
	col.position.y = h * 0.5
	var eye_y := h - 0.12

	# ---- target speed ----
	_sprinting = Input.is_action_pressed("sprint") and input.y < -0.1 and crouch_k < 0.3 and on_floor and sliding <= 0.0 and not weapons.reloading and weapons.ads_k < 0.2
	var speed := Game.WALK_SPEED
	if _sprinting:
		speed = Game.SPRINT_SPEED
	elif crouch_k > 0.5:
		speed = Game.CROUCH_SPEED
	speed *= weapons.move_mult()
	if on_floor and dir != Vector3.ZERO:
		var n := get_floor_normal()
		var nh := Vector3(n.x, 0, n.z)
		if nh.length() > 0.001:
			var steep := nh.length()                   # sin of the slope angle
			speed *= clampf(1.0 + dir.dot(nh.normalized()) * steep * 0.9, 0.55, 1.25)

	# ---- horizontal velocity ----
	if sliding > 0.0:
		# no steering during a slide: friction only
		var f := 1.0 - exp(-2.2 * delta)
		velocity.x = lerpf(velocity.x, 0.0, f)
		velocity.z = lerpf(velocity.z, 0.0, f)
	else:
		var target := dir * speed
		var rate := 14.0 if on_floor else 3.0
		var k := 1.0 - exp(-rate * delta)
		velocity.x = lerpf(velocity.x, target.x, k)
		velocity.z = lerpf(velocity.z, target.z, k)

	# ---- vertical ----
	if not on_floor:
		var g := Game.GRAVITY
		if velocity.y < 0.0:
			g *= Game.FALL_GRAVITY_MULT
		elif not Input.is_action_pressed("jump"):
			g *= 2.0           # released early => short hop
		velocity.y -= g * delta
		fall_speed = maxf(fall_speed, -velocity.y)
	if jump_buf > 0.0 and coyote > 0.0:
		velocity.y = Game.JUMP_SPEED
		jump_buf = 0.0
		coyote = 0.0
		sliding = 0.0
		floor_snap_length = 0.0
	else:
		floor_snap_length = 0.45

	# ---- step up small ledges ----
	var cam_before := 0.0
	if on_floor and dir != Vector3.ZERO and velocity.y <= 0.1:
		var probe := Vector3(velocity.x, 0, velocity.z).normalized() * 0.35
		if probe != Vector3.ZERO:
			cam_before = _try_step(probe)
	if cam_before > 0.0:
		cam_dy -= cam_before

	move_and_slide()

	# ---- landing ----
	on_floor = is_on_floor()
	if on_floor and not was_on_floor:
		if fall_speed > Game.FALL_DAMAGE_SPEED:
			var dmg := minf(70.0, (fall_speed - Game.FALL_DAMAGE_SPEED) * Game.FALL_DAMAGE_PER_MS)
			take_damage(dmg)
		if fall_speed > 4.0:
			land_dip = minf(0.25, fall_speed * 0.012)
			Sfx.play(self, "land", -6.0 + minf(fall_speed, 12.0) * 0.4)
		fall_speed = 0.0
	if on_floor:
		fall_speed = 0.0
	was_on_floor = on_floor

	# ---- footsteps ----
	if on_floor:
		var hs := Vector2(velocity.x, velocity.z).length()
		step_dist += hs * delta
		var stride := 2.3 if _sprinting else (1.6 if crouch_k > 0.5 else 2.0)
		if step_dist > stride and hs > 1.0:
			step_dist = 0.0
			Sfx.play(self, "step", -16.0 + (4.0 if _sprinting else 0.0) - (6.0 if crouch_k > 0.5 else 0.0), randf_range(0.85, 1.15))

	# ---- camera ----
	cam_dy = lerpf(cam_dy, 0.0, 1.0 - exp(-12.0 * delta))
	land_dip = lerpf(land_dip, 0.0, 1.0 - exp(-9.0 * delta))
	hurt_k = move_toward(hurt_k, 0.0, delta * 1.2)
	roll = lerpf(roll, 0.0, 1.0 - exp(-8.0 * delta))
	var bob := 0.0
	if on_floor:
		bob = sin(Time.get_ticks_msec() * 0.001 * Vector2(velocity.x, velocity.z).length() * 1.4) * 0.012 * clampf(Vector2(velocity.x, velocity.z).length() / Game.WALK_SPEED, 0.0, 1.5) * (1.0 - weapons.ads_k)
	var slide_tilt := 0.08 if sliding > 0.0 else 0.0
	head.position.y = eye_y + cam_dy - land_dip + bob
	head.rotation = Vector3(pitch + recoil_pitch, recoil_yaw, roll + slide_tilt)
	camera.fov = lerpf(Game.BASE_FOV + (4.0 if _sprinting else 0.0), float(weapons.stats()["ads_fov"]), weapons.ads_k)


## Tries to hop onto a ledge (<= STEP_HEIGHT) in the direction of `motion`. Returns the height gained.
func _try_step(motion: Vector3) -> float:
	var xf := global_transform
	if not test_move(xf, motion):
		return 0.0
	var up := Vector3.UP * Game.STEP_HEIGHT
	if test_move(xf, up):
		return 0.0
	var xf_up := xf.translated(up)
	if test_move(xf_up, motion):
		return 0.0
	# there must be flat-enough ground to stand on after the step
	var xf_fwd := xf_up.translated(motion)
	var col_info := KinematicCollision3D.new()
	if not test_move(xf_fwd, -up * 1.2, col_info):
		return 0.0
	if col_info.get_normal().y < 0.7:
		return 0.0
	# the downward probe stopped after `travel`; the ledge top is that far below the raised position
	var gained := clampf(up.y * 1.2 - col_info.get_travel().length(), 0.0, Game.STEP_HEIGHT)
	global_position.y += gained
	return gained
