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
var shake := 0.0              # camera shake (explosions), 0 .. 1, fades in about a second
var hurt_k := 0.0             # 0..1 for the red flash
const HEAL_AMOUNT := 25.0     # one med kit
const HEAL_TIME := 3.0        # seconds the kit takes; health rises evenly meanwhile (moving, shooting and damage do not stop it)
var heal_t := 0.0             # >0: seconds of healing left
var death_cause := ""         # what the last hit was ("SHOT BY A RIFLEMAN"); the death screen shows it
var _healed := 0.0            # health actually gained by the current kit (for the "+25 HEALTH" toast)
var _look_delta := Vector2.ZERO
var _sprinting := false
var climbing := false         # on a ladder (City.ladders): W / S climb, Space jumps off backwards, no gravity, no firing
var ladder: Dictionary = {}
var _climb_flip := 1.0        # +1: W climbs up (facing the wall), -1: W climbs down (facing out over the edge)
var _climb_cool := 0.0        # no re-attach for a moment after letting go
const MANTLE_TIME := 0.4
var _mantle_t := 0.0          # >0: easing over the top of a ladder onto the roof
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _climb_dist := 0.0       # metres climbed since the last rung sound


func _ready() -> void:
	collision_layer = Game.L_PLAYER
	collision_mask = Game.L_WORLD | Game.L_ENEMY          # the 0.15 m pavement kerbs (L_KERB) are visual only: stepping onto them was laggy and shifted the height
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
	camera.fov = Settings.fov
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


## Camera shake from a blast: strong within 10 m, fading to nothing at 30 m.
func add_shake(distance: float) -> void:
	var k := 1.0 if distance <= 10.0 else clampf(1.0 - (distance - 10.0) / 20.0, 0.0, 1.0)
	shake = maxf(shake, k)


func add_recoil(pitch_deg: float, yaw_deg: float, recover: float) -> void:
	recoil_pitch += deg_to_rad(pitch_deg)
	recoil_yaw += deg_to_rad(yaw_deg)
	recoil_recover = recover


func _input(event: InputEvent) -> void:
	if not Game.dead:
		HoldInput.feed(event)
		if event.is_action_pressed("sprint") and not event.is_echo():
			HoldInput.release("aim")          # sprinting stops a toggled aim and a toggled crouch, as it does held ones
			HoldInput.release("crouch")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not Game.dead:
		var scale := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(Settings.fov) * 0.5)
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		yaw -= rel.x * Game.MOUSE_SENS * Settings.sens * scale
		pitch = clampf(pitch - rel.y * (-1.0 if Settings.invert_y else 1.0) * Game.MOUSE_SENS * Settings.sens * scale, deg_to_rad(-89.0), deg_to_rad(89.0))
		_look_delta += rel


## `cause` is what the death screen says if this hit kills ("SHOT BY A RIFLEMAN").
func take_damage(amount: float, from: Vector3 = Vector3.ZERO, cause: String = "") -> void:
	if Game.dead or Game.invulnerable or amount <= 0.0:
		return
	death_cause = cause
	health = maxf(0.0, health - amount)
	hurt_k = minf(1.0, hurt_k + 0.4 + amount / 40.0)
	roll += randf_range(-0.05, 0.05)
	Sfx.play(self, "hurt", -3.0)
	damaged.emit(amount, from)
	if health <= 0.0:
		Game.dead = true
		HoldInput.clear()
		died.emit()
		Game.player_died.emit()


## A story failure that ends the run at once, whatever the health ("MIRA WAS FOUND"): the death screen shows the reason.
func die(reason: String) -> void:
	if Game.dead:
		return
	health = 0.0
	death_cause = reason
	Game.dead = true
	HoldInput.clear()
	died.emit()
	Game.player_died.emit()


## A med kit is taken only when hurt and not already healing.
func can_heal() -> bool:
	return not Game.dead and heal_t <= 0.0 and health < Game.MAX_HEALTH


func start_heal() -> void:
	heal_t = HEAL_TIME
	_healed = 0.0
	Sfx.play(self, "bandage", -4.0)


## 0..1 progress of the current kit (HUD bar).
func heal_progress() -> float:
	return 1.0 - heal_t / HEAL_TIME if heal_t > 0.0 else 0.0


