class_name Grenade
extends RigidBody3D
## A thrown frag grenade. A RigidBody3D node (so it is a proper physics object in the tree), but it is frozen and moved by
## `sim_step()` every physics tick: the aiming preview (`predict()`) runs the very same step function, so the dotted arc and
## the ring where it will rest are exactly where the real grenade goes. Bounces off the world with damping, fuse 2.5 s from
## the release, blinking red light. `detonate()` does the blast: damage that falls off with distance and is blocked by walls
## (enemies and the player), push, camera shake, flash, fireball, smoke, debris, a scorch mark, the boom and `Game.gunshot`.

const GRAVITY := 18.0
const FUSE := 2.5
const RADIUS := 7.0               # blast radius (m)
const DAMAGE := 140.0             # at the centre, linear to 0 at the edge
const PUSH := 14.0                # impulse on enemies at the centre (decreases with distance)
const THROW_SPEED := 16.0
const BODY_R := 0.1               # collision radius used by the step function
const BOUNCE := 0.4               # share of the normal speed that comes back after an impact
const FRICTION_KEEP := 0.6        # share of the sideways speed that survives an impact
const REST_SPEED := 1.2           # slower than this after an impact on a floor = at rest
const LOUDNESS := 140.0           # Game.gunshot loudness: enemies within loudness * 0.45 (63 m) hear it
const ORIGIN_LIFT := 0.7          # the blast goes off this far above the resting grenade: low crates and kerbs do not shield (it was 0.15 and a crate hid a man)
const SCORCH_LIFE := 60.0
const SCORCH_MAX := 12
static var scorches: Array = []

var vel := Vector3.ZERO
var fuse := FUSE
var resting := false
var landed := false
var first_land := Vector3.INF     # where it first touched a floor
var rest_pos := Vector3.INF
var _lamp: MeshInstance3D
var _light: OmniLight3D
var _spin := Vector3.ZERO


## Call BEFORE add_child (position first, as everything physical in this project).
func setup(pos: Vector3, velocity: Vector3) -> void:
	position = pos
	vel = velocity
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 0
	collision_mask = 0
	_spin = Vector3(randf_range(-9.0, 9.0), randf_range(-3.0, 3.0), randf_range(-9.0, 9.0))


func _ready() -> void:
	var model := build_model()
	add_child(model)
	_lamp = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.02
	sm.height = 0.04
	sm.radial_segments = 6
	sm.rings = 3
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.1, 0.05)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = lm
	_lamp.mesh = sm
	_lamp.position = Vector3(0, 0.075, 0)
	model.add_child(_lamp)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.15, 0.1)
	_light.omni_range = 2.0
	_light.light_energy = 1.2
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.12, 0)
	add_child(_light)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = BODY_R
	cs.shape = shape
	add_child(cs)


## Low-poly grenade: a cylinder body, a small lever box and a pin ring (also used for the viewmodel and the pickup).
static func build_model() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.042
	cm.bottom_radius = 0.045
	cm.height = 0.11
	cm.radial_segments = 8
	cm.rings = 1
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.25, 0.3, 0.17)
	bmat.roughness = 0.9
	cm.material = bmat
	body.mesh = cm
	root.add_child(body)
	var lever := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.016, 0.075, 0.022)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.6, 0.6, 0.62)
	lmat.metallic = 0.5
	lb.material = lmat
	lever.mesh = lb
	lever.position = Vector3(0.05, 0.03, 0.0)
	root.add_child(lever)
	var cap := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.05, 0.03, 0.05)
	cb.material = lmat
	cap.mesh = cb
	cap.position = Vector3(0, 0.07, 0)
	root.add_child(cap)
	return root


func _physics_process(delta: float) -> void:
	if not resting:
		var space := get_world_3d().direct_space_state
		var before := vel
		var r := sim_step(space, global_position, vel, delta)
		global_position = r["pos"]
		vel = r["vel"]
		rotation += _spin * delta
		if bool(r["hit"]):
			var n: Vector3 = r["normal"]
			if absf(before.dot(n)) > 2.0:
				Sfx.play_at(get_tree().current_scene, global_position, "clink", -4.0, randf_range(0.85, 1.15), 40.0)
			_spin *= 0.6
			if not landed and n.y > 0.5:
				landed = true
				first_land = global_position
				Game.grenade_landed.emit(global_position)
		if bool(r["rest"]):
			resting = true
			rest_pos = global_position
			if not landed:
				landed = true
				first_land = global_position
				Game.grenade_landed.emit(global_position)
	fuse -= delta
	# blink faster as the fuse runs down
	var rate := lerpf(4.0, 14.0, 1.0 - clampf(fuse / FUSE, 0.0, 1.0))
	var on := int(floor((FUSE - fuse) * rate)) % 2 == 0
	_lamp.visible = on
	_light.visible = on
	if fuse <= 0.0:
		var at := global_position
		var scene := get_tree().current_scene
		queue_free()
		detonate(scene, at)


