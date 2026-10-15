class_name World
extends Node3D
## Open field: noise terrain (flat-shaded, with trimesh collision), scattered trees and rocks, sky, sun, fog, boundary walls.

const HALF := Game.WORLD_SIZE * 0.5
const SPAWN_CLEAR := 22.0     # flat, empty field around the origin

static var _noise: FastNoiseLite = null
static var _detail: FastNoiseLite = null


static func _ensure_noise() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = 1944
	_noise.frequency = 0.0055
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.seed = 77
	_detail.frequency = 0.04


## Ground height at (x, z). Flat near the origin so the player starts on an empty field.
static func height_at(x: float, z: float) -> float:
	_ensure_noise()
	var d := Vector2(x, z).length()
	var k := smoothstep(SPAWN_CLEAR, SPAWN_CLEAR + 45.0, d)
	var h := _noise.get_noise_2d(x, z) * 20.0 + _detail.get_noise_2d(x, z) * 0.9
	return h * k


static func slope_at(x: float, z: float) -> float:
	var e := 1.0
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector2(dx, dz).length() / (2.0 * e)


var trunk_mat: StandardMaterial3D
var leaf_mat: StandardMaterial3D
var rock_mat: StandardMaterial3D
var sun: DirectionalLight3D
var _faces := PackedVector3Array()   # every ground triangle, for the collision shape


func build() -> void:
	_environment()
	_terrain()
	_boundary()
	_scatter()


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.82)
	sky_mat.sky_horizon_color = Color(0.7, 0.8, 0.9)
	sky_mat.ground_horizon_color = Color(0.7, 0.8, 0.9)
	sky_mat.ground_bottom_color = Color(0.62, 0.72, 0.82)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 330.0
	env.fog_depth_curve = 1.4
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)


func _terrain() -> void:
	var n := int(Game.WORLD_SIZE / Game.WORLD_CELL)
	var cell := Game.WORLD_CELL
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			heights[iz * (n + 1) + ix] = height_at(-HALF + ix * cell, -HALF + iz * cell)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass_a := Color(0.2, 0.37, 0.11)
	var grass_b := Color(0.35, 0.47, 0.15)
	var dirt := Color(0.4, 0.31, 0.19)
	var rock := Color(0.4, 0.39, 0.36)
	for iz in n:
		for ix in n:
			var x0 := -HALF + ix * cell
			var z0 := -HALF + iz * cell
			var h00: float = heights[iz * (n + 1) + ix]
			var h10: float = heights[iz * (n + 1) + ix + 1]
			var h01: float = heights[(iz + 1) * (n + 1) + ix]
			var h11: float = heights[(iz + 1) * (n + 1) + ix + 1]
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x0 + cell, h10, z0)
			var p01 := Vector3(x0, h01, z0 + cell)
			var p11 := Vector3(x0 + cell, h11, z0 + cell)
			# alternate the diagonal so the facets do not all lean one way
			if (ix + iz) % 2 == 0:
				_tri(st, p00, p01, p10, grass_a, grass_b, dirt, rock)
				_tri(st, p10, p01, p11, grass_a, grass_b, dirt, rock)
			else:
				_tri(st, p00, p01, p11, grass_a, grass_b, dirt, rock)
				_tri(st, p00, p11, p10, grass_a, grass_b, dirt, rock)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, grass_a: Color, grass_b: Color, dirt: Color, rock: Color) -> void:
	var centre := (a + b + c) / 3.0
	var nrm := (b - a).cross(c - a).normalized()
	var slope := 1.0 - absf(nrm.y)
	var col := grass_a.lerp(grass_b, clampf(_detail.get_noise_2d(centre.x * 1.7, centre.z * 1.7) * 0.5 + 0.5, 0.0, 1.0))
	if slope > 0.18:
		col = col.lerp(dirt, clampf((slope - 0.18) * 5.0, 0.0, 1.0))
	if slope > 0.4:
		col = col.lerp(rock, clampf((slope - 0.4) * 4.0, 0.0, 1.0))
	# darken a touch per facet so the low-poly look reads
	col = col.darkened(randf_range(0.0, 0.07))
	for p in [a, c, b]:      # Godot front faces are clockwise
		st.set_color(col)
		st.add_vertex(p)
		_faces.append(p)


