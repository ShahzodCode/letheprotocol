class_name WorldWar
## Turns the plain data in Scn (road decals, scenery parts, colliders, kerbs, fires) into MultiMeshes and colliders.
## One draw call per mesh type: decal boxes / discs, scenery boxes / cylinders / spheres / cones, burning canopies, smoke columns.

## Burning canopies: an unshaded orange / red flicker, phase from the instance colour so neighbours do not pulse together.
const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
varying vec3 wp;
varying float ph;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ph = COLOR.r * 40.0;
	VERTEX += NORMAL * 0.06 * sin(TIME * 7.0 + ph + VERTEX.y * 9.0);
}
void fragment() {
	float t = TIME * 6.0 + ph;
	float f = 0.5 + 0.28 * sin(t + wp.y * 1.7) + 0.22 * sin(t * 2.3 + wp.x * 2.1 + wp.z * 1.3);
	vec3 c = mix(vec3(0.62, 0.08, 0.01), vec3(1.0, 0.58, 0.08), clamp(f, 0.0, 1.0));
	c = mix(c, vec3(1.0, 0.9, 0.5), smoothstep(0.82, 1.0, f) * 0.6);
	ALBEDO = c;
}
"""

const SMOKE_H := {"tree": [8.0, 22.0, 5.0], "car": [10.0, 32.0, 8.0], "build": [30.0, 110.0, 22.0]}      # start height, height, top width


static func build(world: World) -> Fires:
	_decals(world)
	_kerbs(world)
	_scenery(world)
	_colliders(world)
	return _fires(world)


## One MultiMesh per `cell` metres square instead of one for the whole city: the renderer culls a MultiMesh as a whole, so a single
## city-wide one is drawn (and shadow-rendered) in full from everywhere. `range_end` > 0 hides a chunk beyond that distance.
## An item is [Transform3D, Color] or [Transform3D, Color, Color custom data].
static func _mm(world: Node3D, mesh: Mesh, items: Array, mat: Material, shadows: bool, range_end: float = 0.0, cell: float = 96.0) -> void:
	if items.is_empty():
		return
	var groups := {}
	for it in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		var key := Vector2i(floori(o.x / cell), floori(o.z / cell))
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(it)
	var custom: bool = (items[0] as Array).size() > 2
	for key in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = custom
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
			if custom:
				mm.set_instance_custom_data(i, list[i][2])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = mat
		if not shadows:
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			inst.visibility_range_end = range_end + cell
			inst.visibility_range_end_margin = 10.0
		world.add_child(inst)

static func _box() -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3.ONE
	return m


static func _cyl(top: float = 0.5, bottom: float = 0.5, sides: int = 7) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = 1.0
	m.radial_segments = sides
	m.rings = 1
	return m


static func _decals(world: World) -> void:
	var flat := world._flat_mat(Color.WHITE, true)
	for k in ["paint", "dark", "debris"]:
		_mm(world, _box(), Scn.decals[k], flat, false, 110.0)
	_mm(world, _cyl(0.5, 0.5, 14), Scn.decals["disc"], flat, false, 110.0)


static func _kerbs(world: World) -> void:
	if Scn.kerbs.is_empty():
		return
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_KERB
	body.collision_mask = 0
	for r in Scn.kerbs:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3((r as Rect2).size.x, 0.15, (r as Rect2).size.y)
		cs.shape = box
		cs.position = Vector3((r as Rect2).get_center().x, 0.075, (r as Rect2).get_center().y)
		body.add_child(cs)
	world.add_child(body)


static func _scenery(world: World) -> void:
	var flat := world._flat_mat(Color.WHITE, true)
	_mm(world, _box(), Scn.parts["box"], flat, false, 240.0)          # small boxes (balconies, awnings, barricades) cast no shadows: cheaper
	_mm(world, _cyl(0.5, 0.5, 7), Scn.parts["cyl"], flat, true, 280.0)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_mm(world, sphere, Scn.parts["sphere"], flat, true, 300.0)
	_mm(world, _cyl(0.0, 0.5, 8), Scn.parts["cone"], flat, true, 300.0)
	# burning canopies
	var shader := Shader.new()
	shader.code = FIRE_SHADER
	var fire_mat := ShaderMaterial.new()
	fire_mat.shader = shader
	_mm(world, sphere, Scn.parts["fire"], fire_mat, false)
	# lit signs and window lights: unshaded boxes
	var gm := world._flat_mat(Color.WHITE, true)
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mm(world, _box(), Scn.parts["glow"], gm, false, 220.0)
	# glass walkways: translucent blue-green panes
	var glass_mat := world._flat_mat(Color.WHITE, true)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.1
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mm(world, _box(), Scn.parts["glass"], glass_mat, false, 300.0)


static func _colliders(world: World) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	for c in Scn.colliders:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = c["size"]
		cs.shape = box
		cs.transform = c["xf"]
		body.add_child(cs)
	for c in Scn.cyl_colliders:
		var cs2 := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = float(c["r"])
		cyl.height = float(c["h"])
		cs2.shape = cyl
		cs2.position = (c["pos"] as Vector3) + Vector3(0, float(c["h"]) * 0.5, 0)
		body.add_child(cs2)
	world.add_child(body)


## The fire manager (flames, smoke and a few lights near the player) and the far smoke columns.
static func _fires(world: World) -> Fires:
	var fires := Fires.new()
	world.add_child(fires)
	fires.setup(Scn.fires)
	var cols: Array = []
	for f in Scn.fires:
		var kind: String = f["kind"]
		if not SMOKE_H.has(kind):
			continue
		var info: Array = SMOKE_H[kind]
		var p: Vector3 = f["pos"]
		var base_y: float = (p.y + 4.0) if kind == "build" else float(info[0])
		var h: float = float(info[1])
		var w: float = float(info[2]) * float(f["s"])
		cols.append([Transform3D(Basis.from_scale(Vector3(w, h, w)), Vector3(p.x, base_y + h * 0.5, p.z)), Color(0.14, 0.13, 0.13, 0.3)])
	if not cols.is_empty():
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mm(world, _cyl(0.5, 0.1, 10), cols, m, false)
	return fires
