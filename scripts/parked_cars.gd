class_name ParkedCars
## The parked cars of the city (models in models/cars: 3 AssetHub cars of 8.8 - 9.3k triangles, the Cybertruck and the EV, credits in CREDITS.md).
## Spots are fixed, not random: [model, x, z, yaw], worked out by tests/car_spots.gd so the whole car (0.9 m to spare) stands on a wide street,
## clear of buildings, props, trees and barricades. Model 3 (Cybertruck) is rare, model 4 (EV) is occasional.
## Every model is merged into one mesh, scaled to its `len`, centred, set on the ground and turned nose to -z (the nose side is read from the
## shape: the roof sits behind the middle). One MultiMesh per model and 80 m chunk (hidden beyond DRAW_RANGE), one static body with a box per car,
## and every car closes its cells in the navigation grid so soldiers walk round it.
## `build(parent)` once after the world is built, before the enemies are placed.

const DRAW_RANGE := 240.0          # measured from the middle of an 80 m chunk, so a chunk vanishes only when its nearest car is about 200 m away
const CHUNK := 80.0
const MODELS := [
	{"file": "sedan", "len": 4.6},
	{"file": "van", "len": 5.0},
	{"file": "coupe", "len": 4.5},
	{"file": "cybertruck", "len": 5.6},
	{"file": "ev", "len": 4.0}]
const SPOTS := [
	[4, -30.0, 188.4, 1.571],
	[1, -50.6, 143.5, 0.0],
	[2, -50.6, -20.0, 0.0],
	[2, 33.0, -76.6, 1.571],
	[0, -50.7, -269.0, 0.0],
	[1, -50.7, -247.0, 0.0],
	[3, -50.7, -215.0, 0.0],
	[4, -50.7, -189.0, 0.0],
	[3, -50.7, -147.0, 0.0],
	[2, -50.7, -101.0, 0.0],
	[3, -50.7, -73.0, 0.0],
	[4, -50.7, -49.0, 0.0],
	[1, -50.7, 17.0, 0.0],
	[0, -50.7, 39.0, 0.0],
	[2, -50.7, 61.0, 0.0],
	[1, -50.7, 83.0, 0.0],
	[0, -50.7, 109.0, 0.0],
	[2, -50.7, 165.0, 0.0],
	[0, -50.7, 187.0, 0.0],
	[1, -50.7, 221.0, 0.0],
	[2, -50.7, 249.0, 0.0],
	[1, -50.7, 279.0, 0.0],
	[2, -57.3, -282.0, 3.142],
	[1, -57.3, -162.0, 3.142],
	[0, -57.3, -136.0, 3.142],
	[4, -57.3, -114.0, 3.142],
	[2, 57.3, -271.0, 0.0],
	[0, 57.3, -249.0, 0.0],
	[1, 57.3, -215.0, 0.0],
	[4, 57.3, -191.0, 0.0],
	[2, 57.3, -151.0, 0.0],
	[4, 57.3, -115.0, 0.0],
	[1, 57.3, -89.0, 0.0],
	[0, 57.3, -67.0, 0.0],
	[4, 57.3, -41.0, 0.0],
	[1, 57.3, 23.0, 0.0],
	[0, 57.3, 49.0, 0.0],
	[4, 57.3, 71.0, 0.0],
	[0, 57.3, 99.0, 0.0],
	[2, 57.3, 123.0, 0.0],
	[1, 57.3, 157.0, 0.0],
	[2, 57.3, 179.0, 0.0],
	[0, 57.3, 221.0, 0.0],
	[2, 57.3, 255.0, 0.0],
	[1, 57.3, 277.0, 0.0],
	[1, 50.7, -162.0, 3.142],
	[0, 50.7, -134.0, 3.142],
	[2, 50.7, 60.0, 3.142],
	[1, 50.7, 82.0, 3.142],
	[4, 50.7, 136.0, 3.142],
	[2, -144.0, -196.7, 1.571],
	[1, -116.0, -196.7, 1.571],
	[0, -70.0, -196.7, 1.571],
	[1, -20.0, -196.7, 1.571],
	[0, 16.0, -196.7, 1.571],
	[2, 42.0, -196.7, 1.571],
	[0, 94.0, -196.7, 1.571],
	[2, 116.0, -196.7, 1.571],
	[1, 140.0, -196.7, 1.571],
	[2, -84.0, -203.3, 4.712],
	[2, -38.0, -203.3, 4.712],
	[2, -118.8, -76.7, 1.571],
	[0, -96.8, -76.7, 1.571],
	[1, -66.8, -76.7, 1.571]]