func _heal(delta: float) -> void:
	if heal_t <= 0.0:
		return
	if Game.dead:
		heal_t = 0.0
		return
	var step := minf(delta, heal_t)
	heal_t -= step
	var add := minf(HEAL_AMOUNT * step / HEAL_TIME, Game.MAX_HEALTH - health)
	health += add
	_healed += add
	if heal_t <= 0.0:
		weapons.notice = "+%d HEALTH" % int(round(_healed))
		weapons.notice_t = 2.0
		Sfx.play(self, "healed", -6.0)


## The wounded arm drips: a dark red spot on the floor every DRIP_SPACING metres walked (a standing player leaves one now and then).
## A ring of DRIP_MAX flat quads that share one mesh and one material, reused oldest first: no allocation after the first twelve.
const DRIP_MAX := 12
const DRIP_SPACING := 1.4
var drips: Array[MeshInstance3D] = []
var _drip_next := 0
var _drip_dist := 0.0
var _drip_idle := 0.0
static var _drip_mesh: QuadMesh = null


func _drip(delta: float) -> void:
	_drip_dist += Vector2(velocity.x, velocity.z).length() * delta
	_drip_idle += delta
	if not is_on_floor() or (_drip_dist < DRIP_SPACING and _drip_idle < 3.0):
		return
	_drip_dist = 0.0
	_drip_idle = 0.0
	place_drip(global_position)


func place_drip(at: Vector3) -> void:
	var mi: MeshInstance3D
	if drips.size() < DRIP_MAX:
		if _drip_mesh == null:
			_drip_mesh = QuadMesh.new()
			_drip_mesh.size = Vector2(0.32, 0.32)
			_drip_mesh.orientation = PlaneMesh.FACE_Y
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.32, 0.03, 0.03, 0.85)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			_drip_mesh.material = m
		mi = MeshInstance3D.new()
		mi.mesh = _drip_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(mi)
		drips.append(mi)
	else:
		mi = drips[_drip_next]
		_drip_next = (_drip_next + 1) % DRIP_MAX
	mi.global_position = Vector3(at.x + randf_range(-0.12, 0.12), at.y + 0.03, at.z + randf_range(-0.12, 0.12))
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3.ONE * randf_range(0.5, 1.1)
	mi.visible = true


func clear_drips() -> void:
	for d in drips:
		d.visible = false
	_drip_next = 0


func _can_stand() -> bool:
	var up := Vector3.UP * (Game.STAND_HEIGHT - shape.height + 0.02)
	return not test_move(global_transform, up)


func _physics_process(delta: float) -> void:
	# view
	rotation.y = yaw
	recoil_pitch = lerpf(recoil_pitch, 0.0, 1.0 - exp(-recoil_recover * delta))
	recoil_yaw = lerpf(recoil_yaw, 0.0, 1.0 - exp(-recoil_recover * delta))
	_heal(delta)

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

	# ---- ladders: walking into one while pressing forward attaches; the rest of the frame is the climb ----
	_climb_cool = maxf(0.0, _climb_cool - delta)
	if _mantle_t > 0.0:
		_mantle(delta)
		return
	if not climbing and Game.has_focus():
		_try_attach_ladder(input)
	if climbing:
		_climb(delta)
		return

	# ---- crouch / slide ----
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var crouch_held := HoldInput.held("crouch")
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
	if input.y >= -0.1:
		HoldInput.release("sprint")          # a toggled sprint ends when he stops running forward
	_sprinting = HoldInput.held("sprint") and input.y < -0.1 and crouch_k < 0.3 and on_floor and sliding <= 0.0 and not weapons.reloading and weapons.ads_k < 0.2
	var speed := Game.WALK_SPEED
	if _sprinting:
		speed = Game.SPRINT_SPEED
	elif crouch_k > 0.5:
		speed = Game.CROUCH_SPEED
	speed *= weapons.move_mult()
	if Game.arm_injured:
		speed *= Weapons.WOUND_MOVE          # a little slower with the wounded arm
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
	if Game.arm_injured:
		_drip(delta)

	# ---- landing ----
	on_floor = is_on_floor()
	if on_floor and not was_on_floor:
		var hurt_by_fall := 0.0
		if fall_speed > Game.FALL_DAMAGE_SPEED:
			hurt_by_fall = Player.fall_damage(fall_speed)
			take_damage(hurt_by_fall, Vector3.ZERO, "YOU FELL TO YOUR DEATH")
			# a hard landing: a pain grunt, a stronger camera dip and a shake that grow with the damage
			Sfx.play(self, "pain", -2.0 + minf(hurt_by_fall, 60.0) * 0.05)
			add_shake(8.0 + clampf(1.0 - hurt_by_fall / 70.0, 0.0, 1.0) * 14.0)
		if fall_speed > 4.0:
			land_dip = minf(0.25, fall_speed * 0.012) + minf(0.3, hurt_by_fall * 0.006)
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

	_update_camera(delta, on_floor, eye_y)


