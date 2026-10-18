class_name ShipModels
## Procedural landing craft, in the style of GunModels: boxes and cylinders merged into ONE cached two-surface mesh (lit + glowing)
## per detail level, so the ship in the park costs one draw call (plus its ground patch and two heat-shimmer quads).
## The craft is blunt, grey and boxy, on four short legs, with two engine pods and a lowered rear ramp that leads into a short
## vestibule: the interior itself is not modelled (a dark alcove behind a lit loading threshold: `Lander.threshold` is the area a
## later interior level hooks into).
##
## Model space: the nose is -z, the ramp at the back (+z), the ground is y = 0, the middle of the hull z = 0. World placement
## turns it (`City.LANDER_YAW`). `lander_boxes()` is the collision box set in the same space; `site_mesh()` the ground it landed
## on (scorch ring, crushed flowerbeds, fallen trees), cached too.

const LENGTH := 20.5                 # nose to the back wall (the ramp reaches 6 m further)
const WIDTH := 10.0                  # the hull (the engine pods stick out to +-7.3 m)
const HEIGHT := 6.0                  # the collision top (the dorsal block rises 0.8 m above it)
const SILL_Y := 1.5                  # the floor of the doorway; the ramp climbs from the ground to here
const RAMP_LEN := 6.0
const DOOR_W := 4.6
const NEAR_LOD_DIST := 85.0          # nearer than this the detailed mesh is shown

const HULL := Color(0.5, 0.52, 0.53)
const HULL2 := Color(0.41, 0.43, 0.45)
const PLATE := Color(0.57, 0.58, 0.58)
const DARKP := Color(0.2, 0.21, 0.23)
const RUSTY := Color(0.47, 0.27, 0.16)
const SOOT := Color(0.08, 0.075, 0.07)
const ORANGE := Color(1.0, 0.55, 0.2)
const COLD := Color(0.78, 0.9, 1.0)
const GLASS := Color(0.16, 0.34, 0.4)

static var _meshes := {}             # "lander:2" / "lander:1" / "site" -> ArrayMesh


## The hull as one mesh. lod 2 adds panel plating, vents, rivet rows, a turret and the ramp ribs.
static func lander_mesh(lod: int) -> ArrayMesh:
	var key := "lander:%d" % lod
	if not _meshes.has(key):
		_meshes[key] = _build_lander(lod).mesh()
	return _meshes[key]