func _boundary() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	var t := 4.0
	var sz := Game.WORLD_SIZE + t * 2.0
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var along_x: bool = absf(side.x) > 0.5
		box.size = Vector3(t if along_x else sz, 120.0, sz if along_x else t)
		cs.shape = box
		cs.position = side * (HALF + t * 0.5) + Vector3(0, 40, 0)
		body.add_child(cs)
	add_child(body)


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	trunk_mat = _flat_mat(Color(0.35, 0.24, 0.14))
	leaf_mat = _flat_mat(Color.WHITE, true)
	rock_mat = _flat_mat(Color.WHITE, true)

	var tree_spots: Array = []
	var rock_spots: Array = []
	var tries := 0
	while tree_spots.size() < 260 and tries < 4000:
		tries += 1
		var x := rng.randf_range(-HALF + 6, HALF - 6)
		var z := rng.randf_range(-HALF + 6, HALF - 6)
		if Vector2(x, z).length() < SPAWN_CLEAR + 12.0:
			continue
		if slope_at(x, z) > 0.45:
			continue
		# trees cluster: a second noise decides where forests are
		if _detail.get_noise_2d(x * 0.25 + 300.0, z * 0.25) < -0.1 and rng.randf() < 0.85:
			continue
		tree_spots.append(Vector3(x, height_at(x, z), z))
	tries = 0
	while rock_spots.size() < 90 and tries < 2000:
		tries += 1
		var rx := rng.randf_range(-HALF + 6, HALF - 6)
		var rz := rng.randf_range(-HALF + 6, HALF - 6)
		if Vector2(rx, rz).length() < SPAWN_CLEAR + 8.0:
			continue
		rock_spots.append(Vector3(rx, height_at(rx, rz), rz))

	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	add_child(body)

	# --- trees: trunk + two cones, three MultiMeshes ---
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.32
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 1.0
	cone_mesh.height = 1.0
	cone_mesh.radial_segments = 7
	cone_mesh.rings = 1

	var trunks := _multimesh(trunk_mesh, trunk_mat, tree_spots.size(), false)
	var cones := _multimesh(cone_mesh, leaf_mat, tree_spots.size() * 2, true)
	var ci := 0
	for i in tree_spots.size():
		var p: Vector3 = tree_spots[i]
		var th := rng.randf_range(4.0, 7.5)
		var s := rng.randf_range(0.8, 1.3)
		var tb := Transform3D(Basis().scaled(Vector3(s, th, s)), p + Vector3(0, th * 0.5, 0))
		trunks.multimesh.set_instance_transform(i, tb)
		var green := Color(0.09, 0.26, 0.11).lerp(Color(0.18, 0.38, 0.13), rng.randf())
		for layer in 2:
			var cr := (3.0 - layer * 1.0) * s
			var ch := 3.6 - layer * 0.6
			var cy := p.y + th * (0.55 + layer * 0.35) + ch * 0.5
			var cb := Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(cr, ch, cr)), Vector3(p.x, cy, p.z))
			cones.multimesh.set_instance_transform(ci, cb)
			cones.multimesh.set_instance_color(ci, green.darkened(layer * 0.08))
			ci += 1
		var shape := CylinderShape3D.new()
		shape.radius = 0.32 * s + 0.05
		shape.height = th
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = p + Vector3(0, th * 0.5, 0)
		body.add_child(cs)
	add_child(trunks)
	add_child(cones)

	# --- grass tufts: thousands of tiny cones in one draw call ---
	var tuft_mesh := CylinderMesh.new()
	tuft_mesh.top_radius = 0.0
	tuft_mesh.bottom_radius = 0.09
	tuft_mesh.height = 0.4
	tuft_mesh.radial_segments = 4
	tuft_mesh.rings = 1
	var tuft_spots: Array = []
	tries = 0
	while tuft_spots.size() < 5000 and tries < 20000:
		tries += 1
		var gx: float
		var gz: float
		if tuft_spots.size() < 3200:
			gx = rng.randf_range(-130.0, 130.0)     # dense around the start so the field is not bare
			gz = rng.randf_range(-130.0, 130.0)
		else:
			gx = rng.randf_range(-HALF + 4, HALF - 4)
			gz = rng.randf_range(-HALF + 4, HALF - 4)
		if slope_at(gx, gz) > 0.6 or Vector2(gx, gz).length() < 3.5:
			continue
		tuft_spots.append(Vector3(gx, height_at(gx, gz), gz))
	var tufts := _multimesh(tuft_mesh, leaf_mat, tuft_spots.size(), true)
	tufts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in tuft_spots.size():
		var tp: Vector3 = tuft_spots[i]
		var ts := rng.randf_range(0.6, 1.3)
		var tb2 := Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ts, ts * rng.randf_range(0.8, 1.6), ts)), tp + Vector3(0, 0.22 * ts, 0))
		tufts.multimesh.set_instance_transform(i, tb2)
		var gc := Color(0.13, 0.28, 0.08).lerp(Color(0.3, 0.4, 0.12), rng.randf())
		tufts.multimesh.set_instance_color(i, gc)
	add_child(tufts)

	# --- rocks ---
	var rock_mesh := SphereMesh.new()
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 4
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	var rocks := _multimesh(rock_mesh, rock_mat, rock_spots.size(), true)
	for i in rock_spots.size():
		var p2: Vector3 = rock_spots[i]
		var r := rng.randf_range(0.6, 2.4)
		var bs := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r * rng.randf_range(0.9, 1.5), r * rng.randf_range(0.6, 0.9), r * rng.randf_range(0.9, 1.4)))
		rocks.multimesh.set_instance_transform(i, Transform3D(bs, p2 + Vector3(0, r * 0.25, 0)))
		var g := rng.randf_range(0.28, 0.46)
		rocks.multimesh.set_instance_color(i, Color(g, g * 0.97, g * 0.92))
		var rs := SphereShape3D.new()
		rs.radius = r * 0.85
		var rcs := CollisionShape3D.new()
		rcs.shape = rs
		rcs.position = p2 + Vector3(0, r * 0.2, 0)
		body.add_child(rcs)
	add_child(rocks)


func _flat_mat(color: Color, vertex_colors: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = vertex_colors
	m.vertex_color_is_srgb = vertex_colors
	return m


func _multimesh(mesh: Mesh, mat: Material, count: int, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	return inst