## One tick of the grenade's motion: gravity, then a ray along the step; an impact bounces it (normal part x BOUNCE, sideways
## part x FRICTION_KEEP) and puts it to rest when it is slow on a floor. Returns {pos, vel, hit, normal, rest}.
static func sim_step(space: PhysicsDirectSpaceState3D, pos: Vector3, velocity: Vector3, dt: float) -> Dictionary:
	var v := velocity
	v.y -= GRAVITY * dt
	var next := pos + v * dt
	var out := {"pos": next, "vel": v, "hit": false, "normal": Vector3.UP, "rest": false}
	var dir := v.normalized()
	var q := PhysicsRayQueryParameters3D.create(pos, next + dir * BODY_R, Game.L_WORLD)
	var h := space.intersect_ray(q)
	if h.is_empty():
		return out
	var n: Vector3 = h["normal"]
	var vn := v.dot(n)
	var vt := v - n * vn
	var nv := vt * FRICTION_KEEP - n * vn * BOUNCE
	out["pos"] = (h["position"] as Vector3) + n * BODY_R
	out["hit"] = true
	out["normal"] = n
	if nv.length() < REST_SPEED and n.y > 0.7:
		out["rest"] = true
		nv = Vector3.ZERO
	out["vel"] = nv
	return out


## The preview: simulates the same steps. {points: every few steps along the way, land: first floor contact, rest: where it stops}.
static func predict(space: PhysicsDirectSpaceState3D, from: Vector3, velocity: Vector3, max_time: float = FUSE) -> Dictionary:
	var pts := PackedVector3Array()
	var pos := from
	var v := velocity
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var t := 0.0
	var land := Vector3.INF
	var steps := 0
	while t < max_time:
		var r := sim_step(space, pos, v, dt)
		pos = r["pos"]
		v = r["vel"]
		t += dt
		steps += 1
		if bool(r["hit"]) and land == Vector3.INF and (r["normal"] as Vector3).y > 0.5:
			land = pos
		if steps % 5 == 0:
			pts.append(pos)
		if bool(r["rest"]):
			if land == Vector3.INF:
				land = pos
			break
	return {"points": pts, "land": land, "rest": pos}


# ---------------------------------------------------------------- the blast

## Damage at distance d from the blast: 140 at the centre, linear to 0 at RADIUS.
static func damage_at(d: float) -> float:
	return DAMAGE * clampf(1.0 - d / RADIUS, 0.0, 1.0)


static func detonate(scene: Node, pos: Vector3) -> void:
	Game.mark("explosion")
	var space := (scene as Node3D).get_world_3d().direct_space_state
	var origin := pos + Vector3(0, ORIGIN_LIFT, 0)
	# enemies: only those with a clear ray from the blast point (walls protect)
	for e in Game.enemies.duplicate():
		var en := e as Enemy
		if not is_instance_valid(en) or en.state == Enemy.State.DEAD:
			continue
		var target := en.global_position + Vector3(0, 1.0 * en.body_scale, 0)
		var d := origin.distance_to(target)
		if d >= RADIUS:
			continue
		if not _exposed(space, origin, en.global_position, en.body_scale):
			continue
		var k := 1.0 - d / RADIUS
		var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
		flat = flat.normalized() if flat.length() > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		en.take_hit(damage_at(d), "body", flat * PUSH * (0.4 + k) + Vector3(0, 6.0 * k, 0), target)
	# civilians too (and the player is told)
	for cv_node in Game.civilians.duplicate():
		var cv := cv_node as Civilian
		if not is_instance_valid(cv) or cv.state == Civilian.State.DEAD:
			continue
		var ctarget := cv.chest_pos()
		var cd := origin.distance_to(ctarget)
		if cd >= RADIUS or not _exposed(space, origin, cv.global_position, 1.0):
			continue
		var cflat := Vector3(ctarget.x - origin.x, 0.0, ctarget.z - origin.z).normalized()
		cv.take_hit(damage_at(cd), "body", cflat * PUSH, ctarget)
		if Game.player != null:
			(Game.player as Player).weapons.notice = "CIVILIAN HIT"
			(Game.player as Player).weapons.notice_t = 2.5
	# the player is hurt by his own grenades too
	var pl := Game.player as Player
	if pl != null and not Game.dead:
		var chest := pl.global_position + Vector3(0, 1.0, 0)
		var pd := origin.distance_to(chest)
		pl.add_shake(pos.distance_to(pl.global_position))
		if pd < RADIUS and _exposed(space, origin, pl.global_position, 1.0):
			pl.take_damage(damage_at(pd), pos, "KILLED BY A GRENADE")
	Game.exploded.emit(pos)
	Game.gunshot.emit(pos, LOUDNESS)
	Sfx.play_at(scene, pos, "explosion", 6.0, 1.0, 220.0)
	_effects(scene, pos)


