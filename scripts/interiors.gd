class_name Interiors
extends Node
## Streams the enterable buildings of CityInteriors (city pass, phase 3). While the player is within STREAM_RADIUS of one, its inside exists:
## one StaticBody3D (walls, props, ceiling: at most MAX_SHAPES boxes), ONE merged mesh drawn with the building shader, one dim OmniLight3D
## without shadows, and a small navigation layer joined to the street grid at the entrance door. The building's closed collider is switched
## off and its box shrinks to the floors above the ceiling. Beyond FREE_RADIUS (and with nobody inside) everything is freed again. At most
## MAX_ALIVE interiors exist at once; building one takes three frames (colliders, mesh + light, navigation), never more in one frame.

const STREAM_RADIUS := 60.0
const FREE_RADIUS := 75.0
const MAX_ALIVE := 3
const MAX_SHAPES := 40
const CHECK_STEP := 0.4
const FLOOR_COL := Color(0.4, 0.38, 0.35)
const CEIL_COL := Color(0.84, 0.82, 0.77)
const WALL_COL := Color(0.78, 0.74, 0.66)
const PLAIN := 0.99                       # building shader style: plain wall
const LIGHT_COL := Color(1.0, 0.84, 0.6)
const LIGHT_ENERGY := 0.7

static var shapes: Dictionary = {}        # iid -> the CollisionShape3D of the building's closed collider (World fills it)

var main
var player: Player
var alive: Dictionary = {}                # iid -> {body, mesh, light}
var _job: Dictionary = {}                 # the interior being built: {iid, stage, body, mesh, light}
var _t := 0.0
var built_total := 0
var freed_total := 0
var max_alive_seen := 0


func setup(m) -> void:
	main = m
	player = m.player


func _process(delta: float) -> void:
	if City.interiors.is_empty() or player == null:
		return
	if not _job.is_empty():
		_step_job()
		return
	_t -= delta
	if _t <= 0.0:
		_t = CHECK_STEP
		_scan()


func _dist(plan: Dictionary, p: Vector3) -> float:
	var r: Rect2 = plan["rect"]
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.z, p.z - r.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


func _scan() -> void:
	var pp := player.global_position
	var near: Array = []
	for plan in City.interiors:
		var d := _dist(plan, pp)
		if d < STREAM_RADIUS:
			near.append([d, int(plan["iid"])])
	near.sort_custom(func(a, c): return a[0] < c[0])
	# free the ones that are far away (and empty)
	for iid in alive.keys():
		var plan: Dictionary = City.interiors[iid]
		if _dist(plan, pp) > FREE_RADIUS and _empty(plan):
			_free(iid)
	for e in near:
		var iid2: int = e[1]
		if alive.has(iid2):
			continue
		if alive.size() >= MAX_ALIVE:
			# make room: the farthest living one that is not among the wanted
			var far_id := -1
			var far_d := -1.0
			for a in alive.keys():
				var d2 := _dist(City.interiors[a], pp)
				if d2 > far_d and d2 > float(e[0]) and _empty(City.interiors[a]):
					far_d = d2
					far_id = a
			if far_id < 0:
				break
			_free(far_id)
		_job = {"iid": iid2, "stage": 0}
		break


## Nobody (the player, a soldier, a civilian) stands inside the footprint.
func _empty(plan: Dictionary) -> bool:
	var r: Rect2 = (plan["rect"] as Rect2).grow(0.8)
	if r.has_point(Vector2(player.global_position.x, player.global_position.z)):
		return false
	for e in Game.enemies:
		if is_instance_valid(e) and r.has_point(Vector2((e as Node3D).global_position.x, (e as Node3D).global_position.z)):
			return false
	for c in Game.civilians:
		if is_instance_valid(c) and r.has_point(Vector2((c as Node3D).global_position.x, (c as Node3D).global_position.z)):
			return false
	return true


func _step_job() -> void:
	var iid: int = _job["iid"]
	var plan: Dictionary = City.interiors[iid]
	match int(_job["stage"]):
		0:
			_job["body"] = _make_body(plan)
		1:
			_job["mesh"] = _make_mesh(plan)
			_job["light"] = _make_light(plan)
		2:
			_activate(plan)
			alive[iid] = {"body": _job["body"], "mesh": _job["mesh"], "light": _job["light"]}
			built_total += 1
			max_alive_seen = maxi(max_alive_seen, alive.size())
			_job = {}
			return
	_job["stage"] = int(_job["stage"]) + 1


func _box_shape(body: StaticBody3D, r: Rect2, y0: float, y1: float) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(r.size.x, y1 - y0, r.size.y)
	cs.shape = box
	cs.position = Vector3(r.get_center().x, (y0 + y1) * 0.5, r.get_center().y)
	body.add_child(cs)


