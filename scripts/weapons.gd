class_name Weapons
extends Node3D
## Pistol + rifle: hitscan with spread/bloom/recoil/falloff, magazines, reload, ADS, viewmodels, tracers, casings.
## Sits under the player's camera. Logic runs in _physics_process, visuals in _process.

signal hit_marker(headshot: bool, killed: bool)
signal fired(id: String)

const HIP_POS := Vector3(0.2, -0.2, -0.5)
const MAX_CASINGS := 40

var player: Player
var camera: Camera3D
var holder: Node3D
var models := {}              # id -> Node3D viewmodel (children of holder)
var muzzles := {}             # id -> Marker3D
var state := {}               # id -> {"ammo": int, "spare": Array[int]}
var current := "pistol"

var cooldown := 0.0
var reloading := false
var reload_t := 0.0
var _reload_sound_stage := 0
var switching := 0.0
var pending := ""
var ads_k := 0.0
var bloom := 0.0              # extra spread (deg) from firing, decays fast
var kick := 0.0               # viewmodel push-back
var kick_pitch := 0.0
var sway := Vector2.ZERO
var bob_t := 0.0
var empty_click_cd := 0.0
var _trigger_was_down := false

var flash_light: OmniLight3D
var flash_node: Node3D
var flash_t := 0.0
var _casings: Array = []
var _rng := RandomNumberGenerator.new()


