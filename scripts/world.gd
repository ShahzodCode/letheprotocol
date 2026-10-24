class_name World
extends Node3D
## The city as geometry: flat asphalt ground, every building as a box (merged into one MultiMesh drawn with a window
## shader, one collision box each), footpaths, lane markings, parked cars, sky, sun, fog, boundary walls.
## The layout itself lives in City (plain data) so the AI can use it for navigation.

const SITE_SEED := 4242
static var building_mat: ShaderMaterial          # the window shader material of all buildings (Interiors draws its walls with it too)
const BUILDING_LOD := 120.0        # chunks of buildings farther than this (plus the 80 m chunk size) are drawn as plain tinted boxes: no window shader, no shadows
const FAR_TINT := Color(0.84, 0.86, 0.9)   # the far boxes are the wall colour times this (the windows average out to a slightly darker, cooler tone)

var sun: DirectionalLight3D
var env_ref: Environment
var sites: Array = []           # Site nodes, same order as City.sites
var fires: Fires                # flames, smoke and fire lights near the player (Main updates it)
var veil: Veil                  # the invasion sky: Veil shader, wound, landers, smoke pillars (null with LETHE_NOVEIL=1)
var lander: ShipModels.Lander    # the landing craft in the park: hidden until the story brings it down (Main._sync_lander)
var far_landers_node: MultiMeshInstance3D   # the other craft settled in far plazas (hidden until the lookout)


## The city is flat: ground height is 0 everywhere (kept as a function so callers need not care).
static func height_at(_x: float, _z: float) -> float:
	return 0.0


static func slope_at(_x: float, _z: float) -> float:
	return 0.0


func build() -> void:
	City.generate()
	_environment()
	_ground()

	_buildings()
	CityModels.build(self)
	_ramps()
	_street_details()
	_cars()
	_decor()
	_obstacles()
	fires = WorldWar.build(self)
	_lights()
	_sites()
	_goal_marker()
	_lander()


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	# about 11:30 on a March morning: clear sky, hazy with smoke near the horizon
	sky_mat.sky_top_color = Color(0.34, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.74, 0.72, 0.68)
	sky_mat.ground_horizon_color = Color(0.7, 0.67, 0.62)
	sky_mat.ground_bottom_color = Color(0.58, 0.56, 0.54)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var veil_mat: ShaderMaterial = null
	if Veil.enabled():
		veil_mat = Veil.make_sky_material()
		sky.sky_material = veil_mat
		sky.radiance_size = Sky.RADIANCE_SIZE_32           # only the ambient colour is taken from it (set below), so the smallest map
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.58, 0.56)         # hazy daylight bounce, not a blue sky tint in the shadows
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 60.0           # smoke from the fighting tints the distance grey-brown
	env.fog_depth_end = 430.0
	env.fog_depth_curve = 1.25
	env.fog_light_color = Color(0.66, 0.62, 0.57)
	env.fog_sky_affect = 0.0
	env_ref = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-53, -35, 0)          # 53 degrees above the horizon
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_pancake_size = 400.0
	sun.light_color = Color(1.0, 0.97, 0.9)
	add_child(sun)
	if veil_mat != null:
		veil = Veil.new()
		add_child(veil)
		veil.setup(sun, veil_mat)


## The ground is a flat asphalt plane and collider, cut open above the cellar's stairs. The collider has three layers: a thin
## top layer (open over the stairwell), a middle layer (open over the stairwell and the cellar) and a solid bottom, so the
## cellar is a real hollow under the yard with a 2.4 m ceiling.
func _ground() -> void:
	var mat := _flat_mat(Color(0.2, 0.2, 0.22))
	var half := Vector2(City.OUT_X + 400.0, City.OUT_Z + 400.0)
	for r in CityPlaces.cut(Rect2(-half, half * 2.0), [City.STAIR_HOLE]):
		var plane := PlaneMesh.new()
		plane.size = (r as Rect2).size
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.position = Vector3((r as Rect2).get_center().x, 0.0, (r as Rect2).get_center().y)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	# big enough that soldiers parked outside the border by the tests still have ground under them
	var big := Rect2(-(City.OUT_X + 300.0), -(City.OUT_Z + 300.0), (City.OUT_X + 300.0) * 2.0, (City.OUT_Z + 300.0) * 2.0)
	_ground_layer(body, CityPlaces.cut(big, [City.STAIR_HOLE]), City.CELLAR_CEIL_Y, 0.0)
	_ground_layer(body, CityPlaces.cut(big, [City.STAIR_HOLE, City.CELLAR_RECT]), City.CELLAR_FLOOR_Y, City.CELLAR_CEIL_Y)
	_ground_layer(body, [big], -4.0, City.CELLAR_FLOOR_Y)
	add_child(body)