func _make_body(plan: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	var n := 1
	for r in plan["shell"]:
		_box_shape(body, r, 0.0, CityInteriors.HEIGHT)
		n += 1
	for r in plan["walls"]:
		if n >= MAX_SHAPES:
			break
		_box_shape(body, r, 0.0, CityInteriors.HEIGHT)
		n += 1
	for p in plan["props"]:
		if n >= MAX_SHAPES:
			break
		_box_shape(body, p["rect"], 0.0, float(p["h"]))
		n += 1
	_box_shape(body, plan["rect"], CityInteriors.HEIGHT, CityInteriors.HEIGHT + CityInteriors.CEIL)          # the ceiling slab
	add_child(body)
	return body


## Everything of one interior in ONE mesh (vertex colours; alpha = building shader style).
func _make_mesh(plan: Dictionary) -> MeshInstance3D:
	var a := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	var base: Color = plan["color"]
	var shell_col := Color(base.r, base.g, base.b, float(plan["style"]))
	var h := CityInteriors.HEIGHT
	for r in plan["shell"]:
		_add_box(a, Vector3(r.get_center().x, h * 0.5, r.get_center().y), Vector3(r.size.x, h, r.size.y), shell_col)
	for r in plan["walls"]:
		_add_box(a, Vector3(r.get_center().x, h * 0.5, r.get_center().y), Vector3(r.size.x, h, r.size.y), Color(WALL_COL.r, WALL_COL.g, WALL_COL.b, PLAIN))
	for p in plan["props"]:
		var pr: Rect2 = p["rect"]
		var pc: Color = p["color"]
		_add_box(a, Vector3(pr.get_center().x, float(p["h"]) * 0.5, pr.get_center().y), Vector3(pr.size.x, float(p["h"]), pr.size.y), Color(pc.r, pc.g, pc.b, PLAIN))
	var rect: Rect2 = plan["rect"]
	var cc := rect.get_center()
	_add_box(a, Vector3(cc.x, 0.02, cc.y), Vector3(rect.size.x - 0.2, 0.04, rect.size.y - 0.2), Color(FLOOR_COL.r, FLOOR_COL.g, FLOOR_COL.b, PLAIN))
	_add_box(a, Vector3(cc.x, h + CityInteriors.CEIL * 0.5, cc.y), Vector3(rect.size.x, CityInteriors.CEIL, rect.size.y), Color(CEIL_COL.r, CEIL_COL.g, CEIL_COL.b, PLAIN))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a["v"]
	arrays[Mesh.ARRAY_NORMAL] = a["n"]
	arrays[Mesh.ARRAY_COLOR] = a["c"]
	arrays[Mesh.ARRAY_INDEX] = a["i"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = World.building_mat
	add_child(mi)
	return mi


func _make_light(plan: Dictionary) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = plan["light"]
	l.omni_range = float(plan["range"])
	l.light_energy = LIGHT_ENERGY
	l.light_color = LIGHT_COL
	l.shadow_enabled = false
	add_child(l)
	return l


func _activate(plan: Dictionary) -> void:
	var grid := City.interior_grid(plan["rect"], plan["inner"], plan["solids"], CityInteriors.NAV_MARGIN)
	City.interior_layer(int(plan["slot"]), grid)
	var iid: int = plan["iid"]
	if shapes.has(iid) and is_instance_valid(shapes[iid]):
		(shapes[iid] as CollisionShape3D).disabled = true
	var reg: Array = WorldWar.registry.get(iid, [])
	if not reg.is_empty():
		var xf0: Transform3D = reg[2]
		var sc := xf0.basis.get_scale()
		var floor_top := CityInteriors.HEIGHT + CityInteriors.CEIL
		var upper := maxf(float(plan["h"]) - floor_top, 0.05)
		(reg[0] as MultiMesh).set_instance_transform(int(reg[1]), Transform3D(Basis.from_scale(Vector3(sc.x, upper, sc.z)), Vector3(xf0.origin.x, floor_top + upper * 0.5, xf0.origin.z)))
	if bool(plan["lone"]) and not bool(plan.get("spawned", false)):
		plan["spawned"] = true
		var rc := (plan["inner"] as Rect2).get_center()
		main._spawn_enemy_at(Vector3(rc.x, 0.0, rc.y), "soldier")


func _free(iid: int) -> void:
	var plan: Dictionary = City.interiors[iid]
	var rec: Dictionary = alive[iid]
	for k in ["body", "mesh", "light"]:
		if is_instance_valid(rec[k]):
			(rec[k] as Node).queue_free()
	City.interior_layer(int(plan["slot"]), {})
	if shapes.has(iid) and is_instance_valid(shapes[iid]):
		(shapes[iid] as CollisionShape3D).disabled = false
	var reg: Array = WorldWar.registry.get(iid, [])
	if not reg.is_empty():
		(reg[0] as MultiMesh).set_instance_transform(int(reg[1]), reg[2])
	alive.erase(iid)
	freed_total += 1


## Appends one closed box (24 vertices, outward normals; clockwise front faces as Godot draws them).
func _add_box(a: Dictionary, c: Vector3, size: Vector3, col: Color) -> void:
	var hs := size * 0.5
	var verts: PackedVector3Array = a["v"]
	var norms: PackedVector3Array = a["n"]
	var cols: PackedColorArray = a["c"]
	var idx: PackedInt32Array = a["i"]
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var ua := (axis + 1) % 3
			var va := (axis + 2) % 3
			var eu := Vector3.ZERO
			eu[ua] = hs[ua]
			var ev := Vector3.ZERO
			ev[va] = hs[va]
			var o := verts.size()
			var centre := c + n * hs[axis]
			verts.append(centre - eu - ev)
			verts.append(centre + eu - ev)
			verts.append(centre + eu + ev)
			verts.append(centre - eu + ev)
			for k in 4:
				norms.append(n)
				cols.append(col)
			if sgn > 0.0:
				idx.append_array(PackedInt32Array([o, o + 2, o + 1, o, o + 3, o + 2]))
			else:
				idx.append_array(PackedInt32Array([o, o + 1, o + 2, o, o + 2, o + 3]))
	a["v"] = verts
	a["n"] = norms
	a["c"] = cols
	a["i"] = idx