static func build(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "ParkedCarBodies"
	body.collision_layer = Game.L_WORLD
	parent.add_child(body)
	var prepared: Array = []
	for info in MODELS:
		prepared.append(_prepare(info))
	var chunks := {}                  # "model:cx:cz" -> {mi, list}
	for sp in SPOTS:
		var mi: int = sp[0]
		var md: Dictionary = prepared[mi]
		if md.is_empty():
			continue
		var yaw: float = sp[3]
		var key := "%d:%d:%d" % [mi, floori(float(sp[1]) / CHUNK), floori(float(sp[2]) / CHUNK)]
		if not chunks.has(key):
			chunks[key] = {"mi": mi, "list": []}
		(chunks[key]["list"] as Array).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(sp[1], 0.0, sp[2])) * (md["norm"] as Transform3D))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(md["width"]), 1.4, float(md["length"]))
		cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(sp[1], 0.7, sp[2]))
		body.add_child(cs)
		var hw := float(md["width"]) * 0.5
		var hl := float(md["length"]) * 0.5
		var hx := absf(cos(yaw)) * hw + absf(sin(yaw)) * hl
		var hz := absf(sin(yaw)) * hw + absf(cos(yaw)) * hl
		City._block(Rect2(sp[1] - hx, sp[2] - hz, hx * 2.0, hz * 2.0), 0.4)
	for key in chunks:
		var mi: int = chunks[key]["mi"]
		var list: Array = chunks[key]["list"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = (prepared[mi] as Dictionary)["mesh"]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "Cars_%s" % key
		inst.multimesh = mm
		inst.visibility_range_end = DRAW_RANGE
		inst.visibility_range_end_margin = 20.0
		parent.add_child(inst)


## One model: its meshes merged (node transforms baked in), and `norm`, the transform that scales it to `len`, centres it, sets it on the ground
## (2 cm sunk for the tyres) and turns the nose to -z. Also its footprint (`width`, `length`) in metres. Empty if the file is missing.
static func _prepare(info: Dictionary) -> Dictionary:
	var res := load("res://models/cars/%s.glb" % info["file"]) as PackedScene
	if res == null:
		return {}
	var root := res.instantiate() as Node3D
	var merged := ArrayMesh.new()
	var verts := PackedVector3Array()          # every vertex in the model's space, for the size and the nose test
	_merge(root, root, merged, verts)
	root.free()
	if merged.get_surface_count() == 0:
		return {}
	var box := merged.get_aabb()
	var along_x := box.size.x >= box.size.z
	var long_side := box.size.x if along_x else box.size.z
	var mid := box.get_center()
	# the roof sits behind the middle of a car: the mean of the high vertices against the mean of the low ones along the long axis
	var hi := 0.0
	var lo := 0.0
	var nh := 0
	var nl := 0
	for v in verts:
		var h := (v.y - box.position.y) / maxf(box.size.y, 0.001)
		var u := (v.x - mid.x) if along_x else (v.z - mid.z)
		if h > 0.8:
			hi += u
			nh += 1
		elif h < 0.45:
			lo += u
			nl += 1
	var nose_plus := (hi / maxf(nh, 1.0)) < (lo / maxf(nl, 1.0))        # roof towards -axis: the nose is at +axis
	var turn := 0.0
	if along_x:
		turn = PI * 0.5 if nose_plus else -PI * 0.5
	else:
		turn = PI if nose_plus else 0.0
	var s := float(info["len"]) / long_side
	var norm := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * s), Vector3(0.0, -0.02, 0.0)) * Transform3D(Basis.IDENTITY, -Vector3(mid.x, box.position.y, mid.z))
	var short_side := box.size.z if along_x else box.size.x
	return {"mesh": merged, "norm": norm, "width": short_side * s, "length": long_side * s}


static func _merge(n: Node, root: Node3D, out: ArrayMesh, verts: PackedVector3Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var xf := Transform3D.IDENTITY                 # this node's transform inside the model
		var p: Node = mi
		while p != root:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for s in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(mi.mesh, s, xf)
			var mat := mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			st.commit(out)
			out.surface_set_material(out.get_surface_count() - 1, _tame(mat))
			for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				verts.append(xf * (v as Vector3))
	for c in n.get_children():
		_merge(c, root, out, verts)


## The models were made for a renderer with reflections: with the sky as the only light source their metal looks washed out and grey and the
## paint glows. Keep the paint colour and the detail, take the metal and the shine down, and a touch of the brightness.
const METAL_MAX := 0.12
const SPECULAR := 0.3
const PAINT_DIM := 0.88


static func _tame(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.metallic = minf(m.metallic, METAL_MAX)
	m.metallic_specular = SPECULAR
	m.roughness = maxf(m.roughness, 0.85) if m.roughness_texture == null else 1.0
	m.albedo_color = m.albedo_color * PAINT_DIM
	m.emission_enabled = m.emission_enabled and m.emission_energy_multiplier < 2.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