func _ground_layer(body: StaticBody3D, rects: Array, y0: float, y1: float) -> void:
	for r in rects:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3((r as Rect2).size.x, y1 - y0, (r as Rect2).size.y)
		cs.shape = box
		cs.position = Vector3((r as Rect2).get_center().x, (y0 + y1) * 0.5, (r as Rect2).get_center().y)
		body.add_child(cs)


## All building boxes (playable ones with colliders, the far backdrop without) in a single MultiMesh.
func _buildings() -> void:
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = BuildingShader.CODE
	mat.shader = shader
	building_mat = mat
	WorldWar.registry.clear()
	Interiors.shapes.clear()
	var items: Array = []
	for b in City.buildings:
		for bx in b["boxes"]:
			items.append([bx, b, true])
	for pr in City.props:
		items.append([{"rect": pr["rect"], "y0": pr["y0"], "y1": pr["y1"]}, pr, true])
	for b in City.backdrop:
		for bx in b["boxes"]:
			items.append([bx, b, false])
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	add_child(body)
	for sb in City.buildings:          # simple buildings (no way in, no ladder, no damage cut-out, no story role) get ONE collider for the whole footprint
		sb["one_box"] = not (bool(sb.get("access", false)) or sb.has("tunnel") or sb.has("arch_damage") or sb.has("special") or sb.has("story") or sb.has("institute") or sb.has("home") or sb.has("bridge") or sb.has("nav_rects") or sb.has("slab_holes") or sb.has("no_slab") or sb.has("model"))
	var render: Array = []        # [Transform3D, Color, custom data]: drawn in chunks (see WorldWar._mm)
	for i in items.size():
		var bx: Dictionary = items[i][0]
		var b: Dictionary = items[i][1]
		var r: Rect2 = bx["rect"]
		var y0: float = bx["y0"]
		var y1: float = bx["y1"]
		var size := Vector3(r.size.x, y1 - y0, r.size.y)
		var centre := Vector3(r.get_center().x, (y0 + y1) * 0.5, r.get_center().y)
		var col: Color = bx.get("color", b["color"])
		# small per-box colour variation so neighbours do not look cloned
		col = col.darkened(float((i * 37) % 11) * 0.008)
		# damage, a per-building random number and the burning flag go to the shader as custom data (the far backdrop gets some too)
		var dmg := float(b.get("damage", 0.0))
		if not bool(items[i][2]) and b.has("h"):
			dmg = fposmod(float(i) * 0.6180339, 1.0) * 0.55
		render.append([Transform3D(Basis.from_scale(size), centre), Color(col.r, col.g, col.b, float(bx.get("style", b["style"]))),
			Color(dmg, float(b.get("seed", fposmod(float(i) * 0.37, 1.0))), 1.0 if bool(b.get("burning", false)) else 0.0, 0.0), int(b.get("iid", -1))])
		if bool(items[i][2]) and not bool(b.get("one_box", false)):
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			cs.shape = shape
			cs.position = centre
			body.add_child(cs)
	WorldWar._mm(self, mesh, render, mat, true, BUILDING_LOD, 80.0)
	# the same boxes again for the far chunks: one flat material, no custom data, no shadows
	var far_items: Array = []
	for it in render:
		far_items.append([it[0], it[1]])
	var far_mat := _flat_mat(FAR_TINT, true)
	WorldWar._mm(self, mesh, far_items, far_mat, false, 0.0, 80.0, BUILDING_LOD)
	# one collider per simple building (the footprint up to its top); buildings with a way in, a ladder, a missing corner or a story role keep their boxes
	for b in City.buildings:
		if bool(b.get("one_box", false)):
			var fr: Rect2 = b["rect"]
			var bh: float = b["h"]
			var ocs := CollisionShape3D.new()
			var oshape := BoxShape3D.new()
			oshape.size = Vector3(fr.size.x, bh, fr.size.y)
			ocs.shape = oshape
			ocs.position = Vector3(fr.get_center().x, bh * 0.5, fr.get_center().y)
			body.add_child(ocs)
			if b.has("iid"):
				Interiors.shapes[int(b["iid"])] = ocs