static func _radial_texture(inner: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


static func _effects(scene: Node, pos: Vector3) -> void:
	var tree := scene.get_tree()
	# flash
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.5)
	flash.light_energy = 10.0
	flash.omni_range = 18.0
	flash.shadow_enabled = false
	scene.add_child(flash)
	flash.global_position = pos + Vector3(0, 1.0, 0)
	tree.create_timer(0.15).timeout.connect(flash.queue_free)
	# fireball: a billboard quad with a radial gradient that grows and fades
	var fb := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = _radial_texture(Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.35, 0.05, 0.0))
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = fm
	fb.mesh = quad
	fb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(fb)
	fb.global_position = pos + Vector3(0, 0.9, 0)
	fb.scale = Vector3.ONE * 1.5
	var tw := fb.create_tween().set_parallel(true)
	tw.tween_property(fb, "scale", Vector3.ONE * 10.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fm, "albedo_color:a", 0.0, 0.45).set_delay(0.1)
	tw.chain().tween_callback(fb.queue_free)
	# smoke
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.emitting = true
	smoke.amount = 22
	smoke.lifetime = 2.6
	smoke.explosiveness = 0.7
	smoke.direction = Vector3.UP
	smoke.spread = 35.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 5.0
	smoke.gravity = Vector3(0, 0.8, 0)
	smoke.scale_amount_min = 1.2
	smoke.scale_amount_max = 2.6
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.22, 0.22, 0.24, 0.55)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.roughness = 1.0
	sm.material = smat
	smoke.mesh = sm
	smoke.finished.connect(smoke.queue_free)
	scene.add_child(smoke)
	smoke.global_position = pos + Vector3(0, 0.5, 0)
	# debris
	var deb := CPUParticles3D.new()
	deb.one_shot = true
	deb.emitting = true
	deb.amount = 28
	deb.lifetime = 1.4
	deb.explosiveness = 1.0
	deb.direction = Vector3.UP
	deb.spread = 70.0
	deb.initial_velocity_min = 6.0
	deb.initial_velocity_max = 14.0
	deb.gravity = Vector3(0, -18.0, 0)
	deb.angular_velocity_min = -400.0
	deb.angular_velocity_max = 400.0
	var dm := BoxMesh.new()
	dm.size = Vector3(0.14, 0.1, 0.12)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.18, 0.16, 0.14)
	dm.material = dmat
	deb.mesh = dm
	deb.finished.connect(deb.queue_free)
	scene.add_child(deb)
	deb.global_position = pos + Vector3(0, 0.3, 0)
	# scorch mark on the ground, stays 60 s, fades out in the last 6
	var ground := pos
	var hit := (scene as Node3D).get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.6, 0), pos + Vector3(0, -2.0, 0), Game.L_WORLD))
	if not hit.is_empty():
		ground = hit["position"]
	var sc := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(6.5, 6.5)
	var scm := StandardMaterial3D.new()
	scm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scm.albedo_texture = _radial_texture(Color(0.02, 0.02, 0.02, 0.85), Color(0.02, 0.02, 0.02, 0.0))
	sq.material = scm
	sc.mesh = sq
	sc.rotation.x = -PI * 0.5
	sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(sc)
	sc.global_position = Vector3(pos.x, maxf(ground.y, 0.0) + 0.125, pos.z)      # above floor slabs (up to 0.11)
	scorches.append(sc)
	while scorches.size() > SCORCH_MAX:
		var old = scorches.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var stw := sc.create_tween()
	stw.tween_interval(SCORCH_LIFE - 6.0)
	stw.tween_property(scm, "albedo_color:a", 0.0, 6.0)
	stw.tween_callback(sc.queue_free)


## Is a person standing at `feet` hit by a blast at `origin`? He is if the blast has a clear line to his feet, chest or head: only a wall
## or a high cover shields him, not a crate in front of him.
static func _exposed(space: PhysicsDirectSpaceState3D, origin: Vector3, feet: Vector3, scale: float) -> bool:
	for h in [0.25, 1.0, 1.6]:
		var target := feet + Vector3(0.0, h * scale, 0.0)
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target, Game.L_WORLD)).is_empty():
			return true
	return false