## Eased camera offsets, bob, shake, recoil and FOV (also used while climbing).
func _update_camera(delta: float, on_floor: bool, eye_y: float) -> void:
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
	shake = move_toward(shake, 0.0, delta * 1.2)
	var sh := shake * shake * 0.06
	head.rotation = Vector3(pitch + recoil_pitch + weapons.sway_view.x + randf_range(-sh, sh), recoil_yaw + weapons.sway_view.y + randf_range(-sh, sh), roll + slide_tilt + randf_range(-sh, sh) * 1.5)
	camera.fov = lerpf(Settings.fov + (4.0 if _sprinting else 0.0), float(weapons.stats()["ads_fov"]), weapons.ads_k)


## Damage from landing at `speed` m/s: nothing up to 15 m/s, then 5.5 per m/s (about 29 from 2 storeys, 75 from 4, 110 from 6).
static func fall_damage(speed: float) -> float:
	return clampf((speed - Game.FALL_DAMAGE_SPEED) * Game.FALL_DAMAGE_PER_MS, 0.0, Game.FALL_DAMAGE_MAX)


# ---------------------------------------------------------------- ladders

## Pressing forward while standing at the foot of a ladder and facing it (or at its top, facing down over the edge) attaches.
func _try_attach_ladder(input: Vector2) -> void:
	if input.y > -0.1 or sliding > 0.0 or crouch_k > 0.6 or _climb_cool > 0.0:
		return
	var look := Vector2(-sin(yaw), -cos(yaw))
	var p := Vector2(global_position.x, global_position.z)
	for l in City.ladders:
		var base: Vector3 = l["pos"]
		var n: Vector2 = l["n"]
		var to := p - Vector2(base.x, base.z)
		if to.length() > 1.8:
			continue
		var along := to.dot(n)                          # in front of the wall (positive) or over the roof (negative)
		var across := to.dot(Vector2(-n.y, n.x))
		if absf(across) > 0.6:
			continue
		var top: float = l["top"]
		if along >= 0.0 and along <= 1.1 and global_position.y <= base.y + 0.9 and look.dot(-n) > 0.35:
			_attach(l, global_position.y)
			return
		# from the roof: standing at the edge by the opening, looking out and down, pressing forward climbs down
		if along < 0.0 and along > -1.6 and absf(global_position.y - top) < 0.5 and look.dot(n) > 0.35 and pitch < deg_to_rad(-15.0):
			_attach(l, top - 0.05)
			return


func _attach(l: Dictionary, y: float) -> void:
	climbing = true
	ladder = l
	_climb_flip = 1.0 if y < float(l["top"]) - 0.5 else -1.0
	velocity = Vector3.ZERO
	sliding = 0.0
	crouch_k = 0.0
	shape.height = Game.STAND_HEIGHT
	col.position.y = Game.STAND_HEIGHT * 0.5
	was_on_floor = false
	fall_speed = 0.0
	_climb_dist = 0.0
	var base: Vector3 = l["pos"]
	var n: Vector2 = l["n"]
	global_position.y = y                             # the climb eases the player onto the rungs (no snap)
	Sfx.play(self, "climb", -8.0, randf_range(0.9, 1.1))


func _detach(push: Vector3 = Vector3.ZERO) -> void:
	climbing = false
	ladder = {}
	_climb_cool = 0.5
	velocity = push
	coyote = 0.0
	was_on_floor = false
	fall_speed = 0.0