## Footpaths around every building, green squares on empty lots, dashed lane lines down the avenues.
func _street_details() -> void:
	# [Rect2, Color, lift]: lift 0 = footpaths and plazas, 1 = yards and parks, 2 = floors and paths, 3 = tiles. Each level sits
	# 1 cm higher, so overlapping slabs never flicker; the ground is open above the cellar stairs, so no slab covers that hole.
	# The pavement round a building is a raised kerb (0.15 m): only the player collides with it (Game.L_KERB, stepped over
	# automatically), so soldiers and civilians keep walking flat. The pavement is a ring: nothing under the building itself
	# (a pass-through corridor stays at street level).
	var raw: Array = []      # [Rect2, Color, lift, kerb]
	for b in City.buildings:
		if not b.get("border", false) and not b.get("no_slab", false):
			var holes: Array = [b["rect"]]
			holes.append_array(b.get("slab_holes", []))
			for piece in CityPlaces.cut((b["rect"] as Rect2).grow(1.2), holes):
				raw.append([piece, Color(0.58, 0.57, 0.55), 0, true])
	for gs in City.ground_slabs:
		raw.append([gs[0], gs[1], int(gs[2]) if gs.size() > 2 else 1, false])
	for s in City.streets:
		if s["cls"] == "plaza":
			raw.append([(s["rect"] as Rect2).grow(-0.4), Color(0.26, 0.45, 0.22), 0, false])
	var slabs: Array = []
	for rs in raw:
		for piece in CityPlaces.cut(rs[0], [City.STAIR_HOLE]):
			slabs.append([piece, rs[1], rs[2], rs[3]])
			if rs[3]:
				Scn.kerbs.append(piece)
	var slab_mm := _flat_multimesh(slabs.size())
	for i in slabs.size():
		var r: Rect2 = slabs[i][0]
		var thick := 0.15 if slabs[i][3] else 0.1
		var cy := 0.075 if slabs[i][3] else 0.03 + int(slabs[i][2]) * 0.01
		slab_mm.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r.size.x, thick, r.size.y)), Vector3(r.get_center().x, cy, r.get_center().y)))
		slab_mm.multimesh.set_instance_color(i, slabs[i][1])
	add_child(slab_mm)


## Parked, wrecked and abandoned vehicles: WorldCars draws them (boxes in two MultiMeshes) with one collider each.
func _cars() -> void:
	WorldCars.build(self)


func _flat_mat(color: Color, vertex_colors: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = vertex_colors
	m.vertex_color_is_srgb = vertex_colors
	return m


## A MultiMesh of unit boxes with per-instance colours, drawn with one flat material.
func _flat_multimesh(count: int, unshaded: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var fm := _flat_mat(Color.WHITE, true)
	if unshaded:
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inst.material_override = fm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


## Small extras without collision: glowing doors, window lights, the house roof trim.
func _decor() -> void:
	for glow in [false, true]:
		var items: Array = []
		for d in City.decor:
			if bool(d["glow"]) == glow:
				items.append(d)
		if items.is_empty():
			continue
		var mi := _flat_multimesh(items.size(), glow)
		for i in items.size():
			mi.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(items[i]["size"]), items[i]["pos"]))
			mi.multimesh.set_instance_color(i, items[i]["color"])
		add_child(mi)


const HEDGEHOG_SCENE := "res://models/chars/hedgehog.glb"
const HEDGEHOG_PLATE := "hedgehog2_hedgehog2_0"          # a flat snow patch that comes with the model: not wanted

## Steel hedgehog barricades around the battle sites (City.obstacles): the model without its snow patch, one box collider
## each (bullets and people stop at it; City blocks the navigation grid there too).
func _obstacles() -> void:
	if City.obstacles.is_empty():
		return
	var scene := load(HEDGEHOG_SCENE) as PackedScene
	var probe := scene.instantiate() as Node3D
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for mi in probe.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name == HEDGEHOG_PLATE:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != probe and n != null:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var bb := xf * m.get_aabb()
		lo = lo.min(bb.position)
		hi = hi.max(bb.end)
	probe.free()
	var size := hi - lo
	var centre := (lo + hi) * 0.5
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	add_child(body)
	for ob in City.obstacles:
		var half: Vector2 = ob["half"]
		var k: float = half.x * 2.0 * 1.3 / size.x          # the whole barricade is a little longer than its collider
		var holder := Node3D.new()
		holder.position = ob["pos"]
		holder.rotation.y = float(ob["yaw"])
		add_child(holder)
		var inst := scene.instantiate() as Node3D
		inst.scale = Vector3.ONE * k
		inst.position = Vector3(-centre.x * k, -lo.y * k, -centre.z * k)
		var plate := inst.find_child(HEDGEHOG_PLATE, true, false)
		if plate != null:
			(plate as Node3D).visible = false
		holder.add_child(inst)
		var height := size.y * k
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(half.x * 2.0, height, half.y * 2.0)
		cs.shape = box
		cs.transform = Transform3D(Basis().rotated(Vector3.UP, float(ob["yaw"])), Vector3(float((ob["pos"] as Vector3).x), height * 0.5, float((ob["pos"] as Vector3).z)))
		body.add_child(cs)