static func _build_lander(lod: int) -> GunModels.Builder:
	var b := GunModels.Builder.new()
	var rot_ramp := Basis(Vector3.RIGHT, atan2(SILL_Y, RAMP_LEN))
	# belly, body, nose and dorsal block
	b.box(Vector3(0, 0.95, -1.0), Vector3(8.2, 0.9, 19.0), SOOT)                                         # scorched underbelly
	b.box(Vector3(0, 3.55, -1.75), Vector3(WIDTH, 4.1, 17.5), HULL)                                       # the main body, z -10.5 .. 7
	b.box(Vector3(0, 3.5, 8.5), Vector3(WIDTH, 4.0, 3.0), HULL2)                                          # the rear block with the doorway cut out (below)
	b.box(Vector3(0, 3.5, 8.5), Vector3(DOOR_W, 4.1, 3.2), DARKP)                                         # ...a dark alcove...
	b.box(Vector3(0, SILL_Y + 0.02, 8.5), Vector3(DOOR_W - 0.1, 0.04, 3.0), HULL2)                        # ...with a floor
	b.box(Vector3(0, 5.55, 8.5), Vector3(DOOR_W + 0.4, 0.9, 3.05), HULL)                                  # header over the door
	b.box(Vector3(0, 3.3, 7.06), Vector3(DOOR_W - 0.3, 3.0, 0.1), Color(0.1, 0.1, 0.12))                  # the alcove's back wall (the interior lies behind)
	b.box(Vector3(0, 2.1, 7.0), Vector3(DOOR_W - 0.3, 0.14, 0.12), COLD, true)                            # the loading threshold: a cold white line
	b.box(Vector3(0, 4.7, 8.4), Vector3(DOOR_W - 0.5, 0.1, 1.4), COLD, true)                              # ...and a strip light in the ceiling
	b.box(Vector3(0, 6.4, -0.5), Vector3(6.2, 1.0, 11.0), HULL2)                                          # dorsal block
	b.box(Vector3(0, 5.95, -9.6), Vector3(9.4, 0.5, 3.4), PLATE, false, Basis(Vector3.RIGHT, -0.28))      # the sloped nose cap
	b.box(Vector3(0, 3.0, -10.85), Vector3(9.4, 3.6, 0.5), PLATE)                                         # blunt nose plate
	b.box(Vector3(0, 4.5, -11.13), Vector3(6.8, 0.75, 0.1), GLASS, true)                                  # cockpit band (a dull teal glow)
	for sx in [-1.0, 1.0]:
		# engine pods with their struts and the glowing exhausts at the back
		b.cyl(Vector3(sx * 5.9, 3.5, 3.5), 1.45, 7.0, HULL2, "z", false, 1.25, 10)
		b.box(Vector3(sx * 4.9, 3.4, 3.5), Vector3(1.4, 0.8, 5.0), PLATE)
		b.cyl(Vector3(sx * 5.9, 3.5, 7.0), 1.05, 0.3, ORANGE, "z", true, -1.0, 10)
		b.cyl(Vector3(sx * 5.9, 3.5, 7.2), 0.55, 0.2, SOOT, "z", false, -1.0, 8)
		# the ramp's side flanges
		b.box(Vector3(sx * (DOOR_W * 0.5 + 0.1), 0.95, 13.0), Vector3(0.2, 0.5, 6.1), HULL2, false, rot_ramp)
		# four short landing legs
		for sz in [-6.5, 3.5]:
			b.box(Vector3(sx * 4.2, 0.85, sz), Vector3(0.55, 1.6, 0.55), DARKP)
			b.box(Vector3(sx * 4.2, 0.1, sz), Vector3(1.7, 0.2, 1.7), HULL2)
	# the ramp: lowered from the sill (z = 10, y = 1.5) to the ground (z = 16)
	b.box(Vector3(0, SILL_Y * 0.5 + 0.03, 10.0 + RAMP_LEN * 0.5), Vector3(DOOR_W, 0.18, RAMP_LEN + 0.2), HULL, false, rot_ramp)
	if lod >= 2:
		# panel plating along both sides, rust and soot streaks
		for sx in [-1.0, 1.0]:
			for i in 8:
				var z := -9.2 + float(i) * 2.3
				var shade := 0.9 + 0.2 * fposmod(float(i) * 0.618 + (0.3 if sx > 0.0 else 0.0), 1.0)
				b.box(Vector3(sx * (WIDTH * 0.5 + 0.04), 3.7, z), Vector3(0.1, 3.0, 2.1), Color(HULL.r * shade, HULL.g * shade, HULL.b * shade))
				if i % 3 == 1:
					b.box(Vector3(sx * (WIDTH * 0.5 + 0.1), 2.4, z + 0.5), Vector3(0.06, 1.5, 0.35), RUSTY)
			for k in 3:
				b.box(Vector3(sx * (WIDTH * 0.5 + 0.1), 4.3, -6.0 + float(k) * 5.0), Vector3(0.05, 0.5, 1.6), DARKP)           # vents
			b.box(Vector3(sx * 3.9, 6.95, -3.0), Vector3(0.6, 0.3, 4.0), DARKP)                                                  # roof vents
		for i in 6:
			var zz := 10.4 + float(i) * 0.95
			b.box(Vector3(0, SILL_Y - (zz - 10.0) * SILL_Y / RAMP_LEN + 0.13, zz), Vector3(DOOR_W - 0.4, 0.05, 0.12), DARKP, false, rot_ramp)   # ramp ribs
		b.box(Vector3(0, 6.9, -6.5), Vector3(1.8, 0.7, 2.2), DARKP)                                                              # a small turret
		b.cyl(Vector3(0, 7.15, -8.0), 0.07, 1.8, DARKP, "z", false, -1.0, 6)
		b.cyl(Vector3(2.0, 8.0, 3.0), 0.05, 2.4, DARKP, "y", false, -1.0, 6)                                                     # antenna
		b.box(Vector3(0, 5.65, -10.5), Vector3(2.4, 0.18, 0.06), ORANGE, true)                                                   # a running light
		for sz in [-6.5, 3.5]:
			for sx in [-1.0, 1.0]:
				b.box(Vector3(sx * 3.5, 1.2, sz), Vector3(1.4, 0.12, 0.12), DARKP, false, Basis(Vector3.BACK, sx * 0.55))    # leg braces
	return b