## The climb: W / S move along the ladder at 2.5 m/s, Space jumps off backwards, reaching the top steps onto the roof.
func _climb(delta: float) -> void:
	var l := ladder
	var base: Vector3 = l["pos"]
	var n: Vector2 = l["n"]
	var top: float = l["top"]
	var up := 0.0
	if Game.has_focus():
		var face := Vector2(-sin(yaw), -cos(yaw)).dot(-n)       # >0 facing the wall, <0 facing out over the edge
		if face > 0.25:
			_climb_flip = 1.0
		elif face < -0.25:
			_climb_flip = -1.0
		up = Input.get_axis("move_back", "move_forward") * _climb_flip
	if Input.is_action_just_pressed("jump") and Game.has_focus():
		_detach(Vector3(n.x * 4.5, 3.0, n.y * 4.5))
		return
	var p := global_position
	var line := Vector2(base.x + n.x * 0.5, base.z + n.y * 0.5)
	var xz := Vector2(p.x, p.z).lerp(line, 1.0 - exp(-9.0 * delta))
	var y := p.y + up * Game.CLIMB_SPEED * delta
	if up != 0.0:
		_climb_dist += absf(up) * Game.CLIMB_SPEED * delta
		if _climb_dist >= 0.55:
			_climb_dist = 0.0
			Sfx.play(self, "climb", -10.0, randf_range(0.9, 1.15))
	if y >= top - 0.02 and up > 0.0:
		# over the top: step onto the roof 0.9 m in from the edge
		_mantle_from = global_position
		_mantle_to = Vector3(base.x - n.x * 0.9, top + 0.05, base.z - n.y * 0.9)
		_mantle_t = MANTLE_TIME
		return
	if y <= base.y + 0.02 and up < 0.0:
		global_position = Vector3(base.x + n.x * 0.55, base.y + 0.02, base.z + n.y * 0.55)
		_detach()
		return
	global_position = Vector3(xz.x, clampf(y, base.y, top), xz.y)
	_update_camera(delta, false, Game.STAND_HEIGHT - 0.12)


## What the HUD should hint at: 1 = a ladder to climb, 2 = a crouch passage ahead, 0 = nothing.
func context_hint() -> int:
	if climbing or Game.dead:
		return 0
	var look := Vector2(-sin(yaw), -cos(yaw))
	var p := Vector2(global_position.x, global_position.z)
	for l in City.ladders:
		var base: Vector3 = l["pos"]
		var to := Vector2(base.x, base.z) - p
		if to.length() < 2.4 and to.length() > 0.01 and look.dot(to.normalized()) > 0.7 and absf(global_position.y - base.y) < 1.0:
			return 1
	for c in City.crouch_passages:
		var cp: Vector3 = c["pos"]
		var to2 := Vector2(cp.x, cp.z) - p
		if to2.length() < 5.0 and to2.length() > 0.01 and look.dot(to2.normalized()) > 0.75 and crouch_k < 0.6 and absf(global_position.y - cp.y) < 1.5:
			return 2
	return 0


## Tries to hop onto a ledge (<= STEP_HEIGHT) in the direction of `motion`. Returns the height gained.
func _try_step(motion: Vector3) -> float:
	var xf := global_transform
	var hit := KinematicCollision3D.new()
	if not test_move(xf, motion, hit):
		return 0.0
	# a walkable slope is climbed by normal movement; stepping there only pushed the body above the ground
	if hit.get_normal().y >= cos(floor_max_angle) - 0.01:
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


## Over the top of a ladder: a short eased hop onto the roof instead of a jump cut.
func _mantle(delta: float) -> void:
	_mantle_t = maxf(0.0, _mantle_t - delta)
	var k := smoothstep(0.0, 1.0, 1.0 - _mantle_t / MANTLE_TIME)
	var p := _mantle_from.lerp(_mantle_to, k)
	p.y += sin(k * PI) * 0.25
	global_position = p
	velocity = Vector3.ZERO
	_update_camera(delta, false, Game.STAND_HEIGHT - 0.12)
	if _mantle_t <= 0.0:
		_detach()
		Sfx.play(self, "land", -14.0)
