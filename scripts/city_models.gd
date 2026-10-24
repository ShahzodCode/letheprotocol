class_name CityModels
## Ten Sketchfab buildings (models/buildings, credits in CREDITS.md) stand in the generated city in place of box buildings.
## Two kinds of place:
##   lot models: an ordinary generated lot (fixed list LOT_SPOTS, worked out by tests/building_spots.gd) loses its box building and gets the
##     model instead, turned so its front faces the widest street, scaled to fit the lot (within the model's scale range), flush with the street.
##     If a spot no longer holds a lot the model fits (the generator changed), it is skipped.
##   ring models: fixed RING_SPOTS replace a stretch of the border ring (the box towers there are cut back), the model's front flush with the
##     inner face of the ring; a deep model sticks out beyond it. `sci3` stands behind the hotel, outside the map: a picture only.
## The building dict of a model: rect = the model's footprint, h, boxes = [] (World draws no box and makes no box collider), model = id,
## model_yaw, model_scale. CityClimb, CityBuildings, CityInteriors and CityStory leave such buildings alone (no damage, ladders, interiors).
## `place()` in City.generate (after the backdrop); `build(parent)` in World after the buildings: the meshes (merged per material, with LODs),
## and the colliders: one box for a lot model, slices along a ring model that follow its front and close the ring behind it.

## file, front (model space x/z of the side with the entrance), sink (model units below the ground), size (model units: x, z, height),
## scale range for lots (smin..smax) or the fixed scale of a ring model, drop (mesh names left out of the merge)
const MODELS := {
	"residential": {"file": "residential_building", "front": Vector2(1, 0), "size": Vector3(14.0, 35.6, 17.5), "smin": 0.85, "smax": 1.05},
	"office": {"file": "office_building_2", "front": Vector2(1, 0), "size": Vector3(21.6, 51.6, 20.0), "smin": 0.6, "smax": 0.72},
	"building": {"file": "building", "front": Vector2(1, 0), "size": Vector3(26.7, 35.4, 41.5), "smin": 0.85, "smax": 1.1, "sink": 2.0},
	"korean": {"file": "korean_apartment", "front": Vector2(1, 0), "size": Vector3(4.55, 4.62, 9.53), "smin": 4.9, "smax": 5.5},
	"japanese": {"file": "japanese_building__cc0", "front": Vector2(0, -1), "size": Vector3(13.0, 16.8, 31.1), "smin": 0.9, "smax": 1.15,
		"drop": ["Object_4"]},
	"futuristic": {"file": "futuristic_building", "front": Vector2(1, 0), "size": Vector3(0.0346, 0.0363, 0.157), "smin": 750.0, "smax": 1000.0},
	"hotel": {"file": "grand_hotel_building", "front": Vector2(1, 0), "size": Vector3(29.5, 114.8, 39.2), "scale": 1.0,
		"drop": ["Plane_001_Material_001_0"]},
	"tokyo": {"file": "building_no_6_form_tokyo_otemachi_building_pack", "front": Vector2(0, 1), "size": Vector3(69.6, 42.8, 105.0), "scale": 0.8},
	"sci11": {"file": "sci-fi_building_11", "front": Vector2(1, 0), "size": Vector3(70.7, 152.1, 277.75), "scale": 0.8},
	"sci3": {"file": "sci-fi_building_3", "front": Vector2(0, -1), "size": Vector3(121.7, 59.7, 195.8), "scale": 0.8}}

## [model, x, z]: a point inside the lot (tests/building_spots.gd prints candidates)
const LOT_SPOTS := [
	["futuristic", -29.7, 26.1],       # by the central crossroads, seen from the whole walk
	["japanese", -19.9, 169.2],        # on the central avenue
	["korean", 35.6, 89.5],
	["building", 35.1, 162.9],
	["building", 127.8, -28.1],
	["office", 30.2, -104.3],
	["office", 29.9, -126.2],
	["office", -30.5, -215.5],
	["residential", -81.4, 212.6],
	["residential", -127.6, 263.5],
	["residential", -127.7, -28.3],
	["residential", 90.0, -120.5]]

## [model, side of the ring ("n", "s", "w", "e") or "" for a picture outside the map, centre along the ring (or x), z for a picture]
const RING_SPOTS := [
	["hotel", "n", 0.0, 0.0],             # low, at the end of the central avenue: a gap in the skyline ...
	["sci3", "", 0.0, -346.0],            # ... with the landmark tower behind it, dead ahead on the walk home
	["sci11", "w", 0.0, 0.0],             # the two ends of the z = 0 avenue
	["tokyo", "e", 0.0, 0.0]]