## Collision boxes in model space: {c: centre, s: size, rx: pitch (the ramp)}. The hull is solid from the ground up; the doorway is an
## alcove (floor, side walls) closed at its back by the hull: the interior stays behind the loading threshold.
static func lander_boxes() -> Array:
	var out: Array = []
	out.append({"c": Vector3(0, HEIGHT * 0.5, -1.75), "s": Vector3(WIDTH, HEIGHT, 17.5), "rx": 0.0})                  # body z -10.5 .. 7
	for sx in [-1.0, 1.0]:
		out.append({"c": Vector3(sx * (DOOR_W * 0.5 + (WIDTH - DOOR_W) * 0.25), HEIGHT * 0.5, 8.5), "s": Vector3((WIDTH - DOOR_W) * 0.5, HEIGHT, 3.0), "rx": 0.0})   # beside the doorway
		out.append({"c": Vector3(sx * 5.9, 3.5, 3.5), "s": Vector3(2.9, 3.0, 7.0), "rx": 0.0})                         # engine pods
	out.append({"c": Vector3(0, 5.3, 8.5), "s": Vector3(DOOR_W, 1.4, 3.0), "rx": 0.0})                                # header over the door
	out.append({"c": Vector3(0, SILL_Y * 0.5, 8.5), "s": Vector3(DOOR_W, SILL_Y, 3.0), "rx": 0.0})                    # the alcove floor
	var a := atan2(SILL_Y, RAMP_LEN)
	out.append({"c": Vector3(0, SILL_Y * 0.5 - 0.02, 10.0 + RAMP_LEN * 0.5), "s": Vector3(DOOR_W, 0.3, RAMP_LEN / cos(a)), "rx": a})   # the ramp
	return out


## World position (given the ship's transform) of the top of the ramp / the loading threshold, and the foot of the ramp.
static func ramp_top_local() -> Vector3:
	return Vector3(0, SILL_Y, 10.0)


static func ramp_foot_local() -> Vector3:
	return Vector3(0, 0.0, 10.0 + RAMP_LEN)


## The ground the craft came down on: a scorched ring with burn streaks, crushed flowerbeds with spilled petals, three trees it knocked
## over (a trunk and a flattened crown each) and a bench smashed to planks. Model space again (the ship's origin on the ground).
static func site_mesh() -> ArrayMesh:
	if _meshes.has("site"):
		return _meshes["site"]
	var b := GunModels.Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	var soil := Color(0.2, 0.15, 0.1)
	# scorch: two dark discs and streaks blown outwards
	b.cyl(Vector3(0, 0.05, 0), 15.0, 0.03, Color(0.12, 0.11, 0.08), "y", false, -1.0, 20)
	b.cyl(Vector3(0, 0.07, 1.0), 10.5, 0.03, SOOT, "y", false, -1.0, 20)
	for i in 14:
		var a := TAU * float(i) / 14.0 + rng.randf_range(-0.15, 0.15)
		var len := rng.randf_range(5.0, 9.0)
		var r := 11.0 + len * 0.5
		b.box(Vector3(cos(a) * r, 0.065, sin(a) * r), Vector3(rng.randf_range(0.6, 1.4), 0.02, len), Color(0.08, 0.075, 0.06), false, Basis(Vector3.UP, -a + PI * 0.5))
	# crushed flowerbeds round the ship: churned soil with flattened stems and petals
	for bed in [Vector3(-10.5, 0, -8.0), Vector3(-9.5, 0, 6.5), Vector3(10.0, 0, -9.0), Vector3(11.0, 0, 2.0), Vector3(-3.0, 0, -13.0), Vector3(4.0, 0, 14.5)]:
		var yaw := rng.randf_range(0.0, PI)
		b.box(bed + Vector3(0, 0.1, 0), Vector3(3.6, 0.2, 1.4), soil, false, Basis(Vector3.UP, yaw))
		b.box(bed + Vector3(0, 0.22, 0), Vector3(3.0, 0.05, 0.9), Color(0.22, 0.34, 0.14), false, Basis(Vector3.UP, yaw + 0.1))
		for k in 7:
			var off := Basis(Vector3.UP, yaw) * Vector3(rng.randf_range(-1.6, 1.6), 0.26, rng.randf_range(-0.6, 0.6))
			var col := [Color(0.85, 0.2, 0.25), Color(0.95, 0.8, 0.2), Color(0.9, 0.5, 0.7), Color(0.95, 0.95, 0.95)][rng.randi() % 4] as Color
			b.box(bed + off, Vector3(0.22, 0.04, 0.22), col, false, Basis(Vector3.UP, rng.randf() * TAU))
	# trees that were knocked over: trunk + flattened crown, lying away from the hull
	for tr in [[Vector3(-8.5, 0, -2.0), 3.0], [Vector3(9.5, 0, -6.0), 0.2], [Vector3(2.5, 0, -12.5), -1.4]]:
		var yaw2: float = tr[1]
		var base: Vector3 = tr[0]
		var bas := Basis(Vector3.UP, yaw2)
		b.box(base + bas * Vector3(0, 0.3, 0), Vector3(0.55, 0.55, 6.5), Color(0.34, 0.24, 0.15), false, bas)
		b.box(base + bas * Vector3(0, 0.55, -4.6), Vector3(4.2, 1.1, 3.6), Color(0.14, 0.27, 0.12), false, bas)
		b.box(base + bas * Vector3(0.6, 0.9, -4.2), Vector3(2.8, 0.9, 2.6), Color(0.18, 0.33, 0.14), false, bas)
		b.box(base + bas * Vector3(0, 0.15, 3.4), Vector3(1.4, 0.3, 0.9), Color(0.3, 0.2, 0.12), false, bas)        # the torn root plate
	for k in 5:
		b.box(Vector3(-6.0 + rng.randf_range(-1.5, 1.5), 0.1, 9.0 + rng.randf_range(-1.5, 1.5)), Vector3(1.4, 0.06, 0.16), Color(0.45, 0.32, 0.2), false, Basis(Vector3.UP, rng.randf() * TAU))   # planks
	_meshes["site"] = b.mesh()
	return _meshes["site"]