## Battle sites: ground damage + fires. Main switches their detail on and off by distance (Site.set_lod).
func _sites() -> void:
	for i in City.sites.size():
		var s := Site.new()
		add_child(s)
		s.build(City.sites[i]["center"], float(City.sites[i]["radius"]), SITE_SEED + i)
		sites.append(s)


## An inverted glowing triangle (a three-sided pyramid pointing down) hovering over the goal house, plus a faint beam
## down to the roof. Unaffected by fog so it can be seen across the whole map.
var _marker: Node3D

func _goal_marker() -> void:
	_marker = Node3D.new()
	_marker.position = _marker_base
	_marker.visible = false          # the mission shows it (set_marker_target)
	add_child(_marker)
	var cm := CylinderMesh.new()
	cm.top_radius = 15.0
	cm.bottom_radius = 0.0
	cm.height = 26.0
	cm.radial_segments = 3
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.15)
	mat.disable_fog = true
	cm.material = mat
	var tri := MeshInstance3D.new()
	tri.mesh = cm
	tri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(tri)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 85.0, 0.5)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(1.0, 0.82, 0.15, 0.35)
	bmat.disable_fog = true
	bm.material = bmat
	beam.mesh = bm
	beam.position = Vector3(0, -13.0 - 42.5, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(beam)


var _marker_base := Vector3(0.0, 95.0, 0.0)
var _marker_tween: Tween
var _marker_placed := false


## Move the marker over a new spot in 1 s (the first spot is taken at once); null hides it.
func set_marker_target(p: Variant) -> void:
	if _marker == null:
		return
	if _marker_tween != null:
		_marker_tween.kill()
	if p == null:
		_marker.visible = false
		return
	var target := Vector3((p as Vector3).x, 95.0, (p as Vector3).z)
	if not _marker.visible or not _marker_placed:
		_marker_base = target
		_marker.visible = true
		_marker_placed = true
		return
	_marker_tween = create_tween()
	_marker_tween.tween_property(self, "_marker_base", target, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	if _marker != null:
		_marker.rotation.y += delta * 0.6
		_marker.position = _marker_base + Vector3(0.0, sin(Time.get_ticks_msec() * 0.0015) * 2.0, 0.0)


## Smooth slope colliders (the stairs): a tilted box whose top surface runs from the top point to the bottom point.
func _ramps() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	add_child(body)
	for r in City.ramps:
		var a: Vector3 = r["a"]
		var b: Vector3 = r["b"]
		var f := (b - a).normalized()
		var right := Vector3.UP.cross(f).normalized()
		var n := f.cross(right)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(float(r["width"]), 0.4, (b - a).length())
		cs.shape = shape
		cs.transform = Transform3D(Basis(right, n, f), (a + b) * 0.5 - n * 0.2)
		body.add_child(cs)


## The few lights indoors (lobby, apartment, cellar): cheap omni lights without shadows.
func _lights() -> void:
	for l in City.lights:
		var ol := OmniLight3D.new()
		ol.position = l["pos"]
		ol.omni_range = float(l["range"])
		ol.light_energy = float(l["energy"])
		ol.light_color = l["color"]
		ol.shadow_enabled = false
		add_child(ol)




## The landing craft of "The Lander" on the park's landing area (hidden until the story starts its descent).
func _lander() -> void:
	lander = ShipModels.Lander.new()
	add_child(lander)
	lander.build()
	lander.position = City.LANDER_POS
	lander.rotation.y = City.LANDER_YAW
	_far_landers()


## The other craft that have settled in far plazas (seen from the lookout roof): one MultiMesh of the cheap hull, hidden until the lookout.
func _far_landers() -> void:
	far_landers_node = null
	if CityStory.far_landers.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = ShipModels.lander_mesh(1)
	mm.instance_count = CityStory.far_landers.size()
	for i in CityStory.far_landers.size():
		var fl: Dictionary = CityStory.far_landers[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(fl["yaw"]) + PI) * Basis.from_scale(Vector3.ONE * CityStory.FAR_SCALE), fl["pos"]))       # (ramp the other way round: they face the square's middle)
	far_landers_node = MultiMeshInstance3D.new()
	far_landers_node.multimesh = mm
	far_landers_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far_landers_node.visible = false
	add_child(far_landers_node)