const SLICE := 6.0                         # ring colliders: one box per this many metres along the ring
const PAVEMENT := Color(0.58, 0.57, 0.55)

static var placed: Array = []              # {id, rect, yaw, scale, ring: "" | side, building: the dict or {}}
static var _cache := {}                     # id -> {mesh, aabb} (World side)


static func _angle(v: Vector2) -> float:
	return atan2(v.x, v.y)


## The model's x / z size in the world for this yaw (a quarter turn swaps them).
static func _turned(id: String, yaw: float) -> Vector2:
	var sz: Vector3 = MODELS[id]["size"]
	return Vector2(sz.y, sz.x) if absf(sin(yaw)) > 0.5 else Vector2(sz.x, sz.y)


static func _yaw_to(id: String, n: Vector2) -> float:
	return _angle(n) - _angle(MODELS[id]["front"])


# ---------------------------------------------------------------- City side

static func place() -> void:
	placed.clear()
	for sp in RING_SPOTS:
		_place_ring(String(sp[0]), String(sp[1]), float(sp[2]), float(sp[3]))
	for sp in LOT_SPOTS:
		var b := _plain_lot_at(Vector2(sp[1], sp[2]))
		if b.is_empty():
			continue
		var f := fit_lot(b, String(sp[0]))
		if f.is_empty():
			continue
		var lot_rect: Rect2 = b["rect"]
		City.ground_slabs.append([lot_rect, PAVEMENT, 2])          # the part of the lot the model leaves free is paved
		b["rect"] = f["rect"]
		b["h"] = f["h"]
		b["boxes"] = []
		b["model"] = String(sp[0])
		b["model_yaw"] = f["yaw"]
		b["model_scale"] = f["scale"]
		placed.append({"id": String(sp[0]), "rect": f["rect"], "yaw": f["yaw"], "scale": f["scale"], "ring": "", "building": b})


## An ordinary generated building (nothing but a box on a lot: no story role, no passage) whose footprint holds `p`, or {}.
static func _plain_lot_at(p: Vector2) -> Dictionary:
	for b in City.buildings:
		if not (b["rect"] as Rect2).has_point(p):
			continue
		for k in b:
			if not String(k) in ["rect", "boxes", "style", "color", "h"]:
				return {}
		return b
	return {}


## How model `id` stands on the footprint of building `b`: {rect, yaw, scale, h, side} with its front to the widest street it fits on, or {}.
static func fit_lot(b: Dictionary, id: String) -> Dictionary:
	var m: Dictionary = MODELS[id]
	var fp: Rect2 = b["rect"]
	for ws in CityBuildings.street_sides(fp):
		if float(ws[0]) <= 0.0:
			continue
		var side: int = ws[1]
		var n: Vector2 = CityBuildings.SIDE_N[side]
		var yaw := _yaw_to(id, n)
		var dim := _turned(id, yaw)
		var s := minf(fp.size.x / dim.x, fp.size.y / dim.y)
		if s < float(m["smin"]):
			continue
		s = minf(s, float(m["smax"]))
		var w := dim * s
		# flush with the street side, centred along it
		var c := fp.get_center()
		if side == 0:
			c.y = fp.position.y + w.y * 0.5
		elif side == 1:
			c.y = fp.end.y - w.y * 0.5
		elif side == 2:
			c.x = fp.position.x + w.x * 0.5
		else:
			c.x = fp.end.x - w.x * 0.5
		var sink := float(m.get("sink", 0.0))
		return {"rect": Rect2(c - w * 0.5, w), "yaw": yaw, "scale": s, "h": (float((m["size"] as Vector3).z) - sink) * s, "side": side}
	return {}