func setup(p: Player, cam: Camera3D) -> void:
	player = p
	camera = cam
	_rng.randomize()
	holder = Node3D.new()
	holder.position = HIP_POS
	camera.add_child(holder)

	for id in WeaponsDB.ORDER:
		var w: Dictionary = WeaponsDB.WEAPONS[id]
		var spare: Array[int] = []
		for i in int(w["spare_mags"]):
			spare.append(int(w["mag"]))
		state[id] = {"ammo": int(w["mag"]), "spare": spare}
		var model := _build_model(w)
		model.visible = false
		holder.add_child(model)
		models[id] = model
		var m := Marker3D.new()
		m.position = Vector3(0, float(w["top_y"]) - 0.03, float(w["center_z"]) - float(w["length"]) * 0.5 - 0.02)
		model.add_child(m)
		muzzles[id] = m

	# one muzzle flash for everything, re-parented to the active muzzle
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.75, 0.4)
	flash_light.light_energy = 4.0
	flash_light.omni_range = 9.0
	flash_light.shadow_enabled = false
	flash_light.visible = false
	flash_node = Node3D.new()
	flash_node.visible = false
	flash_node.add_child(flash_light)
	var fm := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var glow := Gradient.new()
	glow.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	glow.set_color(1, Color(1.0, 0.55, 0.15, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = glow
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 64
	gtex.height = 64
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_texture = gtex
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.no_depth_test = true
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.material = fmat
	fm.mesh = quad
	flash_node.add_child(fm)
	muzzles[current].add_child(flash_node)
	_show_only(current)


func _show_only(id: String) -> void:
	for k in models:
		models[k].visible = (k == id)
	if flash_node.get_parent() != muzzles[id]:
		flash_node.get_parent().remove_child(flash_node)
		muzzles[id].add_child(flash_node)
		flash_node.position = Vector3.ZERO


# ---------------------------------------------------------------- viewmodel loading

static func _collect_aabb(node: Node, xf: Transform3D, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var a: AABB = xf * mi.mesh.get_aabb() if mi.mesh else AABB()
		if mi.mesh:
			out.append(a)
	for c in node.get_children():
		if c is Node3D:
			_collect_aabb(c, xf * (c as Node3D).transform, out)


static func _aabb_of(node: Node3D) -> AABB:
	var list: Array = []
	_collect_aabb(node, Transform3D.IDENTITY, list)
	if list.is_empty():
		return AABB()
	var box: AABB = list[0]
	for i in range(1, list.size()):
		box = box.merge(list[i])
	return box


func _build_model(w: Dictionary) -> Node3D:
	var root := Node3D.new()
	var scene: PackedScene = null
	if ResourceLoader.exists(String(w["model"])):
		scene = load(String(w["model"])) as PackedScene
	if scene == null:
		_blocky(root, w)
		return root
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	if float(w["mirror_z"]) != 0.0:
		# half-models (the pistol) are built on one side of a plane: add a mirrored twin so it is solid
		var twin := scene.instantiate() as Node3D
		model.add_child(twin)
		twin.position.z = 2.0 * float(w["mirror_z"])
		twin.scale.z = -1.0
	model.rotation.y = deg_to_rad(float(w["rot_y"]))
	var size := _aabb_of(root).size
	var s := float(w["length"]) / maxf(size.x, size.z)
	model.scale = Vector3.ONE * s
	var box := _aabb_of(root)
	var c := box.get_center()
	model.position = Vector3(-c.x, float(w["top_y"]) - box.end.y, float(w["center_z"]) - c.z)
	return root


func _blocky(root: Node3D, w: Dictionary) -> void:
	var col: Color = w["color"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.5
	mat.metallic = 0.6
	var len := float(w["length"])
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.07, len)
	body.mesh = bm
	body.material_override = mat
	body.position = Vector3(0, float(w["top_y"]) - 0.035, float(w["center_z"]))
	root.add_child(body)
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.04, 0.12, 0.05)
	grip.mesh = gm
	grip.material_override = mat
	grip.position = Vector3(0, float(w["top_y"]) - 0.12, float(w["center_z"]) + len * 0.3)
	grip.rotation_degrees.x = 12
	root.add_child(grip)


# ---------------------------------------------------------------- queries used by the player / HUD

func stats() -> Dictionary:
	return WeaponsDB.WEAPONS[current]


func ammo() -> int:
	return state[current]["ammo"]


func reserve() -> int:
	var total := 0
	for m in state[current]["spare"]:
		total += int(m)
	return total


func spare_mags() -> int:
	return (state[current]["spare"] as Array).size()


func move_mult() -> float:
	return lerpf(1.0, float(stats()["ads_move"]), ads_k)


func current_spread() -> float:
	var s := stats()
	var spread := lerpf(float(s["spread_hip"]), float(s["spread_ads"]), ads_k)
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	spread += float(s["spread_move"]) * clampf(hspeed / Game.WALK_SPEED, 0.0, 1.5) * lerpf(1.0, 0.35, ads_k)
	if not player.is_on_floor():
		spread += 3.0
	if player.crouch_k > 0.5:
		spread *= 0.75
	spread += bloom
	return spread


func can_aim() -> bool:
	return not reloading and switching <= 0.0 and not player.is_sprinting() and not Game.dead


# ---------------------------------------------------------------- logic

func _physics_process(delta: float) -> void:
	if Game.dead:
		return
	cooldown = maxf(0.0, cooldown - delta)
	empty_click_cd = maxf(0.0, empty_click_cd - delta)
	bloom = move_toward(bloom, 0.0, delta * 6.0)

	# ADS
	var want_ads := Input.is_action_pressed("aim") and can_aim()
	var rate := 1.0 / maxf(0.05, float(stats()["ads_time"]))
	ads_k = move_toward(ads_k, 1.0 if want_ads else 0.0, rate * delta)

	# weapon switching
	if switching > 0.0:
		var before := switching
		switching -= delta
		if before > 0.15 and switching <= 0.15 and pending != "":
			current = pending
			pending = ""
			_show_only(current)
			Sfx.play(self, "bolt", -14.0, 0.9)
	else:
		if Input.is_action_just_pressed("slot_1"):
			switch_to("pistol")
		elif Input.is_action_just_pressed("slot_2"):
			switch_to("rifle")
		elif Input.is_action_just_pressed("cycle_weapon") or Input.is_action_just_pressed("wheel_up") or Input.is_action_just_pressed("wheel_down"):
			switch_to("rifle" if current == "pistol" else "pistol")

	# reload
	if reloading:
		reload_t += delta
		var total := float(stats()["reload_time"])
		var k := reload_t / total
		if _reload_sound_stage == 0 and k > 0.25:
			_reload_sound_stage = 1
			Sfx.play(self, "mag_out", -8.0)
		elif _reload_sound_stage == 1 and k > 0.62:
			_reload_sound_stage = 2
			Sfx.play(self, "mag_in", -6.0)
		if reload_t >= total:
			_finish_reload()
	elif Input.is_action_just_pressed("reload"):
		start_reload()

	# firing
	var s := stats()
	var down := Input.is_action_pressed("fire")
	var pressed := down and not _trigger_was_down
	_trigger_was_down = down
	if down and switching <= 0.0 and not reloading and not player.is_sprinting() and Game.has_focus():
		if bool(s["auto"]) or pressed:
			if cooldown <= 0.0:
				if int(state[current]["ammo"]) > 0:
					_fire_shot()
				elif empty_click_cd <= 0.0:
					Sfx.play(self, "click", -6.0)
					empty_click_cd = 0.3
					if pressed:
						start_reload()


func switch_to(id: String) -> void:
	if id == current or switching > 0.0 or Game.dead:
		return
	reloading = false
	reload_t = 0.0
	ads_k = 0.0
	pending = id
	switching = 0.32


func start_reload() -> void:
	if reloading or switching > 0.0:
		return
	var st: Dictionary = state[current]
	if int(st["ammo"]) >= int(stats()["mag"]):
		return
	var has_ammo := false
	for m in st["spare"]:
		if int(m) > 0:
			has_ammo = true
	if not has_ammo:
		return
	reloading = true
	reload_t = 0.0
	_reload_sound_stage = 0
	ads_k = 0.0


func _finish_reload() -> void:
	reloading = false
	reload_t = 0.0
	var st: Dictionary = state[current]
	var spare: Array = st["spare"]
	var best := -1
	for i in spare.size():
		if best < 0 or int(spare[i]) > int(spare[best]):
			best = i
	if best < 0:
		return
	var fresh := int(spare[best])
	spare.remove_at(best)
	var left := int(st["ammo"])
	if left > 0:
		# tactical reload: the partly used magazine goes back into the pouch and a round stays chambered
		spare.append(left)
		fresh = mini(fresh + 1, int(stats()["mag"]) + 1)
	st["ammo"] = fresh


func add_ammo_mags(n: int) -> void:
	for id in state:
		for i in n:
			(state[id]["spare"] as Array).append(int(WeaponsDB.WEAPONS[id]["mag"]))


func _fire_shot() -> void:
	var s := stats()
	var st: Dictionary = state[current]
	st["ammo"] = int(st["ammo"]) - 1
	cooldown = 60.0 / float(s["rpm"])
	Game.shots_fired += 1

	var spread_deg := current_spread()
	bloom = minf(bloom + float(s["spread_per_shot"]), float(s["spread_max_bloom"]))

	var cam_xf := camera.global_transform
	var origin := cam_xf.origin
	var dir := _spread_dir(cam_xf.basis, spread_deg)
	var to := origin + dir * 400.0
	var q := PhysicsRayQueryParameters3D.create(origin, to, Game.L_WORLD | Game.L_HITBOX)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var space := player.get_world_3d().direct_space_state
	var hit := space.intersect_ray(q)

	var muzzle_pos: Vector3 = (muzzles[current] as Node3D).global_position
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var dist := origin.distance_to(end)
		var collider: Object = hit["collider"]
		if collider is Area3D and (collider as Area3D).has_meta("part"):
			var part: String = (collider as Area3D).get_meta("part")
			var enemy: Enemy = (collider as Area3D).get_meta("enemy")
			var f := 1.0
			if dist > float(s["falloff_start"]):
				f = lerpf(1.0, float(s["falloff_min"]), clampf((dist - float(s["falloff_start"])) / (float(s["falloff_end"]) - float(s["falloff_start"])), 0.0, 1.0))
			var dmg := float(s["damage"]) * f * (float(s["head_mult"]) if part == "head" else 1.0)
			if part == "legs":
				dmg *= 0.75
			Game.shots_hit += 1
			var killed := enemy.take_hit(dmg, part, dir * float(s["impulse"]), end)
			hit_marker.emit(part == "head", killed)
			Sfx.play(self, "headshot" if part == "head" else "hit", -4.0)
			Sfx.play_at(get_tree().current_scene, end, "thump", -2.0)
		else:
			_spawn_impact(end, hit["normal"])
			Sfx.play_at(get_tree().current_scene, end, "impact", -4.0, randf_range(0.9, 1.1))

	_tracer(muzzle_pos, end)
	_eject_casing()
	_muzzle_flash()
	Sfx.play(self, current, -2.0, randf_range(0.97, 1.03))
	Game.gunshot.emit(origin, float(s["loudness"]))
	fired.emit(current)

	# recoil: the view itself climbs and has to be pulled back down; ADS tames it
	var tame := lerpf(1.0, 0.7, ads_k)
	player.add_recoil(float(s["recoil_pitch"]) * tame * _rng.randf_range(0.85, 1.15), _rng.randf_range(-1.0, 1.0) * float(s["recoil_yaw"]) * tame, float(s["recoil_recover"]))
	kick = minf(kick + 0.035 * (1.0 - ads_k * 0.5), 0.08)
	kick_pitch = minf(kick_pitch + 0.07 * (1.0 - ads_k * 0.4), 0.2)

	if int(st["ammo"]) <= 0 and reserve() > 0:
		# empty: ready to reload on the next trigger pull (the click will start it)
		pass


func _spread_dir(basis: Basis, spread_deg: float) -> Vector3:
	var ang := deg_to_rad(spread_deg) * sqrt(_rng.randf())
	var rot := _rng.randf() * TAU
	var d := -basis.z
	d = d.rotated(basis.x, sin(rot) * ang)
	d = d.rotated(basis.y, cos(rot) * ang)
	return d.normalized()


func _tracer(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.004, 0.004, minf(len, 3.0))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.45)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var scene := get_tree().current_scene
	scene.add_child(mi)
	# the streak is a short segment that flies from the muzzle to the target
	var dir := (to - from).normalized()
	var seg := minf(len, 3.0)
	mi.global_position = from + dir * seg * 0.5
	mi.look_at(to, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var travel := maxf(0.0, len - seg)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", from + dir * (travel + seg * 0.5), clampf(len / 420.0, 0.03, 0.2))
	tw.tween_callback(mi.queue_free)


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 55.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12, 0)
	var m := BoxMesh.new()
	m.size = Vector3(0.03, 0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.36, 0.25)
	m.material = mat
	p.mesh = m
	p.finished.connect(p.queue_free)
	get_tree().current_scene.add_child(p)
	p.global_position = pos + normal * 0.03


func _muzzle_flash() -> void:
	flash_t = 0.045
	flash_node.visible = true
	flash_light.visible = true
	flash_node.rotation.z = _rng.randf() * TAU


func _eject_casing() -> void:
	var w := stats()
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = Game.L_WORLD
	rb.continuous_cd = true
	rb.mass = 0.02
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.6
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.012, 0.012, 0.04)
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.2)
	mat.metallic = 0.8
	mat.roughness = 0.35
	bm.material = mat
	mi.mesh = bm
	rb.add_child(mi)
	get_tree().current_scene.add_child(rb)
	var port: Vector3 = holder.global_transform * Vector3(0.04, float(w["top_y"]) - 0.02, float(w["center_z"]) - 0.02)
	rb.global_position = port
	var b := camera.global_transform.basis
	rb.linear_velocity = player.velocity * 0.6 + b.x * _rng.randf_range(1.8, 3.0) + b.y * _rng.randf_range(1.0, 2.2) + b.z * _rng.randf_range(-0.3, 0.6)
	rb.angular_velocity = Vector3(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30), _rng.randf_range(-30, 30))
	_casings.append(rb)
	if _casings.size() > MAX_CASINGS:
		var old = _casings.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var life := Timer.new()
	life.wait_time = 5.0
	life.one_shot = true
	life.autostart = true
	life.timeout.connect(rb.queue_free)
	rb.add_child(life)