# ================================================================== the node

## The landing craft in the world: hull mesh (distance LOD), the ground patch, the collider body (meta "hull" lets bullets spark),
## the loading threshold area, two heat-shimmer columns, a spark, and the descent (`begin_landing`).
class Lander extends Node3D:
	signal touched_down
	signal entered_threshold

	const DROP_H := 70.0
	const DROP_TIME := 9.0

	var hull: MeshInstance3D
	var site: MeshInstance3D
	var body: StaticBody3D
	var threshold: Area3D
	var shimmer: Array[MeshInstance3D] = []
	var lod := -1
	var landed := false
	var _fall_t := -1.0                    # 0 .. DROP_TIME while descending, -1 otherwise
	var _spark_light: OmniLight3D
	var _spark_fx: CPUParticles3D
	var _spark_t := 0.0
	var _engine: AudioStreamPlayer3D
	var _dust: CPUParticles3D

	func _init() -> void:
		visible = false

	func build() -> void:
		site = MeshInstance3D.new()
		site.mesh = ShipModels.site_mesh()
		site.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		site.material_override = _vertex_material()
		add_child(site)
		hull = MeshInstance3D.new()
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(hull)
		set_lod(1)
		body = StaticBody3D.new()
		body.collision_layer = Game.L_WORLD
		body.collision_mask = 0
		body.set_meta("hull", self)
		for bx in ShipModels.lander_boxes():
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = bx["s"]
			cs.shape = sh
			cs.transform = Transform3D(Basis(Vector3.RIGHT, float(bx["rx"])), bx["c"])
			body.add_child(cs)
		hull.add_child(body)
		threshold = Area3D.new()
		threshold.collision_layer = 0
		threshold.collision_mask = Game.L_PLAYER
		var tcs := CollisionShape3D.new()
		var tsh := BoxShape3D.new()
		tsh.size = Vector3(ShipModels.DOOR_W - 0.6, 2.6, 1.6)
		tcs.shape = tsh
		tcs.position = Vector3(0, ShipModels.SILL_Y + 1.4, 8.4)
		threshold.add_child(tcs)
		threshold.body_entered.connect(func(n: Node3D) -> void:
			if n is Player and landed:
				entered_threshold.emit())
		hull.add_child(threshold)
		# heat shimmer rising from the engines (the Veil's additive column shader on two billboards: no particles)
		var shader := Shader.new()
		shader.code = Veil.SHIMMER_SHADER
		var smat := ShaderMaterial.new()
		smat.shader = shader
		var quad := QuadMesh.new()
		quad.size = Vector2(5.0, 13.0)
		quad.center_offset = Vector3(0, 0.5, 0)
		for sx in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = smat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(sx * 5.9, 4.8, 5.0)
			mi.extra_cull_margin = 8.0
			hull.add_child(mi)
			shimmer.append(mi)
		# one spark (a shell hit the hull): a light that flashes 0.12 s and a puff of bright particles, both reused
		_spark_light = OmniLight3D.new()
		_spark_light.light_color = Color(1.0, 0.85, 0.5)
		_spark_light.light_energy = 5.0
		_spark_light.omni_range = 8.0
		_spark_light.shadow_enabled = false
		_spark_light.visible = false
		_spark_light.top_level = true
		add_child(_spark_light)
		_spark_fx = CPUParticles3D.new()
		_spark_fx.one_shot = true
		_spark_fx.emitting = false
		_spark_fx.amount = 22
		_spark_fx.lifetime = 0.5
		_spark_fx.explosiveness = 1.0
		_spark_fx.spread = 60.0
		_spark_fx.initial_velocity_min = 3.0
		_spark_fx.initial_velocity_max = 9.0
		_spark_fx.gravity = Vector3(0, -14, 0)
		_spark_fx.top_level = true
		var sm := BoxMesh.new()
		sm.size = Vector3(0.05, 0.05, 0.16)
		var smat2 := StandardMaterial3D.new()
		smat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat2.albedo_color = Color(1.0, 0.92, 0.6)
		smat2.disable_fog = true
		sm.material = smat2
		_spark_fx.mesh = sm
		add_child(_spark_fx)
		# dust thrown up at touchdown
		_dust = CPUParticles3D.new()
		_dust.one_shot = true
		_dust.emitting = false
		_dust.amount = 36
		_dust.lifetime = 2.2
		_dust.explosiveness = 0.9
		_dust.direction = Vector3.UP
		_dust.spread = 90.0
		_dust.initial_velocity_min = 3.0
		_dust.initial_velocity_max = 9.0
		_dust.gravity = Vector3(0, -1.0, 0)
		_dust.damping_min = 2.0
		_dust.damping_max = 4.0
		var dm := QuadMesh.new()
		dm.size = Vector2(3.0, 3.0)
		var dmat := StandardMaterial3D.new()
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.albedo_color = Color(0.5, 0.45, 0.38, 0.35)
		dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		dm.material = dmat
		_dust.mesh = dm
		_dust.position = Vector3(0, 0.5, 0)
		add_child(_dust)
		_engine = AudioStreamPlayer3D.new()
		_engine.stream = Sfx.get_sound("hum")
		_engine.max_distance = 260.0
		_engine.unit_size = 40.0
		_engine.volume_db = 6.0
		add_child(_engine)
		set_process(false)
		_set_colliders(false)

	static func _vertex_material() -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m

	func set_lod(l: int) -> void:
		if l == lod:
			return
		lod = l
		hull.mesh = ShipModels.lander_mesh(l)

	## Called every few tenths of a second with the player's distance.
	func update_lod(dist: float) -> void:
		set_lod(2 if dist < ShipModels.NEAR_LOD_DIST else 1)
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if dist < 140.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _set_colliders(on: bool) -> void:
		for c in body.get_children():
			(c as CollisionShape3D).disabled = not on
		threshold.monitoring = on

	## The craft comes down out of the sky over DROP_TIME seconds, throws up dust and is solid from then on.
	func begin_landing() -> void:
		if landed or _fall_t >= 0.0:
			return
		visible = true
		_fall_t = 0.0
		hull.position.y = DROP_H
		_set_colliders(false)
		_engine.pitch_scale = 0.5
		_engine.play()
		set_process(true)

	func land_now() -> void:
		visible = true
		_fall_t = -1.0
		hull.position = Vector3.ZERO
		hull.rotation = Vector3.ZERO
		landed = true
		_set_colliders(true)
		_engine.stop()
		set_process(false)

	func hide_ship() -> void:
		visible = false
		landed = false
		_fall_t = -1.0
		_set_colliders(false)
		_engine.stop()
		set_process(false)

	func _process(delta: float) -> void:
		if _fall_t >= 0.0:
			_fall_t += delta
			var k := clampf(_fall_t / DROP_TIME, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 2.6)             # fast at first, settling gently at the end
			hull.position.y = DROP_H * (1.0 - e)
			hull.rotation = Vector3(sin(_fall_t * 1.3) * 0.02 * (1.0 - e), sin(_fall_t * 0.5) * 0.03 * (1.0 - e), cos(_fall_t * 1.7) * 0.02 * (1.0 - e))
			_engine.pitch_scale = lerpf(0.5, 0.8, e)
			if k >= 1.0:
				_fall_t = -1.0
				hull.position = Vector3.ZERO
				hull.rotation = Vector3.ZERO
				landed = true
				_set_colliders(true)
				_engine.stop()
				_dust.restart()
				Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 3, 0), "far_boom", 8.0, 1.0, 400.0, 60.0)
				touched_down.emit()
				if _spark_t <= 0.0:
					set_process(false)
		if _spark_t > 0.0:
			_spark_t -= delta
			if _spark_t <= 0.0:
				_spark_light.visible = false
				if _fall_t < 0.0:
					set_process(false)

	## A shell hit the hull at `pos`: a bright spark.
	func spark(pos: Vector3, normal: Vector3) -> void:
		_spark_light.global_position = pos + normal * 0.6
		_spark_light.visible = true
		_spark_fx.global_position = pos + normal * 0.05
		_spark_fx.direction = normal
		_spark_fx.restart()
		_spark_t = 0.12
		set_process(true)