## A ring model: the border towers along its stretch are cut back (what is left of them stays a tower), the model takes the stretch with its
## front on the inner face of the ring. Side "" is a picture outside the map (no building, no collider).
static func _place_ring(id: String, side: String, along: float, z: float) -> void:
	var m: Dictionary = MODELS[id]
	var s := float(m["scale"])
	var inward := {"n": Vector2(0, 1), "s": Vector2(0, -1), "w": Vector2(1, 0), "e": Vector2(-1, 0), "": Vector2(0, 1)}
	var yaw := _yaw_to(id, inward[side])
	var w := _turned(id, yaw) * s
	var h := float((m["size"] as Vector3).z) * s
	if side == "":
		var pic := Rect2(Vector2(along, z) - w * 0.5, w)
		_clear_backdrop(pic)
		placed.append({"id": id, "rect": pic, "yaw": yaw, "scale": s, "ring": "", "building": {}})
		return
	var along_x := side == "n" or side == "s"
	var half := (w.x if along_x else w.y) * 0.5
	var depth := w.y if along_x else w.x
	var model_rect: Rect2
	var ring_rect: Rect2            # the stretch of the ring (and beyond, as deep as the model): nav and the closing colliders
	match side:
		"n":
			model_rect = Rect2(along - half, -City.IN_Z - depth, half * 2.0, depth)
			ring_rect = Rect2(along - half, minf(-City.OUT_Z, -City.IN_Z - depth), half * 2.0, maxf(City.RING, depth))
		"s":
			model_rect = Rect2(along - half, City.IN_Z, half * 2.0, depth)
			ring_rect = Rect2(along - half, City.IN_Z, half * 2.0, maxf(City.RING, depth))
		"w":
			model_rect = Rect2(-City.IN_X - depth, along - half, depth, half * 2.0)
			ring_rect = Rect2(minf(-City.OUT_X, -City.IN_X - depth), along - half, maxf(City.RING, depth), half * 2.0)
		_:
			model_rect = Rect2(City.IN_X, along - half, depth, half * 2.0)
			ring_rect = Rect2(City.IN_X, along - half, maxf(City.RING, depth), half * 2.0)
	_cut_border(ring_rect, along_x)
	_clear_backdrop(ring_rect)
	var b := {"rect": ring_rect, "boxes": [], "style": 0.1, "color": PAVEMENT, "h": h, "border": true, "model": id, "model_yaw": yaw,
		"model_scale": s}
	City.buildings.append(b)
	placed.append({"id": id, "rect": model_rect, "yaw": yaw, "scale": s, "ring": side, "building": b})


## Cuts the border towers that overlap `cut` (a stretch of the ring) back to the parts outside it.
static func _cut_border(cut: Rect2, along_x: bool) -> void:
	var keep: Array = []
	for b in City.buildings:
		if not b.get("border", false) or b.has("model") or not (b["rect"] as Rect2).intersects(cut):
			keep.append(b)
			continue
		var r: Rect2 = b["rect"]
		var pieces: Array = []
		if along_x:
			if r.position.x < cut.position.x:
				pieces.append(Rect2(r.position.x, r.position.y, cut.position.x - r.position.x, r.size.y))
			if r.end.x > cut.end.x:
				pieces.append(Rect2(cut.end.x, r.position.y, r.end.x - cut.end.x, r.size.y))
		else:
			if r.position.y < cut.position.y:
				pieces.append(Rect2(r.position.x, r.position.y, r.size.x, cut.position.y - r.position.y))
			if r.end.y > cut.end.y:
				pieces.append(Rect2(r.position.x, cut.end.y, r.size.x, r.end.y - cut.end.y))
		for p in pieces:
			var nb: Dictionary = b.duplicate()
			nb["rect"] = p
			nb["boxes"] = City._tower_boxes(p, float(b["h"]))
			keep.append(nb)
	City.buildings.assign(keep)


static func _clear_backdrop(r: Rect2) -> void:
	var keep: Array = []
	for b in City.backdrop:
		if not (b["rect"] as Rect2).intersects(r.grow(4.0)):
			keep.append(b)
	City.backdrop.assign(keep)


# ---------------------------------------------------------------- World side