# ---------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			flash_node.visible = false
			flash_light.visible = false

	var s := stats()
	kick = move_toward(kick, 0.0, delta * 0.5)
	kick_pitch = lerpf(kick_pitch, 0.0, 1.0 - exp(-12.0 * delta))
	sway = sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	sway += player.consume_look_delta() * Vector2(-0.0007, -0.0007)
	sway = sway.limit_length(0.05)

	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	var moving := player.is_on_floor() and hspeed > 0.5
	bob_t += delta * (hspeed * 1.5 if moving else 0.0)
	var bob_amt := (0.006 + 0.004 * clampf(hspeed / Game.SPRINT_SPEED, 0.0, 1.0)) * (1.0 - ads_k * 0.85)
	var bob := Vector3(sin(bob_t) * bob_amt, absf(cos(bob_t)) * bob_amt * 0.8, 0.0)

	var ads_pos: Vector3 = s["ads_pos"]
	var pos := HIP_POS.lerp(ads_pos, ads_k) + bob + Vector3(sway.x, sway.y, 0.0) + Vector3(0, 0, kick)
	var rot := Vector3(kick_pitch, 0, 0)

	if player.is_sprinting():
		pos += Vector3(0.05, -0.06, 0.02)
		rot += Vector3(0.0, 0.45, 0.15)

	if reloading:
		var k := clampf(reload_t / float(s["reload_time"]), 0.0, 1.0)
		var dip := sin(PI * k)
		pos += Vector3(-0.04 * dip, -0.16 * dip, 0.03 * dip)
		rot += Vector3(-0.55 * dip, 0.15 * dip, 0.5 * dip)
	if switching > 0.0:
		var k2 := 1.0 - absf(switching / 0.32 * 2.0 - 1.0)   # 0 -> 1 -> 0
		pos += Vector3(0.0, -0.45 * k2, 0.1 * k2)
		rot += Vector3(-0.7 * k2, 0.0, 0.0)

	holder.position = holder.position.lerp(pos, 1.0 - exp(-30.0 * delta))
	holder.rotation = holder.rotation.lerp(rot, 1.0 - exp(-24.0 * delta))