static func build(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "ModelBuildingBodies"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	parent.add_child(body)
	for p in placed:
		var id: String = p["id"]
		var md := _prepare(id)
		if md.is_empty():
			continue
		var aabb: AABB = md["aabb"]
		var yaw: float = p["yaw"]
		var rect: Rect2 = p["rect"]
		var basis := Basis(Vector3.UP, yaw)
		var turned := (basis * aabb.size).abs()
		var s := minf(rect.size.x / turned.x, rect.size.y / turned.z)
		var sink := float(MODELS[id].get("sink", 0.0))
		var anchor := Vector3(aabb.get_center().x, aabb.position.y + sink, aabb.get_center().z)
		var xf := Transform3D(basis.scaled(Vector3.ONE * s), Vector3(rect.get_center().x, 0.0, rect.get_center().y)) * Transform3D(Basis.IDENTITY, -anchor)
		var mi := MeshInstance3D.new()
		mi.name = "Model_%s" % id
		mi.mesh = md["mesh"]
		mi.transform = xf
		parent.add_child(mi)
		var b: Dictionary = p["building"]
		if b.is_empty():
			continue
		var top := (aabb.size.y - sink) * s
		if String(p["ring"]) == "":
			_box(body, rect, 0.0, top)
		else:
			_ring_colliders(body, p, md["verts"], xf, b["rect"], top)


## Slices along the ring: each one a box from the model's front in that slice (its innermost vertex) back to the far side of the ring stretch,
## so the wall follows a curved or stepped front and the ring stays closed behind it.
static func _ring_colliders(body: StaticBody3D, p: Dictionary, verts: PackedVector3Array, xf: Transform3D, ring_rect: Rect2, top: float) -> void:
	var side: String = p["ring"]
	var along_x := side == "n" or side == "s"
	var r: Rect2 = p["rect"]
	var a0 := r.position.x if along_x else r.position.y
	var length := r.size.x if along_x else r.size.y
	var n := maxi(1, ceili(length / SLICE))
	var step := length / float(n)
	var front := []                     # per slice: the innermost coordinate across the ring
	front.resize(n)
	var inward_plus := side == "n" or side == "w"       # the map lies towards +z / +x
	for i in n:
		front[i] = -INF if inward_plus else INF
	for v in verts:
		var w := xf * v
		if w.y > top * 0.6:                 # the street-level front, not an overhanging crown
			continue
		var u := w.x if along_x else w.z
		var k := clampi(int((u - a0) / step), 0, n - 1)
		var acr := w.z if along_x else w.x
		front[k] = maxf(front[k], acr) if inward_plus else minf(front[k], acr)
	for i in n:
		var f: float = front[i]
		if is_inf(f):
			f = (r.end.y if along_x else r.end.x) if inward_plus else (r.position.y if along_x else r.position.x)
		var u0 := a0 + step * i
		var box: Rect2
		if along_x:
			box = Rect2(u0, ring_rect.position.y, step, f - ring_rect.position.y) if inward_plus else Rect2(u0, f, step, ring_rect.end.y - f)
		else:
			box = Rect2(ring_rect.position.x, u0, f - ring_rect.position.x, step) if inward_plus else Rect2(f, u0, ring_rect.end.x - f, step)
		_box(body, box, 0.0, top)


static func _box(body: StaticBody3D, r: Rect2, y0: float, y1: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(r.size.x, y1 - y0, r.size.y)
	cs.shape = shape
	cs.position = Vector3(r.get_center().x, (y0 + y1) * 0.5, r.get_center().y)
	body.add_child(cs)


## One model: its meshes merged into one surface per material (node transforms baked in, the `drop` meshes left out), LODs generated;
## {mesh, aabb, verts} in model space, or {} if the file is missing.
static func _prepare(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var info: Dictionary = MODELS[id]
	var res := load("res://models/buildings/%s.glb" % info["file"]) as PackedScene
	if res == null:
		_cache[id] = {}
		return {}
	var root := res.instantiate() as Node3D
	var by_mat := {}                    # material -> SurfaceTool
	var verts := PackedVector3Array()
	_collect(root, root, info.get("drop", []), by_mat, verts)
	root.free()
	var im := ImporterMesh.new()
	for mat in by_mat:
		var st: SurfaceTool = by_mat[mat]
		var arrays := st.commit_to_arrays()
		for a in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[a] = null              # SurfaceTool hands them back as floats without their format flags: the mesh would be refused
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _tame(mat))
	if im.get_surface_count() == 0:
		_cache[id] = {}
		return {}
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	var out := {"mesh": mesh, "aabb": mesh.get_aabb(), "verts": verts}
	_cache[id] = out
	return out


static func _collect(n: Node, root: Node3D, drop: Array, by_mat: Dictionary, verts: PackedVector3Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and not String(n.name) in drop:
		var mi := n as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != root:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			if not by_mat.has(mat):
				var nst := SurfaceTool.new()
				nst.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = nst
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, s, xf)
			for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				verts.append(xf * (v as Vector3))
	for c in n.get_children():
		_collect(c, root, drop, by_mat, verts)


## The sci-fi towers are all metal: with the sky as the only thing to reflect they turn black. Metal down, the glow lines kept.
const METAL_MAX := 0.25


static func _tame(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.metallic = minf(m.metallic, METAL_MAX)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
